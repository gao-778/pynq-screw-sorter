/* PL performs visual inference; ARM schedules vision and bounded arm motion. */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "xil_io.h"
#include "xil_printf.h"
#include "xiltimer.h"
#include "sleep.h"
#include "ff.h"
#include "arm_motion.h"
#include "arm_bus.h"
#include "fusion_clock.h"
#include "auto_pick_api.h"
#include <stdint.h>
#define GPIO_BASE 0x41200000U
#define RGB_RED (1U<<10)
#define RGB_GREEN (1U<<9)
#define RGB_BLUE (1U<<8)
#define BUILD_TAG "BUILD_MC18_UI_MINT_ARM_BUS_FIX_20261101"
static void control(u32 value);
static void fusion_service(void);
static void fusion_menu_confirm(void);
static void fusion_menu_cancel(void);
static void fusion_status_line(char *line,unsigned capacity);
static void fusion_vision_fault(void);
static void fusion_pick_press(void);
static unsigned fusion_pick_pending(void);
static void fusion_pick_cancel_pending(const char *reason);
static unsigned fusion_ready;
static unsigned recognition_motion_paused(void);
static unsigned recognition_resume_waiting(void);
static void recognition_scene_published(void);
static unsigned runtime_motion_log_dropped;

/*
 * The SD card log is deliberately small and line oriented.  The file stays
 * open during the run. Lines accumulate in RAM; normal operation syncs every
 * sixteen attempts and errors sync immediately. Power loss may lose recent lines.
 */
static FATFS runtime_filesystem;
static FIL runtime_log_file;
static int runtime_log_ready;
static char runtime_log_buffer[32768];
static unsigned runtime_log_used,run_attempt;
/* Detailed recognition rows are recorded only for a button-selected frame. */
static int runtime_detail_enabled=1;
static unsigned runtime_ms(void) {
    XTime now;XTime_GetTime(&now);
    return fusion_ticks_ms(now);
}
static void runtime_log_flush(void) {
    if(arm_motion_busy() || !runtime_log_ready || !runtime_log_used)return;
    UINT written=0;
    if(f_write(&runtime_log_file,runtime_log_buffer,runtime_log_used,&written)!=FR_OK || written!=runtime_log_used){
        runtime_log_ready=0;xil_printf("SD_LOG_WRITE_FAILED\r\n");
    }
    runtime_log_used=0;
}

static int runtime_log_open(void) {
    FRESULT result = f_mount(&runtime_filesystem, "0:/", 1);
    if (result != FR_OK) {
        xil_printf("SD_LOG_MOUNT_FAILED=%u\r\n", (unsigned)result);
        return -1;
    }
    result = f_open(&runtime_log_file, "0:/RUNLOG.TXT", FA_WRITE | FA_OPEN_ALWAYS);
    if (result != FR_OK) {
        xil_printf("SD_LOG_OPEN_FAILED=%u\r\n", (unsigned)result);
        return -1;
    }
    if (f_lseek(&runtime_log_file, f_size(&runtime_log_file)) != FR_OK) {
        xil_printf("SD_LOG_SEEK_FAILED\r\n");
        f_close(&runtime_log_file);
        return -1;
    }
    runtime_log_ready = 1;
    if (f_size(&runtime_log_file) == 0) {
        static const char header[] =
            "# MC18 event log: records use named key,value fields; full class scores are in button-saved CSV files.\r\n";
        UINT written = 0;
        if (f_write(&runtime_log_file, header, sizeof(header) - 1, &written) != FR_OK ||
            written != sizeof(header) - 1) {
            xil_printf("SD_LOG_HEADER_FAILED\r\n");
            runtime_log_ready = 0;
            f_close(&runtime_log_file);
            return -1;
        }
    }
    if (f_sync(&runtime_log_file) != FR_OK) {
        xil_printf("SD_LOG_SYNC_FAILED\r\n");
        runtime_log_ready = 0;
        f_close(&runtime_log_file);
        return -1;
    }
    xil_printf("SD_LOG_READY=0:/RUNLOG.TXT\r\n");
    return 0;
}

static void runtime_logv(const char *format, va_list args) {
    char line[384];
    if (!runtime_log_ready) return;
    /* No FatFs call may delay a servo packet/phase. Keep only control events. */
    if(arm_motion_busy() && (strncmp(format,"BOX,",4)==0 ||
        strncmp(format,"PERF,",5)==0 || strncmp(format,"JOY_",4)==0 ||
        strncmp(format,"AUTO_T,",7)==0)){
        ++runtime_motion_log_dropped;return;
    }
    int length = vsnprintf(line, sizeof(line), format, args);
    if (length < 0 || length >= (int)sizeof(line)) return;
    if(runtime_log_used+(unsigned)length>sizeof(runtime_log_buffer)){
        if(arm_motion_busy()){++runtime_motion_log_dropped;return;}
        runtime_log_flush();
    }
    if(!runtime_log_ready)return;
    memcpy(runtime_log_buffer+runtime_log_used,line,(unsigned)length);
    runtime_log_used+=(unsigned)length;
}
void runtime_logf(const char *format, ...) {
    va_list args;
    if(!runtime_detail_enabled)return;
    va_start(args,format);runtime_logv(format,args);va_end(args);
}
/* Button, file completion and error events are never hidden by detail gating. */
static void runtime_eventf(const char *format, ...) {
    va_list args;
    va_start(args,format);runtime_logv(format,args);va_end(args);
}

void runtime_log_sync(void) {
    if(arm_motion_busy())return;
    runtime_log_flush();
    if (runtime_log_ready && f_sync(&runtime_log_file) != FR_OK) {
        runtime_log_ready = 0;
        xil_printf("SD_LOG_SYNC_FAILED\r\n");
    }
}

#define sample_log runtime_eventf
#include "sensor_exposure.h"
static void control(u32 value) {set_led(value);}
#include "recognition_app.h"
#include "fusion_app.h"
int main(void) {
    /* DATA must be zero before enabling GPIO outputs. Never expose mode
     * negotiation or partial SCCB writes to the independent preview master. */
    gpio_word=0;Xil_Out32(GPIO_BASE,gpio_word);
    Xil_Out32(GPIO_BASE+4,0);Xil_Out32(GPIO_BASE+12,0xffffffffU);
    fusion_init();
    control(RGB_BLUE);
    runtime_log_open();runtime_eventf("\r\n" BUILD_TAG "\r\n");
    runtime_eventf("ARM_RANGE_POLICY,mode,EXPERIMENTAL_PROTOCOL_RANGE,command_min,0,command_max,1000,planning_margin_raw,0\r\n");
    runtime_eventf("ARM_FEEDBACK_POLICY,upper_percent,120,lower,0,arrival_limits_unchanged,1\r\n");
    runtime_eventf("ARM_BUS_POLICY,rx_error_scope,RECEIVE_ONLY,pre_rx_flush,1,tx_timeout_ms,50,no_move_retry,1\r\n");
    runtime_eventf("ARM_BUS_HW,rx_idle_guard,1,open_delay_clocks,8,clock_hz,100000000\r\n");
    runtime_eventf("UART_SERVICE_POLICY,window_us,%llu,call_limit,%u,deadline_fifo_bytes,32,retries_total,3,move_replay,0;TIMING_IS_SERVICE_OBSERVATION\r\n",
        (unsigned long long)FUSION_BUS_WINDOW_US,FUSION_BUS_WINDOW_CALL_LIMIT);
    runtime_eventf("READ_RECHECK_POLICY,max_per_pick,%u,max_per_group,1,settle_us,%llu,initial_read,1,all_servo_ids,1,move_replay,0,full_group_fresh,1,arrival_limits_unchanged,1,query_quiet_us,%llu,retry1_us,%llu,retry2_us,%llu\r\n",
        ARM_READ_RECOVERY_MAX_PER_REQUEST,(unsigned long long)ARM_READ_RECOVERY_SETTLE_US,
        (unsigned long long)ARM_BUS_QUERY_QUIET_US,(unsigned long long)ARM_READ_RETRY_FIRST_US,
        (unsigned long long)ARM_READ_RETRY_SECOND_US);
    runtime_eventf("AUTO_PICK_POLICY,explicit_start,1,initial_count_limit,1,fresh_reselect,1,max_targets,12,fresh_frames,4,verify_removal_frames,2,verify_removal_and_count,1,new_batch_autostart,0,consumed_frame_expiry_keeps_evidence,1,command_fresh_ms,750,wait_timeout_ms,4000\r\n");
    runtime_eventf("VIDEO_POLICY,preview_write_burst_beats,16,preview_banks,3,actual_new_frame_counter,1,rate_window_ms,3000,camera_exposure_unchanged,0,recognition_input_unchanged,0,recognition_geometry_unchanged,1,weights_unchanged,1,target_millifps,11667,fast30_startup_disabled,1,exposure_ms,30,gain16,111\r\n");
    runtime_eventf("VERTICAL_PICK,pitch,%.0f,pregrasp_z,%.0f,pick_z,%.0f,transport_z,%.0f,margin_raw,0\r\n",
        ARM_VERTICAL_PITCH_DEG,ARM_VERTICAL_PREGRASP_Z_MM,PICK_Z_MM,ARM_VERTICAL_TRANSPORT_Z_MM);
    runtime_eventf("BASE_HEIGHT,riser_mm,%.0f,platform_pick_z_mm,%.0f,robot_pick_z_mm,%.0f,platform_pregrasp_z_mm,13,robot_pregrasp_z_mm,%.0f\r\n",
        PICK_BASE_RISER_MM,PICK_PLATFORM_Z_MM,PICK_Z_MM,ARM_VERTICAL_PREGRASP_Z_MM);
    runtime_eventf("ARM_SMOOTH,transport_internal_settle_ms,0,near_table_waits_preserved,1,home_min_ms,%u,deadline_guard_us,%llu,legacy_fixed_tests_disabled,1\r\n",
        ARM_VISUAL_HOME_MIN_MS,(unsigned long long)ARM_VISUAL_SERVICE_WINDOW_US);
    runtime_eventf("TRANSPORT_PROFILE,whole_phase_quintic_reference,1,local_timing_limits,1,segment_floor_ms,%u,arm_accel_raw_s2,%.0f,wrist_accel_raw_s2,%.0f;DISCRETE_COMMAND_REFERENCE_ONLY\r\n",
        ARM_VISUAL_PROFILE_MIN_MS,ARM_VISUAL_ARM_ACCEL_RAW_S2,ARM_VISUAL_WRIST_ACCEL_RAW_S2);
    runtime_eventf("INITIAL_REUSE,prior_visual_completed_required,1,fresh_six_axes_required,1,max_age_us,%llu,tolerance_raw,%u,open_requires_home_skip,1\r\n",
        (unsigned long long)ARM_INITIAL_REUSE_MAX_AGE_US,ARM_INITIAL_REUSE_TOLERANCE_RAW);
    runtime_eventf("VERTICAL_PATH_POLICY,original_first,1,adaptive_depth,%u,high_align_robot_z,%.0f,pick_pitch,-90,pregrasp_robot_z,%.0f,pick_robot_z,%.0f\r\n",
        ARM_VISUAL_SUBDIVIDE_MAX_DEPTH,ARM_VISUAL_HIGH_ALIGN_Z_MM,ARM_VERTICAL_PREGRASP_Z_MM,PICK_Z_MM);
    runtime_eventf("BASE_MAPPING,platform_origin_mm,0,-150,geometric_y_offset_mm,150,command_y_trim_mm,5,effective_y_offset_mm,155\r\n");
    runtime_eventf("X_CALIBRATION,command_x_trim_mm,%.1f,display_coordinates_unchanged,1\r\n",PICK_COMMAND_X_TRIM_MM);
    runtime_eventf("WRIST_POLICY,sign,-1,center,500,integer_mirror,1;XY_LOCK_AND_CALIBRATION_UNCHANGED\r\n");
    runtime_eventf("UI,SW1_UP,SW3_DOWN,SW2_CONFIRM,SW4_RESET;X_Y_SELECT;Z_SINGLE_PICK_PLATFORM_Z3_BASE100;15_PL_COUNTERS\r\n");
    runtime_eventf("JOYSTICK_POLICY,REVERSE_XY;TIMED_DWELL_REPEAT;NO_NEUTRAL_LOCK;POLL_MS=5;DWELL_MS=40;REPEAT_MS=350;GUARD_MS=150;ENTER=300;HOLD=220;CENTER=180;CAL_MIN=128;CAL_MAX=3967\r\n");
    xil_printf(BUILD_TAG "\r\n");
    ui_raw=ui_stable=ui_read(0x2c)&31U;ui_changed=runtime_ms();ui_released=0;
    ui_message("等待相机");ui_render();
    if(ui_read(0)!=0x4a4f5931U || recognition_load_model()){
        runtime_eventf("HARDWARE_MODEL_MISMATCH\r\n");runtime_log_sync();
        for(;;){ui_message("等待有效识别结果");ui_wait(1000);}
    }
    int camera_ready=0;
    for(unsigned trial=0;trial<3 && !camera_ready;++trial){
        if(sensor_initialize_host()==0 && sensor_configure_baseline()==0)camera_ready=1;
        else{bus_recover();ui_wait(200);}
    }
    if(!camera_ready){
        runtime_eventf("CAMERA_INIT_FAILED\r\n");runtime_log_sync();
        for(;;){ui_message("等待相机");ui_wait(1000);}
    }
    rec_write(0x80,1U);rec_write(0x18,0x100U|40U);rec_write(0x1c,400);rec_write(0x30,0);rec_write(0x74,1);
    if(pipeline_start_camera_profile()){
        runtime_log_sync();
        for(;;){ui_message(pipeline_camera_fault_message);ui_wait(1000);}
    }
    runtime_eventf("POLICY,VIDEO11P7_CAPTURE;highlight_v2_model;MAX_TARGETS12;PL_actual_capture_age;bounded_selected_target_refresh;unchanged_ROI64_and_weights;target_period_ms_200\r\n");
    runtime_log_sync();fusion_ready=1;
    for(;;){
        fusion_service();
        /* Short UART transactions have priority; PL camera/display keep running. */
        if(arm_motion_urgent())continue;
        pipeline_service();fusion_service();
        if(arm_motion_urgent())continue;
        ui_poll();fusion_service();
        if(arm_motion_urgent())continue;
        shot_service();joystick_reset_service();
        control(shot_state?RGB_BLUE:RGB_GREEN);
        if(!arm_motion_urgent())usleep(500);
    }
}
