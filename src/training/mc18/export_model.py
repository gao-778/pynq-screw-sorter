"""Project source and interface utilities."""
from settings import REPO_ROOT,TRAIN_OUTPUT,DATASET_INPUT
from pathlib import Path
from collections import defaultdict
import argparse,hashlib,importlib.util,json,re,shutil,struct,zlib
import numpy as np
import torch
from model_contract import ROOT,SPEC,CLASSES,Net,arrays,integer_features,metrics,widened_initialization,teacher_path
PROJECT=REPO_ROOT
DEST=PROJECT/'data/model';OUT=TRAIN_OUTPUT
def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf8')
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def publish():
    assert json.loads((ROOT/'label_mapping_status.json').read_text())['status'] in ['USER_CONFIRMED','ROOT_REVIEWED_ASSUMPTION']
    source=OUT/'training';report=json.loads((source/'selection_report.json').read_text());assert report['status']=='VALIDATION_FROZEN'
    assert report['changed_conv_weights']>0,'A copied widened CNN is not a trained expanded architecture'
    assert report['changed_conv_weights_from_joint_seed']>0 and report['selected']['stage']=='joint_qat'
    architecture=json.loads((PROJECT/'data/model/architecture_contract.json').read_text());assert architecture['cnn']['weights']==SPEC['weights'] and architecture['classes']==CLASSES
    checkpoint=torch.load(source/'selected_candidate.pt',map_location='cpu',weights_only=False);model=Net();model.load_state_dict(checkpoint['state_dict']);model.eval();w,b=arrays(model);s=np.asarray([6,6,6],np.int32)
    saved=np.load(source/'selected_candidate.npz');assert np.array_equal(w,saved['weights']) and np.array_equal(b,saved['biases'])
    old=np.load(teacher_path());initial=widened_initialization(old['weights'],old['biases']);initial_w,initial_b=arrays(initial)
    seed_w=initial_w.copy();kernel=seed_w[288+27648:288+27648+221184].reshape(256,96,3,3)
    for oc in range(128):
        for ic in range(0,96,8):
            for output,sign in [(oc,1),(oc+128,-1)]:
                if abs(int(kernel[output,ic,0,0]))<127 and abs(int(kernel[output,ic,2,2]))<127:
                    kernel[output,ic,0,0]+=sign;kernel[output,ic,2,2]-=sign
    changes={};wi=bi=0
    for i,(ni,no) in enumerate(zip(SPEC['channels'][:-1],SPEC['channels'][1:])):
        n=ni*no*9
        changes[f'conv{i}']=dict(weights=n,int8_changed_from_widened_teacher=int(np.sum(w[wi:wi+n]!=initial_w[wi:wi+n])),
            int8_changed_by_training_from_perturbed_seed=int(np.sum(w[wi:wi+n]!=seed_w[wi:wi+n])),
            max_int8_training_difference=int(np.abs(w[wi:wi+n].astype(np.int64)-seed_w[wi:wi+n]).max()),
            biases=no,int32_biases_changed=int(np.sum(b[bi:bi+no]!=initial_b[bi:bi+no])))
        wi+=n;bi+=no
    assert sum(v['int8_changed_by_training_from_perturbed_seed'] for v in changes.values())==report['changed_conv_weights_from_joint_seed']>0
    write(DEST/'weight_change_report.json',dict(status='ACTUAL_INTEGER_WEIGHT_CHANGES',layers=changes,
        latent_dither_note='Float bin-interior offsets alone are excluded; comparisons use exported int8 weights.'))
    spec=importlib.util.spec_from_file_location('mc18_independent_reference',DEST/'reference.py');ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
    data=np.load(OUT/'dataset_trainval.npz');cases=[]
    for family in ['clean','pose','photo']:
        for domain in sorted(set(data['lighting'])):
            for cl in range(18):
                ii=np.flatnonzero((data['splits']=='val')&(data['family']==family)&(data['lighting']==domain)&(data['labels']==cl))
                if len(ii):cases.append(int(ii[0]))
    with torch.no_grad():
        for j,i in enumerate(cases):
            gold=ref.infer(data['images64'][i],data['geometry'][i],w,b,s);actual=model(torch.from_numpy(data['images64'][i:i+1]),torch.from_numpy(data['geometry'][i:i+1]),details=True)
            for key in ['conv_0','pool_0','conv_1','pool_1','conv_2','gap_deep','gap_middle','features']:
                assert np.array_equal(np.rint(actual[key][0].numpy()*128).astype(np.int64),gold[key]),(key,data['ids'][i])
            assert np.array_equal(np.rint(actual['logits'][0].numpy()*8192).astype(np.int64),gold['logits'])
            if j%30==0:print('INT64_VERIFY',j,len(cases),flush=True)
    np.savez(DEST/'quantized_model.npz',weights=w,biases=b,shifts=s,classes=np.asarray(CLASSES),channels=np.asarray(SPEC['channels']),dilations=np.asarray([2,2,2]))
    shutil.copy2(source/'selected_candidate.pt',DEST/'best_qat.pt');write(DEST/'classes.json',CLASSES)
    words=np.concatenate([w.astype(np.int64)&255,b.astype(np.int64)&0xffffffff,s.astype(np.int64)]).astype('<u4');payload=words.tobytes();crc=zlib.crc32(payload)
    binary=struct.pack('<4s5I',b'FNET',1,len(w),len(b),3,crc)+payload;(DEST/'model.bin').write_bytes(binary)
    for name,values,bits in [('weights.hex',w,8),('biases.hex',b,32),('shifts.hex',s,32)]:
        (DEST/name).write_text(''.join(f'{int(x)&((1<<bits)-1):0{bits//4}x}\n' for x in values),encoding='ascii')
    lines=['/* MC18: 15 screw classes and three nut size classes; FPGA integer CNN. */','#ifndef SCREW_OBB_MODEL_H','#define SCREW_OBB_MODEL_H','#include <stdint.h>',f'#define SCREW_MODEL_WEIGHT_COUNT {len(w)}',f'#define SCREW_MODEL_BIAS_COUNT {len(b)}','#define SCREW_MODEL_SHIFT_COUNT 3','#define SCREW_MODEL_HARDWARE_ID 0x4D433138U',f'static const uint32_t shape_model_words[{len(words)}] = {{']
    lines+=['    '+', '.join(f'0x{int(v):08x}' for v in words[i:i+8])+',' for i in range(0,len(words),8)];lines+=['};','#endif',''];header='\n'.join(lines);(DEST/'shape_model.h').write_text(header,encoding='ascii')
    
    parsed=np.asarray([int(v,16) for v in re.findall(r'0x([0-9a-f]{8})',header.split('{',1)[1])],dtype='<u4');assert np.array_equal(parsed,words)
    assert np.array_equal(np.frombuffer(binary[24:],dtype='<u4'),words) and struct.unpack('<4s5I',binary[:24])==(b'FNET',1,len(w),len(b),3,zlib.crc32(binary[24:]))
    for name,values,bits in [('weights.hex',w,8),('biases.hex',b,32),('shifts.hex',s,32)]:assert [int(x,16) for x in (DEST/name).read_text().split()]==[int(v)&((1<<bits)-1) for v in values]
    write(DEST/'export_verification.json',dict(status='PASS',independent_int64_cases=len(cases),case_ids=data['ids'][cases].tolist(),qat_intermediate_int64_exact=True,npz_hex_header_binary_exact=True,binary_crc32=f'{crc:08x}',model_sha256=sha(DEST/'model.bin'),hardware_board_tested=False))
    manifest=dict(format='FNET-v1',hardware_id='0x4D433138',hardware_name='MC18',weights=len(w),biases=len(b),shifts=3,trainable_parameters=SPEC['parameters'],model_sha256=sha(DEST/'model.bin'),class_names=CLASSES,channels=SPEC['channels'],dilation=[2,2,2],padding=[2,2,2],roi_size=64,features=355,feature_order=['deep_gap256','middle_gap96_prepool','geometry3'],gap_shifts=[8,10],shift_values=[6,6,6],native_image_size=[1280,960],threshold_contract='CENTER8_P90_SPREAD3_CLAMP40_220_V1',threshold_formula='histogram(gray[4::8,4::8]), T=clamp(P90+max(8,3*(P90-P50)),40,220)',roi_contract='inclusive AABB; ceil_sqrt(w*w+h*h); integer Q8 16-angle rotation; floor(u*side/64)-floor(side/2); same frame T for CCL/moments/geometry/mask; raw gray>>1; outside AABB/image=0',geometry='sat127(projected_length>>1), sat127(2*max_end_width), sat127(2*min_end_width); horizontal supported triples',bias_base='0xE800',shift_base='0xEF00',weight_port='0x0070',requires='MC18 hardware with 18-class high bit ABI; older 15-class bitstreams are incompatible',test_status='FROZEN; test ROI evaluation not yet performed')
    write(DEST/'model_manifest.json',manifest);write(DEST/'training_report.json',report)
    write(DEST/'export_marker.json',dict(status='FROZEN_EXPORTED',model_sha256=sha(DEST/'model.bin'),checkpoint_sha256=sha(source/'selected_candidate.pt')))
    write(DEST/'artifact_hashes.json',{n:sha(DEST/n) for n in ['model.bin','quantized_model.npz','best_qat.pt','weights.hex','biases.hex','shifts.hex','shape_model.h','model_manifest.json','export_verification.json','reference.py','weight_change_report.json']})
    print('MODEL_EXPORTED',manifest['model_sha256'],flush=True)

def evaluate(device,batch):
    marker=json.loads((DEST/'export_marker.json').read_text());assert marker['model_sha256']==sha(DEST/'model.bin')
    output=OUT/'final_test_report.json';assert not output.exists(),'Test was already evaluated: do not tune on it'
    data=np.load(OUT/'dataset_test.npz');assert set(data['splits'])=={'test'}
    q=np.load(DEST/'quantized_model.npz');f=integer_features(data['images64'],data['geometry'],q['weights'],q['biases'],device,batch)
    logits=f@q['weights'][-18*355:].reshape(18,355).astype(np.int64).T+q['biases'][-18:];pred=logits.argmax(1);y=data['labels'];result={}
    for family in ['clean','pose','photo']:
        mask=data['family']==family
        result[family]=dict(overall=metrics(y[mask],pred[mask]),screws=metrics(y[mask&(y<15)],pred[mask&(y<15)]),nuts=metrics(y[mask&(y>=15)],pred[mask&(y>=15)]),domains={d:metrics(y[mask&(data['lighting']==d)],pred[mask&(data['lighting']==d)]) for d in sorted(set(data['lighting']))},conditions={c:metrics(y[mask&(data['condition']==c)],pred[mask&(data['condition']==c)]) for c in sorted(set(data['condition'][mask]))})
    np.savez(OUT/'test_predictions.npz',ids=data['ids'],labels=y,predictions=pred,logits=logits,lighting=data['lighting'],family=data['family'],condition=data['condition'])
    annotations=json.loads((OUT/'nut_annotations.json').read_text(encoding='utf8'));screening={}
    for domain in ['NUT_OLD','NUT_NEW']:
        for cl in ['NUT_L','NUT_M','NUT_S']:
            rows=[r for r in annotations if r['split']=='test' and r['lighting']==domain and r['class_name']==cl]
            candidate=sum(len(r['objects']) for r in rows);accepted=sum(o['accepted'] for r in rows for o in r['objects'])
            screening[f'{domain}/{cl}']=dict(frames=len(rows),candidates_after_area_and_border_gates=candidate,accepted_for_classification=accepted,rejected_after_candidates=candidate-accepted,early_rejected_components=sum(len(r['diagnostics']['rejected']) for r in rows),accepted_fraction=accepted/max(1,candidate))
    augmentation=defaultdict(lambda:dict(original_accepted_objects=0,matched_after_photometric_redetection=0,frames=0))
    for r in json.loads((OUT/'frame_augmentations_test.json').read_text(encoding='utf8')):
        cell=augmentation[f"{r['lighting']}/{CLASSES[r['class_id']]}/{r['condition']}"]
        cell['original_accepted_objects']+=r['original'];cell['matched_after_photometric_redetection']+=r['matched'];cell['frames']+=1
    for cell in augmentation.values():cell['matching_coverage']=cell['matched_after_photometric_redetection']/max(1,cell['original_accepted_objects'])
    old_coverage=DATASET_INPUT/'output/dataset_report_test.json'
    coverage=dict(nut_candidate_screening=screening,nut_photometric_matching=dict(augmentation),legacy_screw_screening=json.loads(old_coverage.read_text()),legacy_coverage_sha256=sha(old_coverage),limitation='Denominators are detected candidate components or preaccepted objects, not independently manually counted physical targets. Scenes may contain more than the runtime twelve-object display limit.')
    write(DEST/'test_coverage_report.json',coverage)
    report=dict(status='TEST_EVALUATED_AFTER_FREEZE',results=result,model_sha256=sha(DEST/'model.bin'),dataset_sha256=sha(OUT/'dataset_test.npz'),coverage_report_sha256=sha(DEST/'test_coverage_report.json'),old_test_disclosure='All legacy screw test partitions have been evaluated in prior development. Nut test scenes held out from this training, but visual quality audit covered thumbnails before split.',scope='Screened ROI classification only; not whole-frame detection recall or robot grasp success.')
    write(output,report);write(DEST/'test_report.json',report)
    print('TEST_RESULT',json.dumps({k:{g:result[k][g]['accuracy'] for g in ['overall','screws','nuts']} for k in result}),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--publish',action='store_true');p.add_argument('--evaluate',action='store_true');p.add_argument('--device',default='cpu');p.add_argument('--batch',type=int,default=64);a=p.parse_args()
    if a.publish:publish()
    if a.evaluate:evaluate(a.device,a.batch)
