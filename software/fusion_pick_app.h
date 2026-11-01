#ifndef FUSION_PICK_APP_H
#define FUSION_PICK_APP_H
#include "workstation_config.h"
#include "sort_bins.h"

static unsigned fusion_visual_active;
/* A single explicit press may wait briefly for a coherent fresh observation.
 * No command survives a timeout, cursor movement, disable, reset or vision fault. */
static unsigned fusion_pick_waiting,fusion_pick_has_anchor;
static unsigned fusion_pick_requested_ms,fusion_pick_requested_moves;
static VisualPickTarget fusion_pick_anchor;
static unsigned fusion_pick_pending(void){return fusion_pick_waiting;}

/* Read a coherent selected object. Freshness is evaluated separately so an
 * old displayed object may identify WHAT to refresh, never WHERE to move. */
static int fusion_pick_snapshot_mode(VisualPickTarget *t,const char **reason,unsigned anchor_only)
{
    unsigned now=runtime_ms(),scene=ui_read(4),status=ui_read(8);
    unsigned selected=ui_read(0x34),slot=selected&15U;
    *reason="WAIT VALID TARGET";
    if(!joy_enabled || !coordinate_valid || !ui_inference_valid || !(status&128U))return -1;
    if(coordinate_visible_version!=scene ||
       (!anchor_only && ((status&256U) || (unsigned)(now-coordinate_published_ms)<30U))){*reason="WAIT SCENE";return 1;}
    unsigned command=ui_read(0x20);
    if(joy_head!=joy_tail || (command&1U)!=((command>>1)&1U)){*reason="WAIT SELECTION";return 1;}
    if((selected&0x300U)!=0x300U || slot>=coordinate_count || slot>=REC_MAX_OBJECTS)return -1;
    const PlatformPosition *p=&coordinate_visible[slot];
    if(!p->valid || p->class_id!=recognition_selection_class(selected))return -1;
    if(!recognition_pickable(p->class_id)){*reason="NUT: RECOGNITION ONLY";return -1;}
    if(!p->axis_valid){*reason="LONG AXIS UNCERTAIN";return -1;}
    t->x=p->x_tenth_mm/10.0+PICK_COMMAND_X_TRIM_MM;
    t->y=p->y_tenth_mm/10.0+PICK_CAMERA_BASE_Y_MM+PICK_COMMAND_Y_TRIM_MM;
    t->dx=p->axis_x;t->dy=p->axis_y;t->class_id=p->class_id;
    t->frame=coordinate_frame;t->captured_ms=p->captured_ms;
    if(!visual_pick_target_valid(t)){*reason="OUTSIDE PICK AREA";return -1;}
    for(unsigned k=0;k<coordinate_count;++k){
        if(k!=slot && coordinate_visible[k].valid &&
           hypot((coordinate_visible[k].x_tenth_mm-p->x_tenth_mm)/10.0,
                 (coordinate_visible[k].y_tenth_mm-p->y_tenth_mm)/10.0)<5.0){
            *reason="TARGETS TOO CLOSE";return -1;
        }
    }
    if(scene!=ui_read(4) || selected!=ui_read(0x34)){*reason="WAIT SCENE";return 1;}
    return 0;
}
static int fusion_pick_snapshot(VisualPickTarget *t,const char **reason)
{ return fusion_pick_snapshot_mode(t,reason,0); }
static int fusion_pick_read(VisualPickTarget *t,const char **reason)
{
    int result=fusion_pick_snapshot(t,reason);
    if(result)return result;
    if((unsigned)(runtime_ms()-t->captured_ms)>PICK_FRESH_MS){*reason="TARGET STALE";return 1;}
    return 0;
}
static void fusion_pick_reject(const char *reason)
{
    ui_message(reason);
    unsigned selected=ui_read(0x34),slot=selected&15U;
    unsigned age=slot<coordinate_count?runtime_ms()-coordinate_visible[slot].captured_ms:0xffffffffU;
    runtime_eventf("PICK_REJECT,reason,%s,ms,%u,frame,%u,scene,%u,visible,%u,selected,%08x,age_ms,%u,valid,%u,ready,%u,hw,%u\r\n",
        reason,runtime_ms(),coordinate_frame,ui_read(4),coordinate_visible_version,selected,
        age,coordinate_valid,fusion_ready,fusion_available);
    fusion_console_write("PICK REJECT: ");fusion_console_write(reason);fusion_console_write("\r\n");
}
static void fusion_pick_cancel_pending(const char *reason)
{
    if(!fusion_pick_waiting)return;
    fusion_pick_waiting=0;fusion_pick_has_anchor=0;ui_dirty=1;
    fusion_pick_reject(reason);
}
static void fusion_pick_service(void)
{
    VisualPickTarget current;const char *reason;
    if(!fusion_pick_waiting)return;
    unsigned now=runtime_ms();
    if((unsigned)(now-fusion_pick_requested_ms)>=PICK_REFRESH_TIMEOUT_MS){
        fusion_pick_cancel_pending("TARGET REFRESH TIMEOUT");return;
    }
    if(!joy_enabled || joy_reset_pending || (ui_read(0x2c)&16U) ||
       joy_moves!=fusion_pick_requested_moves){
        fusion_pick_cancel_pending("SELECTION CHANGED / CANCELLED");return;
    }
    if(arm_motion_busy() || !fusion_ready || !fusion_available || shot_state){
        fusion_pick_cancel_pending("PICK NOT READY");return;
    }
    int result=fusion_pick_snapshot(&current,&reason);
    if(result<0){fusion_pick_cancel_pending(reason);return;}
    if(result>0)return;
    if(!fusion_pick_has_anchor){fusion_pick_cancel_pending("NO LOCKED TARGET");return;}
    if(!visual_pick_same(&fusion_pick_anchor,&current)){
        fusion_pick_cancel_pending("TARGET CHANGED / SELECT AGAIN");return;
    }
    if((unsigned)(now-current.captured_ms)>PICK_FRESH_MS)return;
    /* Freshness was checked AFTER preflush and scene publication. No filesystem
     * operation occurs between this check and committing the immutable target. */
    fusion_pick_waiting=0;fusion_pick_has_anchor=0;
    VisualPickTarget command;
    if(visual_pick_prepare_command(&current,&command)){
        fusion_pick_reject("OUTSIDE PICK AREA AFTER COMPENSATION");return;
    }
    int started=arm_motion_start_visual_place(&command,SORT_BIN_SINGLE_PICK,fusion_now_us());
    ArmVisualPlanDiagnostic planning;
    arm_visual_plan_get_diagnostic(&planning);
    runtime_eventf("PICK_LOCAL_Y,mode,SINGLE,platform_y,%.3f,observed_robot_y,%.3f,offset_y,%.3f,command_y,%.3f\r\n",
        current.y-PICK_CAMERA_BASE_Y_MM-PICK_COMMAND_Y_TRIM_MM,current.y,command.y-current.y,command.y);
    runtime_eventf("PICK_PLAN,x,%.3f,y,%.3f,dx,%.6f,dy,%.6f,z,%.1f,pitch,%.0f,result,%d,original,%d,route,%u,phase,%u,subdivisions,%u\r\n",
        command.x,command.y,command.dx,command.dy,PICK_Z_MM,ARM_VERTICAL_PITCH_DEG,
        planning.result,planning.original_result,planning.route,planning.phase,planning.subdivisions);
    if(started){fusion_pick_reject(started==-1?"ARM BUSY":"PICK OR BIN1 PATH UNREACHABLE");return;}
    fusion_visual_active=1;recognition_motion_sync();
    ui_message("PICK TO BIN1 / SW4 STOP");
    /* Executor is active now; runtime_logv cannot flush storage while busy. */
    runtime_eventf("PICK_CAL,camera_y,%.2f,base_y,%.2f,trim_y,%.2f,local_y,%.2f,command_y,%.2f\r\n",
        current.y-PICK_CAMERA_BASE_Y_MM-PICK_COMMAND_Y_TRIM_MM,
        PICK_CAMERA_BASE_Y_MM,PICK_COMMAND_Y_TRIM_MM,command.y-current.y,command.y);
    runtime_eventf("PICK_CAL_X,camera_x,%.2f,trim_x,%.2f,command_x,%.2f\r\n",
        current.x-PICK_COMMAND_X_TRIM_MM,PICK_COMMAND_X_TRIM_MM,current.x);
    runtime_eventf("PICK_HEIGHT,platform_z,%.1f,base_riser,%.1f,robot_z,%.1f,robot_pregrasp_z,%.1f\r\n",
        PICK_PLATFORM_Z_MM,PICK_BASE_RISER_MM,PICK_Z_MM,ARM_VERTICAL_PREGRASP_Z_MM);
    runtime_eventf("PICK_REQUEST,trigger,SINGLE_Z_REFRESHED,frame,%u,class,%u,x,%.2f,y,%.2f,dx,%.6f,dy,%.6f,z,%.1f,age_ms,%u,wait_ms,%u\r\n",
        command.frame,command.class_id,command.x,command.y,command.dx,command.dy,PICK_Z_MM,
        (unsigned)(now-current.captured_ms),(unsigned)(now-fusion_pick_requested_ms));
    {
        runtime_eventf("PICK_STARTED,trigger,SINGLE_Z_REFRESHED,frame,%u,class,%u,x,%.2f,y,%.2f,z,%.1f\r\n",
            command.frame,command.class_id,command.x,command.y,PICK_Z_MM);
        runtime_eventf("PICK_DESTINATION,mode,SINGLE,bin,%u\r\n",SORT_BIN_SINGLE_PICK+1U);
        fusion_console_write("90DEG PICK: ALIGN / ROTATE / PLACE BIN1 / RETURN HOME\r\n");
    }
}
static void fusion_pick_press(void)
{
    VisualPickTarget candidate;const char *reason;
    fusion_confirm_until=0;
    if(auto_pick_is_open()){fusion_pick_reject("EXIT AUTO PICK FIRST");return;}
    if(arm_motion_busy()){fusion_pick_reject("ARM BUSY / SW4 STOP");return;}
    if(fusion_pick_waiting){ui_message("UPDATING TARGET / PLEASE WAIT");return;}
    if(!fusion_ready || !fusion_available || shot_state || joy_reset_pending){
        fusion_pick_reject("PICK NOT READY");return;
    }
    int snapshot=fusion_pick_snapshot_mode(&candidate,&reason,1);
    if(snapshot!=0){fusion_pick_reject(reason);return;}
    unsigned requested=runtime_ms(),moves=joy_moves;
    /* Drain prior log data once while no request/motor is active. A slow SD
     * write cannot make a stale snapshot execute: service rechecks fresh data. */
    runtime_log_sync();
    fusion_pick_requested_ms=requested;fusion_pick_requested_moves=moves;
    fusion_pick_has_anchor=1;fusion_pick_anchor=candidate;
    fusion_pick_waiting=1;ui_message("UPDATING TARGET / PLEASE WAIT");
    runtime_eventf("PICK_WAIT,ms,%u,anchor_valid,%u,frame,%u,timeout_ms,%u\r\n",
        requested,fusion_pick_has_anchor,coordinate_frame,PICK_REFRESH_TIMEOUT_MS);
    fusion_pick_service();
}
#endif
