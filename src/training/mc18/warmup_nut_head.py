"""Project source and interface utilities."""
from settings import REPO_ROOT,TRAIN_OUTPUT,DATASET_INPUT
from pathlib import Path
import copy,json,time,hashlib
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F
from model_contract import ROOT,Net,SPEC,CLASSES,arrays,widened_initialization,metrics,teacher_path

def write(p,r):p.write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8')
def main():
    assert json.loads((ROOT/'label_mapping_status.json').read_text())['status'] in ['USER_CONFIRMED','ROOT_REVIEWED_ASSUMPTION']
    out=TRAIN_OUTPUT;dest=out/'training';data=np.load(out/'dataset_trainval.npz');feat=np.load(out/'initial_features.npy')
    y=data['labels'];split=data['splits'];domain=data['lighting'];family=data['family'];train=np.flatnonzero(split=='train');val=np.flatnonzero(split=='val');assert not np.any(split=='test')
    prior=np.load(teacher_path());model=widened_initialization(prior['weights'],prior['biases']);iw,ib=arrays(model)
    ck=torch.load(dest/'head_selected.pt',weights_only=False,map_location='cpu');model.load_state_dict(ck['state_dict']);w,b=arrays(model)
    
    w[-18*355:-3*355]=iw[-18*355:-3*355];b[-18:-3]=ib[-18:-3]
    head=nn.Linear(355,3)
    with torch.no_grad():head.weight.copy_(torch.tensor(w[-3*355:].reshape(3,355).astype(np.float32)/64));head.bias.copy_(torch.tensor(b[-3:].astype(np.float32)/8192))
    xx=torch.tensor(feat,dtype=torch.float32)/128;yy=torch.tensor(y,dtype=torch.long)
    oldw=torch.tensor(iw[-18*355:].reshape(18,355)[:15].astype(np.float32)/64);oldb=torch.tensor(ib[-18:][:15].astype(np.float32)/8192)
    oldlogits=F.linear(xx,oldw,oldb)*16
    weights=np.zeros(len(y),np.float32)
    for fam,mass in [('clean',.4),('pose',.3),('photo',.3)]:
        for cl in range(18):
            domains=[d for d in sorted(set(domain)) if np.any((split=='train')&(family==fam)&(domain==d)&(y==cl))]
            for dom in domains:
                ids=train[(family[train]==fam)&(domain[train]==dom)&(y[train]==cl)];weights[ids]=mass/18/len(domains)*len(train)/len(ids)
    ww=torch.from_numpy(weights);rng=np.random.default_rng(20261101);torch.manual_seed(20261101)
    baseline=json.loads((dest/'baseline_validation.json').read_text())
    def evaluate():
        with torch.no_grad():
            qnew=F.linear(xx[val],Net.qw(head.weight),Net.qb(head.bias))*16;pred=torch.cat([oldlogits[val],qnew],dim=1).argmax(1).numpy()
        r={};failed=[]
        for fam in ['clean','pose','photo']:
            at=np.flatnonzero(family[val]==fam);ids=val[at]
            r[fam]=dict(overall=metrics(y[ids],pred[at]),nuts=metrics(y[ids[y[ids]>=15]],pred[at[y[ids]>=15]]),domains={})
            for dom in sorted(set(domain)):
                chosen=domain[ids]==dom;res=metrics(y[ids[chosen]],pred[at[chosen]]);r[fam]['domains'][dom]=res
                if dom in ['OLD','YEW','WAY','H_W_WAY'] and res['count'] and res['accuracy']<baseline[fam]['domains'][dom]['accuracy']-(.01 if fam=='photo' else .005):failed.append(f'{fam}/{dom}')
            if r[fam]['nuts']['accuracy']<(.9 if fam=='photo' else .95):failed.append(f'{fam}/nuts')
        score=sum(r[f]['overall']['macro_f1']*s for f,s in [('clean',.4),('pose',.3),('photo',.3)])
        return score,r,failed
    optimizer=torch.optim.Adam(head.parameters(),lr=.001);best=None;best_state=None;history=[];start=time.time()
    for epoch in range(1,41):
        optimizer.param_groups[0]['lr']=.001 if epoch<=20 else .0003
        order=rng.permutation(train)
        for offset in range(0,len(order),2048):
            ids=order[offset:offset+2048]
            new=F.linear(xx[ids],Net.qw(head.weight),Net.qb(head.bias))*16
            logits=torch.cat([oldlogits[ids],new],dim=1)
            loss=(F.cross_entropy(logits,yy[ids],reduction='none')*ww[ids]).sum()/ww[ids].sum()
            optimizer.zero_grad();loss.backward();optimizer.step()
            with torch.no_grad():head.weight.clamp_(-127/64,127/64)
        score,result,failed=evaluate();row=dict(epoch=epoch,score=score,results=result,guard_failures=failed,eligible=not failed,elapsed_seconds=time.time()-start);history.append(row)
        if best is None or ((not failed) and not best['eligible']) or ((not failed)==best['eligible'] and score>best['score']):best=row;best_state=copy.deepcopy(head.state_dict())
        write(dest/'nut_head_qat_progress.json',dict(status='TRAINING',latest=row,selected=best,history=history))
        print('HEAD_QAT',epoch,round(score,6),'clean',round(result['clean']['overall']['accuracy'],5),'nut',round(result['clean']['nuts']['accuracy'],5),'guard',not failed,failed,'seconds',round(time.time()-start),flush=True)
        if epoch>=15 and not failed and score>=.985:break
    head.load_state_dict(best_state)
    
    with torch.no_grad():
        model.fc.weight[:15].copy_(torch.tensor(iw[-18*355:].reshape(18,355)[:15].astype(np.float32)/64));model.fc.bias[:15].copy_(torch.tensor(ib[-18:][:15].astype(np.float32)/8192))
        model.fc.weight[15:].copy_(Net.qw(head.weight));model.fc.bias[15:].copy_(Net.qb(head.bias))
    torch.save(dict(state_dict=model.state_dict(),spec=SPEC,classes=CLASSES,selection=best),dest/'head_selected.pt')
    write(dest/'nut_head_qat_report.json',dict(status='WARMUP_COMPLETE',selected=best,history=history,old_fifteen_head_unchanged=True,only_train_val_used=True))
    print('NUT_HEAD_WARMUP_DONE',best['score'],best['guard_failures'],flush=True)
if __name__=='__main__':main()
