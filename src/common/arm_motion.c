/* Motion execution with position feedback, bounded read recovery, and cancellation. */
#if defined(SCREWSORT_LINUX) || defined(SCREWSORT_BAREMETAL)
#include "port_platform.h"
#define MOTION_PLATFORM_ALLOWED() (sl_motion_enabled)
#else
#define MOTION_PLATFORM_ALLOWED() 1
#endif
#include "arm_motion.h"
#include "arm_bus.h"

#include <string.h>

enum MotionState {
    MOTION_IDLE, MOTION_READ_START, MOTION_READ_WAIT, MOTION_RETRY_WAIT,
    MOTION_ACTION_BEGIN, MOTION_MOVE_START, MOTION_MOVE_WAIT,
    MOTION_ACTION_WAIT, MOTION_STOP_START, MOTION_STOP_WAIT,
    MOTION_COMPLETED, MOTION_ERROR, MOTION_CANCELLED,
    MOTION_READ_RECOVERY_WAIT
};
enum ReadPurpose { READ_INITIAL, READ_ARRIVAL, READ_HOLD };
enum MotionError {
    ERROR_NONE, ERROR_PLAN, ERROR_BUS_START, ERROR_BUS_RESULT, ERROR_POSITION,
    ERROR_ARRIVAL, ERROR_CANCELLED, ERROR_RUN_TIMEOUT, ERROR_CLOCK,
    ERROR_TARGET_STALE
};

static ArmAction plan[ARM_PLAN_CAPACITY];
static unsigned action_count, action_index, completed_actions;
static enum MotionState state;
static enum ReadPurpose read_purpose;
static enum MotionError last_error;
static const char *failed_bus_error = "NONE";
static unsigned servo_id, read_mask, read_attempt, query_retries;
static unsigned query_line_errors, fault_lsr;
static unsigned fault_servo, stop_attempt_mask;
static int actual[7];
static ArmPickFeedback pick_feedback;
static ArmBusDiagnostic bus_fault;
static ArmMotionFailure last_failure;
static ArmReadRecovery read_recovery;
static ArmReadAttemptFailure read_failures[3];
static unsigned read_failure_count, actual_mask;
static unsigned read_group_recovery_used;
static int motion_attempted, cancellation_requested;
static int visual_request;

static unsigned place_start_pending,place_capture_ms;
static unsigned initial_reuse_allowed, skipped_initial_actions;
static uint64_t actual_sample_started_us[7], current_read_started_us;
static uint64_t deadline_us, run_started_us, last_service_us;

static int terminal(void)
{
    return state == MOTION_IDLE || state == MOTION_COMPLETED ||
           state == MOTION_ERROR || state == MOTION_CANCELLED;
}

static unsigned next_id(unsigned mask, unsigned first)
{
    unsigned id;
    for (id = first; id <= 6U; ++id)
        if (mask & (1U << id)) return id;
    return 7U;
}

static void finish_error(void)
{
    arm_bus_cancel();
    state = last_error == ERROR_CANCELLED ? MOTION_CANCELLED : MOTION_ERROR;
}

static void clear_read_failures(void)
{
    read_failure_count = 0U;
    memset(read_failures, 0, sizeof(read_failures));
}

static void capture_failure(enum MotionError error, int has_action)
{
    unsigned sequence;
    if (error == ERROR_NONE || error == ERROR_CANCELLED) return;
    sequence = last_failure.sequence;
    memset(&last_failure, 0, sizeof(last_failure));
    last_failure.valid = 1U;
    last_failure.sequence = sequence == ~0U ? sequence : sequence+1U;
    last_failure.error_code = (unsigned)error;
    if (!has_action) return;  
    last_failure.action_valid = action_index < action_count;
    last_failure.action_index = action_index;
    last_failure.action_count = action_count;
    last_failure.fault_servo = fault_servo;
    last_failure.query_retries = query_retries;
    last_failure.query_line_errors = query_line_errors;
    last_failure.motion_attempted = (unsigned)motion_attempted;
    last_failure.actual_mask = actual_mask;
    memcpy(last_failure.actual, actual, sizeof(actual));
    if (last_failure.action_valid) {
        const ArmAction *action = &plan[action_index];
        last_failure.phase = action->phase;
        last_failure.commanded_mask = action->mask;
        memcpy(last_failure.commanded, action->positions, sizeof(action->positions));
        memcpy(last_failure.pose, action->pose, sizeof(action->pose));
    }
    if (error == ERROR_BUS_START || error == ERROR_BUS_RESULT) {
        last_failure.bus_valid = bus_fault.valid;
        last_failure.bus = bus_fault;
    }
    last_failure.read_failure_count = read_failure_count;
    memcpy(last_failure.read_failures, read_failures, sizeof(read_failures));
}

static void fail(enum MotionError error)
{
    /* Discard the outstanding transaction before explicit best-effort STOP.
     * No logging, formatting, file operations or automatic return occurs here. */
    last_error = error;
    if (read_recovery.active) read_recovery.error_code = (unsigned)error;
    read_recovery.active = 0U;
    if (error == ERROR_BUS_START || error == ERROR_BUS_RESULT) {
        (void)arm_bus_get_diagnostic(&bus_fault);
        failed_bus_error = arm_bus_error_name();
        fault_lsr = arm_bus_last_lsr();
    }
    capture_failure(error, 1);
    arm_bus_cancel();
    if (motion_attempted) {
        servo_id = 1U;
        state = MOTION_STOP_START;
    } else finish_error();
}

static void start_read_group(enum ReadPurpose purpose, unsigned mask)
{
    

    if (!read_recovery.active) read_group_recovery_used = 0U;
    read_purpose = purpose;
    read_mask = mask;
    servo_id = next_id(mask, 1U);
    read_attempt = 0;
    clear_read_failures();
    state = MOTION_READ_START;
}

static int start_read_recovery(uint64_t now_us)
{
    const ArmAction *action;
    unsigned k;
    if (!visual_request || read_group_recovery_used || read_recovery.active ||
        read_recovery.attempts_total >= ARM_READ_RECOVERY_MAX_PER_REQUEST ||
        action_index >= action_count ||
        !read_mask || (read_mask & ~0x7eU) ||
        read_attempt != 3U || read_failure_count != 3U ||
        arm_bus_result() != ARM_BUS_RX_TIMEOUT) return 0;
    action = &plan[action_index];
    if (read_purpose == READ_INITIAL) {
        if (motion_attempted || read_mask != 0x7eU) return 0;
    } else if ((read_purpose != READ_ARRIVAL && read_purpose != READ_HOLD) ||
               !motion_attempted || action->mask != read_mask) return 0;
    for (k=0;k<3U;++k) {
        const ArmReadAttemptFailure *attempt=&read_failures[k];
        const ArmBusDiagnostic *b=&attempt->bus;
        if (attempt->attempt != k+1U || !b->valid || b->command != 28U ||
            b->servo_id != servo_id || b->error_code != ARM_BUS_ERROR_RX_TIMEOUT ||
            b->received_bytes != 0U || (b->lsr & 0x9eU)) return 0;
    }
    unsigned attempts=read_recovery.attempts_total, successes=read_recovery.successes_total;
    memset(&read_recovery,0,sizeof(read_recovery));
    read_recovery.attempts_total=attempts+1U;read_recovery.successes_total=successes;
    read_recovery.read_purpose=(unsigned)read_purpose;
    read_group_recovery_used=1U;
    read_recovery.attempted=read_recovery.active=1U;
    read_recovery.action_index=action_index;
    read_recovery.phase=action->phase;
    read_recovery.read_mask=read_mask;
    read_recovery.fault_servo=servo_id;
    read_recovery.read_failure_count=read_failure_count;
    read_recovery.started_us=now_us;
    read_recovery.original_fault=read_failures[2].bus;
    memcpy(read_recovery.read_failures,read_failures,sizeof(read_failures));
    /* Keep the issued pose; only discard the finished failed query. Fresh
     * positions for the entire mask will be required after this finite wait. */
    arm_bus_cancel();
    deadline_us=now_us+ARM_READ_RECOVERY_SETTLE_US;
    state=MOTION_READ_RECOVERY_WAIT;
    return 1;
}

static void complete_action(void)
{
    ++completed_actions;
    ++action_index;
    if (action_index == action_count) {
        state = MOTION_COMPLETED;
         
    } else state = MOTION_ACTION_BEGIN;
}

static int initial_home_already_reached(void)
{
    unsigned id;
    if (!initial_reuse_allowed || !visual_request || action_count < 2U ||
        plan[0].phase != ARM_PHASE_HOME || plan[0].mask != 0x7cU || plan[0].hold ||
        plan[1].phase != ARM_PHASE_OPEN || plan[1].mask != 2U || plan[1].hold ||
        (actual_mask & 0x7eU) != 0x7eU) return 0;
    

    for (id=1U;id<=6U;++id) {
        int difference;
        if (last_service_us < actual_sample_started_us[id] ||
            last_service_us-actual_sample_started_us[id] > ARM_INITIAL_REUSE_MAX_AGE_US)
            return 0;
        if (id == 1U) continue;
        difference=actual[id]-plan[0].positions[id];
        if (difference > (int)ARM_INITIAL_REUSE_TOLERANCE_RAW ||
            difference < -(int)ARM_INITIAL_REUSE_TOLERANCE_RAW) return 0;
    }
    return 1;
}

static int finish_read_recovery(void)
{
    if (!read_recovery.active) return 1;
    if (read_recovery.fresh_mask != read_mask) {
        fail(ERROR_POSITION);
        return 0;
    }
    read_recovery.succeeded=1U;read_recovery.active=0U;
    ++read_recovery.successes_total;
    return 1;
}

static void finish_read_group(void)
{
    const ArmAction *action;
    unsigned id, tolerance;
    if (read_purpose == READ_INITIAL) {
        if (!finish_read_recovery()) return;

        if (visual_request) {
            ArmAction *home = &plan[0];
            unsigned duration = ARM_VISUAL_HOME_MIN_MS;
            for (id = 2U; id <= 6U; ++id) {
                int difference;
                unsigned delta, limit, required;
                if (!(home->mask & (1U << id))) continue;
                difference = home->positions[id]-actual[id];
                delta = (unsigned)(difference < 0 ? -difference : difference);
                limit = id == 2U ? ARM_VISUAL_WRIST_STEP_RAW : ARM_VISUAL_ARM_STEP_RAW;
                required = (delta*ARM_VISUAL_REFERENCE_STEP_MS+limit-1U)/limit;
                if (required > duration) duration = required;
            }
            home->duration_ms = (uint16_t)duration;
        }
        if (initial_home_already_reached()) {
            int difference=actual[1]-plan[1].positions[1];
            ++skipped_initial_actions;
            complete_action();
            if (difference <= (int)ARM_INITIAL_REUSE_TOLERANCE_RAW &&
                difference >= -(int)ARM_INITIAL_REUSE_TOLERANCE_RAW) {
                ++skipped_initial_actions;
                complete_action();
            }
            initial_reuse_allowed=0U;
            return;
        }
        initial_reuse_allowed=0U;
        state = MOTION_ACTION_BEGIN;
        return;
    }
    action = &plan[action_index];
    if (read_purpose == READ_ARRIVAL && action->phase == ARM_PHASE_DESCEND) {
        pick_feedback.action_index = action_index;
        pick_feedback.mask = action->mask;
        memcpy(pick_feedback.pose, action->pose, sizeof(pick_feedback.pose));
        memcpy(pick_feedback.commanded, action->positions, sizeof(pick_feedback.commanded));
        memcpy(pick_feedback.measured, actual, sizeof(pick_feedback.measured));
        pick_feedback.valid = 1U;
    }
    if (action->phase != ARM_PHASE_CLOSE) {
        tolerance = (action->phase == ARM_PHASE_OPEN || action->phase == ARM_PHASE_RELEASE ||
                     action->phase == ARM_PHASE_PLACE_RELEASE) &&
                    action->mask == 2U ? 40U : 20U;
        for (id = 1; id <= 6U; ++id) {
            int difference;
            if (!(read_mask & (1U << id))) continue;
            if (read_purpose == READ_HOLD && id == 1U) continue;
            difference = actual[id] - action->positions[id];
            if (difference > (int)tolerance || difference < -(int)tolerance) {
                fault_servo = id;
                fail(ERROR_ARRIVAL);
                return;
            }
        }
    }
     
    if (!finish_read_recovery()) return;
    complete_action();
}

void arm_motion_init(void)
{
    state = MOTION_IDLE;
    last_error = ERROR_NONE;
    failed_bus_error = "NONE";
    action_count = action_index = completed_actions = 0;
    query_retries = fault_servo = stop_attempt_mask = 0;
    query_line_errors = fault_lsr = 0;
    motion_attempted = cancellation_requested = 0;
    visual_request = 0;
    place_start_pending=place_capture_ms=0U;
    initial_reuse_allowed = skipped_initial_actions = 0U;
    memset(actual_sample_started_us, 0, sizeof(actual_sample_started_us));
    memset(actual, 0, sizeof(actual));
    memset(&pick_feedback, 0, sizeof(pick_feedback));
    memset(&bus_fault, 0, sizeof(bus_fault));
    memset(&last_failure, 0, sizeof(last_failure));
    memset(&read_recovery, 0, sizeof(read_recovery));
    read_group_recovery_used = 0U;
    actual_mask = 0U;
    clear_read_failures();
}

int arm_motion_start(unsigned mode, uint64_t now_us)
{
    if(!MOTION_PLATFORM_ALLOWED())return -1;
    unsigned count = 0;
    if (!terminal() || arm_bus_busy()) return -1;
    place_start_pending=place_capture_ms=0U;
    initial_reuse_allowed = skipped_initial_actions = 0U;
    memset(actual_sample_started_us, 0, sizeof(actual_sample_started_us));
    memset(&read_recovery, 0, sizeof(read_recovery));
    read_group_recovery_used = 0U;
    visual_request = 0;
    memset(&bus_fault, 0, sizeof(bus_fault));
    memset(&pick_feedback, 0, sizeof(pick_feedback));
    actual_mask = 0U;
    clear_read_failures();
    action_count = action_index = completed_actions = 0U;
    query_retries = fault_servo = stop_attempt_mask = 0U;
    query_line_errors = fault_lsr = 0U;
    failed_bus_error = "NONE";motion_attempted = cancellation_requested = 0;
    memset(actual,0,sizeof(actual));
    if (arm_plan_build(mode,plan,ARM_PLAN_CAPACITY,&count) || count == 0U) {
        last_error = ERROR_PLAN;
        state = MOTION_ERROR;
        capture_failure(ERROR_PLAN, 0);
        return -2;
    }
    action_count = count;
    action_index = completed_actions = 0;
    query_retries = fault_servo = stop_attempt_mask = 0;
    query_line_errors = fault_lsr = 0;
    last_error = ERROR_NONE;
    failed_bus_error = "NONE";
    motion_attempted = cancellation_requested = 0;
    run_started_us = last_service_us = now_us;
    memset(actual,0,sizeof(actual));
    start_read_group(READ_INITIAL,0x7eU);
    return 0;
}

static int start_visual_request(const VisualPickTarget *target,unsigned place,unsigned bin_index,
                                uint64_t now_us)
{
    unsigned count=0;
    if(!MOTION_PLATFORM_ALLOWED())return -1;
    if(!terminal() || arm_bus_busy())return -1;
    place_start_pending=place_capture_ms=0U;
    initial_reuse_allowed = visual_request && state == MOTION_COMPLETED;
    skipped_initial_actions = 0U;
    memset(actual_sample_started_us, 0, sizeof(actual_sample_started_us));
    memset(&read_recovery,0,sizeof(read_recovery));
    read_group_recovery_used=0U;
    visual_request = 0;
    memset(&bus_fault, 0, sizeof(bus_fault));
    memset(&pick_feedback, 0, sizeof(pick_feedback));
    actual_mask = 0U;
    clear_read_failures();
    action_count=action_index=completed_actions=0U;
    query_retries=fault_servo=stop_attempt_mask=0U;
    query_line_errors=fault_lsr=0U;
    failed_bus_error="NONE";motion_attempted=cancellation_requested=0;
    memset(actual,0,sizeof(actual));
     
    int result=place?arm_plan_build_visual_place(target,bin_index,plan,ARM_PLAN_CAPACITY,&count):
                     arm_plan_build_visual(target,plan,ARM_PLAN_CAPACITY,&count);
    if(result || !count){
        last_error=ERROR_PLAN;state=MOTION_ERROR;
        capture_failure(ERROR_PLAN,0);return -2;
    }
    action_count=count;action_index=completed_actions=0;
    visual_request = 1;
    if(place){place_start_pending=1U;place_capture_ms=target->captured_ms;}
    query_retries=fault_servo=stop_attempt_mask=0;
    query_line_errors=fault_lsr=0;
    last_error=ERROR_NONE;failed_bus_error="NONE";
    motion_attempted=cancellation_requested=0;
    run_started_us=last_service_us=now_us;
    memset(actual,0,sizeof(actual));
    start_read_group(READ_INITIAL,0x7eU);
    return 0;
}

int arm_motion_start_visual(const VisualPickTarget *target,uint64_t now_us)
{
    return start_visual_request(target,0U,0U,now_us);
}

int arm_motion_start_visual_place(const VisualPickTarget *target,unsigned bin_index,uint64_t now_us)
{
    return start_visual_request(target,1U,bin_index,now_us);
}

void arm_motion_cancel(void)
{
    if (!terminal()) cancellation_requested = 1;
}

void arm_motion_service(uint64_t now_us)
{
    const ArmAction *action;
    arm_bus_result_t bus_result;
    if (terminal()) return;
    

    if (state != MOTION_STOP_START && state != MOTION_STOP_WAIT) {
        if (cancellation_requested) { fail(ERROR_CANCELLED); return; }
        if (now_us < last_service_us) { fail(ERROR_CLOCK); return; }
        if (now_us-run_started_us > UINT64_C(600000000)) {
            fail(ERROR_RUN_TIMEOUT); return;
        }
    }
    last_service_us = now_us;
    if(place_start_pending && state==MOTION_READ_START && read_purpose==READ_INITIAL){
        place_start_pending=0U;
        if((uint32_t)((uint32_t)(now_us/UINT64_C(1000))-place_capture_ms)>PICK_FRESH_MS){
            

            action_count=action_index=completed_actions=0U;
            last_error=ERROR_TARGET_STALE;state=MOTION_ERROR;
            capture_failure(ERROR_TARGET_STALE,0);return;
        }
    }
    arm_bus_service(now_us);
    action = &plan[action_index];
    switch (state) {
    case MOTION_READ_START:
        if (servo_id > 6U) { finish_read_group(); break; }
        if (arm_bus_start_read(servo_id,now_us)) {
            fault_servo = servo_id; fail(ERROR_BUS_START); break;
        }
        current_read_started_us = now_us;
        ++read_attempt;
        state = MOTION_READ_WAIT;
        break;
    case MOTION_READ_WAIT:
        if (arm_bus_busy()) break;
        bus_result = arm_bus_result();
        if (bus_result != ARM_BUS_OK && read_failure_count < 3U) {
            ArmReadAttemptFailure *attempt = &read_failures[read_failure_count++];
            attempt->attempt = read_attempt;
            (void)arm_bus_get_diagnostic(&attempt->bus);
        }
        if (bus_result == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_LINE) {
            ++query_line_errors;
            fault_lsr = arm_bus_last_lsr();
        }
        /* A position read has no motion side effect. Discard the complete bad
         * receive transaction and retry at most twice, with a bounded quiet
         * gap. No MOVE is resent and no corrupt position is accepted. */
        if ((bus_result == ARM_BUS_RX_TIMEOUT ||
             (bus_result == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_LINE)) &&
            read_attempt < 3U) {
            ++query_retries;
            arm_bus_cancel();
            deadline_us = now_us+(read_attempt == 1U ?
                ARM_READ_RETRY_FIRST_US : ARM_READ_RETRY_SECOND_US);
            state = MOTION_RETRY_WAIT;
            break;
        }
        if (bus_result != ARM_BUS_OK) {
            if (start_read_recovery(now_us)) break;
            fault_servo = servo_id; fail(ERROR_BUS_RESULT); break;
        }
        actual[servo_id] = arm_bus_position();
        actual_mask |= 1U << servo_id;
        if (!arm_feedback_position_allowed(servo_id,actual[servo_id])) {
            fault_servo = servo_id; fail(ERROR_POSITION); break;
        }
        

        actual_sample_started_us[servo_id] = current_read_started_us;
        if (read_recovery.active) read_recovery.fresh_mask |= 1U << servo_id;
        servo_id = next_id(read_mask,servo_id+1U);
        read_attempt = 0;
        clear_read_failures();
        state = MOTION_READ_START;
        break;
    case MOTION_RETRY_WAIT:
        if (now_us >= deadline_us) state = MOTION_READ_START;
        break;
    case MOTION_READ_RECOVERY_WAIT:
        if (now_us >= deadline_us) {
            read_recovery.recheck_started_us=now_us;
            

            actual_mask &= ~read_mask;
            start_read_group(read_purpose,read_mask);
        }
        break;
    case MOTION_ACTION_BEGIN:
        if (action->hold) {
            deadline_us = now_us+(uint64_t)action->duration_ms*1000U;
            state = MOTION_ACTION_WAIT;
        } else {
            servo_id = next_id(action->mask,1U);
            state = MOTION_MOVE_START;
        }
        break;
    case MOTION_MOVE_START:
        if (servo_id > 6U) {
             
            deadline_us = now_us+(uint64_t)(action->duration_ms+action->settle_ms)*1000U;
            state = MOTION_ACTION_WAIT;
            break;
        }
        motion_attempted = 1;
        if (arm_bus_start_move(servo_id,(unsigned)action->positions[servo_id],
                               action->duration_ms,now_us)) {
            fault_servo = servo_id; fail(ERROR_BUS_START); break;
        }
        state = MOTION_MOVE_WAIT;
        break;
    case MOTION_MOVE_WAIT:
        if (arm_bus_busy()) break;
        if (arm_bus_result() != ARM_BUS_OK) {
            fault_servo = servo_id; fail(ERROR_BUS_RESULT); break;
        }
        servo_id = next_id(action->mask,servo_id+1U);
        state = MOTION_MOVE_START;
        break;
    case MOTION_ACTION_WAIT:
        if (now_us < deadline_us) break;
        if (action->hold) start_read_group(READ_HOLD,action->mask);
        else if (action_index+1U == action_count ||
                 plan[action_index+1U].phase != action->phase ||
                 plan[action_index+1U].cycle != action->cycle ||
                 plan[action_index+1U].hold)
            start_read_group(READ_ARRIVAL,action->mask);
        else complete_action();
        break;
    case MOTION_STOP_START:
        if (servo_id > 6U) { finish_error(); break; }
        stop_attempt_mask |= 1U << servo_id;
        if (arm_bus_start_stop(servo_id,now_us)) {
            arm_bus_cancel(); ++servo_id;
        } else state = MOTION_STOP_WAIT;
        break;
    case MOTION_STOP_WAIT:
        if (arm_bus_busy()) break;
        ++servo_id;
        state = MOTION_STOP_START;
        break;
    default:
        fail(ERROR_PLAN);
        break;
    }
}

int arm_motion_busy(void) { return !terminal(); }
int arm_motion_transport_busy(void) { return arm_bus_busy(); }
int arm_motion_urgent(void)
{
    if (terminal()) return 0;
    if (cancellation_requested || arm_bus_busy()) return 1;
    if (visual_request && state == MOTION_ACTION_WAIT &&
        (last_service_us >= deadline_us ||
         deadline_us-last_service_us <= ARM_VISUAL_SERVICE_WINDOW_US)) return 1;
    return state != MOTION_ACTION_WAIT && state != MOTION_RETRY_WAIT &&
           state != MOTION_READ_RECOVERY_WAIT;
}
unsigned arm_motion_cycle(void)
{
    return action_count ? plan[action_index < action_count ? action_index : action_count-1U].cycle : 0U;
}
const char *arm_motion_phase_name(void)
{
    return action_count ? arm_phase_name(plan[action_index < action_count ? action_index : action_count-1U].phase) : "none";
}
unsigned arm_motion_completed_actions(void) { return completed_actions; }
unsigned arm_motion_action_count(void) { return action_count; }
unsigned arm_motion_skipped_initial_actions(void) { return skipped_initial_actions; }
unsigned arm_motion_query_retries(void) { return query_retries; }
unsigned arm_motion_query_line_errors(void) { return query_line_errors; }
unsigned arm_motion_fault_lsr(void) { return fault_lsr; }
unsigned arm_motion_fault_servo(void) { return fault_servo; }
unsigned arm_motion_stop_attempt_mask(void) { return stop_attempt_mask; }
int arm_motion_last_position(unsigned id) { return id >= 1U && id <= 6U ? actual[id] : 0; }
int arm_motion_get_pick_feedback(ArmPickFeedback *out)
{
    if (out) *out = pick_feedback;
    return (int)pick_feedback.valid;
}

int arm_motion_get_bus_fault(ArmBusDiagnostic *out)
{
    if (out) *out = bus_fault;
    return (int)bus_fault.valid;
}

int arm_motion_get_last_failure(ArmMotionFailure *out)
{
    if (out) *out = last_failure;
    return (int)last_failure.valid;
}

int arm_motion_get_read_recovery(ArmReadRecovery *out)
{
    if (out) *out=read_recovery;
    return (int)read_recovery.attempted;
}

const char *arm_motion_state_name(void)
{
    if (state == MOTION_IDLE) return "IDLE";
    if (state == MOTION_COMPLETED) return "COMPLETED";
    if (state == MOTION_ERROR) return "ERROR";
    if (state == MOTION_CANCELLED) return "CANCELLED";
    if (state == MOTION_STOP_START || state == MOTION_STOP_WAIT) return "STOPPING";
    if (read_purpose == READ_INITIAL && (state == MOTION_READ_START ||
        state == MOTION_READ_WAIT || state == MOTION_RETRY_WAIT ||
        state == MOTION_READ_RECOVERY_WAIT)) return "PREFLIGHT";
    return "RUNNING";
}

const char *arm_motion_error_name(unsigned error_code)
{
    static const char *const names[] = {
        "NONE", "PLAN", "BUS_START", "BUS_RESULT", "POSITION_RANGE",
        "ARRIVAL", "CANCELLED", "RUN_TIMEOUT", "CLOCK", "TARGET_STALE"
    };
    return error_code < sizeof(names)/sizeof(names[0]) ? names[error_code] : "UNKNOWN";
}

const char *arm_motion_last_error(void) { return arm_motion_error_name((unsigned)last_error); }

const char *arm_motion_bus_error(void) { return failed_bus_error; }
