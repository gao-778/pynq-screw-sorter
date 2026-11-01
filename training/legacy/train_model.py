"""Train/validation-only MC18 classifier; never opens test ROI data.

Start with exact integer widening, fit the 18-class head on cached features,
then jointly fine tune all convolutions with QAT and old-screw distillation.
"""
from pathlib import Path
from collections import Counter
import argparse,copy,hashlib,json,time
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F
from model_contract import ROOT,CLASSES,SPEC,Net,arrays,load_arrays,widened_initialization,integer_features,metrics,teacher_path
OUT=ROOT/'output';SEED=20261101

def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf8')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--device',default='cpu');ap.add_argument('--epochs',type=int,default=24);ap.add_argument('--batch',type=int,default=64)
    ap.add_argument('--min-epochs',type=int,default=3);ap.add_argument('--patience',type=int,default=2)
    ap.add_argument('--stop-after',type=int,default=0,help='Stop after this many complete epochs, retaining the original LR schedule horizon.')
    ap.add_argument('--teacher-weight',type=float,default=.7);ap.add_argument('--freeze-screw-head',action='store_true')
    ap.add_argument('--latent-dither',type=float,default=0)
    ap.add_argument('--conv-lr',type=float,default=3e-6);ap.add_argument('--head-lr',type=float,default=1e-6);ap.add_argument('--head-only',action='store_true');ap.add_argument('--resume-head',action='store_true');ap.add_argument('--fixed-screw-head',action='store_true');args=ap.parse_args()
    mapping=json.loads((ROOT/'label_mapping_status.json').read_text());assert mapping['status'] in ['USER_CONFIRMED','ROOT_REVIEWED_ASSUMPTION'], 'Formal training requires explicit mapping review'
    started=time.time();torch.manual_seed(SEED);rng=np.random.default_rng(SEED);device=torch.device(args.device)
    print('LABEL_MAPPING_STATUS',mapping['status'],mapping.get('basis'),flush=True)
    dest=OUT/'training';dest.mkdir(exist_ok=True)
    data=np.load(OUT/'dataset_trainval.npz');image=data['images64'];geo=data['geometry'];y=data['labels'];split=data['splits'];domain=data['lighting'];family=data['family'];condition=data['condition']
    assert not np.any(split=='test') and set(y)==set(range(18));train=np.flatnonzero(split=='train');val=np.flatnonzero(split=='val')
    old=teacher_path();legacy=np.load(old);model=widened_initialization(legacy['weights'],legacy['biases']);iw,ib=arrays(model)
    # The complete uint8 image tensor is ~454 MB; resident transfer avoids
    # per-minibatch WDDM host/device synchronization while retaining ALL data.
    image_t=torch.from_numpy(image).to(device);geo_t=torch.from_numpy(geo).to(device);labels=torch.from_numpy(y).to(device)
    cache=OUT/'initial_features.npy';identity=dict(dataset_sha256=sha(OUT/'dataset_trainval.npz'),teacher_sha256=sha(old),spec=SPEC)
    if cache.exists() and json.loads((OUT/'initial_features.json').read_text())==identity:features=np.load(cache)
    else:
        print('EXTRACT_INITIAL_FEATURES',len(y),args.device,flush=True)
        features=integer_features(image,geo,iw,ib,args.device,args.batch).astype(np.int16);np.save(cache,features);write(OUT/'initial_features.json',identity)
    teacher=features.astype(np.int64)@iw[-18*355:].reshape(18,355).astype(np.int64).T+ib[-18:]
    teacher=teacher[:,:15];teacher_t=torch.from_numpy(teacher.astype(np.float32)/8192).to(device)
    teacher_good=(y<15)&(teacher.argmax(1)==y)
    teacher_good_t=torch.tensor(teacher_good,device=device)
    def evaluation(pred):
        r={}
        for fam in ['clean','pose','photo']:
            ix=val[family[val]==fam]
            rr=dict(overall=metrics(y[ix],pred[ix]),screws=metrics(y[ix[y[ix]<15]],pred[ix[y[ix]<15]]),nuts=metrics(y[ix[y[ix]>=15]],pred[ix[y[ix]>=15]]))
            rr['domains']={dom:metrics(y[ix[domain[ix]==dom]],pred[ix[domain[ix]==dom]]) for dom in sorted(set(domain))}
            rr['conditions']={c:metrics(y[ix[condition[ix]==c]],pred[ix[condition[ix]==c]]) for c in sorted(set(condition[ix]))}
            r[fam]=rr
        return r
    baseline=evaluation(teacher.argmax(1));write(dest/'baseline_validation.json',baseline)
    def score(result):
        # Class macro-F1 prevents numerous old screw samples drowning new nuts.
        return float(sum(weight*result[fam]['overall']['macro_f1'] for fam,weight in [('clean',.4),('pose',.3),('photo',.3)]))
    def guards(result):
        failed=[]
        for fam in ['clean','pose','photo']:
            tol=.005 if fam!='photo' else .01
            for dom in ['OLD','YEW','WAY','H_W_WAY']:
                a=result[fam]['domains'][dom];b=baseline[fam]['domains'][dom]
                if a['count'] and a['accuracy']<b['accuracy']-tol:failed.append(f'{fam}/{dom}/accuracy')
            if result[fam]['nuts']['accuracy']<(.95 if fam!='photo' else .90):failed.append(f'{fam}/nuts/minimum')
        return failed
    sample_weights=np.zeros(len(y),np.float32);cells={}
    for fam,mass in [('clean',.4),('pose',.3),('photo',.3)]:
        for c in range(18):
            available=[dom for dom in sorted(set(domain)) if np.any((split=='train')&(family==fam)&(domain==dom)&(y==c))]
            assert available,(fam,c)
            for dom in available:
                ix=train[(family[train]==fam)&(domain[train]==dom)&(y[train]==c)];amount=mass/18/len(available)
                sample_weights[ix]=amount*len(train)/len(ix);cells[f'{fam}/{dom}/{CLASSES[c]}']=dict(count=len(ix),mass=amount)
    sample_weights*=len(train)/sample_weights[train].sum();write(dest/'sample_weights.json',cells)
    weights_t=torch.from_numpy(sample_weights).to(device)
    initial_state=copy.deepcopy(model.state_dict());model=model.to(device)
    best=None;best_state=None;history=[]
    def consider(stage,result,extra=None):
        nonlocal best,best_state
        row=dict(stage=stage,score=score(result),guard_failures=guards(result),results=result,elapsed_seconds=time.time()-started,**(extra or {}));row['eligible']=not row['guard_failures'];history.append(row)
        if row['eligible'] and (best is None or row['score']>best['score']):
            best=row;best_state={k:v.detach().cpu().clone() for k,v in model.state_dict().items()};torch.save(dict(state_dict=best_state,spec=SPEC,classes=CLASSES,selection=row),dest/'best_guarded.pt')
        torch.save(dict(state_dict={k:v.detach().cpu() for k,v in model.state_dict().items()},spec=SPEC,classes=CLASSES,selection=row),dest/'latest.pt')
        write(dest/'progress.json',dict(status='TRAINING',latest=row,selected=best,history=history))
        print('PROGRESS',stage,extra,'score',round(row['score'],5),'guard',row['eligible'],'fails',row['guard_failures'],'clean',round(result['clean']['overall']['accuracy'],4),'nuts',round(result['clean']['nuts']['accuracy'],4),'elapsed',round(time.time()-started),flush=True)
        return row
    def eval_model():
        pred=torch.zeros(len(y),dtype=torch.long,device=device);model.eval()
        with torch.no_grad():
            for start in range(0,len(val),args.batch):
                ids=torch.as_tensor(val[start:start+args.batch],device=device);pred[ids]=model(image_t[ids],geo_t[ids]).argmax(1)
        return evaluation(pred.cpu().numpy())
    if args.resume_head:
        head_checkpoint=dest/'head_selected.pt'
        if not head_checkpoint.exists():head_checkpoint=ROOT/'reproducibility_inputs/head_selected.pt'
        ckpt=torch.load(head_checkpoint,weights_only=False,map_location='cpu');model.load_state_dict(ckpt['state_dict']);consider('resume_head',eval_model())
    else:
        # Train only head using features that exactly correspond to widened
        # fixed convolutions. Floating optimization is quantized before scoring.
        mean=features[train].mean(0);std=features[train].std(0);std[std<1e-6]=1
        # Standardize raw integer features during convex fitting, then undo
        # normalization and quantize the ENTIRE head with one shared scale.
        # Independent clipping of oversized floating weights corrupts logits.
        feat=torch.tensor((features[train]-mean)/std,dtype=torch.float64,device=device);yy=labels[train].to(device);ww=weights_t[train].to(device,dtype=torch.float64)
        head=nn.Linear(355,18,dtype=torch.float64).to(device)
        oldw=iw[-18*355:].reshape(18,355).astype(np.float64);oldb=ib[-18:].astype(np.float64)
        oldscore=features[train].astype(np.float64)@oldw[:15].T+oldb[:15]
        oldscale=max(1e-9,float(np.std(oldscore-oldscore.mean(1,keepdims=True))))
        selected_any=None;selected_any_state=None
        for strength in ([] if args.fixed_screw_head else [0.01,0.03,0.1,0.3]):
            with torch.no_grad():head.weight.zero_();head.bias.zero_()
            optimizer=torch.optim.LBFGS(head.parameters(),lr=1,max_iter=140,line_search_fn='strong_wolfe')
            def closure():
                optimizer.zero_grad();logits=head(feat)
                ce=F.cross_entropy(logits,yy,reduction='none')
                loss=(ce*ww).sum()/ww.sum()+head.weight.square().sum()/(2*strength*len(train))
                loss.backward();return loss
            optimizer.step(closure)
            rw=head.weight.detach().cpu().numpy()/std;rb=head.bias.detach().cpu().numpy()-rw@mean
            scores=features[train].astype(np.float64)@rw[:15].T+rb[:15]
            scale=oldscale/max(1e-9,float(np.std(scores-scores.mean(1,keepdims=True))));rw*=scale;rb*=scale
            for fraction in [.5,.75,1.0]:
                mixed=(1-fraction)*oldw+fraction*rw;bias=(1-fraction)*oldb+fraction*rb
                qscale=126/max(1e-9,float(np.abs(mixed).max()));qw=np.rint(mixed*qscale).astype(np.int8);qb=np.rint(bias*qscale).astype(np.int32)
                with torch.no_grad():model.fc.weight.copy_(torch.tensor(qw.astype(np.float32)/64,device=device));model.fc.bias.copy_(torch.tensor(qb.astype(np.float32)/8192,device=device))
                pred=(features.astype(np.int64)@qw.astype(np.int64).T+qb).argmax(1)
                row=consider('head_fit',evaluation(pred),dict(C=strength,fraction=fraction,qscale=qscale))
                if selected_any is None or row['score']>selected_any['score']:
                    selected_any=row;selected_any_state={k:v.detach().cpu().clone() for k,v in model.state_dict().items()}
        # Incremental alternative: retain the established screw discriminants,
        # fit only three new nut rows against ALL eighteen competing logits.
        # This avoids unnecessary refitting of already accurate screw classes.
        for temperature in [256.,512.,1024.]:
            nuthead=nn.Linear(355,3,dtype=torch.float64).to(device)
            with torch.no_grad():nuthead.weight.zero_();nuthead.bias.zero_()
            screw_logits=torch.tensor(teacher[train]/temperature,dtype=torch.float64,device=device)
            optimizer=torch.optim.LBFGS(nuthead.parameters(),lr=1,max_iter=180,line_search_fn='strong_wolfe')
            def incremental_closure():
                optimizer.zero_grad();logits=torch.cat([screw_logits,nuthead(feat)],dim=1)
                loss=(F.cross_entropy(logits,yy,reduction='none')*ww).sum()/ww.sum()+nuthead.weight.square().sum()/(2*.1*len(train))
                loss.backward();return loss
            optimizer.step(incremental_closure)
            nw=nuthead.weight.detach().cpu().numpy()/std;nb=nuthead.bias.detach().cpu().numpy()-nw@mean
            mixed=oldw.copy();bias=oldb.copy();mixed[15:]=nw*temperature;bias[15:]=nb*temperature
            qscale=min(1.,126/max(1e-9,float(np.abs(mixed).max())));qw=np.rint(mixed*qscale).astype(np.int8);qb=np.rint(bias*qscale).astype(np.int32)
            with torch.no_grad():model.fc.weight.copy_(torch.tensor(qw.astype(np.float32)/64,device=device));model.fc.bias.copy_(torch.tensor(qb.astype(np.float32)/8192,device=device))
            pred=(features.astype(np.int64)@qw.astype(np.int64).T+qb).argmax(1)
            row=consider('incremental_nut_head',evaluation(pred),dict(temperature=temperature,qscale=qscale))
            if selected_any is None or row['score']>selected_any['score']:
                selected_any=row;selected_any_state={k:v.detach().cpu().clone() for k,v in model.state_dict().items()}
        model.load_state_dict(best_state if best_state is not None else selected_any_state)
        torch.save(dict(state_dict={k:v.detach().cpu() for k,v in model.state_dict().items()},spec=SPEC,classes=CLASSES),dest/'head_selected.pt')
        del feat,yy,ww,head
        if device.type=='cuda':torch.cuda.empty_cache()
    if not args.head_only:
        head_selection=copy.deepcopy(best)
        head_score=head_selection['score'] if head_selection is not None else score(eval_model())
        # Distinct deep channels must learn different filters instead of
        # remaining redundant replicas. Paired integer perturbations have zero
        # DC per kernel and opposite signs across the copied output pair.
        ww,bb=arrays(model);joint_seed=ww.copy();kernel=joint_seed[288+27648:288+27648+221184].reshape(256,96,3,3)
        for oc in range(128):
            for ic in range(0,96,8):
                for output,sign in [(oc,1),(oc+128,-1)]:
                    if abs(int(kernel[output,ic,0,0]))<127 and abs(int(kernel[output,ic,2,2]))<127:
                        kernel[output,ic,0,0]+=sign;kernel[output,ic,2,2]-=sign
        load_arrays(model,joint_seed,bb)
        # A fake-quant latent weight may lie anywhere within its quantization
        # bin. Deterministic bin-interior offsets preserve EVERY initial int8
        # weight, but permit small learning rates to cross a boundary without
        # first accumulating many epochs from the exact bin center.
        if args.latent_dither:
            assert 0<args.latent_dither<.5
            latent_rng=np.random.default_rng(SEED+1)
            with torch.no_grad():
                for layer in model.convs:
                    delta=latent_rng.uniform(-args.latent_dither,args.latent_dither,tuple(layer.weight.shape)).astype(np.float32)/64
                    layer.weight.add_(torch.from_numpy(delta).to(device))
            assert np.array_equal(arrays(model)[0],joint_seed),'Latent dither changed the initial integer model'
        write(dest/'symmetry_break.json',dict(changed_weights=int(np.sum(ww!=joint_seed)),seed=SEED,method='deep paired-copy +/-1 integer units at opposite 3x3 taps, zero kernel DC',head_validation_score=head_score,perturbed_validation=eval_model()))
        # Preserve the head benchmark, but select a genuinely jointly trained
        # model under the original screw/nut validation guards.
        write(dest/'head_selection.json',dict(selected=head_selection,score=head_score))
        best=None;best_state=None
        optimizer=torch.optim.Adam([dict(params=model.convs.parameters(),lr=args.conv_lr),dict(params=model.fc.parameters(),lr=args.head_lr)])
        stale=0;progress=-1
        for epoch in range(1,args.epochs+1):
            epoch_started=time.time()
            model.train();order=torch.as_tensor(rng.permutation(train),device=device);total_loss=torch.zeros((),device=device)
            factor=1. if epoch<=args.epochs//2 else .35
            optimizer.param_groups[0]['lr']=args.conv_lr*factor;optimizer.param_groups[1]['lr']=args.head_lr*factor
            for start in range(0,len(order),args.batch):
                ids=order[start:start+args.batch];xx=image_t[ids];gg=geo_t[ids];yy=labels[ids];ww=weights_t[ids]
                logits=model(xx,gg)*16;ce=F.cross_entropy(logits,yy,reduction='none')
                kl=F.kl_div(F.log_softmax(logits[:,:15],dim=1),F.softmax(teacher_t[ids]*16,dim=1),reduction='none').sum(1)
                loss=((ce+args.teacher_weight*kl*teacher_good_t[ids])*ww).sum()/ww.sum()
                optimizer.zero_grad();loss.backward()
                if args.freeze_screw_head:
                    model.fc.weight.grad[:15].zero_();model.fc.bias.grad[:15].zero_()
                torch.nn.utils.clip_grad_norm_(model.parameters(),5);optimizer.step();total_loss+=loss.detach()*len(ids)
            result=eval_model()
            row=consider('joint_qat',result,dict(epoch=epoch,loss=float(total_loss/len(train)),epoch_seconds=time.time()-epoch_started))
            if row['score']>progress+1e-7:progress=row['score'];stale=0
            else:stale+=1
            if epoch>=args.min_epochs and stale>=args.patience:break
            if args.stop_after and epoch>=args.stop_after:break
    if best_state is None:
        write(dest/'selection_report.json',dict(status='NO_GUARD_PASS',history=history));raise RuntimeError('No validation-qualified model; do not publish')
    model.load_state_dict(best_state);w,b=arrays(model)
    np.savez(dest/'selected_candidate.npz',weights=w,biases=b,shifts=np.array([6,6,6],np.int32),classes=np.array(CLASSES),channels=np.array(SPEC['channels']),dilation=np.array([2,2,2]))
    torch.save(dict(state_dict=best_state,spec=SPEC,classes=CLASSES,selection=best),dest/'selected_candidate.pt')
    write(dest/'selection_report.json',dict(status='VALIDATION_FROZEN',spec=SPEC,classes=CLASSES,selected=best,history=history,seed=SEED,device=str(device),torch=torch.__version__,tf32=False,half=False,dataset_sha256=sha(OUT/'dataset_trainval.npz'),teacher_sha256=sha(old),mapping_sha256=sha(ROOT/'label_mapping_status.json'),test_used=False,elapsed_seconds=time.time()-started,changed_conv_weights=int(np.sum(w[:-18*355]!=iw[:-18*355])),changed_conv_weights_from_joint_seed=int(np.sum(w[:-18*355]!=joint_seed[:-18*355])) if not args.head_only else 0,command_args=vars(args)))
    print('MODEL_VALIDATION_FROZEN',best['score'],flush=True)

if __name__=='__main__':main()
