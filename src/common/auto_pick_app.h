#ifndef AUTO_PICK_APP_H
#define AUTO_PICK_APP_H
#include "auto_pick_api.h"
#include "sort_bins.h"

#define AUTO_PICK_FRAME_WAIT_MS 4000U
#define AUTO_PICK_REMOVE_RADIUS_MM 5.0
#define AUTO_TARGET_CONFIRM_FRAMES 4U
#define AUTO_TARGET_CONFIRM_SPAN_MS 300U
#define AUTO_TARGET_SAMPLE_SPACING_MS 100U
#define AUTO_TARGET_SPREAD_MM 1.0
#define AUTO_TARGET_AXIS_DOT_MIN 0.9902680687415704  
#define AUTO_VIEW_EXPIRE_MS 3000U
#define AUTO_SCENE_INVALID (-1)
#define AUTO_SCENE_HANDOFF (-2)
#define AUTO_SCENE_EXPIRED (-3)
typedef struct AutoPickScene {
    VisualPickTarget target[REC_MAX_OBJECTS];
    unsigned axis_valid[REC_MAX_OBJECTS],sx[REC_MAX_OBJECTS],sy[REC_MAX_OBJECTS];
    unsigned count,frame,version,captured_ms;
} AutoPickScene;
static unsigned auto_open,auto_state=AUTO_PICK_OFF,auto_selected_class=REC_CLASS_INVALID,auto_order;
static unsigned auto_mode=AUTO_PICK_CLASS_PICK;

static unsigned auto_bin_count;
static unsigned auto_bin_class_ids[4]={REC_CLASS_INVALID,REC_CLASS_INVALID,REC_CLASS_INVALID,REC_CLASS_INVALID};
static unsigned auto_bin_for_class[REC_CLASS_COUNT]={4U,4U,4U,4U,4U,4U,4U,4U,4U,4U,4U,4U,4U,4U,4U,4U,4U,4U};
static unsigned auto_remaining[REC_CLASS_COUNT];
static unsigned auto_current_class=REC_CLASS_INVALID,auto_current_bin=4U;
static unsigned auto_counts[REC_CLASS_COUNT],auto_classes[REC_CLASS_COUNT],auto_class_count;
static unsigned auto_catalog_valid,auto_catalog_stale,auto_catalog_seen;
static unsigned auto_catalog_frame,auto_catalog_capture;
static unsigned auto_catalog_candidate[REC_CLASS_COUNT],auto_catalog_streak[REC_CLASS_COUNT];
static unsigned auto_queue_count,auto_queue_index,auto_actions_completed,auto_removed_count;
static unsigned auto_current_slot,auto_current_slot_valid,auto_wait_started;
static unsigned auto_observations,auto_observed_frame,auto_observed_capture,auto_preflushed;
static unsigned auto_expired_repolls;
static int auto_last_snapshot_result;
static unsigned auto_committed_class_count;
static VisualPickTarget auto_stable_target,auto_committed_target;
static VisualPickTarget auto_target_samples[AUTO_TARGET_CONFIRM_FRAMES];
static const char *auto_message="SELECT A PRESENT CLASS";

static unsigned auto_pick_is_open(void){return auto_open;}
static unsigned auto_pick_is_running(void){
    return auto_state==AUTO_PICK_WAIT_START || auto_state==AUTO_PICK_WAIT_TARGET || auto_state==AUTO_PICK_MOVING ||
           auto_state==AUTO_PICK_WAIT_REMOVAL;
}

static void auto_target_window_reset(void){auto_observations=0;}
static unsigned auto_target_window_matches(const VisualPickTarget *target){
    for(unsigned k=0;k<auto_observations;++k){
        const VisualPickTarget *sample=&auto_target_samples[k];
        if(sample->class_id!=target->class_id ||
           hypot(sample->x-target->x,sample->y-target->y)>AUTO_TARGET_SPREAD_MM ||
           fabs(sample->dx*target->dx+sample->dy*target->dy)<AUTO_TARGET_AXIS_DOT_MIN)
            return 0;
    }
    return 1;
}
static unsigned auto_target_window_observe(const VisualPickTarget *target){
    if(auto_observations &&
       ((unsigned)(target->captured_ms-auto_observed_capture)>PICK_FRESH_MS ||
        !auto_target_window_matches(target)))auto_target_window_reset();

    if(auto_observations &&
       (unsigned)(target->captured_ms-auto_observed_capture)<AUTO_TARGET_SAMPLE_SPACING_MS)return 0;
    if(auto_observations==AUTO_TARGET_CONFIRM_FRAMES){
        memmove(auto_target_samples,auto_target_samples+1,
                (AUTO_TARGET_CONFIRM_FRAMES-1U)*sizeof(auto_target_samples[0]));
        --auto_observations;
    }
    auto_target_samples[auto_observations++]=*target;
    auto_stable_target=*target;
    auto_observed_frame=target->frame;auto_observed_capture=target->captured_ms;
    return 1;
}
static void auto_target_window_median(VisualPickTarget *target){
    double x[AUTO_TARGET_CONFIRM_FRAMES],y[AUTO_TARGET_CONFIRM_FRAMES];
    for(unsigned k=0;k<AUTO_TARGET_CONFIRM_FRAMES;++k){
        x[k]=auto_target_samples[k].x;y[k]=auto_target_samples[k].y;
        for(unsigned j=k;j>0U && x[j]<x[j-1U];--j){
            double v=x[j];x[j]=x[j-1U];x[j-1U]=v;
        }
        for(unsigned j=k;j>0U && y[j]<y[j-1U];--j){
            double v=y[j];y[j]=y[j-1U];y[j-1U]=v;
        }
    }
    target->x=(x[1]+x[2])*0.5;target->y=(y[1]+y[2])*0.5;
    

}
static void auto_set_state(unsigned state,const char *message){
    auto_state=state;auto_message=message;ui_dirty=1;
    recognition_visibility_sync();
}


static int auto_scene_snapshot_mode(AutoPickScene *out,unsigned motion){
    unsigned now=runtime_ms(),version=ui_read(4),flags=ui_read(8);
    if(!coordinate_valid || !ui_inference_valid)return AUTO_SCENE_INVALID;
    if((flags&256U) || coordinate_visible_version!=version ||
       (motion && (unsigned)(now-coordinate_published_ms)<30U))return AUTO_SCENE_HANDOFF;
    if(!(flags&128U) ||
       coordinate_count>REC_MAX_OBJECTS || (flags&63U)!=coordinate_count ||
       (motion && (!fusion_ready || !fusion_available)))return AUTO_SCENE_INVALID;
    out->count=coordinate_count;out->frame=coordinate_frame;out->version=version;
    out->captured_ms=coordinate_visible_source_ms;
    for(unsigned k=0;k<out->count;++k){
        const PlatformPosition *p=&coordinate_visible[k];
        VisualPickTarget *t=&out->target[k];
        if(!p->valid || p->class_id>=REC_CLASS_COUNT || p->captured_ms!=out->captured_ms ||
           p->screen_x>=1280U || p->screen_y>=960U)return -1;
        t->x=p->x_tenth_mm/10.0+PICK_COMMAND_X_TRIM_MM;
        t->y=p->y_tenth_mm/10.0+PICK_CAMERA_BASE_Y_MM+PICK_COMMAND_Y_TRIM_MM;
        t->dx=p->axis_x;t->dy=p->axis_y;t->class_id=p->class_id;
        t->frame=out->frame;t->captured_ms=out->captured_ms;
        out->axis_valid[k]=p->axis_valid;out->sx[k]=p->screen_x;out->sy[k]=p->screen_y;
    }
    if(version!=ui_read(4) || flags!=ui_read(8))return AUTO_SCENE_HANDOFF;
    

    if((unsigned)(now-out->captured_ms)>(motion?PICK_FRESH_MS:AUTO_VIEW_EXPIRE_MS))
        return AUTO_SCENE_EXPIRED;
    return 0;
}
static int auto_scene_snapshot(AutoPickScene *out){return auto_scene_snapshot_mode(out,1);}
static void auto_class_list_rebuild(void){
    auto_class_count=0;
    for(unsigned number=1;number<=REC_CLASS_COUNT;++number)
        for(unsigned id=0;id<REC_CLASS_COUNT;++id)if(auto_counts[id] && recognition_number(id)==number)
            auto_classes[auto_class_count++]=id;
     
    if(auto_selected_class>=REC_CLASS_COUNT && auto_class_count)auto_selected_class=auto_classes[0];
}
static void auto_view_reset(void){
    memset(auto_counts,0,sizeof(auto_counts));memset(auto_classes,0,sizeof(auto_classes));
    memset(auto_catalog_candidate,0,sizeof(auto_catalog_candidate));
    memset(auto_catalog_streak,0,sizeof(auto_catalog_streak));
    auto_class_count=auto_catalog_valid=auto_catalog_seen=0;auto_catalog_stale=1;
}


static void auto_view_invalidate(void){
    memset(auto_counts,0,sizeof(auto_counts));
    memset(auto_catalog_streak,0,sizeof(auto_catalog_streak));
    auto_class_list_rebuild();auto_catalog_valid=0;auto_catalog_stale=1;
    ui_dirty=1;
}

static void auto_pick_refresh_view(void){
    AutoPickScene scene;
    if(!auto_open)return;
    unsigned old_valid=auto_catalog_valid,old_stale=auto_catalog_stale;
    unsigned now=runtime_ms(),changed=0;
    int snapshot=auto_scene_snapshot_mode(&scene,0);
    if(!snapshot){
        unsigned newer=!auto_catalog_seen ||
            (scene.frame!=auto_catalog_frame && (int32_t)(scene.captured_ms-auto_catalog_capture)>0);
        if(newer){
            unsigned counts[REC_CLASS_COUNT]={0};
            for(unsigned k=0;k<scene.count;++k)++counts[scene.target[k].class_id];
            for(unsigned id=0;id<REC_CLASS_COUNT;++id){
                if(!auto_catalog_valid){auto_counts[id]=counts[id];auto_catalog_streak[id]=0;changed=1;}
                else if(counts[id]==auto_counts[id])auto_catalog_streak[id]=0;
                else{
                    if(auto_catalog_candidate[id]!=counts[id]){auto_catalog_candidate[id]=counts[id];auto_catalog_streak[id]=0;}
                    if(++auto_catalog_streak[id]>=2U){auto_counts[id]=counts[id];auto_catalog_streak[id]=0;changed=1;}
                }
            }
            auto_catalog_seen=auto_catalog_valid=1;auto_catalog_stale=0;
            auto_catalog_frame=scene.frame;auto_catalog_capture=scene.captured_ms;
            if(changed)auto_class_list_rebuild();
        }
    }else if(snapshot==AUTO_SCENE_INVALID || !auto_catalog_seen ||
              (unsigned)(now-auto_catalog_capture)>AUTO_VIEW_EXPIRE_MS){
        

        memset(auto_catalog_streak,0,sizeof(auto_catalog_streak));
    }
    unsigned age=(unsigned)(now-auto_catalog_capture);
    auto_catalog_stale=!auto_catalog_valid || !auto_catalog_seen || age>AUTO_VIEW_EXPIRE_MS;
    if(auto_catalog_valid && age>AUTO_VIEW_EXPIRE_MS){
        auto_view_invalidate();changed=1;
    }
    if(changed || old_valid!=auto_catalog_valid || old_stale!=auto_catalog_stale)ui_dirty=1;
}
static void auto_pick_get_view(AutoPickView *out){
    if(!out)return;
    memset(out,0,sizeof(*out));out->open=auto_open;out->running=auto_pick_is_running();
    out->state=auto_state;out->selected_class=auto_selected_class;out->order=auto_order;
    out->mode=auto_mode;out->bin_count=auto_bin_count;
    memcpy(out->bin_class_ids,auto_bin_class_ids,sizeof(auto_bin_class_ids));
    memcpy(out->bin_for_class,auto_bin_for_class,sizeof(auto_bin_for_class));
    memcpy(out->remaining,auto_remaining,sizeof(auto_remaining));
    out->current_class=auto_current_class;out->current_bin=auto_current_bin;
    memcpy(out->counts,auto_counts,sizeof(auto_counts));memcpy(out->class_ids,auto_classes,sizeof(auto_classes));
    out->class_count=auto_class_count;out->queue_count=auto_queue_count;out->queue_index=auto_queue_index;
    out->catalog_valid=auto_catalog_valid;out->catalog_stale=auto_catalog_stale;
    out->actions_completed=auto_actions_completed;out->removed_count=auto_removed_count;
    out->current_slot=auto_current_slot;out->current_slot_valid=auto_current_slot_valid;out->message=auto_message;
}
static void auto_pick_cancel(const char *reason,unsigned abort_motion){
    if(!auto_open && !auto_pick_is_running())return;
    if(!strcmp(reason,"TARGET REFRESH TIMEOUT") ||
       !strcmp(reason,"REMOVAL NOT CONFIRMED / CHECK PICK")){
        runtime_eventf("AUTO_REFRESH_TIMEOUT,state,%u,wait_ms,%u,samples,%u,last_snapshot,%d,expired_repolls,%u,frame,%u,observed_frame,%u,age_ms,%u,flags,%08x,coordinate_valid,%u\r\n",
            auto_state,(unsigned)(runtime_ms()-auto_wait_started),auto_observations,
            auto_last_snapshot_result,auto_expired_repolls,coordinate_frame,auto_observed_frame,
            (unsigned)(runtime_ms()-coordinate_visible_source_ms),ui_read(8),coordinate_valid);
    }
    unsigned owned_motion=auto_state==AUTO_PICK_MOVING;
    auto_current_slot_valid=0;auto_observations=0;
    auto_set_state(AUTO_PICK_STOPPED,reason);
    if(abort_motion && owned_motion && arm_motion_busy())arm_motion_cancel();
    runtime_eventf("AUTO_STOP,reason,%s,index,%u,planned,%u,actions,%u,removed,%u\r\n",
        reason,auto_queue_index,auto_queue_count,auto_actions_completed,auto_removed_count);
}
static void auto_pick_close(void){
    auto_pick_cancel("AUTO CLOSED",1);auto_open=0;auto_set_state(AUTO_PICK_OFF,"AUTO OFF");
    fusion_pick_cancel_pending("AUTO MENU CLOSED");
}
static void auto_pick_toggle_mode(unsigned mode){
    if(mode>AUTO_PICK_SORT_ALL)return;
    if(auto_open && auto_mode==mode){auto_pick_close();return;}
    if(auto_open)auto_pick_close();
    fusion_pick_cancel_pending("AUTO MENU OPENED");
    auto_mode=mode;
    if(mode==AUTO_PICK_SORT_ALL)auto_order=AUTO_PICK_LEFT_RIGHT;
    auto_open=1;auto_current_slot_valid=0;auto_observations=0;
    auto_current_class=REC_CLASS_INVALID;auto_current_bin=4U;
    auto_set_state(AUTO_PICK_BROWSE,mode==AUTO_PICK_SORT_ALL?
        "LEFT TO RIGHT / Z: START SORT":"UP/DOWN CLASS / LEFT/RIGHT ORDER");
    auto_view_reset();auto_pick_refresh_view();
}
static void auto_pick_toggle(void){auto_pick_toggle_mode(AUTO_PICK_CLASS_PICK);}
static void auto_pick_direction(unsigned direction){
    if(!auto_open || auto_pick_is_running())return;
    auto_pick_refresh_view();
    if(auto_mode==AUTO_PICK_SORT_ALL)return;
    if(direction==1U)auto_order=AUTO_PICK_LEFT_RIGHT;
    else if(direction==2U)auto_order=AUTO_PICK_TOP_BOTTOM;
    else if((direction==3U || direction==4U) && auto_class_count){
        unsigned index=auto_class_count;
        for(unsigned k=0;k<auto_class_count;++k)if(auto_classes[k]==auto_selected_class)index=k;
        if(index==auto_class_count)index=direction==3U?auto_class_count-1U:0U;
        else index=direction==3U?(index?index-1U:auto_class_count-1U):(index+1U)%auto_class_count;
        auto_selected_class=auto_classes[index];
    }
    auto_set_state(AUTO_PICK_BROWSE,"Z: START SELECTED CLASS");
}
static int auto_scene_before(const AutoPickScene *scene,unsigned a,unsigned b){
    unsigned ap=auto_order==AUTO_PICK_LEFT_RIGHT?scene->sx[a]:scene->sy[a];
    unsigned bp=auto_order==AUTO_PICK_LEFT_RIGHT?scene->sx[b]:scene->sy[b];
    unsigned as=auto_order==AUTO_PICK_LEFT_RIGHT?scene->sy[a]:scene->sx[a];
    unsigned bs=auto_order==AUTO_PICK_LEFT_RIGHT?scene->sy[b]:scene->sx[b];
    if(ap!=bp)return ap<bp;
    if(as!=bs)return as<bs;
    if(scene->target[a].x!=scene->target[b].x)return scene->target[a].x<scene->target[b].x;
    return scene->target[a].y<scene->target[b].y;
}
static unsigned auto_scene_class_count(const AutoPickScene *scene,unsigned class_id){
    unsigned count=0;
    for(unsigned k=0;k<scene->count;++k)if(scene->target[k].class_id==class_id)++count;
    return count;
}
static int auto_scene_has_unmapped_class(const AutoPickScene *scene){
    if(auto_mode!=AUTO_PICK_SORT_ALL)return 0;
    for(unsigned k=0;k<scene->count;++k)
        if(recognition_pickable(scene->target[k].class_id) &&
           auto_bin_for_class[scene->target[k].class_id]>=AUTO_PICK_BIN_COUNT)return 1;
    return 0;
}
static void auto_stop_error(const char *message){
    auto_pick_cancel(message,0);auto_set_state(AUTO_PICK_ERROR,message);
}
static void auto_wait_for_target(void){
    auto_wait_started=runtime_ms();auto_observations=0;auto_preflushed=0;auto_current_slot_valid=0;
    auto_expired_repolls=0;auto_last_snapshot_result=AUTO_SCENE_HANDOFF;
    auto_current_class=REC_CLASS_INVALID;auto_current_bin=AUTO_PICK_BIN_COUNT;
    auto_set_state(AUTO_PICK_WAIT_TARGET,"CONFIRM NEXT TARGET IN BACKGROUND");
}


static void auto_pick_try_start(void){
    AutoPickScene scene;
    if(!auto_open || auto_state!=AUTO_PICK_WAIT_START)return;
    if((unsigned)(runtime_ms()-auto_wait_started)>=AUTO_PICK_FRAME_WAIT_MS){
        auto_pick_cancel("START REFRESH TIMEOUT",0);return;
    }
    if(arm_motion_busy() || shot_state || joy_reset_pending || !fusion_available){
        auto_pick_cancel("ARM OR CAMERA NOT READY",0);return;
    }
    

    if(!fusion_ready || recognition_resume_waiting() || auto_scene_snapshot(&scene))return;
    

    unsigned candidate_map[REC_CLASS_COUNT],candidate_classes[4],candidate_bins=auto_bin_count;
    unsigned pending[REC_CLASS_COUNT]={0},ordered[REC_MAX_OBJECTS],ordered_count=0;
    memcpy(candidate_map,auto_bin_for_class,sizeof(candidate_map));
    memcpy(candidate_classes,auto_bin_class_ids,sizeof(candidate_classes));
    for(unsigned k=0;k<scene.count;++k)if(recognition_pickable(scene.target[k].class_id) &&
        (auto_mode==AUTO_PICK_SORT_ALL || scene.target[k].class_id==auto_selected_class)){
        if(!scene.axis_valid[k] || !visual_pick_target_valid(&scene.target[k])){
            auto_queue_count=0;auto_set_state(AUTO_PICK_ERROR,"CLASS TARGET OUTSIDE PICK AREA");return;
        }
        unsigned pos=ordered_count;
        while(pos && auto_scene_before(&scene,k,ordered[pos-1U])){
            ordered[pos]=ordered[pos-1U];--pos;
        }
        ordered[pos]=k;++ordered_count;++pending[scene.target[k].class_id];
    }
    if(!ordered_count){auto_set_state(AUTO_PICK_DONE,"NO TARGETS PRESENT");return;}
    if(auto_mode==AUTO_PICK_SORT_ALL){
        for(unsigned k=0;k<ordered_count;++k){
            unsigned id=scene.target[ordered[k]].class_id;
            if(candidate_map[id]<AUTO_PICK_BIN_COUNT)continue;
            if(candidate_bins==AUTO_PICK_BIN_COUNT){
                auto_set_state(AUTO_PICK_ERROR,"BIN MAP FULL / RESTART WITH EMPTY BINS");return;
            }
            candidate_map[id]=candidate_bins;candidate_classes[candidate_bins++]=id;
        }
        memcpy(auto_bin_for_class,candidate_map,sizeof(auto_bin_for_class));
        memcpy(auto_bin_class_ids,candidate_classes,sizeof(auto_bin_class_ids));
        auto_bin_count=candidate_bins;
    }
    memcpy(auto_remaining,pending,sizeof(auto_remaining));auto_queue_count=ordered_count;
    fusion_pick_cancel_pending("AUTO BATCH STARTED");fusion_confirm_until=0;
    auto_wait_for_target();
    runtime_eventf("AUTO_BEGIN,class,%u,number,%u,order,%u,count,%u,frame,%u;FINITE_COUNT_FRESH_RESELECT\r\n",
        auto_selected_class,recognition_number(auto_selected_class),auto_order,auto_queue_count,scene.frame);
    runtime_eventf("AUTO_MODE,mode,%u,bins,%u,map,%u,%u,%u,%u\r\n",auto_mode,auto_bin_count,
        auto_bin_class_ids[0],auto_bin_class_ids[1],auto_bin_class_ids[2],auto_bin_class_ids[3]);
}
static void auto_pick_press(void){
    if(!auto_open)return;
    if(auto_pick_is_running()){auto_pick_cancel("AUTO STOPPED BY Z",1);return;}
    if(arm_motion_busy() || shot_state || joy_reset_pending || !fusion_available){
        auto_set_state(AUTO_PICK_STOPPED,"ARM OR CAMERA NOT READY");return;
    }
    if(auto_mode==AUTO_PICK_CLASS_PICK && auto_selected_class>=REC_CLASS_COUNT){
        auto_set_state(AUTO_PICK_STOPPED,"SELECT A VALID CLASS");return;
    }
    if(auto_mode==AUTO_PICK_CLASS_PICK && !recognition_pickable(auto_selected_class)){
        auto_set_state(AUTO_PICK_STOPPED,"NUT: RECOGNITION ONLY");return;
    }
    auto_queue_count=auto_queue_index=0;
    auto_actions_completed=auto_removed_count=0;
    auto_current_class=REC_CLASS_INVALID;auto_current_bin=AUTO_PICK_BIN_COUNT;
    auto_current_slot_valid=auto_observations=auto_preflushed=0;
    memset(auto_remaining,0,sizeof(auto_remaining));
    fusion_pick_cancel_pending("AUTO START REQUESTED");fusion_confirm_until=0;
    auto_wait_started=runtime_ms();
    auto_set_state(AUTO_PICK_WAIT_START,"WAITING FOR A FRESH COHERENT SCENE");
    runtime_eventf("AUTO_START_WAIT,mode,%u,class,%u,ms,%u,timeout_ms,%u\r\n",
        auto_mode,auto_selected_class,auto_wait_started,AUTO_PICK_FRAME_WAIT_MS);
    auto_pick_try_start();
}

static int auto_match_target(const AutoPickScene *scene,unsigned *slot,const char **reason){
    unsigned found=REC_MAX_OBJECTS;
    for(unsigned k=0;k<scene->count;++k)if(auto_remaining[scene->target[k].class_id] &&
        (auto_mode==AUTO_PICK_SORT_ALL || scene->target[k].class_id==auto_selected_class) &&
        (found==REC_MAX_OBJECTS || auto_scene_before(scene,k,found)))found=k;
    if(found==REC_MAX_OBJECTS){*reason="WAIT BATCH TARGET";return 1;}
    const VisualPickTarget *candidate=&scene->target[found];
    if(!scene->axis_valid[found] || !visual_pick_target_valid(candidate)){*reason="OUTSIDE PICK AREA / BAD AXIS";return -1;}
    for(unsigned k=0;k<scene->count;++k)if(k!=found &&
        hypot(candidate->x-scene->target[k].x,candidate->y-scene->target[k].y)<5.0){
        *reason="TARGETS TOO CLOSE";return -1;
    }
    *slot=found;return 0;
}
static int auto_new_observation(const AutoPickScene *scene){
    if((int32_t)(scene->captured_ms-auto_wait_started)<=0)return 0;
    return !auto_observations ||
        (scene->frame!=auto_observed_frame && (int32_t)(scene->captured_ms-auto_observed_capture)>0);
}
static void auto_pick_motion_finished(const char *state){
    if(auto_state!=AUTO_PICK_MOVING)return;
    auto_current_slot_valid=0;
    if(strcmp(state,"COMPLETED")){
        auto_pick_cancel(!strcmp(state,"CANCELLED")?"ARM CANCELLED":"ARM ERROR / CHECK LOG",0);
        if(strcmp(state,"CANCELLED"))auto_set_state(AUTO_PICK_ERROR,"ARM ERROR / CHECK LOG");
        return;
    }
    ++auto_actions_completed;auto_observations=0;auto_wait_started=runtime_ms();
    auto_expired_repolls=0;auto_last_snapshot_result=AUTO_SCENE_HANDOFF;
    auto_set_state(AUTO_PICK_WAIT_REMOVAL,"VERIFY REMOVAL IN TWO NEW FRAMES");
    runtime_eventf("AUTO_ACTION_COMPLETE,index,%u,actions,%u;NOT_GRASP_CONFIRMATION\r\n",auto_queue_index,auto_actions_completed);
}
static void auto_pick_vision_fault(void){
    auto_view_invalidate();
    if(auto_pick_is_running())auto_pick_cancel("VISION FAULT / RESTART BATCH",0);
}
static void auto_pick_service(void){
    AutoPickScene scene;const char *reason="WAIT FRESH FRAME";unsigned slot=0;
    auto_pick_refresh_view();
    if(!auto_pick_is_running())return;
    if(joy_reset_pending || (ui_read(0x2c)&16U)){auto_pick_cancel("SW4 / RESET",1);return;}
    if(auto_state==AUTO_PICK_WAIT_START){auto_pick_try_start();return;}
    if(auto_state==AUTO_PICK_MOVING){
        if(!arm_motion_busy())auto_pick_motion_finished(arm_motion_state_name());
        return;
    }
    if(arm_motion_busy()){auto_pick_cancel("OTHER ARM REQUEST",0);return;}
    if((unsigned)(runtime_ms()-auto_wait_started)>=AUTO_PICK_FRAME_WAIT_MS){
        auto_pick_cancel(auto_state==AUTO_PICK_WAIT_REMOVAL?"REMOVAL NOT CONFIRMED / CHECK PICK":"TARGET REFRESH TIMEOUT",0);return;
    }

    if(recognition_resume_waiting())return;
    if(!fusion_ready || !fusion_available){auto_pick_cancel("VISION NOT READY",0);return;}
    if(shot_state)return;
    int snapshot=auto_scene_snapshot(&scene);
    auto_last_snapshot_result=snapshot;
    if(snapshot){

        if(snapshot==AUTO_SCENE_EXPIRED && auto_observations &&
           scene.frame==auto_observed_frame && scene.captured_ms==auto_observed_capture){
            ++auto_expired_repolls;return;
        }
        if(snapshot!=AUTO_SCENE_HANDOFF)auto_observations=0;
        return;
    }
    if(!auto_new_observation(&scene))return;
    if(auto_scene_has_unmapped_class(&scene)){
        auto_stop_error(auto_bin_count>=AUTO_PICK_BIN_COUNT?
            "BIN MAP FULL / NEW CLASS":"NEW CLASS / RESTART BATCH");return;
    }
    if(auto_state==AUTO_PICK_WAIT_REMOVAL){
        unsigned occupied=0;
        for(unsigned k=0;k<scene.count;++k)if(hypot(scene.target[k].x-auto_committed_target.x,
            scene.target[k].y-auto_committed_target.y)<AUTO_PICK_REMOVE_RADIUS_MM)occupied=1;
        auto_observed_frame=scene.frame;auto_observed_capture=scene.captured_ms;
        

        if(occupied || auto_scene_class_count(&scene,auto_committed_target.class_id)>=auto_committed_class_count){auto_observations=0;return;}
        if(++auto_observations<2U)return;
        ++auto_removed_count;++auto_queue_index;
        if(auto_remaining[auto_committed_target.class_id])--auto_remaining[auto_committed_target.class_id];
        runtime_eventf("AUTO_REMOVAL_CONFIRMED,index,%u,removed,%u,frame,%u;VISUAL_ABSENCE_ONLY\r\n",
            auto_queue_index-1U,auto_removed_count,scene.frame);
        if(auto_queue_index==auto_queue_count)auto_set_state(AUTO_PICK_DONE,"BATCH DONE / PRESS Z FOR NEW BATCH");
        else auto_wait_for_target();
        return;
    }
    int matched=auto_match_target(&scene,&slot,&reason);
    if(matched){auto_observations=0;if(matched<0)auto_pick_cancel(reason,0);return;}
    VisualPickTarget current=scene.target[slot];
    if(!auto_target_window_observe(&current))return;
    runtime_eventf("AUTO_CONFIRM_SAMPLE,frame,%u,captured_ms,%u,age_ms,%u,samples,%u,required,%u,class,%u,x,%.3f,y,%.3f,expired_repolls,%u\r\n",
        current.frame,current.captured_ms,(unsigned)(runtime_ms()-current.captured_ms),
        auto_observations,AUTO_TARGET_CONFIRM_FRAMES,current.class_id,current.x,current.y,auto_expired_repolls);
    auto_current_slot=slot;auto_current_slot_valid=1;ui_dirty=1;
    auto_current_class=current.class_id;
    auto_current_bin=auto_mode==AUTO_PICK_SORT_ALL?auto_bin_for_class[current.class_id]:SORT_BIN_CLASS_PICK;
    if(auto_observations<AUTO_TARGET_CONFIRM_FRAMES ||
       (unsigned)(current.captured_ms-auto_target_samples[0].captured_ms)<AUTO_TARGET_CONFIRM_SPAN_MS)return;
    

    if(!auto_preflushed){auto_preflushed=1;runtime_log_sync();}
    if((unsigned)(runtime_ms()-auto_wait_started)>=AUTO_PICK_FRAME_WAIT_MS){auto_pick_cancel("TARGET REFRESH TIMEOUT",0);return;}
    if(joy_reset_pending || (ui_read(0x2c)&16U) || arm_motion_busy() || shot_state ||
       auto_scene_snapshot(&scene))return;
    

    if((int32_t)(scene.captured_ms-auto_wait_started)<=0 ||
       (int32_t)(scene.captured_ms-auto_observed_capture)<0){auto_observations=0;return;}
    if(auto_scene_has_unmapped_class(&scene)){
        auto_stop_error(auto_bin_count>=AUTO_PICK_BIN_COUNT?
            "BIN MAP FULL / NEW CLASS":"NEW CLASS / RESTART BATCH");return;
    }
    matched=auto_match_target(&scene,&slot,&reason);
    if(matched || !auto_target_window_matches(&scene.target[slot])){
        auto_observations=0;if(matched<0)auto_pick_cancel(reason,0);return;
    }
    current=scene.target[slot];
    auto_target_window_median(&current);
    if(!visual_pick_target_valid(&current)){auto_target_window_reset();return;}
    for(unsigned k=0;k<scene.count;++k)if(k!=slot &&
       hypot(current.x-scene.target[k].x,current.y-scene.target[k].y)<AUTO_PICK_REMOVE_RADIUS_MM){
        auto_target_window_reset();return;
    }

    unsigned bin=auto_mode==AUTO_PICK_SORT_ALL?auto_bin_for_class[current.class_id]:SORT_BIN_CLASS_PICK;
    VisualPickTarget command;
    if(visual_pick_prepare_command(&current,&command)){
        auto_stop_error("OUTSIDE PICK AREA AFTER COMPENSATION");return;
    }
    int started=arm_motion_start_visual_place(&command,bin,fusion_now_us());
    runtime_eventf("PICK_LOCAL_Y,mode,AUTO,auto_mode,%u,platform_y,%.3f,observed_robot_y,%.3f,offset_y,%.3f,command_y,%.3f\r\n",
        auto_mode,current.y-PICK_CAMERA_BASE_Y_MM-PICK_COMMAND_Y_TRIM_MM,
        current.y,command.y-current.y,command.y);
    if(started){auto_current_slot_valid=0;auto_set_state(AUTO_PICK_ERROR,started==-1?"ARM BUSY":
        (auto_mode==AUTO_PICK_SORT_ALL?"PICK OR BIN PATH UNREACHABLE":"PICK OR BIN2 PATH UNREACHABLE"));return;}
    

    auto_committed_target=current;auto_current_slot=slot;auto_current_slot_valid=1;
    auto_current_class=current.class_id;auto_current_bin=bin;
    auto_committed_class_count=auto_scene_class_count(&scene,current.class_id);
    fusion_visual_active=1;recognition_motion_sync();
    auto_set_state(AUTO_PICK_MOVING,auto_mode==AUTO_PICK_SORT_ALL?
        "PICK / PLACE / HOME - Z OR SW4 STOP":"CLASS PICK / BIN2 / HOME - Z OR SW4 STOP");
    runtime_eventf("AUTO_TARGET_CONFIRMED,frames,%u,span_ms,%u,max_spread_mm,%.2f,axis_limit_deg,8,median_x,%.3f,median_y,%.3f\r\n",
        auto_observations,(unsigned)(auto_observed_capture-auto_target_samples[0].captured_ms),
        AUTO_TARGET_SPREAD_MM,current.x,current.y);
    runtime_eventf("AUTO_PICK_STARTED,index,%u,planned,%u,class,%u,number,%u,slot,%u,frame,%u,x,%.3f,y,%.3f,z,%.3f,dx,%.6f,dy,%.6f,age_ms,%u\r\n",
        auto_queue_index,auto_queue_count,current.class_id,recognition_number(current.class_id),slot,current.frame,
        command.x,command.y,PICK_Z_MM,command.dx,command.dy,(unsigned)(runtime_ms()-current.captured_ms));
    runtime_eventf("AUTO_PLACE_ROUTE,mode,%u,class,%u,bin,%u\r\n",auto_mode,current.class_id,bin+1U);
}
#endif
