/* Gate recognition during motion; release targets only after a new coherent scene. */
#ifndef RECOGNITION_MOTION_GATE_H
#define RECOGNITION_MOTION_GATE_H

static unsigned recognition_pick_paused;
static unsigned recognition_fresh_pending;
static unsigned recognition_resume_ms;
static unsigned recognition_clear_ms,recognition_clear_version,recognition_clear_drained;

static unsigned recognition_auto_hidden,recognition_auto_reveal_pending;
static unsigned recognition_auto_reveal_after_ms;

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
         
        usleep(10);rec_write(4,16U);
        capture_active=inference_active=0;
        previous_result=previous_launch=0;
        ui_dirty=1;
        runtime_eventf("VISION_PICK_PAUSE,ms,%u,preview_running,1,boxes_hidden,1\r\n",runtime_ms());
    }else if(!busy && recognition_pick_paused){
        if(!strcmp(arm_motion_state_name(),"ERROR"))return;
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

            recognition_clear_drained=1;coordinate_invalidate();return 1;
        }
    }
    return (unsigned)(now-recognition_resume_ms)>=RECOGNITION_CLEAR_DEADLINE_MS?-1:0;
}

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
