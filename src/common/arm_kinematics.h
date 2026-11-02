#ifndef ARM_KINEMATICS_H
#define ARM_KINEMATICS_H

#include <stdint.h>
#include "visual_pick.h"

 
#define ARM_MODE_FRONT 1U
#define ARM_MODE_NINE 2U
#define ARM_PLAN_CAPACITY 384U
#define ARM_FEEDBACK_UPPER_PERCENT 120U


#define ARM_VERTICAL_PITCH_DEG (-90.0)
#define ARM_VERTICAL_PREGRASP_Z_MM (13.0-PICK_BASE_RISER_MM)
#define ARM_VERTICAL_TRANSPORT_Z_MM 100.0
 
#define ARM_VERTICAL_JOINT_MARGIN_RAW 0

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
    uint8_t mask;  
    uint8_t hold;
    uint16_t duration_ms;
    uint16_t settle_ms;
    int16_t positions[7];
    double pose[4];  
} ArmAction;

int arm_position_allowed(unsigned servo_id, int position);


int arm_feedback_position_allowed(unsigned servo_id, int position);
int arm_ik_solve(const double xyz_mm[3], double pitch_deg, int16_t positions[7]);
int arm_plan_build(unsigned mode, ArmAction *actions, unsigned capacity,
                   unsigned *count);
const char *arm_phase_name(unsigned phase);
int arm_pick_wrist(const VisualPickTarget *target,double pitch_deg,int previous,int *position);
int arm_plan_build_visual(const VisualPickTarget *target,ArmAction *actions,unsigned capacity,unsigned *count);


int arm_plan_build_visual_place(const VisualPickTarget *target,unsigned bin_index,
                               ArmAction *actions,unsigned capacity,unsigned *count);
typedef struct {
    int result, original_result;
    unsigned route, phase, subdivisions;
    unsigned retimed_phases, profile_fallbacks;
} ArmVisualPlanDiagnostic;
 
void arm_visual_plan_get_diagnostic(ArmVisualPlanDiagnostic *out);

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

#define ARM_PLACE_PITCH_COUNT 13U
typedef struct {
    double selected_pitch_deg;
    unsigned selected_valid,attempts,attempted_mask;
    int results[ARM_PLACE_PITCH_COUNT];
} ArmPlacePitchDiagnostic;
void arm_place_pitch_get_diagnostic(ArmPlacePitchDiagnostic *out);

#endif
