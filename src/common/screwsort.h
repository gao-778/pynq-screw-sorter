#ifndef SCREWSORT_H
#define SCREWSORT_H
#ifdef __cplusplus
extern "C" {
#endif
int sl_initialize(void);
void sl_service(void);
int sl_urgent(void);
int sl_should_stop(void);
int sl_motion_enable(int enabled);
int sl_command(const char *text);
int sl_pick(void);
int sl_direction(unsigned direction);
int sl_auto(unsigned class_id,unsigned order);
int sl_sort_all(unsigned order);
unsigned sl_target_count(void);
int sl_target(unsigned index,double *output);
int sl_state(unsigned *output,unsigned capacity);
unsigned sl_read_console(char *destination,unsigned capacity);
int sl_shutdown(void);
#ifdef __cplusplus
}
#endif
#endif
