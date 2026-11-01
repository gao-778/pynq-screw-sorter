#ifndef ARM_KINEMATICS_H
#define ARM_KINEMATICS_H

#include <stdint.h>
#include "visual_pick.h"

/* Robot-base millimetres. These modes do not accept visual coordinates. */
#define ARM_MODE_FRONT 1U
#define ARM_MODE_NINE 2U
#define ARM_PLAN_CAPACITY 384U
#define ARM_FEEDBACK_UPPER_PERCENT 120U
/* 90-degree terminal approach: perpendicular to the horizontal platform.
 * Retain the existing ARM_VERTICAL_* identifiers for source compatibility. */
#define ARM_VERTICAL_PITCH_DEG (-90.0)
#define ARM_VERTICAL_PREGRASP_Z_MM (13.0-PICK_BASE_RISER_MM)
#define ARM_VERTICAL_TRANSPORT_Z_MM 100.0
/* Experimental: remove additional software margin, retaining protocol bounds. */
#define ARM_VERTICAL_JOINT_MARGIN_RAW 0
/* Visual requests only. Near-table descent/lift and phase-boundary feedback
 * checks remain unchanged; transport interiors have no added dwell.
 * Geometry subdivision and initial HOME keep the original reference steps.
 * Transport/orientation uses 121 percent of the original speed ceiling,
 * exactly 10 percent above the preceding 110-percent release. Acceleration
 * limits stay unchanged. Only a successful profile shortens end dwell.
 * Opening/releasing restores the original 800+80 ms after an observed S1
 * release arrival error at 730+60 ms. CLOSE also retains 800+80 ms. */
#define ARM_VISUAL_MIN_TRANSPORT_MS 220U
#define ARM_VISUAL_REFERENCE_STEP_MS 300U
#define ARM_VISUAL_ARM_STEP_RAW 80U
#define ARM_VISUAL_WRIST_STEP_RAW 60U
#define ARM_VISUAL_TRANSPORT_SPEED_PERCENT 121U
#define ARM_VISUAL_TRANSPORT_SETTLE_MS 60U
#define ARM_VISUAL_GRIPPER_OPEN_MS 800U
#define ARM_VISUAL_GRIPPER_OPEN_SETTLE_MS 80U
/* Host-checked discrete transport reference only. These do not claim the
 * servo's internal velocity/acceleration response, and do not alter geometry. */
#define ARM_VISUAL_PROFILE_MIN_MS 100U
#define ARM_VISUAL_ARM_ACCEL_RAW_S2 400.0
#define ARM_VISUAL_WRIST_ACCEL_RAW_S2 300.0
/* Fallbacks preserve target XY, pick height and vertical descent. */
#define ARM_VISUAL_SUBDIVIDE_MAX_DEPTH 8U
#define ARM_VISUAL_HIGH_ALIGN_Z_MM 13.0

enum ArmPhase {
    ARM_PHASE_HOME,
    ARM_PHASE_OPEN,
    ARM_PHASE_APPROACH,
    ARM_PHASE_DESCEND,
    ARM_PHASE_CLOSE,
    ARM_PHASE_LIFT,
    ARM_PHASE_RETURN,
    ARM_PHASE_HOLD,
    ARM_PHASE_ORIENT,
    ARM_PHASE_RELEASE,
    ARM_PHASE_VERTICAL_ALIGN,
    ARM_PHASE_LEAVE_VERTICAL,
    /* Append only: existing diagnostic phase numbers remain unchanged. */
    ARM_PHASE_PLACE_APPROACH,
    ARM_PHASE_PLACE_ALIGN,
    ARM_PHASE_PLACE_DESCEND,
    ARM_PHASE_PLACE_RELEASE,
    ARM_PHASE_PLACE_LIFT,
    ARM_PHASE_PLACE_LEAVE,
    ARM_PHASE_PLACE_RETURN
};

typedef struct {
    uint8_t phase;
    uint8_t cycle;
    uint8_t mask; /* Bit n selects servo ID n; bit zero is always clear. */
    uint8_t hold;
    uint16_t duration_ms;
    uint16_t settle_ms;
    int16_t positions[7];
    double pose[4]; /* X/Y/Z millimetres, pitch degrees. */
} ArmAction;

int arm_position_allowed(unsigned servo_id, int position);
/* Feedback only: command lower bound, upper bound multiplied by 1.20.
 * IK and all MOVE commands must still use the 0..1000 protocol bounds. */
int arm_feedback_position_allowed(unsigned servo_id, int position);
int arm_ik_solve(const double xyz_mm[3], double pitch_deg, int16_t positions[7]);
int arm_plan_build(unsigned mode, ArmAction *actions, unsigned capacity,
                   unsigned *count);
const char *arm_phase_name(unsigned phase);
int arm_pick_wrist(const VisualPickTarget *target,double pitch_deg,int previous,int *position);
int arm_plan_build_visual(const VisualPickTarget *target,ArmAction *actions,unsigned capacity,unsigned *count);
/* Full pick/place/home plan, checked before the executor may send anything.
 * bin_index is 0..SORT_BIN_COUNT-1. Failure always leaves *count zero. */
int arm_plan_build_visual_place(const VisualPickTarget *target,unsigned bin_index,
                               ArmAction *actions,unsigned capacity,unsigned *count);
typedef struct {
    int result, original_result;
    unsigned route, phase, subdivisions;
    unsigned retimed_phases, profile_fallbacks;
} ArmVisualPlanDiagnostic;
/* Cached planner diagnostics only: route0 original,1 subdivided,2 high align. */
void arm_visual_plan_get_diagnostic(ArmVisualPlanDiagnostic *out);


/* Bounded, single-owner candidate comparison, not a global collision solver.
 * Costs are requested MOVE durations plus settle, not measured elapsed time. */
#define ARM_PLACE_ROUTE_COUNT 4U
enum ArmPlaceRoute {
    ARM_PLACE_ROUTE_VIA_HOME, ARM_PLACE_ROUTE_DIRECT,
    ARM_PLACE_ROUTE_OUTER_ARC, ARM_PLACE_ROUTE_HIGH_WAYPOINT
};
typedef struct {
    unsigned selected_route,candidates_checked,candidates_valid,valid_route_mask;
    unsigned baseline_cost_ms,selected_cost_ms,baseline_actions,selected_actions;
    unsigned route_cost_ms[ARM_PLACE_ROUTE_COUNT];
} ArmPlacePlanDiagnostic;
void arm_place_plan_get_diagnostic(ArmPlacePlanDiagnostic *out);

/* Drop-only attitude fallback. The vertical PICK constants above never
 * change. Try -90 first, then -85 ... -30, retaining the first complete
 * reachable drop/return path. Keep this separate from route diagnostics so
 * the existing route/cost ABI remains unchanged. */
#define ARM_PLACE_PITCH_COUNT 13U
typedef struct {
    double selected_pitch_deg;
    unsigned selected_valid,attempts,attempted_mask;
    int results[ARM_PLACE_PITCH_COUNT];
} ArmPlacePitchDiagnostic;
void arm_place_pitch_get_diagnostic(ArmPlacePitchDiagnostic *out);

#endif
