"""Project source and interface utilities."""

from pathlib import Path
import math
import numpy as np
from PIL import Image
import cv2

COS_Q8 = np.array([256,251,237,212,181,143,98,50,0,-50,-98,-143,-181,-212,-237,-251], dtype=np.int64)
SIN_Q8 = np.array([0,50,98,143,181,212,237,251,256,251,237,212,181,143,98,50], dtype=np.int64)
COS2_Q8 = np.array([256,237,181,98,0,-98,-181,-237,-256,-237,-181,-98,0,98,181,237], dtype=np.int64)
SIN2_Q8 = np.array([0,98,181,237,256,237,181,98,0,-98,-181,-237,-256,-237,-181,-98], dtype=np.int64)


def load_gray(path):
    arr = np.asarray(Image.open(Path(path)).convert('RGB'), dtype=np.uint16)
    
    
    if np.array_equal(arr[...,0],arr[...,1]) and np.array_equal(arr[...,0],arr[...,2]):
        return arr[...,0].astype(np.uint8)
    return ((arr[...,0]>>2)+(arr[...,1]>>1)+(arr[...,2]>>2)).astype(np.uint8)


def foreground(gray, threshold=120, bright=True):
    return gray > threshold if bright else gray < threshold


def supported_foreground(gray, threshold=120, bright=True):

    raw = foreground(gray, threshold, bright)
    mask = np.zeros_like(raw)
    if raw.shape[1] >= 3:
        mask[:, 1:-1] = raw[:, :-2] & raw[:, 1:-1] & raw[:, 2:]
    return mask


def components(gray, threshold=120, bright=True, min_area=100, min_short=8):

    mask = foreground(gray,threshold,bright)
    pad = np.pad(mask,((1,0),(1,1)))
    left = pad[1:,:-2]; ul=pad[:-1,:-2]; up=pad[:-1,1:-1]; ur=pad[:-1,2:]
    provisional = int((mask & ~left & ~ul & ~up & ~ur).sum())
    n, labels, stats, _ = cv2.connectedComponentsWithStatsWithAlgorithm(mask.astype(np.uint8),8,cv2.CV_32S,cv2.CCL_WU)
    h,w=gray.shape; result=[]; rejected=[]
    for label in range(1,n):
        x,y,bw,bh,area = map(int,stats[label])
        if area < min_area: continue
        box=[x,y,x+bw-1,y+bh-1]
        reason = 'short_side' if min(bw,bh)<min_short else ('frame_border' if x==0 or y==0 or x+bw==w or y+bh==h else None)
        item={'label':label,'aabb_xyxy':box,'area':area}
        if reason: rejected.append({**item,'reason':reason})
        else: result.append(item)
    return result, {'provisional_labels':provisional,'overflow':provisional>=1024,'rejected':rejected,'total_components':n-1}


def orientation(gray, box, threshold=120, bright=True):
    xmin,ymin,xmax,ymax=map(int,box); cx=(xmin+xmax)>>1;cy=(ymin+ymax)>>1
    yy,xx=np.nonzero(supported_foreground(gray[ymin:ymax+1,xmin:xmax+1],threshold,bright))
    dx=xx.astype(np.int64)+xmin-cx;dy=yy.astype(np.int64)+ymin-cy
    mxx=int(np.sum(dx*dx));myy=int(np.sum(dy*dy));mxy=int(np.sum(dx*dy))
    scores=(mxx-myy)*COS2_Q8+(2*mxy)*SIN2_Q8
    
    angle=int(np.argmax(scores))
    return angle, {'mxx':mxx,'myy':myy,'mxy':mxy,'scores':scores.tolist()}


def safe_side(box):
    xmin,ymin,xmax,ymax=map(int,box);w=xmax-xmin+1;h=ymax-ymin+1
    ss=w*w+h*h;root=math.isqrt(ss)
    return root if root*root==ss else root+1


def roi_obb_rtl(gray,box,area,angle_index=None,threshold=120,bright=True):

    xmin,ymin,xmax,ymax=map(int,box);width=xmax-xmin+1;height=ymax-ymin+1
    side=safe_side(box);cx=(xmin+xmax)>>1;cy=(ymin+ymax)>>1
    angle,mom=orientation(gray,box,threshold,bright) if angle_index is None else (int(angle_index)&15,{})
    c=int(COS_Q8[angle]);s=int(SIN_Q8[angle])
    local=(np.arange(32,dtype=np.int64)*side>>5)-(side>>1)
    lx,ly=np.meshgrid(local,local)
    sx=cx+((lx*c-ly*s)>>8);sy=cy+((lx*s+ly*c)>>8)
    valid=(sx>=0)&(sx<gray.shape[1])&(sy>=0)&(sy<gray.shape[0])
    out=np.zeros((32,32),dtype=np.uint8);out[valid]=gray[sy[valid],sx[valid]]>>1
    geom=np.array([min(127,min(width,height)>>2),min(127,side>>2),min(127,int(area)>>4)],dtype=np.uint8)
    return out[None],geom, {'angle_index':angle,'angle_deg':angle*11.25,'side':side,'center':[cx,cy],**mom}


def projected_bounds(gray,box,angle_index,threshold=120,bright=True):

    xmin,ymin,xmax,ymax=map(int,box);cx=(xmin+xmax)>>1;cy=(ymin+ymax)>>1
    yy,xx=np.nonzero(supported_foreground(gray[ymin:ymax+1,xmin:xmax+1],threshold,bright))
    dx=xx.astype(np.int64)+xmin-cx;dy=yy.astype(np.int64)+ymin-cy
    c=int(COS_Q8[angle_index]);s=int(SIN_Q8[angle_index])
    px=(dx*c+dy*s)>>8;py=(-dx*s+dy*c)>>8
    return [int(px.min()),int(py.min()),int(px.max()),int(py.max())] if len(px) else [0,0,0,0]
