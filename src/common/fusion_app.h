#ifndef FUSION_APP_H
#define FUSION_APP_H

#include "xparameters.h"
#define FUSION_CONSOLE_BASE XPAR_XUARTPS_0_BASEADDR
#define FUSION_CONSOLE_STATUS 0x2cU
#define FUSION_CONSOLE_FIFO 0x30U
#define FUSION_RX_EMPTY 2U
#define FUSION_TX_FULL 16U
static unsigned fusion_available,fusion_confirm_until,fusion_previous_busy;
static unsigned fusion_last_cycle,fusion_state_seen,fusion_sw4_since,fusion_sw4_down;
static char fusion_last_state[48];
static char fusion_command[64];
static unsigned fusion_command_used,fusion_command_discard;
static unsigned fusion_status_pending,fusion_failure_status_pending;
 
static char fusion_tx[4096];
static unsigned fusion_tx_head,fusion_tx_tail,fusion_tx_dropped;
#define FUSION_BUS_WINDOW_US UINT64_C(1000)
#define FUSION_BUS_WINDOW_CALL_LIMIT 256U

static uint64_t fusion_now_us(void){
    XTime tick;XTime_GetTime(&tick);
    return fusion_ticks_us(tick);
}
static uint32_t fusion_read32(void *user,uintptr_t address){
    (void)user;return Xil_In32(address);
}
static void fusion_write32(void *user,uintptr_t address,uint32_t value){
    (void)user;Xil_Out32(address,value);
}
static void fusion_console_write(const char *text){
    while(*text){
        unsigned next=(fusion_tx_tail+1U)%sizeof(fusion_tx);
        if(next==fusion_tx_head){++fusion_tx_dropped;return;}
        fusion_tx[fusion_tx_tail]=*text++;fusion_tx_tail=next;
    }
}
#include "fusion_pick_app.h"
#include "auto_pick_app.h"

static void fusion_pick_feedback_status(unsigned to_log){
    ArmPickFeedback feedback;
    char line[192];
    int valid=arm_motion_get_pick_feedback(&feedback);
    snprintf(line,sizeof(line),"GRIP_FEEDBACK,valid,%u;VALID_IS_COMPLETE_READ_NOT_GRASP_SUCCESS\r\n",(unsigned)valid);
    if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    if(!valid)return;
    snprintf(line,sizeof(line),"GRIP_PLAN,action_zero_based,%u,mask,%02x,x_mm,%.3f,y_mm,%.3f,z_mm,%.3f,pitch_deg,%.3f\r\n",
        feedback.action_index,feedback.mask,feedback.pose[0],feedback.pose[1],feedback.pose[2],feedback.pose[3]);
    if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    for(unsigned id=1;id<=6;++id)if(feedback.mask&(1U<<id)){
        snprintf(line,sizeof(line),"GRIP_SERVO,id,%u,target_raw,%d,feedback_raw,%d,delta_raw,%d\r\n",
            id,(int)feedback.commanded[id],feedback.measured[id],feedback.measured[id]-(int)feedback.commanded[id]);
        if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    }
}
 
static void fusion_bus_fault_status(unsigned to_log){
    ArmBusDiagnostic diagnostic;
    char line[192];
    int valid=arm_motion_get_bus_fault(&diagnostic);
    if(valid){
        snprintf(line,sizeof(line),"ARM_BUS_FAULT,valid,1,phase,%s,command,%u,id,%u,lsr,%02x,queued,%u,received,%u,elapsed_us,%llu,error_code,%u\r\n",
            arm_bus_phase_name(diagnostic.phase),diagnostic.command,diagnostic.servo_id,
            diagnostic.lsr,diagnostic.queued_bytes,diagnostic.received_bytes,
            (unsigned long long)diagnostic.elapsed_us,diagnostic.error_code);
    }else snprintf(line,sizeof(line),"ARM_BUS_FAULT,valid,0\r\n");
    if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    if(valid){
        snprintf(line,sizeof(line),"ARM_BUS_TIMING,max_service_gap_us,%llu,rx_enable_us,%llu,first_rx_us,%llu,deadline_check,%u,deadline_accept,%u\r\n",
            (unsigned long long)diagnostic.max_service_gap_us,
            (unsigned long long)diagnostic.rx_enabled_elapsed_us,
            (unsigned long long)diagnostic.first_rx_elapsed_us,
            diagnostic.deadline_fifo_check,diagnostic.accepted_at_deadline);
        if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    }
}
 
static void fusion_last_failure_status(unsigned to_log,unsigned detailed){
    ArmMotionFailure failure;
    char line[256];
    int valid=arm_motion_get_last_failure(&failure);
    if(valid){
        snprintf(line,sizeof(line),"LAST_FAILURE,valid,1,sequence,%u,error,%s,phase,%s,id,%u,action,%u,total,%u,retries,%u\r\n",
            failure.sequence,arm_motion_error_name(failure.error_code),
            failure.action_valid?arm_phase_name(failure.phase):"NO_ACTION",
            failure.fault_servo,failure.action_index,failure.action_count,failure.query_retries);
    }else snprintf(line,sizeof(line),"LAST_FAILURE,valid,0\r\n");
    if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    if(!valid || !detailed)return;
    snprintf(line,sizeof(line),"LAST_FAILURE_POSE,valid,%u,x,%.3f,y,%.3f,z,%.3f,pitch,%.3f,command_mask,%02x,actual_mask,%02x,motion_attempted,%u\r\n",
        failure.action_valid,failure.pose[0],failure.pose[1],failure.pose[2],failure.pose[3],
        failure.commanded_mask,failure.actual_mask,failure.motion_attempted);
    if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    if(failure.bus_valid){
        const ArmBusDiagnostic *b=&failure.bus;
        snprintf(line,sizeof(line),"LAST_FAILURE_BUS,phase,%s,cmd,%u,id,%u,lsr,%02x,queued,%u,received,%u,elapsed_us,%llu,error_code,%u\r\n",
            arm_bus_phase_name(b->phase),b->command,b->servo_id,b->lsr,b->queued_bytes,b->received_bytes,
            (unsigned long long)b->elapsed_us,b->error_code);
        if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
        snprintf(line,sizeof(line),"LAST_FAILURE_TIMING,gap_us,%llu,rx_enable_us,%llu,first_rx_us,%llu,deadline_check,%u,deadline_accept,%u\r\n",
            (unsigned long long)b->max_service_gap_us,(unsigned long long)b->rx_enabled_elapsed_us,
            (unsigned long long)b->first_rx_elapsed_us,b->deadline_fifo_check,b->accepted_at_deadline);
        if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    }
    for(unsigned k=0;k<failure.read_failure_count && k<3U;++k){
        const ArmReadAttemptFailure *attempt=&failure.read_failures[k];
        const ArmBusDiagnostic *b=&attempt->bus;
        snprintf(line,sizeof(line),"LAST_FAILURE_READ,attempt,%u,id,%u,received,%u,elapsed_us,%llu,error_code,%u,gap_us,%llu,rx_enable_us,%llu,first_rx_us,%llu,deadline_check,%u\r\n",
            attempt->attempt,b->servo_id,b->received_bytes,(unsigned long long)b->elapsed_us,b->error_code,
            (unsigned long long)b->max_service_gap_us,(unsigned long long)b->rx_enabled_elapsed_us,
            (unsigned long long)b->first_rx_elapsed_us,b->deadline_fifo_check);
        if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    }
    for(unsigned id=1;id<=6;++id)if((failure.commanded_mask|failure.actual_mask)&(1U<<id)){
        snprintf(line,sizeof(line),"LAST_FAILURE_SERVO,id,%u,command_valid,%u,target,%d,feedback_valid,%u,feedback,%d\r\n",
            id,(failure.commanded_mask>>id)&1U,(int)failure.commanded[id],
            (failure.actual_mask>>id)&1U,failure.actual[id]);
        if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    }
}
 
static void fusion_read_recovery_status(unsigned to_log,unsigned detailed){
    ArmReadRecovery recovery;
    char line[256];
    int attempted=arm_motion_get_read_recovery(&recovery);
    snprintf(line,sizeof(line),"READ_RECOVERY,attempted,%u,active,%u,succeeded,%u,error,%s,action,%u,phase,%s,id,%u,mask,%02x,fresh_mask,%02x,settle_us,%llu;FULL_GROUP_FRESH_NO_MOVE_REPLAY\r\n",
        (unsigned)attempted,recovery.active,recovery.succeeded,arm_motion_error_name(recovery.error_code),recovery.action_index,
        attempted?arm_phase_name(recovery.phase):"NONE",recovery.fault_servo,recovery.read_mask,recovery.fresh_mask,
        (unsigned long long)ARM_READ_RECOVERY_SETTLE_US);
    if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    if(!attempted || !detailed)return;
    snprintf(line,sizeof(line),"READ_RECOVERY_BUDGET,attempts,%u,succeeded,%u,limit,%u,per_group,1,purpose,%u\r\n",
        recovery.attempts_total,recovery.successes_total,ARM_READ_RECOVERY_MAX_PER_REQUEST,recovery.read_purpose);
    if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    snprintf(line,sizeof(line),"READ_RECOVERY_TIME,started_us,%llu,recheck_started_us,%llu,initial_failures,%u\r\n",
        (unsigned long long)recovery.started_us,(unsigned long long)recovery.recheck_started_us,recovery.read_failure_count);
    if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    for(unsigned k=0;k<recovery.read_failure_count && k<3U;++k){
        const ArmReadAttemptFailure *a=&recovery.read_failures[k];
        const ArmBusDiagnostic *b=&a->bus;
        snprintf(line,sizeof(line),"READ_RECOVERY_ORIGINAL,attempt,%u,id,%u,received,%u,elapsed_us,%llu,error_code,%u,gap_us,%llu,rx_enable_us,%llu\r\n",
            a->attempt,b->servo_id,b->received_bytes,(unsigned long long)b->elapsed_us,b->error_code,
            (unsigned long long)b->max_service_gap_us,(unsigned long long)b->rx_enabled_elapsed_us);
        if(to_log)runtime_eventf("%s",line);else fusion_console_write(line);
    }
}
static void fusion_camera_status(void){
    char line[384];
    snprintf(line,sizeof(line),"CAMERA_STATUS,build,%s,active,%s,camera_millifps,%u,publish_millifps,%u,display_millifps,%u,rate_valid,%u,video_status,%08x\r\n",
        BUILD_TAG,sensor_profile_name(sensor_profile_id),ui_camera_fps_milli,
        ui_publish_fps_milli,ui_video_fps_milli,ui_video_rate_valid,ui_video_status);
    fusion_console_write(line);
    for(unsigned p=1;p<=4U;++p){
        const CameraProfileDiagnostic *d=&camera_profile_diagnostic[p];
        snprintf(line,sizeof(line),"CAMERA_HISTORY,profile,%s,accepted,%u,attempts,%u,warmup_bad,%u,validation_bad,%u,reason,%s,last_ms,%u,capture,%08x,dma,%08x,camera_millifps,%u,publish_millifps,%u,display_millifps,%u,video_status,%08x\r\n",
            sensor_profile_name(p),d->accepted,d->attempts,d->warmup_bad,d->validation_bad,
            d->reason?d->reason:"not_tried",d->last_ms,d->last_status,d->last_dma,
            d->camera_rate,d->publish_rate,d->display_rate,d->video_status);
        fusion_console_write(line);
    }
}
static void fusion_console_status(void){
    char line[192];
    fusion_console_write("FIRMWARE=" BUILD_TAG " MODE=PITCH90 WRIST_SIGN=-1\r\n");
    snprintf(line,sizeof(line),"ARM state=%s cycle=%u busy=%u error=%s ready=%u hw=%u fault_id=%u actual=%d actions=%u/%u\r\n",
        arm_motion_state_name(),arm_motion_cycle(),(unsigned)arm_motion_busy(),
        arm_motion_last_error(),fusion_ready,fusion_available,
        arm_motion_fault_servo(),arm_motion_last_position(arm_motion_fault_servo()),
        arm_motion_completed_actions(),arm_motion_action_count());
    fusion_console_write(line);
    snprintf(line,sizeof(line),"ARM_UART,bus_error,%s,query_retries,%u,query_line_errors,%u,fault_lsr,%02x,stop_attempt_mask,%02x\r\n",
        arm_motion_bus_error(),arm_motion_query_retries(),arm_motion_query_line_errors(),
        arm_motion_fault_lsr(),arm_motion_stop_attempt_mask());
    fusion_console_write(line);
    snprintf(line,sizeof(line),"ARM_TX_RX_NOISE,transactions_all_tx,%u,observed_lsr_or,%02x\r\n",
        arm_bus_tx_rx_error_events(),arm_bus_tx_rx_error_lsr());
    fusion_console_write(line);
    fusion_console_write("EXPERIMENTAL RANGE: COMMAND 0..1000; MARGIN=0; FEEDBACK 0..1200; ARRIVAL TOLERANCE UNCHANGED\r\n");
    snprintf(line,sizeof(line),"VERTICAL_PICK,pitch,%.0f,pregrasp_z,%.0f,pick_z,%.0f,transport_z,%.0f,margin_raw,0\r\n",
        ARM_VERTICAL_PITCH_DEG,ARM_VERTICAL_PREGRASP_Z_MM,PICK_Z_MM,ARM_VERTICAL_TRANSPORT_Z_MM);
    fusion_console_write(line);
    snprintf(line,sizeof(line),"CAL BASE: Xr=Xc%+.0fmm; Yr=Yc+%.0f%+.0fmm; platform_Z=%.0f; base_riser=%.0f; robot_Z=%.0fmm; PLACE THEN HOME\r\n",
        PICK_COMMAND_X_TRIM_MM,PICK_CAMERA_BASE_Y_MM,PICK_COMMAND_Y_TRIM_MM,PICK_PLATFORM_Z_MM,PICK_BASE_RISER_MM,PICK_Z_MM);
    fusion_console_write(line);
    snprintf(line,sizeof(line),"PICK_LOCAL_Y_POLICY,platform_start_y,%.1f,platform_full_y,%.1f,max_offset_y,%.1f,curve,smoothstep,scope,PICK_COMMAND_ONLY\r\n",
        PICK_LOCAL_Y_START_MM,PICK_LOCAL_Y_FULL_MM,PICK_LOCAL_Y_MAX_MM);
    fusion_console_write(line);
    fusion_bus_fault_status(0);
    fusion_last_failure_status(0,0);
    fusion_read_recovery_status(0,0);
    fusion_pick_feedback_status(0);
}
static void fusion_request(unsigned mode){
    

    (void)mode;fusion_confirm_until=0;ui_dirty=1;
    ui_message("USE SELECTED PICK / BASE+100");
    fusion_console_write("ARM REJECT: LEGACY FIXED TEST DISABLED AFTER BASE RISER; USE SELECTED VERTICAL PICK\r\n");
}
static void fusion_menu_confirm(void){
    if(arm_motion_busy()){
        arm_motion_cancel();fusion_confirm_until=0;ui_message("ARM STOP REQUEST");return;
    }
    unsigned now=runtime_ms();
    if(fusion_confirm_until && (int)(fusion_confirm_until-now)>0){fusion_pick_press();return;}
    fusion_confirm_until=now+5000U;ui_message("PRESS AGAIN: SELECTED PICK");
}
static void fusion_menu_cancel(void){fusion_confirm_until=0;}
static void fusion_status_line(char *line,unsigned capacity){
    if(!fusion_available){snprintf(line,capacity,"INTERFACE NOT READY");return;}
    if(fusion_confirm_until && (int)(fusion_confirm_until-runtime_ms())>0){
        snprintf(line,capacity,"CONFIRM AGAIN / 5s");return;
    }
    const char *state=arm_motion_state_name();
    if(!strcmp(state,"ERROR")){
        ArmBusDiagnostic diagnostic;
        if(arm_motion_get_bus_fault(&diagnostic)){
            const char *window=!strcmp(arm_bus_phase_name(diagnostic.phase),"RECEIVE")?"RX":"TX";
            snprintf(line,capacity,"ERR %s %s S%u C%u",arm_motion_bus_error(),window,
                diagnostic.servo_id,arm_motion_cycle());
        }else snprintf(line,capacity,"ERROR %s C%u",arm_motion_last_error(),arm_motion_cycle());
        return;
    }
    const char *display=!strcmp(state,"RUNNING")?arm_motion_phase_name():state;
    snprintf(line,capacity,"%s C%u",display,arm_motion_cycle());
}
static void fusion_vision_fault(void){
    auto_pick_vision_fault();
    fusion_confirm_until=0;fusion_ready=0;fusion_pick_cancel_pending("VISION UNAVAILABLE");
    

    if(arm_motion_busy() && !fusion_visual_active)arm_motion_cancel();
}
static void fusion_parse_command(void){
    fusion_command[fusion_command_used]=0;
    if(arm_motion_urgent() && strcmp(fusion_command,"ARM STOP") && strcmp(fusion_command,"STOP")){
        if(!strcmp(fusion_command,"ARM STATUS"))fusion_status_pending=1;
        else if(!strcmp(fusion_command,"ARM LASTERROR"))fusion_failure_status_pending=1;
        else if(fusion_command_used)fusion_console_write("BUSY: COMMAND NOT QUEUED\r\n");
        fusion_command_used=0;return;
    }
    if(!strcmp(fusion_command,"ARM STOP") || !strcmp(fusion_command,"STOP")){
        auto_pick_cancel("USB STOP",0);
        fusion_pick_cancel_pending("PICK CANCELLED");arm_motion_cancel();fusion_confirm_until=0;fusion_console_write("ARM STOP REQUESTED\r\n");
    }else if(!strcmp(fusion_command,"ARM FRONT"))fusion_request(1);
    else if(!strcmp(fusion_command,"ARM NINE"))fusion_request(2);
    else if(!strcmp(fusion_command,"ARM STATUS"))fusion_console_status();
    else if(!strcmp(fusion_command,"CAMERA STATUS"))fusion_camera_status();
    else if(!strcmp(fusion_command,"ARM LASTERROR"))fusion_failure_status_pending=1;
    else if(!strcmp(fusion_command,"HELP"))
        fusion_console_write("ARM STATUS | ARM LASTERROR | CAMERA STATUS | ARM STOP | Ctrl-C\r\nSELECTED PICK: Z once > BIN1; CLASS PICK > BIN2; SORT ALL > CLASS BINS1..4\r\nPLATFORM Z=3mm / ROBOT Z=-97mm; BASE RISER=100mm; NO BOOT MOTION\r\nARM FRONT/NINE: DISABLED LEGACY FIXED TESTS\r\n");
    else if(fusion_command_used)fusion_console_write("ERROR: UNKNOWN COMMAND; HELP\r\n");
    fusion_command_used=0;
}
static void fusion_console_poll(void){
#if !defined(SCREWSORT_LINUX)
    for(unsigned n=0;n<8;++n){
        if(Xil_In32(FUSION_CONSOLE_BASE+FUSION_CONSOLE_STATUS)&FUSION_RX_EMPTY)break;
        unsigned byte=Xil_In32(FUSION_CONSOLE_BASE+FUSION_CONSOLE_FIFO)&255U;
        if(byte==3){
            auto_pick_cancel("USB CANCEL",0);
            fusion_pick_cancel_pending("PICK CANCELLED");arm_motion_cancel();fusion_confirm_until=0;fusion_command_used=0;fusion_command_discard=0;
            fusion_console_write("ARM CANCEL REQUESTED\r\n");continue;
        }
        if(byte=='\r' || byte=='\n'){
            if(!fusion_command_discard)fusion_parse_command();
            else fusion_console_write("ERROR: COMMAND DISCARDED\r\n");
            fusion_command_discard=0;fusion_command_used=0;
        }else if(!fusion_command_discard){
            if(byte<32 || byte>126 || fusion_command_used>=sizeof(fusion_command)-1){
                fusion_command_discard=1;fusion_command_used=0;
            }else fusion_command[fusion_command_used++]=(char)byte;
        }
    }
    for(unsigned n=0;n<16 && fusion_tx_head!=fusion_tx_tail;++n){
        if(Xil_In32(FUSION_CONSOLE_BASE+FUSION_CONSOLE_STATUS)&FUSION_TX_FULL)break;
        Xil_Out32(FUSION_CONSOLE_BASE+FUSION_CONSOLE_FIFO,(unsigned char)fusion_tx[fusion_tx_head]);
        fusion_tx_head=(fusion_tx_head+1U)%sizeof(fusion_tx);
    }
#endif
}
static void fusion_fast_stop_poll(void){
    unsigned now=runtime_ms(),raw=ui_read(0x2c)&31U;
    if(!(raw&16U)){fusion_sw4_down=0;return;}
    if(!fusion_sw4_down){fusion_sw4_down=1;fusion_sw4_since=now;}
    if(fusion_sw4_down==2U){
        ui_raw=raw;ui_stable=raw;ui_released=0;ui_changed=now;return;
    }
    if((arm_motion_busy() || auto_pick_is_running() || auto_pick_is_open()) &&
       (unsigned)(now-fusion_sw4_since)>=25U){
        fusion_sw4_down=2U;
        auto_pick_cancel("SW4 STOP",0);
        arm_motion_cancel();fusion_confirm_until=0;
         
        ui_raw=raw;ui_stable=raw;ui_released=0;ui_changed=now;
    }
}

static void fusion_motion_service_window(void){
    uint64_t started=fusion_now_us();
    arm_motion_service(started);
    for(unsigned calls=1;arm_motion_transport_busy() && calls<FUSION_BUS_WINDOW_CALL_LIMIT;++calls){
        uint64_t now=fusion_now_us();
        if(now<started){arm_motion_service(now);break;}
        if(now-started>=FUSION_BUS_WINDOW_US)break;
        arm_motion_service(now);
    }
}
static void fusion_service(void){
    recognition_motion_sync();
    fusion_motion_service_window();
    recognition_motion_sync();
    fusion_fast_stop_poll();fusion_console_poll();
    fusion_pick_service();
    if(arm_motion_urgent()){
        fusion_previous_busy=(unsigned)arm_motion_busy();return;
    }
    if(fusion_status_pending){
        fusion_status_pending=0;fusion_console_status();
    }
    if(fusion_failure_status_pending && fusion_tx_head==fusion_tx_tail &&
       !(fusion_previous_busy && !arm_motion_busy())){
        fusion_failure_status_pending=0;fusion_last_failure_status(0,1);
        fusion_read_recovery_status(0,1);
    }
    const char *state=arm_motion_busy()?arm_motion_phase_name():arm_motion_state_name();
    unsigned cycle=arm_motion_cycle();
    unsigned busy=(unsigned)arm_motion_busy();
    if(!fusion_state_seen || strcmp(fusion_last_state,state) || cycle!=fusion_last_cycle){
        snprintf(fusion_last_state,sizeof(fusion_last_state),"%s",state);
        fusion_last_cycle=cycle;fusion_state_seen=1;ui_dirty=1;
        runtime_eventf("ARM_STATE,%s,cycle,%u,error,%s,ms,%u\r\n",state,cycle,arm_motion_last_error(),runtime_ms());
    }
    if(fusion_previous_busy && !busy){
        ArmVisualPlanDiagnostic transport_profile;
        arm_visual_plan_get_diagnostic(&transport_profile);
        fusion_visual_active=0;
        runtime_eventf("ARM_FINISH,%s,error,%s,vision_log_lines_omitted,%u,console_dropped,%u\r\n",
            state,arm_motion_last_error(),runtime_motion_log_dropped,fusion_tx_dropped);
        runtime_eventf("ARM_RESULT,actions,%u,planned,%u,retries,%u,fault_id,%u,stop_attempt_mask,%u,skipped_initial,%u\r\n",
            arm_motion_completed_actions(),arm_motion_action_count(),arm_motion_query_retries(),
            arm_motion_fault_servo(),arm_motion_stop_attempt_mask(),arm_motion_skipped_initial_actions());
        runtime_eventf("ARM_PROFILE,retimed_phases,%u,legacy_timing_fallbacks,%u\r\n",
            transport_profile.retimed_phases,transport_profile.profile_fallbacks);
        runtime_eventf("ARM_BUS_ERROR,%s\r\n",arm_motion_bus_error());
        runtime_eventf("ARM_UART_DIAG,query_line_errors,%u,fault_lsr,%02x,tx_rx_noise_transactions_all_tx,%u,tx_rx_noise_lsr_or,%02x\r\n",
            arm_motion_query_line_errors(),arm_motion_fault_lsr(),
            arm_bus_tx_rx_error_events(),arm_bus_tx_rx_error_lsr());
        for(unsigned id=1;id<=6;++id)
            runtime_eventf("ARM_POSITION,id,%u,raw,%d\r\n",id,arm_motion_last_position(id));
        fusion_bus_fault_status(1);
        if(!strcmp(state,"ERROR"))fusion_last_failure_status(1,1);
        fusion_read_recovery_status(1,1);
        fusion_pick_feedback_status(1);
        fusion_console_status();runtime_log_sync();
        auto_pick_motion_finished(state);
    }
    auto_pick_service();
    fusion_previous_busy=(unsigned)arm_motion_busy();
}
static void fusion_init(void){
    arm_bus_hal_t hal={fusion_read32,fusion_write32,0};
    fusion_available=arm_bus_init(&hal)==0;
    arm_motion_init();fusion_ready=0;
    fusion_failure_status_pending=0;
    fusion_console_write("HD15 ARM FUSION: boot is motion-idle. Type HELP.\r\n");
}
#endif
