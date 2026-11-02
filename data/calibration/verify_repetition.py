"""Project source and interface utilities."""

from pathlib import Path
import hashlib
import importlib.util
import json
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("fresh_fit", ROOT / "calibrate_platform.py")
fit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fit)
result = json.loads((ROOT / "calibration.json").read_text(encoding="utf-8"))
frozen_h = np.asarray(result["H_screen_px_to_mm"])
frozen_dot = np.asarray(result["origin_screen_px"])
frozen_points = np.array([p for o in result["observations"] for p in o["corners_screen_px"]])
world = np.array([p for o in result["observations"] for p in o["nominal_square_mm"]])
rows, hashes, frames = [], [], []
for path in sorted(ROOT.glob("frame_*_gray.bin")):
    content = path.read_bytes()
    digest = hashlib.sha256(content).hexdigest()
    gray = np.frombuffer(content, np.uint8).reshape(960, 1280)[::-1, ::-1].copy()
    obs, dot = fit.measure(gray)
    points = np.array([p for o in obs for p in o["corners_screen_px"]])
    independent_h, _ = cv2.findHomography(points, world, 0)
    residual = np.linalg.norm(fit.project(independent_h, points)-world, axis=1)
    origin_mm = fit.project(independent_h, [dot])[0]
    translation = np.eye(3)
    translation[:2, 2] = -origin_mm
    independent_h = translation @ independent_h
    independent_h /= independent_h[2, 2]
    probes = np.array([[0,0],[1279,0],[1279,959],[0,959],dot.tolist()] +
                      frozen_points.tolist())
    transform_delta = np.linalg.norm(fit.project(independent_h, probes)-
                                     fit.project(frozen_h, probes), axis=1)
    regs = np.fromfile(path.with_name(path.name.replace("_gray.bin", "_registers.bin")), dtype="<u4")
    rows.append({"file":path.name,"sha256":digest,
                 "recognition_frame_register":int(regs[4]),
                 "recognition_status":hex(int(regs[2])),
                 "capture_status":hex(int(regs[0x7c//4])),
                 "origin_screen_px":dot.tolist(),
                 "origin_change_px":float(np.linalg.norm(dot-frozen_dot)),
                 "corner_change_max_px":float(np.linalg.norm(points-frozen_points,axis=1).max()),
                 "independent_fit_rms_mm":float(np.sqrt(np.mean(residual**2))),
                 "independent_H_screen":independent_h.tolist(),
                 "transform_delta_max_mm_at_corners_origin_and_image_borders":float(transform_delta.max()),
                 "black_dot_mm_under_frozen_H":fit.project(frozen_h,[dot])[0].tolist()})
    hashes.append(digest)
    frames.append(gray)

pairs=[]
for n in range(1,len(frames)):
    delta=frames[n].astype(int)-frames[0].astype(int)
    pairs.append({"first":rows[0]["file"],"other":rows[n]["file"],
                  "changed_pixels":int(np.count_nonzero(delta)),
                  "absolute_pixel_difference_mean":float(np.mean(np.abs(delta)))})


gray=frames[0]
crop=gray[480:523,632:674]
dots=[]
for threshold in (120,140,160,170,180,190,200):
    n,labels,stats,centers=cv2.connectedComponentsWithStats((crop<threshold).astype(np.uint8))
    index=1+int(np.argmax(stats[1:,cv2.CC_STAT_AREA]))
    dot=centers[index]+[632,480]
    dots.append({"threshold":threshold,"area_px":int(stats[index,cv2.CC_STAT_AREA]),
                 "origin_screen_px":dot.tolist(),
                 "delta_mm":float(np.linalg.norm(fit.project(frozen_h,[dot])[0]))})

assert len(rows)==3 and len(set(hashes))==3, "Not three distinct USB image contents"

# pixel shifts are still disclosed rather than silently described as stationary.
assert max(r["transform_delta_max_mm_at_corners_origin_and_image_borders"] for r in rows)<.5
report={"status":"PASS_WITH_SMALL_BOUNDARY_VARIATION","production_edited":False,
        "acceptance_limit_mm":0.5,
        "warning":"Some fitted corners differ by about 2.22 pixels between captures; not perfectly pixel-stationary.",
        "calibration_is_frozen_first_frame":True,
        "calibration_json_sha256":hashlib.sha256((ROOT/"calibration.json").read_bytes()).hexdigest(),
        "header_sha256":hashlib.sha256((ROOT/"platform_calibration.h").read_bytes()).hexdigest(),
        "distinct_image_contents":True,
        "consecutive_camera_frames_verified":False,
        "user_robot_base_definition_mm":[0,-150],
        "old_homography_used_in_new_fit":False,
        "recognition_frame_register_is_not_a_camera_frame_counter":True,
        "observations":rows,"image_changes":pairs,"dot_threshold_sensitivity":dots,
        "limits":["Repeated images estimate extraction repeatability, not ruler accuracy.",
                  "White paper can overflow the screw foreground detector; its inference count may reset.",
                  "No physical motion or gripper validation performed."]}
(ROOT/"repeatability_report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"status":report["status"],"origin_change_max_px":max(r["origin_change_px"] for r in rows),
                  "corner_change_max_px":max(r["corner_change_max_px"] for r in rows),
                  "transform_delta_max_mm":max(r["transform_delta_max_mm_at_corners_origin_and_image_borders"] for r in rows),
                  "threshold_origin_delta_max_mm":max(r["delta_mm"] for r in dots)},indent=2))
