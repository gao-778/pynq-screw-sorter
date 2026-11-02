"""Project source and interface utilities."""
import numpy as np
from auto_obb_reference import load_gray,components,orientation,COS_Q8,SIN_Q8,safe_side,projected_bounds,supported_foreground

def shape_geometry(gray,box,angle,threshold=120):
 x0,y0,x1,y1=map(int,box);cx=(x0+x1)>>1;cy=(y0+y1)>>1
 yy,xx=np.nonzero(supported_foreground(gray[y0:y1+1,x0:x1+1],threshold))
 dx=xx.astype(np.int64)+x0-cx;dy=yy.astype(np.int64)+y0-cy
 c=int(COS_Q8[angle]);s=int(SIN_Q8[angle]);lx=(dx*c+dy*s)>>8;ly=(-dx*s+dy*c)>>8
 if not len(lx):return np.zeros(3,dtype=np.uint8)
 lo=int(lx.min());hi=int(lx.max());length=hi-lo+1;quarter=max(1,length>>2)
 left=ly[lx<lo+quarter];right=ly[lx>hi-quarter]
 widths=[int(a.max()-a.min()+1) if len(a) else 0 for a in [left,right]]
 return np.array([min(127,length>>1),min(127,max(widths)*2),min(127,min(widths)*2)],dtype=np.uint8)

def roi_obb_rtl(gray,box,area,angle_index=None,threshold=120,bright=True):
 if not bright:raise ValueError('Current foreground model requires bright screws')
 x0,y0,x1,y1=map(int,box);cx=(x0+x1)>>1;cy=(y0+y1)>>1
 angle,mom=orientation(gray,box,threshold,True) if angle_index is None else (int(angle_index)&15,{})
 side=safe_side(box);c=int(COS_Q8[angle]);s=int(SIN_Q8[angle]);local=(np.arange(32,dtype=np.int64)*side>>5)-(side>>1)
 lx,ly=np.meshgrid(local,local);sx=cx+((lx*c-ly*s)>>8);sy=cy+((lx*s+ly*c)>>8)
 valid=(sx>=x0)&(sx<=x1)&(sy>=y0)&(sy<=y1)&(sx>=0)&(sx<gray.shape[1])&(sy>=0)&(sy<gray.shape[0]);raw=np.zeros((32,32),dtype=np.uint8);raw[valid]=gray[sy[valid],sx[valid]]
 out=np.where(raw>threshold,raw>>1,0).astype(np.uint8)
 geom=shape_geometry(gray,box,angle,threshold)
 return out[None],geom,{'angle_index':angle,'angle_deg':angle*11.25,'side':side,'center':[cx,cy],**mom}
