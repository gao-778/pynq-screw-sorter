"""Project source and interface utilities."""

import numpy as np

CONTRACT_ID='CENTER8_P90_SPREAD3_CLAMP40_220_V1'

def threshold_from_histogram(histogram):

    bins=np.asarray(histogram)
    if bins.shape!=(256,)or not np.issubdtype(bins.dtype,np.integer)or np.any(bins<0):
        raise ValueError('Expected 256 nonnegative integer histogram bins')
    total=sum(int(v)for v in bins)
    if total<=0:raise ValueError('Empty histogram')
    target50=(total+1)//2
    target90=(9*total+9)//10
    cumulative=0;p50=None;p90=None
    for level,count in enumerate(bins):
        cumulative+=int(count)
        if p50 is None and cumulative>=target50:p50=level
        if cumulative>=target90:p90=level;break
    raw=p90+max(8,3*(p90-p50))
    return min(220,max(40,raw)),p50,p90

def adaptive_threshold(gray):

    pixels=np.asarray(gray)
    if pixels.ndim!=2 or pixels.dtype!=np.uint8:
        raise ValueError('Expected uint8 HxW raw PL grayscale')
    sampled=pixels[4::8,4::8]
    if sampled.size==0:raise ValueError('Image has no center samples')
    histogram=np.bincount(sampled.ravel(),minlength=256)
    return threshold_from_histogram(histogram)[0]
