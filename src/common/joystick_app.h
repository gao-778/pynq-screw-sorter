#ifndef JOYSTICK_APP_H
#define JOYSTICK_APP_H
 
#define JOY_X_REVERSE 1
#define JOY_Y_REVERSE 1
#define JOY_ENTER_THRESHOLD 300U
#define JOY_HOLD_THRESHOLD 220U
#define JOY_CENTER_THRESHOLD 180U
#define JOY_AXIS_MARGIN 100U
#define JOY_HOLD_AXIS_MARGIN 40U
#define JOY_DWELL_MS 40U
#define JOY_REPEAT_MS 350U
#define JOY_MOVE_GUARD_MS 150U
#define JOY_MIN_DIRECTION_SAMPLES 3U
#define JOY_MAX_SAMPLE_GAP_MS 300U
#define JOY_CAL_MIN 128U
#define JOY_CAL_MAX 3967U
static unsigned joy_reset_pending,joy_next_poll;
static unsigned joy_count,joy_sum_x,joy_sum_y,joy_min_x=4095,joy_max_x,joy_min_y=4095,joy_max_y;
static unsigned joy_center_x=2048,joy_center_y=2048,joy_sample_seen,joy_last_sample;
static unsigned joy_candidate,joy_candidate_since,joy_candidate_count,joy_candidate_fired;
static unsigned joy_last_move,joy_has_moved,joy_moves,joy_diag_next;
static unsigned joy_queue[16],joy_head,joy_tail;
 
static void joystick_motion_reset(void){
    joy_candidate=0;joy_candidate_since=0;joy_candidate_count=0;joy_candidate_fired=0;
}
static void joystick_command(unsigned command){
    unsigned next=(joy_tail+1U)&15U;
    if(next!=joy_head){joy_queue[joy_tail]=command;joy_tail=next;}
}
static void joystick_send(void){
    if(joy_head==joy_tail)return;
    unsigned status=ui_read(0x20);
    if((status&1U)!=((status>>1)&1U))return;
    ui_write(0x20,(joy_queue[joy_head]<<4)|((status^1U)&1U));
    joy_head=(joy_head+1U)&15U;
}
static void joystick_reset_service(void){
    if(!joy_reset_pending || shot_state)return;
    if(arm_motion_busy()){arm_motion_cancel();return;}
    sl_stop_requested=1;
}


static void joystick_auto_focus_changed(unsigned was_open){
    unsigned open=auto_pick_is_open();
    if(open==was_open)return;
    fusion_pick_cancel_pending("AUTO MODE CHANGED");
    joy_head=joy_tail=0;joystick_motion_reset();
    joystick_command(open?7U:(joy_enabled?6U:7U));
    ui_dirty=1;
}
static void joystick_leave_auto(void){
    unsigned was_open=auto_pick_is_open();
    if(was_open){auto_pick_close();joystick_auto_focus_changed(was_open);}
}
static void joystick_confirm(void){
    if(ui_cursor==0){ui_totals=!ui_totals;ui_message(ui_totals?"累计统计已开启":"累计统计已隐藏");}
    else if(ui_cursor==1){
        ui_record_scene();
    }else if(ui_cursor==2)shot_request();
    else if(ui_cursor==3){
        joy_enabled=!joy_enabled;joystick_motion_reset();
        joystick_command(joy_enabled?6:7);
        ui_message(joy_enabled?"摇杆选择已开启":"摇杆选择已关闭");
    }else if(ui_cursor==4){
        ui_axes_visible=!ui_axes_visible;ui_write(0x38,ui_axes_visible);
        ui_message(ui_axes_visible?"坐标轴已展开":"坐标轴已隐藏");
    }else if(ui_cursor==5 || ui_cursor==6){

        if(arm_motion_busy()){
            fusion_pick_cancel_pending("MENU STOP REQUEST");
            if(auto_pick_is_running())auto_pick_cancel("MENU STOP REQUEST",1);
            else arm_motion_cancel();
            ui_message("ARM STOP REQUEST");return;
        }
        unsigned was_open=auto_pick_is_open();
        auto_pick_toggle_mode(ui_cursor==5?AUTO_PICK_CLASS_PICK:AUTO_PICK_SORT_ALL);
        joystick_auto_focus_changed(was_open);
    }
}
static void joystick_poll(void){
    unsigned now=runtime_ms(),raw=ui_read(0x2c)&31U;
    if(raw!=ui_raw){ui_raw=raw;ui_changed=now;}
    if((unsigned)(now-ui_changed)>=25U){
        if(!raw){ui_stable=0;ui_released=1;}
        else if(!ui_stable && ui_released){
            ui_stable=raw;ui_released=0;
            if(raw==2){joystick_leave_auto();ui_cursor=ui_cursor?ui_cursor-1:UI_MENU_COUNT-1U;fusion_menu_cancel();ui_dirty=1;}
            else if(raw==8){joystick_leave_auto();ui_cursor=(ui_cursor+1U)%UI_MENU_COUNT;fusion_menu_cancel();ui_dirty=1;}
            else if(raw==4 && !joy_reset_pending)joystick_confirm();
            else if(raw==1 && !joy_reset_pending){
                if(auto_pick_is_open())auto_pick_press();
                else if(joy_enabled)fusion_pick_press();
            }
            else if(raw==16){
                if(auto_pick_is_open()){
                    auto_pick_cancel("SW4 STOP",1);
                    ui_message("AUTO STOP / Z: NEW BATCH");
                }else if(arm_motion_busy()){arm_motion_cancel();ui_message("ARM STOP REQUEST");}
                else{joy_reset_pending=1;ui_message("会话停止");}
            }
        }
    }
    joystick_send();
    if((int)(now-joy_next_poll)<0)return;
    joy_next_poll=now+5U;
    unsigned samples=ui_read(0x30);
    if(samples==joy_sample_seen){
        if((unsigned)(now-joy_last_sample)>JOY_MAX_SAMPLE_GAP_MS)joystick_motion_reset();
        return;
    }
     
    if(joy_last_sample && (unsigned)(now-joy_last_sample)>JOY_MAX_SAMPLE_GAP_MS)
        joystick_motion_reset();
    joy_sample_seen=samples;joy_last_sample=now;
    unsigned x=ui_read(0x24)&4095U,y=ui_read(0x28)&4095U;
    if((joy_enabled || auto_pick_is_open() || !joy_calibrated) && (int)(now-joy_diag_next)>=0){
        joy_diag_next=now+2000U;
        runtime_eventf("JOY_INPUT,ms,%u,x,%u,y,%u,cx,%u,cy,%u,cal,%u,enabled,%u,dir,%u,moves,%u,samples,%u\r\n",
            now,x,y,joy_center_x,joy_center_y,joy_calibrated,joy_enabled,joy_candidate,joy_moves,samples);
    }
    if(!joy_calibrated){
        joy_sum_x+=x;joy_sum_y+=y;++joy_count;
        if(x<joy_min_x)joy_min_x=x;
        if(x>joy_max_x)joy_max_x=x;
        if(y<joy_min_y)joy_min_y=y;
        if(y>joy_max_y)joy_max_y=y;
        if(joy_count==64){
            

            if(joy_min_x>=JOY_CAL_MIN && joy_max_x<=JOY_CAL_MAX && joy_max_x-joy_min_x<120 &&
               joy_min_y>=JOY_CAL_MIN && joy_max_y<=JOY_CAL_MAX && joy_max_y-joy_min_y<120){
                joy_center_x=joy_sum_x/64;joy_center_y=joy_sum_y/64;joy_calibrated=1;
                joystick_motion_reset();
                runtime_eventf("JOYSTICK_CENTER,x,%u,y,%u\r\n",joy_center_x,joy_center_y);
            }
            joy_count=0;joy_sum_x=0;joy_sum_y=0;joy_min_x=4095;joy_max_x=0;joy_min_y=4095;joy_max_y=0;
        }
        return;
    }
    int dx=(int)x-(int)joy_center_x,dy=(int)y-(int)joy_center_y;
    if(JOY_X_REVERSE)dx=-dx;
    if(JOY_Y_REVERSE)dy=-dy;
    unsigned ax=dx<0?(unsigned)-dx:(unsigned)dx,ay=dy<0?(unsigned)-dy:(unsigned)dy;
    if((!joy_enabled && !auto_pick_is_open()) || joy_reset_pending || auto_pick_is_running()){
        joystick_motion_reset();return;
    }
     
    if(ax<=JOY_CENTER_THRESHOLD && ay<=JOY_CENTER_THRESHOLD){
        joystick_motion_reset();
        return;
    }
    unsigned direction=0;
    

    if(ax>=JOY_ENTER_THRESHOLD && ax>=ay+JOY_AXIS_MARGIN)direction=dx<0?1U:2U;
    else if(ay>=JOY_ENTER_THRESHOLD && ay>=ax+JOY_AXIS_MARGIN)direction=dy<0?3U:4U;
    else if(joy_candidate==(dx<0?1U:2U) && ax>=JOY_HOLD_THRESHOLD &&
            ax>=ay+JOY_HOLD_AXIS_MARGIN)direction=joy_candidate;
    else if(joy_candidate==(dy<0?3U:4U) && ay>=JOY_HOLD_THRESHOLD &&
            ay>=ax+JOY_HOLD_AXIS_MARGIN)direction=joy_candidate;
    if(!direction){joystick_motion_reset();return;}
    if(direction!=joy_candidate){
        joy_candidate=direction;joy_candidate_since=now;joy_candidate_count=1;joy_candidate_fired=0;
        return;
    }
    if(joy_candidate_count<JOY_MIN_DIRECTION_SAMPLES)++joy_candidate_count;
    if(joy_candidate_count<JOY_MIN_DIRECTION_SAMPLES ||
       (unsigned)(now-joy_candidate_since)<JOY_DWELL_MS)return;
    if(joy_has_moved && (unsigned)(now-joy_last_move)<
       (joy_candidate_fired?JOY_REPEAT_MS:JOY_MOVE_GUARD_MS))return;
    if(auto_pick_is_open()){
        auto_pick_direction(direction);
        joy_candidate_fired=1;joy_last_move=now;joy_has_moved=1;++joy_moves;ui_dirty=1;
        runtime_eventf("JOY_AUTO,ms,%u,dir,%u,count,%u\r\n",now,direction,joy_moves);
        return;
    }
     
    unsigned status=ui_read(0x20);
    if(joy_head!=joy_tail || (status&1U)!=((status>>1)&1U))return;
    joystick_command(direction);
    joy_candidate_fired=1;joy_last_move=now;joy_has_moved=1;++joy_moves;
    runtime_eventf("JOY_MOVE,ms,%u,dir,%u,x,%u,y,%u,count,%u\r\n",now,direction,x,y,joy_moves);
}
#endif
