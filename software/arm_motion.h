#ifndef ARM_MOTION_H
#define ARM_MOTION_H

#include <stdint.h>
#include "arm_kinematics.h"
#include "arm_bus.h"

/* Visual requests only. Initial HOME uses complete validated feedback and
 * the existing arm/wrist speed ceilings; this is a floor, not a time cap. */
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

/* Cooperative executor. Call arm_bus_init first, then init. Init never sends
 * a packet; only an explicit successful start request enables this sequence. */
void arm_motion_init(void);
int arm_motion_start(unsigned mode, uint64_t now_us);
int arm_motion_start_visual(const VisualPickTarget *target,uint64_t now_us);
int arm_motion_start_visual_place(const VisualPickTarget *target,unsigned bin_index,uint64_t now_us);
void arm_motion_service(uint64_t now_us);
void arm_motion_cancel(void);
int arm_motion_busy(void);
int arm_motion_transport_busy(void);
/* Keep servicing pending group packets / STOP without slow background work.
 * Timed action waits yield except the final visual 30 ms, which reserves the
 * scheduler for the next group/phase gate. Retry gaps retain their old policy. */
int arm_motion_urgent(void);
const char *arm_motion_state_name(void);
const char *arm_motion_last_error(void);
const char *arm_motion_bus_error(void);
const char *arm_motion_phase_name(void);
unsigned arm_motion_cycle(void);
unsigned arm_motion_completed_actions(void);
unsigned arm_motion_action_count(void);
/* Only a successful preceding visual cycle permits reuse. This request must
 * freshly read all six axes, then verify HOME within 5 raw before skipping it.
 * OPEN can be skipped only with that HOME and its own matching fresh feedback.
 * Counts verified redundant actions, never omitted arrival checks elsewhere. */
unsigned arm_motion_skipped_initial_actions(void);
unsigned arm_motion_query_retries(void);
/* Per-request diagnostics, retained across recovery and cleared by next start. */
unsigned arm_motion_query_line_errors(void);
unsigned arm_motion_fault_lsr(void);
unsigned arm_motion_fault_servo(void);
int arm_motion_last_position(unsigned servo_id);
unsigned arm_motion_stop_attempt_mask(void);
/* Last complete DESCEND arrival read, copied before its arrival check.
 * valid means feedback was received, not that arrival/grasp succeeded.
 * Only IDs selected by mask belong to this read group; other measured entries
 * are older cached readings and are not an arrival measurement for this step.
 * action_index is zero-based. Pose is the plan, not a measured TCP position.
 * A new non-busy start (including a rejected plan) or init clears the snapshot.
 * A NULL output can be used to query validity without copying. */
int arm_motion_get_pick_feedback(ArmPickFeedback *out);
/* Original BUS_START/BUS_RESULT failure, copied before cancel/six STOP attempts
 * can replace bus diagnostics. Cleared by init/new non-busy request, retained
 * across STOP and BUSY rejection. No record means no bus failure this request. */
int arm_motion_get_bus_fault(ArmBusDiagnostic *out);

/* Persistent diagnostic only; never commands or relaxes motion. At most the
 * three failed attempts for the faulting/current position query are retained.
 * Each bus snapshot is copied before cancel/retry can replace its contents. */
typedef struct ArmReadAttemptFailure {
    unsigned attempt;
    ArmBusDiagnostic bus;
} ArmReadAttemptFailure;

/* A pure empty-reply failure can recover once per read group, at most four
 * groups per visual request. Initial six-axis reads and gripper/wrist groups
 * are included. A settled full group must pass every original range/arrival
 * limit. MOVE/STOP are never replayed. Persistent loss still terminates.
 * The record describes the latest episode; totals include earlier episodes. */
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

/* Last real ERROR survives a later successful start/completion and BUSY
 * rejection. Only init clears it; a new ERROR replaces it. User cancellation
 * does not erase an earlier failure. PLAN failures have action_valid=0.
 * actual_mask denotes replies received during that request; they are cached
 * at different times, not simultaneous measured TCP or arrival evidence.
 * commanded_mask/pose identify the current planned action, not proof it moved.
 * Getter copies RAM only; NULL queries validity and no MMIO is performed. */
int arm_motion_get_last_failure(ArmMotionFailure *out);
const char *arm_motion_error_name(unsigned error_code);

#endif
