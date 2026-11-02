"""Project source and interface utilities."""

from pathlib import Path
from collections import Counter, defaultdict
import argparse, hashlib, json, sys, time
import numpy as np
import cv2
from PIL import Image, ImageDraw

sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from settings import DATASET_INPUT,REPO_ROOT
ROOT=DATASET_INPUT
sys.path.insert(0,str(Path(__file__).resolve().parent))
from auto_obb_reference import load_gray,components,orientation,projected_bounds,safe_side,COS_Q8,SIN_Q8
from shape_obb_reference import shape_geometry,roi_obb_rtl
from adaptive_threshold_reference import adaptive_threshold,CONTRACT_ID
from photometric_source import photometric,iou
OUT=ROOT/'output'
SEED=20261027
STRESS={'gain080':{'gain':.8},'gain115':{'gain':1.15},'gamma090':{'gamma':.9},'gamma110':{'gamma':1.1},'shade080':{'shade':.8,'angle':.7},'noise150':{'noise':1.5}}
cv2.setNumThreads(1)

def crop_pair(gray,box,area,threshold,angle_index=None):
    small,geom,meta=roi_obb_rtl(gray,box,area,angle_index=angle_index,threshold=threshold)
    x0,y0,x1,y1=map(int,box);cx=(x0+x1)>>1;cy=(y0+y1)>>1
    side=safe_side(box);a=meta['angle_index'];c=int(COS_Q8[a]);s=int(SIN_Q8[a])
    local=(np.arange(64,dtype=np.int64)*side>>6)-(side>>1)
    lx,ly=np.meshgrid(local,local);sx=cx+((lx*c-ly*s)>>8);sy=cy+((lx*s+ly*c)>>8)
    valid=(sx>=x0)&(sx<=x1)&(sy>=y0)&(sy<=y1)&(sx>=0)&(sx<gray.shape[1])&(sy>=0)&(sy<gray.shape[0])
    raw=np.zeros((64,64),dtype=np.uint8);raw[valid]=gray[sy[valid],sx[valid]]
    large=np.where(raw>threshold,raw>>1,0).astype(np.uint8)[None]
    assert np.array_equal(large[:,::2,::2],small),'32/64 sampling contract diverged'
    return small,large,geom,meta

def scan(row):
    gray=load_gray(row['source']);assert gray.shape==(960,1280)
    assert hashlib.sha256(gray.tobytes()).hexdigest()==row['sha256']
    threshold=adaptive_threshold(gray)
    candidates,diag=components(gray,threshold,True,400,10)
    for o in candidates:
        box=o['aabb_xyxy'];a,_=orientation(gray,box,threshold);bounds=projected_bounds(gray,box,a,threshold)
        x0,y0,x1,y1=box
        o.update(angle_index=a,bounds=bounds,length=bounds[2]-bounds[0]+1,width=bounds[3]-bounds[1]+1,
                 foreign_pixels=int((gray[y0:y1+1,x0:x1+1]>threshold).sum())-o['area'])
    return dict(row,threshold=threshold,diagnostics=diag,objects=candidates)

def screen(row,medians):
    m=medians[row['class_name']]
    for o in row['objects']:
        reasons=[]
        if row['diagnostics']['overflow']:reasons.append('provisional_label_overflow')
        if o['area']<m[0]*.48 or o['length']<m[1]*.65:reasons.append('fragment_or_incomplete')
        if o['area']>m[0]*1.7 or o['width']>m[2]*1.65 or o['length']>m[1]*1.35:reasons.append('possible_touching_or_merged')
        if o['foreign_pixels']>max(30,o['area']*.05):reasons.append('another_object_inside_aabb')
        o.update(accepted=not reasons,reasons=reasons)
    return row

def match(gray,original,threshold):
    candidates,diag=components(gray,threshold,True,400,10)
    reasons=Counter();matched=[];used=set()
    if diag['overflow']:return [],dict(original=len(original),matched=0,overflow=True,reasons={'overflow':len(original)})
    for index,obj in enumerate(original):
        scores=[iou(obj['aabb_xyxy'],c['aabb_xyxy']) if k not in used else -1 for k,c in enumerate(candidates)]
        if not scores or max(scores)<.65:reasons['no_unique_iou065_match']+=1;continue
        k=int(np.argmax(scores));c=candidates[k];used.add(k);x0,y0,x1,y1=c['aabb_xyxy']
        foreign=int((gray[y0:y1+1,x0:x1+1]>threshold).sum())-c['area']
        if foreign>max(30,c['area']*.05):reasons['foreign_foreground']+=1;continue
        if not .55<=c['area']/obj['area']<=1.6:reasons['area_change']+=1;continue
        if any(iou(c['aabb_xyxy'],other['aabb_xyxy'])>.10 for j,other in enumerate(original) if j!=index):reasons['overlap_other']+=1;continue
        matched.append((index,c))
    return matched,dict(original=len(original),matched=len(matched),overflow=False,reasons=dict(reasons))

def training_parameters(rng):
    return [dict(gain=float(rng.uniform(.80,1.18)),gamma=float(rng.uniform(.92,1.12)),offset=float(rng.uniform(-2,2)),noise=float(rng.uniform(.3,1.3))),
            dict(gain=float(rng.uniform(.95,1.10)),shade=float(rng.uniform(.78,.96)),angle=float(rng.uniform(0,2*np.pi)),highlight=float(rng.uniform(0,5)),spot=rng.uniform(.2,.8,2).tolist(),noise=.8)]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--test',action='store_true');args=parser.parse_args()
    if args.test:
        folder=REPO_ROOT/'data/model'
        marker=json.loads((folder/'model_manifest.json').read_text(encoding='utf-8'))
        assert marker['model_sha256']==hashlib.sha256((folder/'model.bin').read_bytes()).hexdigest()
    OUT.mkdir(exist_ok=True);(OUT/'previews').mkdir(exist_ok=True)
    manifest=json.loads((ROOT/'inputs/fixed_split_manifest.json').read_text(encoding='utf-8'))
    requested=['test'] if args.test else ['train','val']
    records=[r for r in manifest['records'] if r['split'] in requested]
    annotations=[];t0=time.time()
    for k,r in enumerate(records):
        annotations.append(scan(r))
        if k%100==0:print('SCAN',k,len(records),'elapsed',round(time.time()-t0),flush=True)
    if args.test:medians=json.loads((OUT/'shape_medians.json').read_text())
    else:
        medians={name:np.median([[o['area'],o['length'],o['width']] for r in annotations if r['split']=='train' and r['class_name']==name for o in r['objects']],axis=0).tolist() for name in manifest['classes']}
        (OUT/'shape_medians.json').write_text(json.dumps(medians,indent=2))
    annotations=[screen(r,medians) for r in annotations]
    keys=['images32','images64','geometry','labels','splits','ids','lighting','scene_groups','family','condition','thresholds']
    arrays={k:[] for k in keys};frame_reports=[];preview_counts=Counter();rng=np.random.default_rng(SEED)
    def append(gray,o,row,threshold,split,family,condition,suffix,angle=None):
        small,large,geo,meta=crop_pair(gray,o['aabb_xyxy'],o['area'],threshold,angle)
        values=dict(images32=small,images64=large,geometry=geo,labels=row['class_id'],splits=split,
                    ids=row['image']+'#'+suffix,lighting=row['lighting'],scene_groups=row['scene_group'],family=family,condition=condition,thresholds=threshold)
        for key,value in values.items():arrays[key].append(value)
        return meta
    for fi,row in enumerate(annotations):
        gray=load_gray(row['source']);threshold=row['threshold'];original=[o for o in row['objects'] if o['accepted']]
        for oi,o in enumerate(original):
            meta=append(gray,o,row,threshold,row['split'],'clean','clean',str(oi))
            
            for delta,dx,dy in [(-1,-1,1),(1,1,-1)]:
                b=o['aabb_xyxy'];shifted=dict(o,aabb_xyxy=[b[0]+dx,b[1]+dy,b[2]+dx,b[3]+dy])
                append(gray,shifted,row,threshold,row['split'],'pose','pose',f'{oi}_a{delta}',(meta['angle_index']+delta)&15)
        variants={f'random{k}':p for k,p in enumerate(training_parameters(rng))} if row['split']=='train' else STRESS
        for j,(name,p) in enumerate(variants.items()):
            seed=SEED+int(row['sha256'][:8],16)+j
            photo=photometric(gray,p,seed);photo_t=adaptive_threshold(photo);matches,diag=match(photo,original,photo_t)
            frame_reports.append(dict(image=row['image'],lighting=row['lighting'],class_id=row['class_id'],split=row['split'],condition=name,threshold=photo_t,parameters=p,seed=seed,**diag))
            for oi,o in matches:append(photo,o,row,photo_t,row['split'],'photo',name,f'{oi}_{name}')
        cell=(row['lighting'],row['class_name'])
        if preview_counts[cell]<2:
            preview_counts[cell]+=1;im=Image.fromarray(gray).convert('RGB');draw=ImageDraw.Draw(im)
            for o in row['objects']:draw.rectangle(o['aabb_xyxy'],outline=(170,120,235) if o['accepted'] else (240,160,40),width=3)
            draw.text((12,12),f"{row['class_name']} {row['lighting']} T={threshold}",fill='white');im.thumbnail((640,480));im.save(OUT/'previews'/f"{row['image']}.jpg")
        if fi%50==0:print('CROP_AUG',fi,len(annotations),'samples',len(arrays['labels']),'elapsed',round(time.time()-t0),flush=True)
    arrays={k:np.stack(v) if k in ['images32','images64','geometry'] else np.asarray(v) for k,v in arrays.items()}
    arrays['labels']=arrays['labels'].astype(np.int64);arrays['thresholds']=arrays['thresholds'].astype(np.uint8)
    tag='test' if args.test else 'trainval'
    np.savez_compressed(OUT/f'dataset_{tag}.npz',**arrays)
    (OUT/f'annotations_{tag}.json').write_text(json.dumps(annotations,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/f'frame_augmentations_{tag}.json').write_text(json.dumps(frame_reports,ensure_ascii=False,indent=2),encoding='utf-8')
    cells={}
    for split in requested:
        for domain in manifest['sources']:
            for name in manifest['classes']:
                rows=[r for r in annotations if r['split']==split and r['lighting']==domain and r['class_name']==name]
                objects=[o for r in rows for o in r['objects']]
                cells[f'{split}/{domain}/{name}']=dict(images=len(rows),candidates=len(objects),accepted=sum(o['accepted'] for o in objects),rejection_reasons=dict(Counter(reason for o in objects for reason in o['reasons'])))
    coverage={}
    for split in requested:
        for domain in manifest['sources']:
            for condition in sorted({r['condition'] for r in frame_reports if r['split']==split}):
                rows=[r for r in frame_reports if r['split']==split and r['lighting']==domain and r['condition']==condition]
                n=sum(r['original'] for r in rows);m=sum(r['matched'] for r in rows)
                coverage[f'{split}/{domain}/{condition}']=dict(frames=len(rows),original=n,matched=m,coverage=m/max(1,n),overflow_frames=sum(r['overflow'] for r in rows),reasons=dict(sum((Counter(r['reasons']) for r in rows),Counter())))
    report=dict(status='READY',split_manifest_sha256=hashlib.sha256((ROOT/'inputs/fixed_split_manifest.json').read_bytes()).hexdigest(),threshold_contract=CONTRACT_ID,
                threshold_reference_sha256=hashlib.sha256((Path(__file__).resolve().parent/'adaptive_threshold_reference.py').read_bytes()).hexdigest(),classes=manifest['classes'],
                sample_counts=dict(Counter(f'{s}/{f}' for s,f in zip(arrays['splits'],arrays['family']))),cells=cells,photometric_coverage=coverage,
                paired_roi_exact=True,raw_gray_preserved=True,test_opened=args.test,shape_medians_from_train_only=medians,
                limitation='Automatic single-class-folder annotations, screening and matched photometric ROIs; not manually audited end-to-end detection truth.',
                stress_conditions=STRESS,elapsed_seconds=time.time()-t0)
    (OUT/f'dataset_report_{tag}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('DATASET_READY',tag,json.dumps(report['sample_counts']),'seconds',round(time.time()-t0),flush=True)

if __name__=='__main__':main()
