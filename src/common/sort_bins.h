#ifndef SORT_BINS_H
#define SORT_BINS_H

#include <math.h>
#include "visual_pick.h"

#define SORT_BIN_COUNT 4U
#define SORT_BIN_SINGLE_PICK 0U  
#define SORT_BIN_CLASS_PICK 1U   

typedef struct {
    double x_mm, y_mm, release_z_mm;
} SortBin;

static const SortBin sort_bins[SORT_BIN_COUNT] = {
    {-130.0,  100.0, 60.0},
    { 130.0,  100.0, 60.0},
    {-130.0, -170.0, 60.0},
    { 130.0, -170.0, 60.0}
};

#define SORT_BIN_PRE_RELEASE_CLEARANCE_MM 10.0
#define SORT_BIN_VERTICAL_STEP_MM 5.0

static inline int sort_bin_robot_pose(unsigned bin_index,double pose[4])
{
    if(!pose || bin_index>=SORT_BIN_COUNT)return -1;
    const SortBin *bin=&sort_bins[bin_index];
    if(!isfinite(bin->x_mm) || !isfinite(bin->y_mm) ||
       !isfinite(bin->release_z_mm) || bin->release_z_mm<0.0 ||
       !(SORT_BIN_PRE_RELEASE_CLEARANCE_MM>0.0) ||
       !(SORT_BIN_VERTICAL_STEP_MM>0.0))return -1;
    pose[0]=bin->x_mm+PICK_COMMAND_X_TRIM_MM;
    pose[1]=bin->y_mm+PICK_CAMERA_BASE_Y_MM+PICK_COMMAND_Y_TRIM_MM;
    pose[2]=bin->release_z_mm-PICK_BASE_RISER_MM;
    pose[3]=-90.0;
    return 0;
}

#endif
