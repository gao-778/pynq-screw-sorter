#ifndef VISUAL_PICK_H
#define VISUAL_PICK_H
#include <math.h>

/* On 2026-10-31 the user confirmed base (0,-150) mm relative to the NEW
 * black-dot origin fitted from the current 40/80/120 mm squares. The old
 * camera homography is not used in this coordinate system. Keep the measured
 * jaw command trims (+1 mm X, +5 mm Y) as separate mechanical compensation.
 * Translation only: retain the previously confirmed matching XY directions.
 * Jaw-to-jaw line at servo2=500 points along +Y for a front-facing arm.
 * User-confirmed physical wrist direction is opposite the previous SDK sign.
 * Reflect servo2 around its unchanged center; camera/robot XY axes stay intact.
 */
/* The physical base is raised 100 mm in total; camera and platform remain fixed.
 * Preserve robot-base coordinates and internal link dimensions. Convert the
 * platform-associated height once; negative robot Z is intentional. */
#define PICK_BASE_RISER_MM 100.0
#define PICK_PLATFORM_Z_MM 3.0
#define PICK_Z_MM (PICK_PLATFORM_Z_MM-PICK_BASE_RISER_MM)
#define PICK_CAMERA_BASE_Y_MM 150.0
/* Latest measured contact was 6 mm right of the screw center.
 * Reduce the former +7 mm X command trim by 6 mm, yielding +1 mm.
 * This is a fixed world-X correction, independent of screw orientation.
 * In the established base frame +X points right when viewed from behind.
 * Correct only the motion command; displayed camera coordinates stay intact. */
#define PICK_COMMAND_X_TRIM_MM 1.0
/* User reports current picks are 25 mm short in Y (2026-10-29).
 * Add 25 to the previous -20 command trim: the new trim is +5 mm.
 * Geometric base translation stays +150; commanded Y=platform Y+155.
 * Apply once before path validation. Camera / HDMI coordinates stay unchanged. */
#define PICK_COMMAND_Y_TRIM_MM 5.0
/* Pick-only trial correction for the repeatable +Y landing bias in the lower
 * half. Keep observations, camera calibration and bin placement in their
 * existing coordinates. Apply only to a separate final motion-command copy.
 * The near-axis samples did not show the same bias; use a C1-continuous ramp. */
#define PICK_LOCAL_Y_START_MM (-10.0)
#define PICK_LOCAL_Y_FULL_MM (-30.0)
#define PICK_LOCAL_Y_MAX_MM (-4.0)
#define PICK_WRIST_SIGN (-1.0)
#define PICK_FRESH_MS 750U
#define PICK_POSITION_TOLERANCE_MM 2.0
#define PICK_AXIS_DOT_MIN 0.9659258262890683 /* 15 deg, modulo 180 deg */

typedef struct {
    double x,y,dx,dy; /* Robot-base mm and unit direction vector. */
    unsigned class_id,frame,captured_ms;
} VisualPickTarget;

static inline int visual_pick_target_valid(const VisualPickTarget *t)
{
    if(!t || !isfinite(t->x) || !isfinite(t->y) || !isfinite(t->dx) || !isfinite(t->dy))return 0;
    double norm=hypot(t->dx,t->dy);
    /* This is only the input envelope. The complete vertical path, including
     * joint margins and the return, must pass IK before any servo is driven. */
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

/* Input is an UNCORRECTED observation (platform XY plus the existing base
 * translation and global trims), never an earlier command. Keep the two
 * objects distinct so matching/removal checks cannot be changed in place.
 * Return 0 on success; leave output unchanged on error. No workspace clipping
 * or expanded limits: the corrected point and full IK must both remain valid. */
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
