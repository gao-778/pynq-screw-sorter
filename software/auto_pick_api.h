#ifndef AUTO_PICK_API_H
#define AUTO_PICK_API_H
#include "workstation_config.h"
/* CPU batch policy only; CNN, target localization and servo execution remain
 * in their existing engines. Class IDs here are raw CNN IDs, not labels 1..15. */
enum AutoPickState {
    AUTO_PICK_OFF, AUTO_PICK_BROWSE, AUTO_PICK_WAIT_TARGET,
    AUTO_PICK_MOVING, AUTO_PICK_WAIT_REMOVAL, AUTO_PICK_DONE,
    AUTO_PICK_STOPPED, AUTO_PICK_ERROR,
    /* A bounded user request awaiting one coherent, motion-fresh scene. */
    AUTO_PICK_WAIT_START
};
enum AutoPickOrder { AUTO_PICK_LEFT_RIGHT, AUTO_PICK_TOP_BOTTOM };
enum AutoPickMode { AUTO_PICK_CLASS_PICK, AUTO_PICK_SORT_ALL };
#define AUTO_PICK_BIN_COUNT 4U
#define AUTO_PICK_NO_CLASS REC_CLASS_INVALID
typedef struct AutoPickView {
    unsigned open,running,state,selected_class,order;
    unsigned mode,bin_count,bin_class_ids[4],bin_for_class[REC_CLASS_COUNT];
    unsigned current_class,current_bin,remaining[REC_CLASS_COUNT];
    unsigned counts[REC_CLASS_COUNT],class_ids[REC_CLASS_COUNT],class_count;
    unsigned catalog_valid,catalog_stale;
    unsigned queue_count,queue_index,actions_completed,removed_count;
    unsigned current_slot,current_slot_valid;
    const char *message;
} AutoPickView;
static unsigned auto_pick_is_open(void);
static unsigned auto_pick_is_running(void);
static void auto_pick_toggle(void);
static void auto_pick_toggle_mode(unsigned mode);
static void auto_pick_close(void);
static void auto_pick_direction(unsigned direction);
static void auto_pick_press(void);
static void auto_pick_cancel(const char *reason,unsigned abort_motion);
static void auto_pick_service(void);
static void auto_pick_vision_fault(void);
static void auto_pick_motion_finished(const char *state);
static void auto_pick_get_view(AutoPickView *out);
static void auto_pick_refresh_view(void);
/* Presentation ownership is separate from inference readiness. Automated
 * confirmation can consume fresh scenes while all candidate results stay hidden. */
static void recognition_visibility_sync(void);
static unsigned recognition_results_hidden(void);
#endif
