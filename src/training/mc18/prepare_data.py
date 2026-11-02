"""Project source and interface utilities."""

from settings import REPO_ROOT,TRAIN_OUTPUT,DATASET_INPUT
from pathlib import Path
from collections import Counter, defaultdict
import argparse, hashlib, json, sys
import numpy as np
import cv2
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parent
LEGACY=DATASET_INPUT
sys.path.insert(0,str(LEGACY/'scripts'))
sys.path.insert(0,str(LEGACY/'support'))
sys.path.insert(0,str(ROOT/'reproducibility_inputs/legacy'))
from auto_obb_reference import load_gray, orientation, projected_bounds, COS_Q8, SIN_Q8
from prepare_dataset import crop_pair, match, training_parameters, STRESS
from photometric_source import photometric
from adaptive_threshold_reference import adaptive_threshold
SEED=20261101
OUT=TRAIN_OUTPUT;OUT.mkdir(exist_ok=True)

def write(p,obj):p.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def initialize():
    source=json.loads((LEGACY/'inputs/fixed_split_manifest.json').read_text(encoding='utf8'))
    classes=source['classes']+['NUT_L','NUT_M','NUT_S']
    rows=json.loads((ROOT/'nut_scan.json').read_text(encoding='utf8'))
    usable=[r for r in rows if not r['frame_rejected']]
    parent=list(range(len(usable)))
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for cn in classes[15:]:
        ids=[i for i,r in enumerate(usable) if r['class_name']==cn];vectors=[]
        for i in ids:
            gray=load_gray(usable[i]['source'])
            layout=cv2.resize((gray>np.median(gray)+20).astype(np.float32),(64,48),interpolation=cv2.INTER_AREA).ravel()
            vectors.append(layout/max(1e-9,np.linalg.norm(layout)))
        similarity=np.stack(vectors)@np.stack(vectors).T
        for j,k in zip(*np.where(np.triu(similarity,1)>=.90)):
            x,y=find(ids[j]),find(ids[k]);parent[y]=x
    groups=defaultdict(list)
    for i,row in enumerate(usable):groups[find(i)].append(row)
    rng=np.random.default_rng(SEED)
    
    
    strata=defaultdict(list)
    for key,group in groups.items():
        strata[(group[0]['class_name'],'+'.join(sorted({r['lighting'] for r in group})))].append(key)
    for (cn,dom),keys in sorted(strata.items()):
        keys=list(np.asarray(sorted(keys))[rng.permutation(len(keys))]);nv=max(1,round(len(keys)*.15));nt=nv
        assert len(keys)>nv+nt
        for index,key in enumerate(keys):
            split='val' if index<nv else 'test' if index<nv+nt else 'train'
            for row in groups[key]:row.update(split=split,scene_group=f'{cn}_scene_{key:04d}',class_id=classes.index(cn))
    for row in rows:
        if row['frame_rejected']:row.update(split='quarantine',scene_group=row['image'],class_id=classes.index(row['class_name']))
    medians={cn:np.median([[o['area'],o['length'],o['width']] for r in rows if r['split']=='train' and r['class_name']==cn for o in r['objects'] if o['length']/max(1,o['width'])<1.4],axis=0).tolist() for cn in classes[15:]}
    for row in rows:
        area,length,width=medians[row['class_name']]
        for o in row['objects']:
            reasons=[]
            if row['frame_rejected']:reasons.append(row['frame_reason'])
            if row['diagnostics']['overflow']:reasons.append('provisional_label_overflow')
            if o['area']<area*.35 or o['length']<length*.72 or o['width']<width*.72:reasons.append('fragment_or_incomplete')
            if o['area']>area*1.70 or o['length']>length*1.28 or o['width']>width*1.28 or o['length']/max(1,o['width'])>1.35:reasons.append('touching_or_merged')
            if o['foreign_pixels']>max(30,o['area']*.05):reasons.append('foreign_foreground_inside_crop')
            x0,y0,x1,y1=o['aabb_xyxy'];cx=(x0+x1)>>1;cy=(y0+y1)>>1
            left,top,right,bottom=o['bounds'];c=COS_Q8[o['angle_index']]/256.;s=SIN_Q8[o['angle_index']]/256.
            if any(not(0<=cx+px*c-py*s<1280 and 0<=cy+px*s+py*c<960) for px,py in [(left,top),(right,top),(right,bottom),(left,bottom)]):reasons.append('oriented_rectangle_outside_frame')
            o.update(accepted=not reasons,reasons=reasons)
    write(ROOT/'classes.json',classes)
    write(OUT/'nut_annotations.json',rows)
    write(OUT/'nut_shape_medians.json',medians)
    all_records=source['records']+[dict((k,r[k]) for k in ['image','source','lighting','class_name','class_id','sha256','scene_group','split']) for r in rows]
    assert len({r['sha256'] for r in all_records if r['split']=='train'}&{r['sha256'] for r in all_records if r['split'] in ['val','test']})==0
    write(OUT/'fixed_split_manifest.json',dict(classes=classes,seed=SEED,records=all_records,inherited_screw_manifest_sha256=sha(LEGACY/'inputs/fixed_split_manifest.json'),nut_grouping='same class, 64x48 foreground-layout cosine>=0.90, connected groups; class/domain stratified 70/15/15; two hand frames quarantined',old_test_disclosure='Legacy screw test partitions have been used in prior model development.',nut_label_mapping={'old/B':'NUT_L','new/L':'NUT_L','old/M':'NUT_M','new/M':'NUT_M','old/S':'NUT_S','new/S':'NUT_S'}))
    labels=OUT/'labels_obb';labels.mkdir(exist_ok=True)
    for row in rows:
        lines=[]
        for o in row['objects']:
            if not o['accepted']:continue
            x0,y0,x1,y1=o['aabb_xyxy'];cx=(x0+x1)>>1;cy=(y0+y1)>>1
            l,t,r,b=o['bounds'];c=COS_Q8[o['angle_index']]/256.;s=SIN_Q8[o['angle_index']]/256.
            corners=[(cx+px*c-py*s,cy+px*s+py*c) for px,py in [(l,t),(r,t),(r,b),(l,b)]]
            assert all(0<=x<1280 and 0<=y<960 for x,y in corners)
            lines.append(str(row['class_id'])+' '+' '.join(f'{v:.8f}' for x,y in corners for v in (x/1280,y/960)))
        (labels/(row['image']+'.txt')).write_text('\n'.join(lines)+('\n' if lines else ''),encoding='ascii')
    counts={}
    for split in ['train','val','test','quarantine']:
        for domain in ['NUT_OLD','NUT_NEW']:
            for cn in classes[15:]:
                rr=[r for r in rows if r['split']==split and r['lighting']==domain and r['class_name']==cn]
                counts[f'{split}/{domain}/{cn}']=dict(images=len(rr),groups=len({r['scene_group'] for r in rr}),accepted=sum(o['accepted'] for r in rr for o in r['objects']),rejected=dict(Counter(reason for r in rr for o in r['objects'] for reason in o['reasons'])))
    write(OUT/'nut_screening_report.json',dict(status='SCREENED_AND_GROUPED',counts=counts,train_only_medians=medians,annotated_corners='YOLO OBB normalized x/y, integer OBB angle and supported foreground projected bounds',visual_review='All 332 source thumbnails reviewed. NEW_S CAM00106/CAM00107 excluded for hand occlusion; component screening rejects touching/fragmented/crop-polluted objects. Folder labels are not independent per-object ground truth.'))

def dataset(test=False):
    if test:
        model=REPO_ROOT/'data/model'
        marker=json.loads((model/'export_marker.json').read_text())
        assert marker['status']=='FROZEN_EXPORTED' and marker['model_sha256']==sha(model/'model.bin')
    rows=json.loads((OUT/'nut_annotations.json').read_text(encoding='utf8'))
    requested=['test'] if test else ['train','val'];rows=[r for r in rows if r['split'] in requested]
    keys=['images32','images64','geometry','labels','splits','ids','lighting','scene_groups','family','condition','thresholds']
    data={k:[] for k in keys};reports=[];rng=np.random.default_rng(SEED)
    def append(gray,obj,row,threshold,family,condition,suffix,angle=None):
        small,large,geo,meta=crop_pair(gray,obj['aabb_xyxy'],obj['area'],threshold,angle)
        values=dict(images32=small,images64=large,geometry=geo,labels=row['class_id'],splits=row['split'],ids=row['image']+'#'+suffix,lighting=row['lighting'],scene_groups=row['scene_group'],family=family,condition=condition,thresholds=threshold)
        for k,v in values.items():data[k].append(v)
        return meta
    for row in rows:
        gray=load_gray(row['source']);assert hashlib.sha256(gray.tobytes()).hexdigest()==row['sha256']
        original=[o for o in row['objects'] if o['accepted']];threshold=row['threshold']
        for oi,o in enumerate(original):
            meta=append(gray,o,row,threshold,'clean','clean',str(oi))
            for delta,dx,dy in [(-1,-1,1),(1,1,-1)]:
                b=o['aabb_xyxy'];shifted=dict(o,aabb_xyxy=[b[0]+dx,b[1]+dy,b[2]+dx,b[3]+dy]);append(gray,shifted,row,threshold,'pose','pose',f'{oi}_a{delta}',(meta['angle_index']+delta)&15)
        variants={f'random{k}':v for k,v in enumerate(training_parameters(rng))} if row['split']=='train' else STRESS
        for index,(name,param) in enumerate(variants.items()):
            seed=SEED+int(row['sha256'][:8],16)+index;photo=photometric(gray,param,seed);photo_t=adaptive_threshold(photo);matched,diag=match(photo,original,photo_t)
            reports.append(dict(image=row['image'],lighting=row['lighting'],class_id=row['class_id'],split=row['split'],condition=name,threshold=photo_t,parameters=param,seed=seed,**diag))
            for oi,obj in matched:append(photo,obj,row,photo_t,'photo',name,f'{oi}_{name}')
    tag='test' if test else 'trainval';prior=LEGACY/'output'/f'dataset_{tag}.npz'
    previous=np.load(prior)
    merged={}
    for k,v in data.items():
        arr=np.stack(v) if k in ['images32','images64','geometry'] else np.asarray(v)
        if k=='labels':arr=arr.astype(np.int64)
        if k=='thresholds':arr=arr.astype(np.uint8)
        merged[k]=np.concatenate([previous[k],arr])
    np.savez_compressed(OUT/f'dataset_{tag}.npz',**merged)
    write(OUT/f'frame_augmentations_{tag}.json',reports)
    mapping=json.loads((ROOT/'label_mapping_status.json').read_text())
    write(OUT/f'dataset_report_{tag}.json',dict(status='READY' if mapping['status'] in ['USER_CONFIRMED','ROOT_REVIEWED_ASSUMPTION'] else 'CANDIDATE_LABEL_MAPPING_PENDING',label_mapping_status=mapping['status'],parent_dataset_sha256=sha(prior),dataset_sha256=sha(OUT/f'dataset_{tag}.npz'),split_manifest_sha256=sha(OUT/'fixed_split_manifest.json'),sample_counts=dict(Counter(f'{s}/{f}' for s,f in zip(merged['splits'],merged['family']))),class_counts=dict(Counter(map(int,merged['labels']))),new_nut_images=len(rows),augmentation_failures=dict(Counter(reason for r in reports for reason in r['reasons'])),limitation='Classification ROI evaluation only, not full-frame detection recall. Test is not used for selection.'))
    print('DATASET_READY',tag,len(merged['labels']),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--initialize',action='store_true');p.add_argument('--test',action='store_true');a=p.parse_args()
    if a.initialize:initialize()
    dataset(a.test)
