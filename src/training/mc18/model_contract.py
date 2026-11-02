"""Project source and interface utilities."""
from settings import REPO_ROOT,TRAIN_OUTPUT,DATASET_INPUT
from pathlib import Path
import json
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

ROOT=Path(__file__).resolve().parent
CLASSES=json.loads((ROOT/'classes.json').read_text())
SPEC=dict(channels=[1,32,96,256],size=64,features=355,classes=18,weights=255510,biases=402,parameters=255912,dilation=[2,2,2],shifts=[6,6,6])
def teacher_path():
    pinned=ROOT/'reproducibility_inputs/teacher.npz'
    return pinned
torch.set_num_threads(4)
torch.backends.cuda.matmul.allow_tf32=False
torch.backends.cudnn.allow_tf32=False
torch.backends.cudnn.benchmark=False
torch.backends.cudnn.deterministic=True

class Net(nn.Module):
    def __init__(self):
        super().__init__();self.spec=SPEC
        self.convs=nn.ModuleList([nn.Conv2d(a,b,3,padding=2,dilation=2) for a,b in zip(SPEC['channels'][:-1],SPEC['channels'][1:])])
        self.fc=nn.Linear(355,18)
    @staticmethod
    def qw(w):return w+(torch.round(w*64).clamp(-128,127)/64-w).detach()
    @staticmethod
    def qb(b):return b+(torch.round(b*8192)/8192-b).detach()
    @staticmethod
    def qa(x):
        x=x.clamp(0,127/128);return x+(torch.floor(x*128)/128-x).detach()
    @staticmethod
    def gap(x):
        mean=x.mean((2,3));q=torch.floor((x*128).sum((2,3))/(x.shape[2]*x.shape[3]))/128
        return mean+(q-mean).detach()
    def forward(self,images,geometry,details=False):
        x=images.float()/128;result={};middle=None
        for i,layer in enumerate(self.convs):
            x=self.qa(F.conv2d(x,self.qw(layer.weight),self.qb(layer.bias),padding=2,dilation=2));result[f'conv_{i}']=x
            if i==1:middle=self.gap(x)
            if i<2:x=F.max_pool2d(x,2);result[f'pool_{i}']=x
        deep=self.gap(x);features=torch.cat([deep,middle,geometry.float()/128],dim=1)
        logits=F.linear(features,self.qw(self.fc.weight),self.qb(self.fc.bias))
        result.update(features=features,logits=logits,gap_middle=middle,gap_deep=deep)
        return result if details else logits

def arrays(model):
    layers=[*model.convs,model.fc]
    w=np.concatenate([np.clip(np.rint(l.weight.detach().cpu().numpy()*64),-128,127).astype(np.int8).ravel() for l in layers])
    b=np.concatenate([np.rint(l.bias.detach().cpu().numpy()*8192).astype(np.int32) for l in layers])
    assert len(w)==SPEC['weights'] and len(b)==SPEC['biases']
    return w,b

def load_arrays(model,w,b):
    wi=bi=0
    with torch.no_grad():
        for layer in [*model.convs,model.fc]:
            n=layer.weight.numel();m=layer.bias.numel()
            layer.weight.copy_(torch.from_numpy(w[wi:wi+n].reshape(layer.weight.shape).astype(np.float32)/64))
            layer.bias.copy_(torch.from_numpy(b[bi:bi+m].astype(np.float32)/8192));wi+=n;bi+=m
    assert wi==len(w) and bi==len(b)

def split_inputs(kernel,map_in):
    result=np.zeros((kernel.shape[0],len(map_in),*kernel.shape[2:]),dtype=np.int64)
    for source in range(kernel.shape[1]):
        copies=np.flatnonzero(map_in==source);original=kernel[:,source];q=original//len(copies);r=original-q*len(copies)
        for rank,dest in enumerate(copies):result[:,dest]=q+(rank<r)
    return result

def widened_initialization(w,b):

    old=[1,32,64,128];new=SPEC['channels'];wi=bi=0;kernels=[];bias=[]
    for i,(ni,no) in enumerate(zip(old[:-1],old[1:])):
        n=ni*no*9;k=w[wi:wi+n].reshape(no,ni,3,3).astype(np.int64);outmap=np.arange(new[i+1])%no
        k=split_inputs(k[outmap],np.arange(new[i])%ni);kernels.append(k.astype(np.int8));bias.append(b[bi:bi+no][outmap]);wi+=n;bi+=no
    oldhead=w[wi:].reshape(15,195).astype(np.int64);head=np.zeros((18,355),dtype=np.int64)
    head[:15,:256]=split_inputs(oldhead[:,:128],np.arange(256)%128)
    head[:15,256:352]=split_inputs(oldhead[:,128:192],np.arange(96)%64)
    head[:15,-3:]=oldhead[:,-3:]
    kernels.append(head.astype(np.int8));bias.append(np.concatenate([b[bi:],np.zeros(3,dtype=np.int32)]))
    model=Net();load_arrays(model,np.concatenate([k.ravel() for k in kernels]),np.concatenate(bias));return model

def integer_features(images,geometry,w,b,device='cpu',batch_size=64,details=False):

    output=[];last=None
    with torch.no_grad():
        for start in range(0,len(images),batch_size):
            x=torch.tensor(images[start:start+batch_size],dtype=torch.float32,device=device);wi=bi=0;intermediates={}
            for i,(ni,no) in enumerate(zip(SPEC['channels'][:-1],SPEC['channels'][1:])):
                n=ni*no*9;k=w[wi:wi+n].reshape(no,ni,3,3).astype(np.int64);bb=b[bi:bi+no].astype(np.int64)
                assert np.max(np.abs(k).sum((1,2,3))*127+np.abs(bb))<2**24
                x=F.conv2d(x,torch.tensor(k,dtype=torch.float32,device=device),torch.tensor(bb,dtype=torch.float32,device=device),padding=2,dilation=2)
                assert torch.equal(x,x.round())
                x=torch.floor(x/64).clamp(0,127);intermediates[f'conv_{i}']=x
                if i==1:middle=torch.floor(x.sum((2,3))/1024)
                if i<2:x=F.max_pool2d(x,2);intermediates[f'pool_{i}']=x
                wi+=n;bi+=no
            deep=torch.floor(x.sum((2,3))/256)
            features=torch.cat([deep,middle,torch.tensor(geometry[start:start+batch_size],dtype=torch.float32,device=device)],dim=1)
            output.append(features.cpu().numpy().astype(np.int64));last=intermediates
    return (np.concatenate(output),last) if details else np.concatenate(output)

def metrics(y,p,n=18):
    cm=np.zeros((n,n),dtype=np.int64);np.add.at(cm,(y,p),1);supported=cm.sum(1)>0
    recall=cm.diagonal()/np.maximum(1,cm.sum(1));f1=2*cm.diagonal()/np.maximum(1,cm.sum(0)+cm.sum(1))
    return dict(count=len(y),accuracy=float(np.mean(y==p)) if len(y) else None,macro_f1=float(f1[supported].mean()) if np.any(supported) else None,per_class_recall=recall.tolist(),confusion_matrix=cm.tolist())
