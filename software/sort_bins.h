#ifndef SORT_BINS_H
#define SORT_BINS_H

#include <math.h>
#include "visual_pick.h"

#define SORT_BIN_COUNT 4U
#define SORT_BIN_SINGLE_PICK 0U /* BIN1: upper left, selected single object */
#define SORT_BIN_CLASS_PICK 1U  /* BIN2: upper right, selected class batch */

/* User-specified sorting regions, in platform millimetres.
 * Platform XY: (-130,+100), (+130,+100), (-130,-170), (+130,-170).
 * Release Z is 60 mm above the platform, not above the raised arm base.
 * Original transforms, vertical pickup and full-path checks are retained.
 * Placement tries vertical first, then a validated tilted pose if necessary.
 * Keep class->slot assignment across all batches in one powered session.
 * Slots 0..3 show as B1..B4.
 * All drop configuration lives here; do not change camera/pick calibration.
 */
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

/* Apply the SAME platform->robot translation and command trims as a pick,
 * exactly once. The pick input envelope is intentionally not a bin envelope:
 * the bins are outside the image. Complete IK/path checks remain mandatory.
 */
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
