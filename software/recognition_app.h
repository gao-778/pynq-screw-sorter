/* ARM transports parameters and results; CNN computation remains in PL. */
#ifndef RECOGNITION_APP_H
#define RECOGNITION_APP_H
#include "workstation_config.h"
/* Detailed scores remain in RUNLOG; avoid blocking UART output per target. */
#ifndef RECOGNITION_VERBOSE_UART
#define RECOGNITION_VERBOSE_UART 0
#endif
void runtime_logf(const char *format, ...);
void runtime_log_sync(void);
#define REC_BASE 0x42000000U
#include "xil_cache.h"
#include "shape_model.h"
#define MODEL_WEIGHT_COUNT 255510U
#define MODEL_BIAS_COUNT 402U
#define MODEL_SHIFT_COUNT 3U
#if SCREW_MODEL_WEIGHT_COUNT != MODEL_WEIGHT_COUNT
#error "CNN weight header does not match 4D433138 hardware"
#endif
#if SCREW_MODEL_BIAS_COUNT != MODEL_BIAS_COUNT
#error "CNN bias header does not match 4D433138 hardware"
#endif
#if SCREW_MODEL_SHIFT_COUNT != MODEL_SHIFT_COUNT
#error "CNN shift header does not match 4D433138 hardware"
#endif
#ifndef SCREW_MODEL_HARDWARE_ID
#error "MC18 model header must declare its dilation/topology ID"
#elif SCREW_MODEL_HARDWARE_ID != 0x4d433138U
#error "CNN model dilation/topology ID mismatch"
#endif
#define MODEL_WEIGHT_PORT 0x0070U
#define MODEL_BIAS_BASE 0xe800U
#define MODEL_SHIFT_BASE 0xef00U
static u32 rec_read(unsigned offset) {return Xil_In32(REC_BASE+offset);}
static void rec_write(unsigned offset,u32 value) {Xil_Out32(REC_BASE+offset,value);}
static int recognition_load_model(void) {
    if(rec_read(0)!=0x464e4554U || rec_read(0x38)!=REC_HARDWARE_ID || rec_read(REC_CAPACITY_REGISTER)!=REC_MAX_OBJECTS) {
        xil_printf("Shape hardware ID mismatch.\r\n");
        runtime_logf("HW_ID_MISMATCH,0,0,0,%u,0,0,0,0,0,0,0,0,0,0,0,0\r\n",(unsigned)rec_read(0));
        return -1;
    }
    rec_write(4,2);
    for(unsigned n=0;n<MODEL_WEIGHT_COUNT;++n) rec_write(MODEL_WEIGHT_PORT,shape_model_words[n]);
    for(unsigned n=0;n<MODEL_BIAS_COUNT;++n) rec_write(MODEL_BIAS_BASE+n*4,shape_model_words[MODEL_WEIGHT_COUNT+n]);
    for(unsigned n=0;n<MODEL_SHIFT_COUNT;++n) rec_write(MODEL_SHIFT_BASE+n*4,shape_model_words[MODEL_WEIGHT_COUNT+MODEL_BIAS_COUNT+n]);
    rec_write(4,4);
    if((rec_read(8)&0x84)!=4) {
        xil_printf("Shape model commit failed.\r\n");
        runtime_logf("MODEL_COMMIT_FAILED,0,0,0,%u,0,0,0,0,0,0,0,0,0,0,0,0\r\n",(unsigned)rec_read(8));
        return -1;
    }
    xil_printf("MC18: 15 screw classes + NUT_L / NUT_M / NUT_S; CNN and temporal inference in PL.\r\n");
    runtime_logf("MODEL_UPLOAD_OK,0,0,0,%u,0,0,0,0,0,0,0,0,0,0,0,0\r\n",(unsigned)rec_read(8));
    return 0;
}
#define GRAY_DMA_BASE 0x40400000U
#define GRAY_FRAME_BASE 0x10000000U
#define GRAY_FRAME_BYTES 1228800U


#include "platform_coordinates.h"
#include "dashboard_app.h"
#include "vision_failure_diag.h"
static unsigned capture_active,capture_bank,capture_started;
static unsigned inference_active,inference_started,inference_bank,previous_result,previous_launch;
static unsigned pipeline_errors;
static unsigned pipeline_capture_errors,pipeline_last_sensor_restart,pipeline_retry_until;
static unsigned pipeline_camera_recovery_pending;
/* Startup may negotiate profiles only before the one-way preview release.
 * Runtime recovery revalidates gray capture without touching sensor clocks or
 * resetting an AXI master that might still own outstanding transactions. */
static unsigned pipeline_preview_released,pipeline_camera_fault_latched;
static const char *pipeline_camera_fault_message="CAMERA ERROR / RESET REQUIRED";
static unsigned pipeline_accepted_profile=SENSOR_PROFILE_COMPACT11P7;
static unsigned pipeline_profile_retry_mask;
static const char *pipeline_camera_reject_reason="none";
/* Keep per-profile evidence after a fallback; the active profile's success
 * must not erase why a faster candidate failed. Read-only USB status uses it. */
typedef struct {
    unsigned attempts,warmup_bad,validation_bad,last_ms,last_status,last_dma;
    unsigned camera_rate,publish_rate,display_rate,video_status,accepted;
    const char *reason;
} CameraProfileDiagnostic;
static CameraProfileDiagnostic camera_profile_diagnostic[5];
static const char *pipeline_deferred_phase;
static unsigned pipeline_deferred_status;
#include "recognition_motion_gate.h"
static int capture_begin(unsigned bank){
    if(dma_reset_arm(GRAY_DMA_BASE,GRAY_FRAME_BASE+bank*0x200000U,GRAY_FRAME_BYTES))return -1;
    rec_write(0x78,1);usleep(10);
    capture_active=1;capture_bank=bank;capture_started=runtime_ms();return 0;
}
/* Bounded frame validation while motion is inhibited. The
 * model/ABI have already been checked. Probe the SAME capture/DMA path used
 * during recognition; register readback alone never proves a usable frame. */
static int pipeline_probe_camera(unsigned frames){
    capture_active=inference_active=0;
    for(unsigned sample=0;sample<frames;++sample){
        if(arm_motion_busy())return -1;
        CameraProfileDiagnostic *diag=&camera_profile_diagnostic[sensor_profile_id];
        ++diag->attempts;
        if(capture_begin(0))return -1;
        unsigned done=0,start=runtime_ms(),last_capture=0,last_dma=0;
        while((unsigned)(runtime_ms()-start)<1800U){
            last_capture=rec_read(0x7c);last_dma=Xil_In32(GRAY_DMA_BASE+0x34);
            if((last_capture&2U)||(last_dma&0x770U))break;
            if((last_capture&1U)&&(last_dma&0x1000U)){
                unsigned age=rec_read(REC_CAPTURE_AGE_REGISTER);
                if((age&0x80000000U) && (age&0x7fffffffU)<=1800U)done=1;
                break;
            }
            fusion_service();ui_poll();usleep(1000);
        }
        runtime_eventf("CAMERA_PROBE,divider,%02x,sample,%u,ok,%u,capture_ms,%u,status,%08x,dma,%08x\r\n",
            sensor_clock_divider,sample+1U,done,runtime_ms()-start,last_capture,last_dma);
        diag->last_ms=runtime_ms()-start;diag->last_status=last_capture;diag->last_dma=last_dma;
        diag->video_status=ui_read(0x4c);
        rec_write(0x78,2);capture_active=0;
        if(!done)return -1;
    }
    return 0;
}
static int pipeline_warmup_camera(void){
    /* A mode switch may produce a partial frame. Require two consecutive
     * complete discarded frames, but allow bounded startup transients.
     * Persistent failures still reject the profile; validation below is strict. */
    unsigned good=0,started=runtime_ms();
    for(unsigned attempt=0;attempt<8U && (unsigned)(runtime_ms()-started)<6000U;++attempt){
        if(arm_motion_busy())return -1;
        if(!pipeline_probe_camera(1)){
            if(++good==2U)return 0;
        }else{
            ++camera_profile_diagnostic[sensor_profile_id].warmup_bad;good=0;
            unsigned pause=runtime_ms();
            while((unsigned)(runtime_ms()-pause)<camera_period_ms){
                fusion_service();ui_poll();usleep(1000);
                if(arm_motion_busy())return -1;
            }
        }
    }
    return -1;
}
static int pipeline_verify_video_rate(void){
    /* The UI's read-only counters count actual incoming VSYNC, published DDR
     * frames and newly displayed frames. Never substitute expected_millifps. */
    ui_video_sample_valid=ui_video_rate_valid=ui_video_poll_seen=0;
    ui_video_stats_poll(runtime_ms());
    unsigned start=runtime_ms();
    while(!ui_video_rate_valid && (unsigned)(runtime_ms()-start)<4500U){
        if(arm_motion_busy()){pipeline_camera_reject_reason="arm_busy";return -1;}
        fusion_service();ui_poll();ui_video_stats_poll(runtime_ms());usleep(1000);
    }
    if(!ui_video_hardware_valid || !ui_video_rate_valid || ui_video_window_ms<3000U){
        pipeline_camera_reject_reason="no_fresh_rate_window";
        runtime_eventf("CAMERA_RATE_REJECT,profile,%s,reason,%s\r\n",
            sensor_profile_name(sensor_profile_id),pipeline_camera_reject_reason);return -1;
    }
    unsigned fast=sensor_profile_id<=SENSOR_PROFILE_COMPACT11P7;
    unsigned low=camera_expected_millifps*(fast?90U:75U)/100U;
    unsigned high=camera_expected_millifps*(fast?110U:125U)/100U;
    /* Offer acceptance counts are not proof of complete, error-free scanout.
     * FIFO overflow, AXI write/read errors and scanline underflow are fatal.
     * Bank-drop counters alone may reflect a delayed swap, not corrupt data. */
    unsigned frame_errors=ui_video_status&0x0fU;
    unsigned ok=!frame_errors && ui_camera_fps_milli>=low && ui_camera_fps_milli<=high &&
        ui_publish_fps_milli>=low && ui_publish_fps_milli<=high &&
        ui_video_fps_milli>=low && ui_video_fps_milli<=high;
    runtime_eventf("CAMERA_RATE_CHECK,profile,%s,ok,%u,window_ms,%u,camera_millifps,%u,publish_millifps,%u,display_millifps,%u,allowed_low,%u,allowed_high,%u,status,%08x\r\n",
        sensor_profile_name(sensor_profile_id),ok,ui_video_window_ms,ui_camera_fps_milli,
        ui_publish_fps_milli,ui_video_fps_milli,low,high,ui_video_status);
    CameraProfileDiagnostic *diag=&camera_profile_diagnostic[sensor_profile_id];
    diag->camera_rate=ui_camera_fps_milli;diag->publish_rate=ui_publish_fps_milli;
    diag->display_rate=ui_video_fps_milli;diag->video_status=ui_video_status;
    if(!ok){pipeline_camera_reject_reason=frame_errors?"preview_data_path_error":"actual_new_frame_rate_out_of_range";return -1;}
    return 0;
}
static void pipeline_latch_camera_fault(const char *reason,const char *message){
    pipeline_camera_fault_latched=1;pipeline_camera_reject_reason=reason;
    pipeline_camera_fault_message=message;
    fusion_vision_fault();
    rec_write(4,8);rec_write(0x78,2);
    capture_active=inference_active=0;ui_inference_valid=0;ui_fps_milli=0;
    pipeline_camera_recovery_pending=0;pipeline_retry_until=0;
    coordinate_invalidate();
    if(sensor_profile_id>=SENSOR_PROFILE_FAST30 && sensor_profile_id<=SENSOR_PROFILE_BASELINE){
        camera_profile_diagnostic[sensor_profile_id].accepted=0;
        camera_profile_diagnostic[sensor_profile_id].reason=reason;
    }
    ui_message(message);ui_render();
    runtime_eventf("CAMERA_FAULT_LATCHED,reason,%s,profile,%s,preview_released,%u,sensor_reconfigure,0,preview_reset,0,reset_required,1\r\n",
        reason,sensor_profile_name(sensor_profile_id),pipeline_preview_released);
}
static int pipeline_release_preview(void){
    if(pipeline_preview_released || (gpio_word&4U))return -1;
    /* Cold-start only: no preview AW/AR has ever been issued in this boot. */
    gpio_word|=4U;Xil_Out32(GPIO_BASE,gpio_word);pipeline_preview_released=1;
    ui_video_sample_valid=ui_video_rate_valid=ui_video_poll_seen=0;
    runtime_eventf("CAMERA_PREVIEW_RELEASE,profile,%s,gray_validated_frames,5,release_count,1\r\n",
        sensor_profile_name(sensor_profile_id));
    return 0;
}
static int pipeline_try_camera_profile(unsigned profile){
    if(arm_motion_busy()){pipeline_camera_reject_reason="arm_busy";return -1;}
    if(pipeline_preview_released || (gpio_word&4U)){
        pipeline_camera_reject_reason="preview_already_released";return -1;
    }
    memset(&camera_profile_diagnostic[profile],0,sizeof(camera_profile_diagnostic[profile]));
    rec_write(0x78,2);capture_active=inference_active=0;fusion_ready=0;
    pipeline_camera_reject_reason="register_programming_or_readback";
    if(sensor_configure_mode(profile))return -1;
    /* Two full captures are explicitly discarded after mode/exposure changes.
     * Three further complete captures must pass the production DMA/age checks. */
    pipeline_camera_reject_reason="warmup_exhausted";
    if(pipeline_warmup_camera())return -1;
    pipeline_camera_reject_reason="complete_frame_validation_failed";
    if(pipeline_probe_camera(3)){
        ++camera_profile_diagnostic[profile].validation_bad;return -1;
    }
    pipeline_camera_reject_reason="preview_release_state_invalid";
    if(pipeline_release_preview())return -1;
    if(pipeline_verify_video_rate())return -1;
    pipeline_camera_reject_reason="none";pipeline_accepted_profile=profile;
    camera_profile_diagnostic[profile].accepted=1;
    camera_profile_diagnostic[profile].reason="none";
    runtime_eventf("CAMERA_PROFILE_ACCEPTED,profile,%s,discarded_frames,2,validated_frames,3,camera_millifps,%u,display_millifps,%u,measured,1\r\n",
        sensor_profile_name(profile),ui_camera_fps_milli,ui_video_fps_milli);
    ui_message(profile==SENSOR_PROFILE_FAST30?"CAMERA 30FPS / VERIFIED":
        profile==SENSOR_PROFILE_COMPACT11P7?"CAMERA 11.67FPS / VERIFIED":
        profile==SENSOR_PROFILE_BALANCED?"CAMERA 3.3FPS / FALLBACK":"CAMERA 2.5FPS / FALLBACK");
    return 0;
}
static int pipeline_camera_profile_chain(unsigned first){
    for(unsigned profile=first;profile<=SENSOR_PROFILE_BASELINE;++profile){
        if(!pipeline_try_camera_profile(profile))return 0;
        camera_profile_diagnostic[profile].reason=pipeline_camera_reject_reason;
        runtime_eventf("CAMERA_PROFILE_REJECTED,profile,%s,reason,%s,next_profile,%s,preview_released,%u\r\n",
            sensor_profile_name(profile),pipeline_camera_reject_reason,
            !pipeline_preview_released && profile<SENSOR_PROFILE_BASELINE?sensor_profile_name(profile+1U):"NONE",
            pipeline_preview_released);
        rec_write(0x78,2);capture_active=inference_active=0;
        if(pipeline_preview_released){
            pipeline_latch_camera_fault(pipeline_camera_reject_reason,"VIDEO CHECK FAILED / RESET REQUIRED");
            return -1;
        }
        if(arm_motion_busy())return -1;
    }
    sensor_invalidate_profile();
    pipeline_latch_camera_fault("no_valid_gray_profile","CAMERA CHECK FAILED / RESET REQUIRED");
    return -1;
}
static int pipeline_start_camera_profile(void){
    if(arm_motion_busy())return -1;
    if(pipeline_camera_fault_latched || pipeline_preview_released || (gpio_word&4U))return -1;
    ui_message("CAMERA CHECK / PREVIEW HELD");ui_render();
    pipeline_profile_retry_mask=0;fusion_ready=0;
    return pipeline_camera_profile_chain(SENSOR_PROFILE_COMPACT11P7);
}
static int pipeline_recover_camera_profile(void){
    if(arm_motion_busy())return -1;
    if(pipeline_camera_fault_latched)return -1;
    unsigned profile=sensor_profile_id;
    if(profile<SENSOR_PROFILE_FAST30 || profile>SENSOR_PROFILE_BASELINE ||
       !sensor_clock_divider || !exposure_verified){
        pipeline_latch_camera_fault("runtime_profile_invalid","CAMERA CONFIG ERROR / RESET REQUIRED");
        return -1;
    }
    fusion_ready=0;rec_write(0x78,2);capture_active=inference_active=0;usleep(10);
    runtime_eventf("CAMERA_RECOVERY_START,profile,%s,mode,GRAY_ONLY_SAME_SENSOR,sensor_reconfigure,0,preview_reset,0,required_frames,5\r\n",
        sensor_profile_name(profile));
    if(pipeline_probe_camera(5)){
        ++camera_profile_diagnostic[profile].validation_bad;
        pipeline_latch_camera_fault("runtime_gray_revalidation_failed","CAMERA FRAME ERROR / RESET REQUIRED");
        return -1;
    }
    pipeline_camera_reject_reason="none";
    camera_profile_diagnostic[profile].reason="runtime_gray_revalidated";
    ui_message("CAMERA CAPTURE RESTORED");
    return 0;
}
static void pipeline_failure(const char *phase,unsigned status){
    fusion_vision_fault();
    if(arm_motion_busy()){
        pipeline_deferred_phase=phase;pipeline_deferred_status=status;return;
    }
    pipeline_deferred_phase=0;
    unsigned label_overflow=!strcmp(phase,"INFERENCE") && (status&0x10U);
    unsigned failed_frame=rec_read(16);
    runtime_eventf("PIPELINE_FAIL,%s,state,%08x,dma,%08x,phase_ms,%u\r\n",phase,status,
        (unsigned)Xil_In32(GRAY_DMA_BASE+0x34),runtime_ms()-inference_started);
    runtime_eventf("VISION_DETAIL,frame,%u,bank,%u,reader_bank,%u,threshold,%u,labels,%u,foreground,%u,overflow_xy,%08x,scan,%u,cycles,%u,capture,%u\r\n",
        failed_frame,inference_bank,(rec_read(0x74)>>1)&1U,(rec_read(0x84)&255U),rec_read(0x5c),
        rec_read(0x60),rec_read(0x64),rec_read(0x68),rec_read(20),rec_read(0x7c));
    rec_write(4,8);rec_write(0x78,2);usleep(10);rec_write(4,16);
    capture_active=0;inference_active=0;ui_inference_valid=0;ui_fps_milli=0;
    ui_message(label_overflow?"LABEL OVERFLOW / SEE DIAG":"等待有效识别结果");
    coordinate_invalidate();
    ++pipeline_errors;
    /* A CCL/ROI/CNN failure is not proof of a stopped camera. Resetting the
     * sensor for label overflow caused the observed persistent black flashes. */
    if(!strcmp(phase,"CAPTURE") || !strcmp(phase,"CAPTURE_AGE"))++pipeline_capture_errors;
    else pipeline_capture_errors=0;
    if(pipeline_capture_errors>=3) pipeline_camera_recovery_pending=1;
    if(label_overflow)vision_failure_save(inference_bank,failed_frame);
    runtime_eventf("AUTO_T_FAILURE,config,%u,state,%08x,samples,%u\r\n",
        rec_read(0x80),rec_read(0x84),rec_read(0x88));
    pipeline_retry_until=runtime_ms()+300U;
    runtime_log_sync();
}
static void inference_complete(unsigned status){
    /* A completed pre-pick/occluded frame must never repopulate coordinates. */
    recognition_motion_sync();
    if(recognition_motion_paused())return;
    unsigned now=runtime_ms(),objects=rec_read(12),total=rec_read(0x34),frame=rec_read(16);
    if(objects>REC_MAX_OBJECTS || status&8U){pipeline_failure("INFERENCE",status);return;}
    if(previous_result){
        unsigned period=now-previous_result;
        if(period)ui_fps_milli=1000000U/period;
    }
    coordinate_snapshot(objects,frame);
    previous_result=now;inference_active=0;pipeline_errors=0;pipeline_capture_errors=0;ui_inference_valid=1;ui_dirty=1;
    fusion_ready=recognition_resume_waiting()?0U:1U;
    runtime_eventf("PERF,frame,%u,objects,%u,total,%u,processing_ms,%u,rate_millihz,%u,cycles,%u,label,%u,orient,%u,roi,%u,cnn,%u,ddrwait,%u\r\n",
        frame,objects,total,now-inference_started,ui_fps_milli,rec_read(20),rec_read(0x44),rec_read(0x48),rec_read(0x4c),rec_read(0x50),rec_read(0x58));
    unsigned threshold_state=rec_read(0x84);
    runtime_eventf("AUTO_T,frame,%u,T,%u,P50,%u,P90,%u,samples,%u,state,%08x\r\n",
        frame,threshold_state&255U,(threshold_state>>8)&255U,
        (threshold_state>>16)&255U,rec_read(0x88)&65535U,threshold_state);
    for(unsigned n=0;n<objects && (((frame&3U)==0) || fusion_pick_pending());++n){
        unsigned base=0xf000+n*64;
        unsigned class_id=recognition_word_class(rec_read(base+20));
        runtime_eventf("BOX,frame,%u,slot,%u,number,%u,model_id,%u,model_name,%s,xmin,%u,ymin,%u,xmax,%u,ymax,%u,angle,%u,xy_valid,%u,x_mm10,%d,y_mm10,%d\r\n",
            frame,n,recognition_number(class_id),class_id,recognition_class_name(class_id),rec_read(base)&2047U,rec_read(base+4)&2047U,
            rec_read(base+8)&2047U,rec_read(base+12)&2047U,(rec_read(base+20)>>8)&15U,
            coordinate_pending[n].valid,coordinate_pending[n].x_tenth_mm,coordinate_pending[n].y_tenth_mm);
    }
    if((frame&15U)==0 && !fusion_pick_pending())runtime_log_sync();
}
static void pipeline_service(void){
    recognition_motion_sync();
    if(recognition_motion_paused())return;
    if(pipeline_camera_fault_latched){
        /* Keep the reset-required message visible while the independent
         * main-loop UI/USB service remains responsive. */
        if((int)(ui_toast_until-runtime_ms())<1000)ui_message(pipeline_camera_fault_message);
        return;
    }
    if(pipeline_deferred_phase){
        if(!arm_motion_busy())pipeline_failure(pipeline_deferred_phase,pipeline_deferred_status);
        return;
    }
    int display_drained=recognition_pipeline_ready();
    if(display_drained<=0){
        if(display_drained<0)pipeline_latch_camera_fault("display_drain_timeout","DISPLAY SYNC ERROR / RESET REQUIRED");
        return;
    }
    unsigned now=runtime_ms();
    /* A partially applied SCCB profile is never an acceptable recognition
     * source, even if the old stream happens to produce a complete DMA frame.
     * An invalid configuration now requires reset. A valid, unchanged mode
     * may resume only after five full gray frames pass again. */
    if(pipeline_camera_recovery_pending || !sensor_clock_divider || !exposure_verified){
        if(arm_motion_busy())return;
        if(!pipeline_camera_recovery_pending){
            fusion_vision_fault();rec_write(4,8);rec_write(0x78,2);
            capture_active=inference_active=0;ui_inference_valid=0;
            coordinate_invalidate();pipeline_camera_recovery_pending=1;
        }
        if(pipeline_retry_until && (int)(now-pipeline_retry_until)<0)return;
        if(pipeline_last_sensor_restart &&
           (unsigned)(now-pipeline_last_sensor_restart)<10000U)return;
        pipeline_last_sensor_restart=now;
        fusion_ready=0;
        ui_message("CAMERA RECOVERY / PLEASE WAIT");ui_render();
        int restored=pipeline_recover_camera_profile();
        rec_write(0x78,2);capture_active=inference_active=0;
        runtime_eventf("CAMERA_RUNTIME_RECOVERY,ok,%u,profile,%s,validated_frames,%u,reason,%s\r\n",
            (unsigned)(restored==0),sensor_profile_name(sensor_profile_id),restored?0U:5U,pipeline_camera_reject_reason);
        if(restored){
            /* No repeated mode switching/resetting after a terminal fault.
             * The main loop still services HDMI UI, USB status and STOP. */
            ui_message(pipeline_camera_fault_message);
            pipeline_retry_until=0;
        }else{
            pipeline_camera_recovery_pending=0;pipeline_capture_errors=0;
            pipeline_retry_until=0;previous_result=previous_launch=0;
            /* Preserve the same-mode capture-restored message. */
        }
        runtime_log_sync();return;
    }
    if(inference_active){
        unsigned status=rec_read(8);
        if(status&2U){
            inference_complete(status);
            /* Recovery may invalidate capture or defer it until arm STOP ends.
             * Do not reuse 'now' sampled before recovery, or start another DMA
             * in this same invocation after a failed inference. */
            if(!ui_inference_valid || pipeline_deferred_phase)return;
            now=runtime_ms();
        }
        else if((unsigned)(now-inference_started)>5000U){pipeline_failure("TIMEOUT",status);return;}
    }
    /* Preserve the first post-pick result's launch-version until the UI has
     * matched its publication. A second coordinate_begin must not overwrite
     * that pending generation while its mask is still being rendered. */
    if(recognition_resume_waiting() && coordinate_ready)return;
    if(!capture_active){
        if(pipeline_retry_until && (int)(now-pipeline_retry_until)<0)return;
        pipeline_retry_until=0;
        if(capture_begin(0))pipeline_failure("DMA_RESET",0);
        return;
    }
    unsigned capture=rec_read(0x7c),dma=Xil_In32(GRAY_DMA_BASE+0x34);
    /* A complete frame may wait safely in DDR while SD writes delay polling.
       Only an unfinished capture can time out. DMA/capture errors still fail. */
    unsigned capture_complete=(capture&1U) && (dma&0x1000U);
    if((capture&2U)||(dma&0x770U)||
       (!capture_complete && (unsigned)(now-capture_started)>2500U)){
        pipeline_failure("CAPTURE",capture);return;
    }
    if(!inference_active && capture_complete &&
       (!previous_launch || (unsigned)(now-previous_launch)>=REC_LAUNCH_PERIOD_MS)){
        // Finished frame is read-only until inference completes; the other bank
        // receives the next frame. The negotiated sensor mode remains fixed.
        unsigned ready_bank=capture_bank;
        inference_bank=ready_bank;
        /* Age begins at the actual accepted VSYNC in PL, not the request
         * which may have waited almost one sensor period. Round conservatively. */
        unsigned capture_age=rec_read(REC_CAPTURE_AGE_REGISTER);
        if(!(capture_age&0x80000000U) || (capture_age&0x7fffffffU)>2500U){
            pipeline_failure("CAPTURE_AGE",capture_age);return;
        }
        coordinate_source_ms=runtime_ms()-(capture_age&0x7fffffffU)-1U;
        coordinate_begin();
        rec_write(0x74,1U|(ready_bank<<1));rec_write(4,1);usleep(10);
        inference_active=1;inference_started=now;previous_launch=now;++run_attempt;
        capture_active=0;
        if(capture_begin(1U-ready_bank))pipeline_failure("DMA_RESET",0);
    }
}
#endif
