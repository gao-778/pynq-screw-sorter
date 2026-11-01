"""Freeze the best qualified completed epoch after an intentional run stop.

Does not inspect test data. A partially executed later epoch is never saved.
"""
from pathlib import Path
import argparse,hashlib,json,shutil
import numpy as np
import torch
from model_contract import ROOT,SPEC,CLASSES,Net,arrays,widened_initialization,teacher_path

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def freeze(minimum_completed=3):
    dest=ROOT/'output/training';progress=json.loads((dest/'progress.json').read_text())
    history=progress['history'];joint=[r for r in history if r['stage']=='joint_qat']
    assert len(joint)>=minimum_completed
    eligible=[r for r in joint if r['eligible'] and not r['guard_failures']]
    assert eligible,'Never substitute the untrained head for a joint CNN'
    selected=max(eligible,key=lambda x:x['score']);ck=torch.load(dest/'best_guarded.pt',map_location='cpu',weights_only=False)
    assert ck['selection']==selected
    model=Net();model.load_state_dict(ck['state_dict']);w,b=arrays(model)
    old=np.load(teacher_path());initial=widened_initialization(old['weights'],old['biases']);iw,ib=arrays(initial)
    seed=iw.copy();kernel=seed[288+27648:288+27648+221184].reshape(256,96,3,3)
    for oc in range(128):
        for ic in range(0,96,8):
            for output,sign in [(oc,1),(oc+128,-1)]:
                if abs(int(kernel[output,ic,0,0]))<127 and abs(int(kernel[output,ic,2,2]))<127:
                    kernel[output,ic,0,0]+=sign;kernel[output,ic,2,2]-=sign
    changed=int(np.sum(w[:-18*355]!=seed[:-18*355]));assert changed>0
    np.savez(dest/'selected_candidate.npz',weights=w,biases=b,shifts=np.array([6,6,6],np.int32),classes=np.array(CLASSES),channels=np.array(SPEC['channels']),dilation=np.array([2,2,2]))
    shutil.copy2(dest/'best_guarded.pt',dest/'selected_candidate.pt')
    report=dict(status='VALIDATION_FROZEN',spec=SPEC,classes=CLASSES,selected=selected,history=history,
        seed=20261101,device='cpu',torch=torch.__version__,tf32=False,half=False,
        dataset_sha256=sha(ROOT/'output/dataset_trainval.npz'),teacher_sha256=sha(teacher_path()),
        mapping_sha256=sha(ROOT/'label_mapping_status.json'),test_used=False,
        changed_conv_weights=int(np.sum(w[:-18*355]!=iw[:-18*355])),changed_conv_weights_from_joint_seed=changed,
        elapsed_seconds=joint[-1]['elapsed_seconds'],
        stop_reason='Three complete fine-tuning epochs reviewed; freeze the best original-guard-passing joint model, discard any incomplete later epoch.',
        command_args=dict(device='cpu',batch=64,epochs=8,min_epochs=3,patience=2,resume_head=True,conv_lr=.000001,head_lr=.000001,teacher_weight=3,freeze_screw_head=True,latent_dither=.45),
        freeze_source_checkpoint_sha256=sha(dest/'best_guarded.pt'),freeze_source_progress_sha256=sha(dest/'progress.json'))
    (dest/'selection_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print('VALIDATION_FROZEN',selected['epoch'],selected['score'],changed)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--minimum-completed',type=int,default=3);args=p.parse_args();freeze(args.minimum_completed)
