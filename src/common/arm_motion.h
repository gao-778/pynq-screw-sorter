#ifndef ARM_MOTION_H
#define ARM_MOTION_H

#include <stdint.h>
#include "arm_kinematics.h"
#include "arm_bus.h"

#define ARM_VISUAL_HOME_MIN_MS 500U
#define ARM_VISUAL_SERVICE_WINDOW_US UINT64_C(30000)
#define ARM_INITIAL_REUSE_TOLERANCE_RAW 5U
#define ARM_INITIAL_REUSE_MAX_AGE_US UINT64_C(100000)

typedef struct ArmPickFeedback {
    unsigned valid, action_index, mask;
    double pose[4];
    int16_t commanded[7];
    int measured[7];
} ArmPickFeedback;

void arm_motion_init(void);
int arm_motion_start(unsigned mode, uint64_t now_us);
int arm_motion_start_visual(const VisualPickTarget *target,uint64_t now_us);
int arm_motion_start_visual_place(const VisualPickTarget *target,unsigned bin_index,uint64_t now_us);
void arm_motion_service(uint64_t now_us);
void arm_motion_cancel(void);
int arm_motion_busy(void);
int arm_motion_transport_busy(void);

int arm_motion_urgent(void);
const char *arm_motion_state_name(void);
const char *arm_motion_last_error(void);
const char *arm_motion_bus_error(void);
const char *arm_motion_phase_name(void);
unsigned arm_motion_cycle(void);
unsigned arm_motion_completed_actions(void);
unsigned arm_motion_action_count(void);

unsigned arm_motion_skipped_initial_actions(void);
unsigned arm_motion_query_retries(void);
 
unsigned arm_motion_query_line_errors(void);
unsigned arm_motion_fault_lsr(void);
unsigned arm_motion_fault_servo(void);
int arm_motion_last_position(unsigned servo_id);
unsigned arm_motion_stop_attempt_mask(void);

int arm_motion_get_pick_feedback(ArmPickFeedback *out);

int arm_motion_get_bus_fault(ArmBusDiagnostic *out);

typedef struct ArmReadAttemptFailure {
    unsigned attempt;
    ArmBusDiagnostic bus;
} ArmReadAttemptFailure;

#define ARM_READ_RECOVERY_SETTLE_US UINT64_C(200000)
#define ARM_READ_RECOVERY_MAX_PER_REQUEST 4U
#define ARM_READ_RETRY_FIRST_US UINT64_C(20000)
#define ARM_READ_RETRY_SECOND_US UINT64_C(50000)
typedef struct ArmReadRecovery {
    unsigned attempted, succeeded, active, error_code, fresh_mask;
    unsigned action_index, phase, read_mask, fault_servo, read_failure_count;
    uint64_t started_us, recheck_started_us;
    ArmBusDiagnostic original_fault;
    ArmReadAttemptFailure read_failures[3];
    unsigned attempts_total, successes_total, read_purpose;
} ArmReadRecovery;
int arm_motion_get_read_recovery(ArmReadRecovery *out);

typedef struct ArmMotionFailure {
    unsigned valid, sequence, error_code;
    unsigned action_valid, phase, action_index, action_count, fault_servo;
    unsigned query_retries, query_line_errors, motion_attempted;
    unsigned commanded_mask, actual_mask, bus_valid, read_failure_count;
    double pose[4];
    int16_t commanded[7];
    int actual[7];
    ArmBusDiagnostic bus;
    ArmReadAttemptFailure read_failures[3];
} ArmMotionFailure;

int arm_motion_get_last_failure(ArmMotionFailure *out);
const char *arm_motion_error_name(unsigned error_code);

#endif
