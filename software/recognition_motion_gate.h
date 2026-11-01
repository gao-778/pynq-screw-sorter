#ifndef RECOGNITION_MOTION_GATE_H
#define RECOGNITION_MOTION_GATE_H
/* A pick owns its immutable target until return-home/release or completed STOP.
 * Preview and sensor configuration are independent: never reset either here.
 * 0x50 bit 0 hides boxes/selection at the next video blanking boundary.
 * Inference abort invalidates the DDR reader cache; its accepted AXI burst is
 * still drained by ddr_gray_reader. Command 16 then publishes an empty scene.
 * No model upload, ledger reset, bus transaction or filesystem call is needed. */
static unsigned recognition_pick_paused;
static unsigned recognition_fresh_pending;
static unsigned recognition_resume_ms;
static unsigned recognition_clear_ms,recognition_clear_version,recognition_clear_drained;
/* Keep the overlay hidden across every inter-pick inference in one batch.
 * A terminal batch requests a NEW scene before revealing anything; this
 * presentation latch must never stop capture, CNN or coordinate publication. */
static unsigned recognition_auto_hidden,recognition_auto_reveal_pending;
static unsigned recognition_auto_reveal_after_ms;
/* detection_overlay_obb runs at 74.25 MHz, not the 100 MHz AXI clock.
 * One pixel costs 5*N+5 clocks. At N=12 an old mask costs at most
 * (192+76800*65)/74250000 + one 60 Hz frame = 83.91 ms.
 * The queued zero-object clear costs (192+76800*5)/74250000 + one
 * frame = 21.85 ms; CDC/ledger overhead is below 0.01 ms. Thus 200 ms
 * from abort strictly exceeds the <106 ms old-mask + clear bound.
 * A changed coherent empty ledger is required as well: elapsed time alone
 * cannot prove a running display clock. The wait never blocks the CPU. */
#define RECOGNITION_CLEAR_DRAIN_MS 200U
#define RECOGNITION_CLEAR_DEADLINE_MS 1000U

static unsigned recognition_motion_paused(void){return recognition_pick_paused;}
static unsigned recognition_resume_waiting(void){
    return recognition_fresh_pending && !recognition_pick_paused;
}
static unsigned recognition_results_hidden(void){
    return recognition_pick_paused || recognition_fresh_pending ||
           recognition_auto_hidden || auto_pick_is_running();
}
static void recognition_visibility_sync(void){
    if(auto_pick_is_running()){
        if(!recognition_auto_hidden){
            recognition_auto_hidden=1;ui_write(0x50,1U);ui_dirty=1;
        }
        recognition_auto_reveal_pending=0;
    }else if(recognition_auto_hidden && !recognition_auto_reveal_pending){
        recognition_auto_reveal_pending=1;
        recognition_auto_reveal_after_ms=runtime_ms();ui_dirty=1;
    }
}
static void recognition_motion_sync(void){
    recognition_visibility_sync();
    unsigned busy=(unsigned)arm_motion_busy();
    if(busy && !recognition_pick_paused){
        recognition_pick_paused=1;recognition_fresh_pending=1;
        ui_write(0x50,1U);
        recognition_clear_version=ui_read(4);recognition_clear_ms=runtime_ms();
        recognition_clear_drained=0;
        fusion_ready=0;ui_inference_valid=0;ui_fps_milli=0;
        coordinate_invalidate();
        rec_write(4,8U);rec_write(0x78,2U);
        /* Ensure abort drops DONE before the empty scene raises it again. */
        usleep(10);rec_write(4,16U);
        capture_active=inference_active=0;
        previous_result=previous_launch=0;
        ui_dirty=1;
        runtime_eventf("VISION_PICK_PAUSE,ms,%u,preview_running,1,boxes_hidden,1\r\n",runtime_ms());
    }else if(!busy && recognition_pick_paused){
        recognition_pick_paused=0;recognition_resume_ms=runtime_ms();
        fusion_ready=0;ui_inference_valid=0;ui_fps_milli=0;
        coordinate_invalidate();
        capture_active=inference_active=0;previous_result=previous_launch=0;
        ui_dirty=1;
        runtime_eventf("VISION_PICK_RESUME,ms,%u,require_new_capture,1,boxes_hidden_until_publish,1\r\n",recognition_resume_ms);
    }
}
static int recognition_pipeline_ready(void){
    if(!recognition_fresh_pending || recognition_clear_drained)return 1;
    unsigned now=runtime_ms();
    if((unsigned)(now-recognition_clear_ms)>=RECOGNITION_CLEAR_DRAIN_MS){
        unsigned version=ui_read(4),status=ui_read(8),end_version=ui_read(4);
        if(version==end_version && version!=recognition_clear_version &&
           !(status&256U) && !(status&63U)){
            /* Empty clear may already have aged to invalid after a long pick;
             * zero count plus the coherent publication, not VALID, is the
             * drain proof. No new inference has been allowed to overwrite it. */
            recognition_clear_drained=1;coordinate_invalidate();return 1;
        }
    }
    return (unsigned)(now-recognition_resume_ms)>=RECOGNITION_CLEAR_DEADLINE_MS?-1:0;
}
/* Called immediately after coordinate_publish. A completed CNN calculation
 * alone is insufficient: wait for its matching display scene and a camera
 * exposure acquired AFTER the executor has reached a terminal state. */
static void recognition_scene_published(void){
    recognition_visibility_sync();
    if(recognition_pick_paused || arm_motion_busy())return;
    if(!recognition_fresh_pending && !recognition_auto_reveal_pending)return;
    if(!ui_inference_valid || !coordinate_valid)return;
    unsigned version=ui_read(4),status=ui_read(8);
    if(version!=ui_read(4) || version!=coordinate_visible_version ||
       (status&256U) || !(status&128U) || (status&63U)!=coordinate_count)return;
    if(recognition_fresh_pending){
        if(!recognition_clear_drained ||
           (int32_t)(coordinate_visible_source_ms-recognition_resume_ms)<=0)return;
        recognition_fresh_pending=0;fusion_ready=1;ui_dirty=1;
        runtime_eventf("VISION_PICK_FRESH,frame,%u,captured_ms,%u,resume_ms,%u,ui_hidden,%u\r\n",
            coordinate_frame,coordinate_visible_source_ms,recognition_resume_ms,
            recognition_auto_hidden);
    }
    if(recognition_auto_reveal_pending && !auto_pick_is_running() &&
       (int32_t)(coordinate_visible_source_ms-recognition_auto_reveal_after_ms)>0){
        recognition_auto_hidden=recognition_auto_reveal_pending=0;ui_dirty=1;
        runtime_eventf("VISION_BATCH_REVEAL,frame,%u,captured_ms,%u,after_ms,%u\r\n",
            coordinate_frame,coordinate_visible_source_ms,recognition_auto_reveal_after_ms);
    }
    if(!recognition_results_hidden())ui_write(0x50,0U);
}
#endif
