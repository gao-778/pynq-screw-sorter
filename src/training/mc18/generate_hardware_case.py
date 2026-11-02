"""Project source and interface utilities."""
from settings import REPO_ROOT,TRAIN_OUTPUT,DATASET_INPUT
from pathlib import Path
import hashlib,importlib.util,json
import numpy as np
from prepare_data import ROOT,OUT,load_gray,crop_pair,adaptive_threshold
MODEL=REPO_ROOT/'data/model'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert json.loads((MODEL/'export_marker.json').read_text())['model_sha256']==sha(MODEL/'model.bin')
refspec=importlib.util.spec_from_file_location('mc18_hardware_case_reference',MODEL/'reference.py')
ref=importlib.util.module_from_spec(refspec);refspec.loader.exec_module(ref)
q=np.load(MODEL/'quantized_model.npz')
rows=json.loads((OUT/'nut_annotations.json').read_text(encoding='utf8'))
row=next(r for r in rows if r['image']=='NUT_OLD_M_CAM00032')
assert row['split']=='val' and len(row['objects'])==5 and all(o['accepted'] for o in row['objects'])
gray=load_gray(row['source']);threshold=adaptive_threshold(gray);assert threshold==row['threshold']==46
images=[];geometries=[];logits=[];cases=[]
for obj in row['objects']:
    small,large,geometry,metadata=crop_pair(gray,obj['aabb_xyxy'],obj['area'],threshold)
    result=ref.infer(large,geometry,q['weights'],q['biases'],q['shifts'])
    pred=int(result['logits'].argmax())
    images.append(large);geometries.append(geometry);logits.append(result['logits'])
    cases.append(dict(aabb_xyxy=obj['aabb_xyxy'],area=obj['area'],angle_index=metadata['angle_index'],
                      geometry=geometry.tolist(),true_class_id=16,predicted_class_id=pred,logits=result['logits'].tolist()))
dest=OUT/'hardware_real_nut';dest.mkdir(exist_ok=True)
np.savez(dest/'case.npz',images64=np.stack(images),geometry=np.stack(geometries),logits=np.stack(logits),gray=gray)
report=dict(status='PASS' if all(c['predicted_class_id']==16 for c in cases) else 'MODEL_CLASSIFICATION_MISMATCH',
            source=row['source'],source_sha256=sha(Path(row['source'])),model_npz_sha256=sha(MODEL/'quantized_model.npz'),
            model_bin_sha256=sha(MODEL/'model.bin'),threshold=threshold,objects=cases,
            scope='Five real separated validation nuts. Independent integer reference. No labels injected into CNN output.')
(dest/'case.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf8')
print(json.dumps(report,ensure_ascii=True))
