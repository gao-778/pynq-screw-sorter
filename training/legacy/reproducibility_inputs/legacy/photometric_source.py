"""在原始高清帧上增强光度，再运行原 FPGA 分割/OBB/几何契约。"""
from pathlib import Path
from collections import Counter, defaultdict
import hashlib
import json
import sys
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/training_photometric"
sys.path.insert(0, str(ROOT/"model"))
from auto_obb_reference import load_gray, components
from shape_obb_reference import roi_obb_rtl

SEED = 20261027
STRESS = {
    "gain080": dict(gain=.80),
    "gain110": dict(gain=1.10),
    "gamma110": dict(gamma=1.10),
    "gamma095": dict(gamma=.95),
    "shade080": dict(shade=.80, angle=.7),
    "noise150": dict(noise=1.5),
}


def photometric(gray, parameters, seed):
    """按相机灰度域模拟光强变化，不生成或宣称新的 RGB 色温。"""
    rng = np.random.default_rng(seed)
    values = gray.astype(np.float32)
    gamma = parameters.get("gamma", 1.0)
    if gamma != 1:
        values = 255*np.power(values/255, gamma)
    values = (values-64)*parameters.get("contrast", 1.0)+64
    values *= parameters.get("gain", 1.0)
    if "shade" in parameters:
        yy, xx = np.mgrid[0:gray.shape[0], 0:gray.shape[1]].astype(np.float32)
        xx = xx/max(1, gray.shape[1]-1)-.5
        yy = yy/max(1, gray.shape[0]-1)-.5
        angle = parameters.get("angle", 0)
        projection = xx*np.cos(angle)+yy*np.sin(angle)
        projection = (projection-projection.min())/max(1e-6, float(projection.max()-projection.min()))
        shade = parameters["shade"]+(1-parameters["shade"])*projection
        values *= shade
    if parameters.get("highlight", 0):
        yy, xx = np.mgrid[0:gray.shape[0], 0:gray.shape[1]].astype(np.float32)
        cx, cy = parameters.get("spot", [.5,.5])
        spot = np.exp(-((xx/gray.shape[1]-cx)**2+(yy/gray.shape[0]-cy)**2)/.025)
        values += parameters["highlight"]*spot
    values += parameters.get("offset", 0)
    if parameters.get("noise", 0):
        values += rng.normal(0, parameters["noise"], values.shape).astype(np.float32)
    return np.clip(np.rint(values), 0, 255).astype(np.uint8)


def iou(first, second):
    x0, y0 = max(first[0],second[0]), max(first[1],second[1])
    x1, y1 = min(first[2],second[2]), min(first[3],second[3])
    intersection = max(0,x1-x0+1)*max(0,y1-y0+1)
    a = (first[2]-first[0]+1)*(first[3]-first[1]+1)
    b = (second[2]-second[0]+1)*(second[3]-second[1]+1)
    return intersection/max(1,a+b-intersection)


def match_objects(gray, original):
    candidates, diagnostics = components(gray, 40, True, 400, 10)
    if diagnostics["overflow"]:
        return [], dict(original=len(original), matched=0, candidates=len(candidates), overflow=True, reasons={"label_overflow":len(original)})
    used = set()
    matched = []
    reasons = Counter()
    for index,obj in enumerate(original):
        scores = [iou(obj["aabb_xyxy"],candidate["aabb_xyxy"]) if k not in used else -1 for k,candidate in enumerate(candidates)]
        if not scores or max(scores)<.65:
            reasons["no_unique_iou065_match"] += 1
            continue
        best = int(np.argmax(scores))
        candidate = candidates[best]
        used.add(best)
        x0,y0,x1,y1 = candidate["aabb_xyxy"]
        foreign = int((gray[y0:y1+1,x0:x1+1]>40).sum())-candidate["area"]
        if foreign>max(30,candidate["area"]*.05):
            reasons["foreign_foreground_inside_aabb"] += 1
            continue
        ratio = candidate["area"]/obj["area"]
        if ratio < .55 or ratio > 1.60:
            reasons["area_changed_or_merged"] += 1
            continue
        if any(iou(candidate["aabb_xyxy"],other["aabb_xyxy"])>.10 for j,other in enumerate(original) if j!=index):
            reasons["overlaps_another_original_object"] += 1
            continue
        matched.append((index,candidate))
    return matched,dict(original=len(original),matched=len(matched),candidates=len(candidates),overflow=False,reasons=dict(reasons))


def parameters_for_training(rng):
    return [
        dict(gain=float(rng.uniform(.78,.96)),gamma=float(rng.uniform(1.0,1.13)),offset=float(rng.uniform(-2,2)),noise=float(rng.uniform(.3,1.3))),
        dict(gain=float(rng.uniform(1.02,1.15)),gamma=float(rng.uniform(.96,1.03)),offset=float(rng.uniform(-2,1)),noise=float(rng.uniform(.3,1.2))),
        dict(gain=float(rng.uniform(.90,1.07)),contrast=float(rng.uniform(.90,1.08)),offset=float(rng.uniform(-2,2)),noise=float(rng.uniform(.3,1.2))),
        dict(gain=float(rng.uniform(.96,1.08)),gamma=float(rng.uniform(.97,1.04)),shade=float(rng.uniform(.76,.90)),angle=float(rng.uniform(0,2*np.pi)),highlight=float(rng.uniform(0,6)),spot=rng.uniform(.2,.8,2).tolist(),noise=.8),
    ]


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows = json.loads((ROOT/"output/training/annotations.json").read_text())
    rng = np.random.default_rng(SEED)
    arrays = {key:[] for key in ["images","geometry","labels","splits","ids","lighting","scene_groups","condition"]}
    frame_reports = []
    for frame_index,row in enumerate(rows):
        gray = load_gray(row["source"])
        original = [obj for obj in row["objects"] if obj["accepted"]]
        variants = {f"random{k}":p for k,p in enumerate(parameters_for_training(rng))} if row["split"] == "train" else STRESS
        for number,(name,parameters) in enumerate(variants.items()):
            seed = SEED+frame_index*17+number
            augmented = photometric(gray,parameters,seed)
            matches,diagnostics = match_objects(augmented,original)
            frame_reports.append(dict(image=row["image"],split=row["split"],lighting=row["lighting"],class_id=row["class_id"],class_name=row["class_name"],condition=name,parameters=parameters,noise_seed=seed,**diagnostics))
            for original_index,obj in matches:
                roi,geometry,_ = roi_obb_rtl(augmented,obj["aabb_xyxy"],obj["area"],threshold=40)
                values = dict(images=roi,geometry=geometry,labels=row["class_id"],splits=row["split"],
                              ids=f'{row["image"]}#accepted{original_index}_{name}',lighting=row["lighting"],
                              scene_groups=row["scene_group"],condition=name)
                for key,value in values.items():
                    arrays[key].append(value)
            if frame_index in [0,100,650] and number<2:
                image=Image.fromarray(augmented)
                image.thumbnail((640,480))
                image.save(OUT/f'example_{frame_index}_{name}.png')
        if frame_index%100 == 0:
            print("PHOTOMETRIC_FRAMES",frame_index,"/",len(rows),flush=True)
    arrays = {key:np.stack(value) if key in ["images","geometry"] else np.asarray(value) for key,value in arrays.items()}
    arrays["labels"] = arrays["labels"].astype(np.int64)
    np.savez_compressed(OUT/"photometric.npz",**arrays)
    summaries = {}
    for split in ["train","val","test"]:
        summaries[split] = {}
        for domain in ["OLD","YEW"]:
            summaries[split][domain] = {}
            for name in sorted({report["condition"] for report in frame_reports if report["split"]==split}):
                subset = [report for report in frame_reports if report["split"]==split and report["lighting"]==domain and report["condition"]==name]
                total = sum(report["original"] for report in subset)
                matched = sum(report["matched"] for report in subset)
                summaries[split][domain][name] = dict(frames=len(subset),original_objects=total,matched_objects=matched,coverage=matched/max(1,total),overflow_frames=sum(report["overflow"] for report in subset),reasons=dict(sum((Counter(report["reasons"]) for report in subset),Counter())))
    report = dict(seed=SEED,source_annotations_sha256=hashlib.sha256((ROOT/"output/training/annotations.json").read_bytes()).hexdigest(),
                  original_photos=len(rows),sample_counts=dict(Counter(arrays["splits"].tolist())),summaries=summaries,stress_parameters=STRESS,
                  pipeline="Full 1280x960 grayscale photometric transform -> unchanged threshold40/CCL -> IoU>=.65 unique match + area/foreign rejection -> recomputed OBB/ROI/geometry.",
                  limits="Real OLD/YEW carry real color-temperature effects. Grayscale transforms simulate intensity/contrast/noise, not new RGB spectra. Rejected augmented objects are retained as coverage failures, not labelled as correct.")
    (OUT/"frame_reports.json").write_text(json.dumps(frame_reports,ensure_ascii=False,indent=2),encoding="utf-8")
    (OUT/"dataset_report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    print("PHOTOMETRIC_DATASET_READY",json.dumps(report),flush=True)


if __name__ == "__main__":
    main()
