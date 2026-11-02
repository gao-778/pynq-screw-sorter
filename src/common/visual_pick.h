#ifndef VISUAL_PICK_H
#define VISUAL_PICK_H
#include <math.h>

#define PICK_BASE_RISER_MM 100.0
#define PICK_PLATFORM_Z_MM 3.0
#define PICK_Z_MM (PICK_PLATFORM_Z_MM-PICK_BASE_RISER_MM)
#define PICK_CAMERA_BASE_Y_MM 150.0

#define PICK_COMMAND_X_TRIM_MM 1.0

#define PICK_COMMAND_Y_TRIM_MM 5.0

#define PICK_LOCAL_Y_START_MM (-10.0)
#define PICK_LOCAL_Y_FULL_MM (-30.0)
#define PICK_LOCAL_Y_MAX_MM (-4.0)
#define PICK_WRIST_SIGN (-1.0)
#define PICK_FRESH_MS 750U
#define PICK_POSITION_TOLERANCE_MM 2.0
#define PICK_AXIS_DOT_MIN 0.9659258262890683  

typedef struct {
    double x,y,dx,dy;  
    unsigned class_id,frame,captured_ms;
} VisualPickTarget;

static inline int visual_pick_target_valid(const VisualPickTarget *t)
{
    if(!t || !isfinite(t->x) || !isfinite(t->y) || !isfinite(t->dx) || !isfinite(t->dy))return 0;
    double norm=hypot(t->dx,t->dy);
    

    return fabs(t->x)<=100 && t->y>=80 && t->y<=230 && hypot(t->x,t->y)<=240 &&
           norm>0.99 && norm<1.01 && t->class_id<15;
}

static inline int visual_pick_same(const VisualPickTarget *a,const VisualPickTarget *b)
{
    return a->class_id==b->class_id && hypot(a->x-b->x,a->y-b->y)<=PICK_POSITION_TOLERANCE_MM &&
           fabs(a->dx*b->dx+a->dy*b->dy)>=PICK_AXIS_DOT_MIN;
}

static inline double visual_pick_local_y_offset_mm(double platform_y)
{
    if(platform_y>=PICK_LOCAL_Y_START_MM)return 0.0;
    if(platform_y<=PICK_LOCAL_Y_FULL_MM)return PICK_LOCAL_Y_MAX_MM;
    double u=(PICK_LOCAL_Y_START_MM-platform_y)/
             (PICK_LOCAL_Y_START_MM-PICK_LOCAL_Y_FULL_MM);
    return PICK_LOCAL_Y_MAX_MM*u*u*(3.0-2.0*u);
}

static inline int visual_pick_prepare_command(const VisualPickTarget *observation,
                                              VisualPickTarget *command)
{
    if(!command || command==observation || !visual_pick_target_valid(observation))return -1;
    VisualPickTarget corrected=*observation;
    double platform_y=observation->y-PICK_CAMERA_BASE_Y_MM-PICK_COMMAND_Y_TRIM_MM;
    corrected.y+=visual_pick_local_y_offset_mm(platform_y);
    if(!visual_pick_target_valid(&corrected))return -1;
    *command=corrected;
    return 0;
}
#endif
