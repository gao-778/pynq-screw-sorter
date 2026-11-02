"""Project source and interface utilities."""
import numpy as np
CHANNELS=(1,32,96,256)
DILATIONS=(2,2,2)
ROI_SIZE=64
FEATURE_COUNT=355
CLASSES=18
WEIGHT_COUNT=255510
BIAS_COUNT=402

def conv_relu(image,weight,bias,shift):
    _,height,width=image.shape
    padded=np.pad(np.asarray(image,dtype=np.int64),((0,0),(2,2),(2,2)))
    output=np.broadcast_to(bias[:,None,None],(len(bias),height,width)).copy().astype(np.int64)
    for ky in range(3):
        for kx in range(3):
            output+=np.einsum('oc,cyx->oyx',weight[:,:,ky,kx],padded[:,ky*2:ky*2+height,kx*2:kx*2+width])
    assert np.all(output>=-2**31) and np.all(output<2**31)
    return np.clip(output>>int(shift),0,127)

def maxpool(image):
    c,h,w=image.shape
    return image.reshape(c,h//2,2,w//2,2).max(axis=(2,4))

def infer(image,geometry,weights,biases,shifts):
    image=np.asarray(image,dtype=np.int64);geometry=np.asarray(geometry,dtype=np.int64)
    weights=np.asarray(weights,dtype=np.int64);biases=np.asarray(biases,dtype=np.int64)
    assert image.shape==(1,64,64) and geometry.shape==(3,)
    assert weights.shape==(WEIGHT_COUNT,) and biases.shape==(BIAS_COUNT,) and list(shifts)==[6,6,6]
    wi=bi=0;result={}
    for i,(ni,no) in enumerate(zip(CHANNELS[:-1],CHANNELS[1:])):
        n=ni*no*9;kernel=weights[wi:wi+n].reshape(no,ni,3,3)
        image=conv_relu(image,kernel,biases[bi:bi+no],shifts[i]);result[f'conv_{i}']=image.copy()
        if i==1:result['gap_middle']=image.sum((1,2))>>10
        if i<2:image=maxpool(image);result[f'pool_{i}']=image.copy()
        wi+=n;bi+=no
    result['gap_deep']=image.sum((1,2))>>8
    features=np.concatenate([result['gap_deep'],result['gap_middle'],geometry])
    logits=weights[wi:].reshape(CLASSES,FEATURE_COUNT)@features+biases[bi:]
    assert np.all(logits>=-2**31) and np.all(logits<2**31)
    result.update(features=features,logits=logits,class_id=int(np.argmax(logits)))
    return result
