#ifndef PLATFORM_COORDINATES_H
#define PLATFORM_COORDINATES_H
#include "workstation_config.h"
#include "platform_calibration.h"
#include <math.h>
/* Positions use the current measured OBB center, including its local-bound offset.
   The FPGA still owns detection, orientation, classification and smoothing.
   CPU post-processing evaluates one planar transform per reported object. */
typedef struct {
    int x_tenth_mm,y_tenth_mm;
    unsigned class_id,valid;
    double axis_x,axis_y; /* Unit long axis in calibrated camera-plane mm, modulo pi. */
    unsigned axis_valid,captured_ms;
    /* Native-resolution display order; HDMI rotates both camera axes 180deg.
       The preview scales these coordinates uniformly by 3/4. */
    unsigned screen_x,screen_y;
} PlatformPosition;
static PlatformPosition coordinate_pending[REC_MAX_OBJECTS],coordinate_visible[REC_MAX_OBJECTS];
static unsigned coordinate_pending_count,coordinate_count;
static unsigned coordinate_pending_frame,coordinate_frame;
static unsigned coordinate_pending_version,coordinate_ready,coordinate_valid;
static unsigned coordinate_visible_version,coordinate_published_ms,coordinate_source_ms;
/* Empty frames need their own capture timestamp for post-pick verification. */
static unsigned coordinate_pending_source_ms,coordinate_visible_source_ms;
static const int coordinate_cos[16]={256,251,237,212,181,143,98,50,0,-50,-98,-143,-181,-212,-237,-251};
static const int coordinate_sin[16]={0,50,98,143,181,212,237,251,256,251,237,212,181,143,98,50};

static int coordinate_signed_bound(unsigned word){
    unsigned value=word>>16;
    return value>=32768U?(int)value-65536:(int)value;
}
static PlatformPosition coordinate_from_words(const unsigned words[6]){
    PlatformPosition p={0};p.class_id=recognition_word_class(words[5]);
    int left=(int)(words[0]&2047U),top=(int)(words[1]&2047U);
    int right=(int)(words[2]&2047U),bottom=(int)(words[3]&2047U);
    int umin=coordinate_signed_bound(words[0]),vmin=coordinate_signed_bound(words[1]);
    int umax=coordinate_signed_bound(words[2]),vmax=coordinate_signed_bound(words[3]);
    unsigned angle=(words[5]>>8)&15U;
    if(p.class_id>=REC_CLASS_COUNT || left>right || top>bottom || right>=1280 || bottom>=960 ||
       umin>umax || vmin>vmax || umin < -1600 || vmin < -1600 || umax>1600 || vmax>1600)return p;
    double x=(left+right)/2+(double)((umin+umax)*coordinate_cos[angle]-
                                  (vmin+vmax)*coordinate_sin[angle])/512.0;
    double y=(top+bottom)/2+(double)((umin+umax)*coordinate_sin[angle]+
                                   (vmin+vmax)*coordinate_cos[angle])/512.0;
    if(x<0 || x>1279 || y<0 || y>959)return p;
    double w=platform_h[6]*x+platform_h[7]*y+platform_h[8];
    if(w<0.1 || w>10.0)return p;
    double px=10.0*(platform_h[0]*x+platform_h[1]*y+platform_h[2])/w;
    double py=10.0*(platform_h[3]*x+platform_h[4]*y+platform_h[5])/w;
    if(px < -10000 || px>10000 || py < -10000 || py>10000)return p;
    p.x_tenth_mm=(int)(px+(px>=0?0.5:-0.5));
    p.y_tenth_mm=(int)(py+(py>=0?0.5:-0.5));
    p.valid=1;
    p.screen_x=(unsigned)(1279.0-x+0.5);
    p.screen_y=(unsigned)(959.0-y+0.5);
    p.captured_ms=coordinate_source_ms;
    double du=(umax-umin+1),dv=(vmax-vmin+1);
    double ax=coordinate_cos[angle]/256.0,ay=coordinate_sin[angle]/256.0;
    if(dv>du){double t=du;du=dv;dv=t;t=ax;ax=-ay;ay=t;}
    if(du>=8 && du>=1.3*dv){
        /* Transform two points, not the pixel angle: display is rotated and H
         * includes camera-plane perspective. Translation cancels in the vector. */
        double a=x-10*ax,b=y-10*ay,c=x+10*ax,d=y+10*ay;
        double w0=platform_h[6]*a+platform_h[7]*b+platform_h[8];
        double w1=platform_h[6]*c+platform_h[7]*d+platform_h[8];
        if(w0>0.1 && w1>0.1){
            double vx=(platform_h[0]*c+platform_h[1]*d+platform_h[2])/w1-
                      (platform_h[0]*a+platform_h[1]*b+platform_h[2])/w0;
            double vy=(platform_h[3]*c+platform_h[4]*d+platform_h[5])/w1-
                      (platform_h[3]*a+platform_h[4]*b+platform_h[5])/w0;
            double norm=hypot(vx,vy);
            if(isfinite(norm) && norm>0.01){p.axis_x=vx/norm;p.axis_y=vy/norm;p.axis_valid=1;}
        }
    }
    return p;
}
static void coordinate_invalidate(void){
    coordinate_ready=0;coordinate_valid=0;coordinate_count=0;
}
static void coordinate_begin(void){
    /* Capture the old scene version before launching inference. This also
       handles CPU/SD delays where display publication precedes CPU polling. */
    coordinate_pending_version=Xil_In32(0x43000004U);
}
static void coordinate_snapshot(unsigned count,unsigned frame){
    coordinate_pending_count=count>REC_MAX_OBJECTS?REC_MAX_OBJECTS:count;coordinate_pending_frame=frame;
    coordinate_pending_source_ms=coordinate_source_ms;
    for(unsigned n=0;n<coordinate_pending_count;++n){
        unsigned words[6];
        /* Display geometry may be filtered. Robot observations always use the
         * current frame's measured geometry under the same selected angle. */
        for(unsigned j=0;j<4;++j)words[j]=rec_read(0xf400+n*32+j*4);
        words[4]=rec_read(0xf000+n*64+16);
        words[5]=rec_read(0xf000+n*64+20);
        coordinate_pending[n]=coordinate_from_words(words);
    }
    coordinate_ready=1;
}
static void coordinate_publish(unsigned scene_version,unsigned scene_status){
    /* The renderer publishes a complete scene; launches are >=200 ms apart.
       A version change after launch therefore identifies this completed scene.
       The pending copy may be made before or after that publication. */
    if(coordinate_ready && scene_version!=coordinate_pending_version){
        coordinate_count=coordinate_pending_count;coordinate_frame=coordinate_pending_frame;
        coordinate_visible_source_ms=coordinate_pending_source_ms;
        for(unsigned n=0;n<coordinate_count;++n)coordinate_visible[n]=coordinate_pending[n];
        coordinate_valid=(scene_status&128U)!=0;coordinate_ready=0;
        coordinate_visible_version=scene_version;coordinate_published_ms=runtime_ms();
    }
    if(!(scene_status&128U)){coordinate_valid=0;coordinate_count=0;}
}
static void coordinate_format(char *text,unsigned size,int tenths){
    unsigned magnitude=(unsigned)(tenths<0?-tenths:tenths);
    snprintf(text,size,"%c%u.%u",tenths<0?'-':'+',magnitude/10,magnitude%10);
}
#endif
