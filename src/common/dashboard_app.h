#ifndef DASHBOARD_APP_H
#define DASHBOARD_APP_H
#define UI_BASE 0x43000000U
#define SCREEN_DMA_BASE 0x40410000U
#define SCREEN_FRAME_BASE sl_screen_address
#define SCREEN_WIDTH 1280U
#define SCREEN_HEIGHT 720U
#define SCREEN_BYTES (SCREEN_WIDTH*SCREEN_HEIGHT*4U)
#define UI_MENU_COUNT 7U
#include "dashboard_font_map.h"
static unsigned joy_enabled,joy_calibrated;
static unsigned ui_axes_visible=1;
static unsigned ui_cursor,ui_totals=0,ui_dirty=1,ui_last_render,ui_fps_milli;


static unsigned ui_video_fps_milli,ui_camera_fps_milli,ui_publish_fps_milli;
static unsigned ui_video_rate_valid,ui_video_hardware_valid,ui_video_sample_valid;
static unsigned ui_video_poll_seen,ui_video_last_poll,ui_video_sample_ms;
static unsigned ui_video_camera_base,ui_video_publish_base,ui_video_display_base;
static unsigned ui_video_status,ui_video_window_ms;
static unsigned ui_raw,ui_stable,ui_changed,ui_released,ui_toast_until;
static unsigned ui_scene_seen,ui_inference_valid;

#define UI_SCENE_HOLD_MS 3000U
static unsigned ui_scene_display[REC_CLASS_COUNT];
static unsigned ui_scene_display_valid,ui_scene_display_seen;
static unsigned ui_scene_display_version,ui_scene_display_ms;
static const char *ui_toast="等待相机";
static char ui_record_message[96];
static u16 ui_cells[1800];

static u16 ui_bank_cells[2][1800];
static unsigned ui_bank_valid[2];
static unsigned shot_state,shot_start,shot_index=1,shot_row,shot_saved,shot_error,shot_open;
static FIL shot_file;
static char shot_path[40],shot_final[40];
static u8 shot_chunk[1280*2*8] __attribute__((aligned(64)));
static unsigned ui_read(unsigned offset){return Xil_In32(UI_BASE+offset);}
static void ui_write(unsigned offset,unsigned value){Xil_Out32(UI_BASE+offset,value);}
#include "ui_class_colors.h"
static void ui_video_stats_poll(unsigned now){
    if(ui_video_poll_seen && (unsigned)(now-ui_video_last_poll)<500U)return;
    ui_video_poll_seen=1U;ui_video_last_poll=now;
    if(ui_read(0x3c)!=0x56504631U){
        if(ui_video_hardware_valid || ui_video_rate_valid)ui_dirty=1U;
        ui_video_hardware_valid=ui_video_sample_valid=ui_video_rate_valid=0U;
        return;
    }
    if(!ui_video_hardware_valid)ui_dirty=1U;
    ui_video_hardware_valid=1U;
    unsigned camera=ui_read(0x40),published=ui_read(0x44),displayed=ui_read(0x48);
    ui_video_status=ui_read(0x4c);
    unsigned elapsed=now-ui_video_sample_ms;
    unsigned camera_delta=camera-ui_video_camera_base;
    unsigned publish_delta=published-ui_video_publish_base;
    unsigned display_delta=displayed-ui_video_display_base;

    uint64_t allowance=(uint64_t)elapsed*120U+2000U;
    unsigned invalid=elapsed>60000U ||
        (uint64_t)camera_delta*1000U>allowance ||
        (uint64_t)publish_delta*1000U>allowance ||
        (uint64_t)display_delta*1000U>allowance;
    if(!ui_video_sample_valid || invalid){
        ui_video_sample_ms=now;ui_video_camera_base=camera;
        ui_video_publish_base=published;ui_video_display_base=displayed;
        ui_video_sample_valid=1U;ui_video_rate_valid=0U;ui_dirty=1U;
        return;
    }
    if(elapsed<3000U)return;
    ui_camera_fps_milli=(unsigned)((uint64_t)camera_delta*1000000U/elapsed);
    ui_publish_fps_milli=(unsigned)((uint64_t)publish_delta*1000000U/elapsed);
    ui_video_fps_milli=(unsigned)((uint64_t)display_delta*1000000U/elapsed);
    ui_video_window_ms=elapsed;ui_video_rate_valid=1U;ui_dirty=1U;
    ui_video_sample_ms=now;ui_video_camera_base=camera;
    ui_video_publish_base=published;ui_video_display_base=displayed;
     
    if(!arm_motion_busy() && runtime_log_used+384U<=sizeof(runtime_log_buffer))
        runtime_eventf("VIDEO_RATE,window_ms,%u,camera_millifps,%u,publish_millifps,%u,display_millifps,%u,camera_frames,%u,published_frames,%u,displayed_frames,%u,status,%08x\r\n",
        elapsed,ui_camera_fps_milli,ui_publish_fps_milli,ui_video_fps_milli,
        camera,published,displayed,ui_video_status);
}
static void ui_message(const char *message){ui_toast=message;ui_toast_until=runtime_ms()+3000U;ui_dirty=1;}
static void ui_scene_display_observe(unsigned now,unsigned version,unsigned status,
        const unsigned *scene,unsigned available,unsigned coherent){
    if(!available){ui_scene_display_valid=0;return;}
    unsigned sum=0;for(unsigned k=0;k<REC_CLASS_COUNT;++k)sum+=scene[k];
    if(coherent && (status&128U) && !(status&256U) &&
       (status&63U)<=REC_MAX_OBJECTS && sum==(status&63U) &&
       (!ui_scene_display_seen || version!=ui_scene_display_version)){
        memcpy(ui_scene_display,scene,sizeof(ui_scene_display));
        ui_scene_display_seen=ui_scene_display_valid=1U;
        ui_scene_display_version=version;ui_scene_display_ms=now;
    }
    if(ui_scene_display_valid && (unsigned)(now-ui_scene_display_ms)>UI_SCENE_HOLD_MS)
        ui_scene_display_valid=0;
}
static void ui_record_scene(void){
    if(arm_motion_busy() || recognition_results_hidden()){
        ui_message("识别暂停或更新中 / 暂不记录");return;
    }
    unsigned before[REC_CLASS_COUNT],batches=ui_read(0x10),code=0,after_batches=batches;
    unsigned long long before_sum=0,after_sum=0;
    for(unsigned k=0;k<REC_CLASS_COUNT;++k){before[k]=ui_read(0x100+4*k);before_sum+=before[k];}
     
    ui_totals=1;
    for(unsigned attempt=0;attempt<8;++attempt){
        ui_write(0x0c,1);
        code=ui_read(0x18);after_batches=ui_read(0x10);
        

        if(code!=4 || after_batches!=batches)break;
        usleep(1);
    }
    unsigned monotonic=1,saturated=0,recorded=ui_read(0x14);
    for(unsigned k=0;k<REC_CLASS_COUNT;++k){
        unsigned value=ui_read(0x100+4*k);after_sum+=value;
        if(value<before[k])monotonic=0;
        if(value==0xffffffffU)saturated=1;
    }
    unsigned long long added=after_sum>=before_sum?after_sum-before_sum:0;
    unsigned expected_batches=batches==0xffffffffU?batches:batches+1U;
    unsigned verified=code==1 && after_batches==expected_batches && monotonic &&
        recorded>=1 && recorded<=REC_MAX_OBJECTS && (added==recorded || (saturated && added<=recorded));
    if(verified){
        snprintf(ui_record_message,sizeof(ui_record_message),"记录完成 +%llu 颗 / 总计 %llu",added,after_sum);
        ui_message(ui_record_message);
    }else if(code==3)ui_message("空场景, 未记录");
    else if(code==4)ui_message("画面正在更新, 请稍后");
    else if(code==2)ui_message("等待有效识别结果");
    else ui_message("记录结果未确认, 查看累计统计");
    runtime_eventf("RECORD,status,%u,verified,%u,scene,%u,scene_flags,%u,before_batches,%u,batches,%u,count,%u,added,%llu,total,%llu\r\n",
        code,verified,ui_read(4),ui_read(8),batches,after_batches,recorded,added,after_sum);
}
static void ui_text(unsigned row,unsigned col,const char *text){
    unsigned position=row*40U+col,limit=(row+1U)*40U;
    const unsigned char *s=(const unsigned char *)text;
    while(*s && position<limit && position<1800U){
        unsigned unicode=*s++,glyph=unicode;
        if(unicode>=0xe0 && *s && s[1]){
            unicode=((unicode&15U)<<12)|((s[0]&63U)<<6)|(s[1]&63U);s+=2;glyph='?';
            for(unsigned k=0;k<sizeof(dashboard_glyphs)/sizeof(dashboard_glyphs[0]);++k)
                if(dashboard_glyphs[k][0]==unicode){glyph=dashboard_glyphs[k][1];break;}
        } else if(unicode>=128){glyph='?';}
        ui_cells[position]=(ui_cells[position]&0xf000U)|glyph;++position;
        if(glyph>=128 && position<limit){ui_cells[position]=(ui_cells[position]&0xf000U)|(glyph+1U);++position;}
    }
}
static void ui_style(unsigned first,unsigned last,unsigned style){
    for(unsigned row=first;row<=last && row<45;++row)
        for(unsigned col=0;col<40;++col)ui_cells[row*40+col]=(style<<12)|' ';
}
 
static void ui_area(unsigned first,unsigned last,unsigned left,unsigned right,unsigned style){
    for(unsigned row=first;row<=last && row<45U;++row)
        for(unsigned col=left;col<=right && col<40U;++col)ui_cells[row*40U+col]=(style<<12)|' ';
}
static void ui_icon(unsigned row,unsigned col,unsigned glyph){
    if(row>=45U || col>=39U || glyph>=511U)return;
    unsigned p=row*40U+col;
    ui_cells[p]=(ui_cells[p]&0xf000U)|glyph;
    ui_cells[p+1]=(ui_cells[p+1]&0xf000U)|(glyph+1U);
}
static const char *ui_arm_phase(void){
    const char *phase=arm_motion_phase_name();
    if(!strcmp(arm_motion_state_name(),"PREFLIGHT"))return "SERVO CHECK";
    if(!strcmp(arm_motion_last_error(),"TARGET_STALE"))return "REFRESH TARGET";
    if(!arm_motion_action_count())return "NO MOTION STARTED";
    

    if(strstr(phase,"place_approach"))return "BIN APPROACH";
    if(strstr(phase,"place_align"))return "BIN ALIGN";
    if(strstr(phase,"place_descend"))return "BIN DESCEND";
    if(strstr(phase,"place_release"))return "BIN RELEASE";
    if(strstr(phase,"place_lift"))return "BIN LIFT";
    if(strstr(phase,"place_leave"))return "BIN DEPART";
    if(strstr(phase,"place_return"))return "HOME RETURN";
    if(strstr(phase,"close"))return "夹爪闭合";
    if(strstr(phase,"open") || strstr(phase,"release"))return "张开夹爪";
    if(strstr(phase,"home") || strstr(phase,"return"))return "回到待机位";
    if(strstr(phase,"descend"))return "下降夹取";
    if(strstr(phase,"lift"))return "抬起目标";
    if(strstr(phase,"align") || strstr(phase,"rotate"))return "对准目标";
    return "执行夹取";
}
static void ui_render(void){
    unsigned now=runtime_ms(),bank_state=ui_read(0x1c);
    ui_video_stats_poll(now);
    if((bank_state&1U)!=((bank_state>>1)&1U))return;
    if(!ui_dirty && (unsigned)(now-ui_last_render)<500U)return;
    ui_last_render=now;ui_dirty=0;
    unsigned totals[REC_CLASS_COUNT],scene[REC_CLASS_COUNT],version,version_end;
    do{
        version=ui_read(4);
        for(unsigned k=0;k<REC_CLASS_COUNT;++k){totals[k]=ui_read(0x100+k*4);scene[k]=ui_read(0x180+k*4);}
        version_end=ui_read(4);
    }while(version!=version_end);
    unsigned status=ui_read(8);
    unsigned moving=arm_motion_busy(),paused=recognition_motion_paused(),refreshing=recognition_resume_waiting();
    unsigned results_hidden=recognition_results_hidden();
    unsigned live=!moving && !paused && !refreshing && !results_hidden && ui_inference_valid &&
        (status&128U) && !(status&256U);
    ui_scene_display_observe(now,version,status,scene,
        !moving && !paused && !refreshing && !results_hidden && ui_inference_valid,
        version==ui_read(4));
    unsigned display_live=ui_scene_display_valid,display_count=0;
    for(unsigned k=0;k<REC_CLASS_COUNT;++k)display_count+=ui_scene_display[k];
    AutoPickView automatic;auto_pick_get_view(&automatic);
    unsigned class_colors=ui_class_colors_prepare(&automatic);
    unsigned selected=ui_read(0x34),slot=selected&15U;
    unsigned selection_valid=live && joy_enabled && coordinate_valid &&
        (selected&0x300U)==0x300U && slot<coordinate_count && slot<REC_MAX_OBJECTS &&
        coordinate_visible_version==version && coordinate_visible[slot].valid &&
        coordinate_visible[slot].class_id<REC_CLASS_COUNT &&
        coordinate_visible[slot].class_id==recognition_selection_class(selected) &&
        version==ui_read(4) && selected==ui_read(0x34);
    

    unsigned positions_live=live && coordinate_valid &&
        coordinate_count<=REC_MAX_OBJECTS && coordinate_count==(status&63U) &&
        coordinate_visible_version==version && version==ui_read(4);
    unsigned class_panel=automatic.open && automatic.mode==AUTO_PICK_CLASS_PICK;
    unsigned sort_panel=automatic.open && automatic.mode==AUTO_PICK_SORT_ALL;
    unsigned waiting_start=automatic.open && automatic.state==AUTO_PICK_WAIT_START;
    /* A catalog is a presentation snapshot, not permission to move the arm.
       Its explicit expiry belongs to the catalog owner; a short publication
       handoff must not turn unchanged counts into blinking '--' characters. */
    unsigned catalog_display=automatic.catalog_valid && !automatic.catalog_stale;
    unsigned failed=!strcmp(arm_motion_state_name(),"ERROR") || automatic.state==AUTO_PICK_ERROR;
    unsigned long long grand=0;
    for(unsigned k=0;k<REC_CLASS_COUNT;++k)grand+=totals[k];
    ui_style(0,44,0);ui_style(0,3,1);
    ui_icon(1,2,UI_ICON_BRAND);ui_text(1,6,"SCREW LAB");
    ui_text(2,6,"螺钉智能分拣");
    ui_area(4,5,2,18,9);ui_area(4,5,21,37,10);
    ui_icon(4,3,UI_ICON_FPS);ui_text(4,6,"视频帧率");
    ui_icon(4,22,UI_ICON_COUNT);ui_text(4,25,"识别数量");
    char line[96];
    if(ui_video_hardware_valid && ui_video_rate_valid)
        snprintf(line,sizeof(line),"%u.%02u FPS",ui_video_fps_milli/1000U,(ui_video_fps_milli%1000U)/10U);
    else snprintf(line,sizeof(line),"-- FPS");
    ui_text(5,6,line);
    if(display_live)snprintf(line,sizeof(line),"%02u 颗",display_count);
    else snprintf(line,sizeof(line),"-- 颗");
    ui_text(5,25,line);
    unsigned state_style=failed?8U:(moving || paused || refreshing || !display_live)?7U:5U;
    ui_area(7,9,2,37,state_style);
    ui_icon(7,3,failed?UI_ICON_WARNING:(moving || paused)?UI_ICON_PAUSE:UI_ICON_READY);
    if(failed){
        ui_text(7,6,"夹取暂停 / 检查机械臂");
        unsigned servo=arm_motion_fault_servo();
        if(!strcmp(arm_motion_state_name(),"ERROR"))
            snprintf(line,sizeof(line),servo?"%s / S%u":"%s",arm_motion_last_error(),servo);
        else snprintf(line,sizeof(line),"%.34s",automatic.message?automatic.message:"SORT ERROR");
        ui_text(8,3,line);
        if(!strcmp(arm_motion_state_name(),"ERROR"))ui_text(9,3,ui_arm_phase());
        else if(automatic.message && strlen(automatic.message)>34U){
            snprintf(line,sizeof(line),"%.34s",automatic.message+34U);ui_text(9,3,line);
        }
    }else if(moving || paused){
        unsigned total=arm_motion_action_count(),done=arm_motion_completed_actions();
        unsigned pct=total?(unsigned)((uint64_t)done*100U/total):0U;if(pct>100U)pct=100U;
        ui_text(7,6,"识别暂停 / 夹取中");ui_text(8,3,ui_arm_phase());
        snprintf(line,sizeof(line),"%3u%%",pct);ui_text(8,32,line);
        if(automatic.running && automatic.current_class<REC_CLASS_COUNT){
            unsigned n=recognition_number(automatic.current_class);
            if(automatic.current_bin<4U)
                snprintf(line,sizeof(line),"M%u%u > BIN%u  %u/%u",(n-1U)/5U+3U,(n-1U)%5U+1U,automatic.current_bin+1U,done,total);
            else snprintf(line,sizeof(line),"M%u%u / %u/%u",(n-1U)/5U+3U,(n-1U)%5U+1U,done,total);
        }else snprintf(line,sizeof(line),"动作 %u/%u",done,total);
        ui_text(9,3,line);
    }else if(waiting_start){
        ui_text(7,6,"分拣准备中");ui_text(8,3,"等待有效识别结果");
        ui_text(9,3,"按下摇杆可停止等待");
    }else if(refreshing || fusion_pick_pending()){
        ui_text(7,6,"更新识别");ui_text(8,6,"获取新的目标位置");
        ui_text(9,3,"等待新画面 / 重新确认位置");
    }else if(automatic.open && automatic.state==AUTO_PICK_WAIT_REMOVAL){
        ui_text(7,6,"夹取完成 / 确认结果");ui_text(8,3,"等待目标位置更新");
        snprintf(line,sizeof(line),"完成 %u/%u / 已确认 %u",automatic.actions_completed,automatic.queue_count,automatic.removed_count);
        ui_text(9,3,line);
    }else if(automatic.open && automatic.state==AUTO_PICK_WAIT_TARGET){
        ui_text(7,6,"重新确认目标位置");ui_text(8,3,"等待新的有效识别结果");
        snprintf(line,sizeof(line),"完成 %u/%u / 从左到右",automatic.actions_completed,automatic.queue_count);
        if(automatic.mode==AUTO_PICK_CLASS_PICK && automatic.order==AUTO_PICK_TOP_BOTTOM)
            snprintf(line,sizeof(line),"完成 %u/%u / 从上到下",automatic.actions_completed,automatic.queue_count);
        ui_text(9,3,line);
    }else if(automatic.open && automatic.state==AUTO_PICK_STOPPED){
        ui_text(7,6,"分拣已停止");
        snprintf(line,sizeof(line),"%.34s",automatic.message?automatic.message:"STOPPED");ui_text(8,3,line);
        if(automatic.message && strlen(automatic.message)>34U){
            snprintf(line,sizeof(line),"%.34s",automatic.message+34U);ui_text(9,3,line);
        }
    }else if(automatic.open && automatic.state==AUTO_PICK_DONE){
        ui_text(7,6,"分拣完成");
        snprintf(line,sizeof(line),"完成 %u / 已确认 %u",automatic.actions_completed,automatic.removed_count);ui_text(8,3,line);
        ui_text(9,3,"按下摇杆开始新的任务");
    }else if(display_live){
        ui_text(7,6,"正在识别");
        ui_text(8,6,automatic.running?"准备下一次夹取":"等待操作");
    }else{
        ui_text(7,6,"等待识别");ui_text(8,6,"正在获取画面");
    }
    ui_text(10,3,"操作");
    static const unsigned menu_icons[7]={UI_ICON_TOTALS,UI_ICON_RECORD,UI_ICON_CAMERA,
        UI_ICON_TARGET,UI_ICON_AXES,UI_ICON_GRIP,UI_ICON_AUTO};
    for(unsigned m=0;m<UI_MENU_COUNT;++m){
        unsigned row=11U+m*2U,style=m==ui_cursor?2U:4U;
        ui_area(row,row+1U,2,37,style);ui_icon(row,3,menu_icons[m]);
        if(m==ui_cursor)ui_text(row,1,">");
    }
    ui_text(11,7,"累计统计");ui_text(11,30,ui_totals?"开启":"关闭");
    ui_text(13,7,"记录数量");ui_text(13,30,moving || paused || refreshing || results_hidden?"暂停":"累加");
    ui_text(15,7,"保存画面");
    if(shot_state)ui_text(15,30,"保存中");
    else{snprintf(line,sizeof(line),"%u 张",shot_saved);ui_text(15,30,line);}
    ui_text(17,7,"目标选择");ui_text(17,30,automatic.open?"自动":joy_enabled?"开启":"关闭");
    ui_text(19,7,"坐标显示");ui_text(19,30,ui_axes_visible?"开启":"关闭");
    ui_text(21,7,moving?"停止运动":"夹取目标");
    ui_text(21,30,moving?"停止":class_panel?"开启":"关闭");
    if(moving && ui_cursor!=5U){ui_area(21,22,2,37,15);ui_icon(21,3,UI_ICON_WARNING);
        ui_text(21,7,"停止运动");ui_text(21,30,"停止");}
    ui_text(23,7,"自动分拣");ui_text(23,30,sort_panel?"开启":"关闭");
    ui_area(25,26,2,37,3);
    if(automatic.open && results_hidden){

        ui_text(25,3,sort_panel?"自动分拣":"夹取目标");
        if(class_panel)ui_text(26,3,"BIN2");
        if(waiting_start){
            ui_text(28,4,"分拣准备中");
            ui_text(30,4,"等待新的有效识别结果");
        }else if(moving || paused){
            ui_text(28,4,"识别暂停 / 夹取中");
        }else{
            ui_text(28,4,"重新确认目标位置");
            ui_text(30,4,"等待新的有效识别结果");
        }
        snprintf(line,sizeof(line),"完成 %u/%u",automatic.actions_completed,automatic.queue_count);
        ui_text(33,4,line);
        snprintf(line,sizeof(line),"已确认 %u",automatic.removed_count);ui_text(35,4,line);
    }else if(automatic.open){
        ui_text(25,3,sort_panel?"自动分拣":"分类选择");
        ui_text(25,25,automatic.order==AUTO_PICK_LEFT_RIGHT?"从左到右":"从上到下");
        ui_text(26,3,"编号  型号");ui_text(26,29,"数量");
        ui_text(26,20,"位置");
        if(!automatic.class_count)ui_text(29,4,catalog_display?"当前没有目标":"等待识别结果");
        for(unsigned k=0;k<automatic.class_count && k<REC_CLASS_COUNT;++k){
            unsigned id=automatic.class_ids[k];if(id>=REC_CLASS_COUNT)continue;
            unsigned number=recognition_number(id),row=27U+k;
            unsigned highlighted=class_panel?id==automatic.selected_class:
                automatic.running && id==automatic.current_class;
            ui_area(row,row,2,37,sort_panel?ui_class_colors_style(id):highlighted?2U:(k&1U)?0U:4U);
            snprintf(line,sizeof(line),"%02u    %s",number,recognition_short_name(id));
            ui_text(row,3,line);
            if(sort_panel){
                if(automatic.bin_for_class[id]<4U)snprintf(line,sizeof(line),"BIN%u",automatic.bin_for_class[id]+1U);
                else snprintf(line,sizeof(line),"--");
                ui_text(row,20,line);
            }else ui_text(row,20,recognition_pickable(id)?"BIN2":"VIEW");
            if(catalog_display)
                snprintf(line,sizeof(line),"%02u",automatic.counts[id]);
            else snprintf(line,sizeof(line),"--");
            ui_text(row,30,line);
        }
    }else if(ui_totals){
        ui_text(25,3,"累计统计");
        snprintf(line,sizeof(line),"总计 %llu",grand);ui_text(25,21,line);
        ui_text(26,3,"型号 当前/累计");ui_text(26,21,"型号 当前/累计");
        for(unsigned k=0;k<REC_CLASS_COUNT;++k){
            unsigned row=27U+k%9U,col=3U+(k/9U)*18U;
            unsigned id=recognition_id_from_number(k+1U);
            if(display_live)snprintf(line,sizeof(line),"%-3.3s %02u/%10u",recognition_short_name(id),ui_scene_display[k],totals[k]);
            else snprintf(line,sizeof(line),"%-3.3s --/%10u",recognition_short_name(id),totals[k]);
            ui_text(row,col,line);
        }
    }else{
        ui_text(25,3,"识别结果");
        ui_text(26,3,"目标 型号");ui_text(26,15,"X/mm");ui_text(26,26,"Y/mm");
        if(moving || paused){
            ui_text(28,4,"识别暂停 / 夹取中");ui_text(30,4,"完成后自动恢复识别");
        }else if(results_hidden || refreshing || fusion_pick_pending() || (live && !positions_live)){
            ui_text(28,4,"正在更新目标");ui_text(30,4,"等待新画面确认位置");
        }else if(!live){
            ui_text(28,4,"等待识别结果");
        }else if(!(status&63U)){
            ui_text(28,4,"当前没有目标");
        }else{
            for(unsigned k=0;k<coordinate_count && k<REC_MAX_OBJECTS;++k){
                const PlatformPosition *p=&coordinate_visible[k];
                unsigned row=27U+k;
                ui_area(row,row,2,37,selection_valid && k==slot?2U:(k&1U)?0U:4U);
                snprintf(line,sizeof(line),"%c",'A'+k);ui_text(row,3,line);
                if(!p->valid || p->class_id>=REC_CLASS_COUNT){ui_text(row,7,"--");continue;}
                snprintf(line,sizeof(line),"%s",recognition_short_name(p->class_id));ui_text(row,8,line);
                coordinate_format(line,sizeof(line),p->x_tenth_mm);ui_text(row,15,line);
                coordinate_format(line,sizeof(line),p->y_tenth_mm);ui_text(row,26,line);
            }
        }
    }
    ui_area(43,44,2,37,6);
    if(moving || paused)ui_text(43,3,"识别暂停 / SW4 停止");
    else if(shot_state)ui_text(43,3,"正在保存画面");
    else if((int)(ui_toast_until-now)>0)ui_text(43,3,ui_toast);
    else if(automatic.open){
        if(automatic.running)ui_text(43,3,"按摇杆停止 / 更新位置");
        else if(automatic.state==AUTO_PICK_DONE)ui_text(43,3,"分拣完成 / 按摇杆再开始");
        else if(sort_panel)ui_text(43,3,"从左到右 / 按摇杆开始");
        else ui_text(43,3,"上下选类型 / 按摇杆开始");
    }else if(!joy_calibrated)ui_text(43,3,"松开摇杆 / 正在校准");
    if(sort_panel){snprintf(line,sizeof(line),"BIN %u/4 / 重启前不重置",automatic.bin_count);ui_text(44,3,line);}
    else if(class_panel)ui_text(44,3,"CLASS > BIN2");
    else if(joy_enabled)ui_text(44,3,"SINGLE > BIN1");
    unsigned front=bank_state&1U,bank=1U-front;
    if(ui_bank_valid[front] && !memcmp(ui_bank_cells[front],ui_cells,sizeof(ui_cells)) &&
       !ui_class_colors_changed(class_colors))return;
    for(unsigned k=0;k<1800;++k){
        if(!ui_bank_valid[bank] || ui_bank_cells[bank][k]!=ui_cells[k])
            ui_write(0x4000+bank*0x2000+k*4,ui_cells[k]);
        ui_bank_cells[bank][k]=ui_cells[k];
    }
    ui_bank_valid[bank]=1;
    ui_class_colors_stage(class_colors);  
    ui_write(0x1c,bank);
}
static void shot_fail(const char *stage,unsigned code){
    if(shot_open){(void)f_close(&shot_file);shot_open=0;}
    gpio_word&=~10U;Xil_Out32(GPIO_BASE,gpio_word);
    shot_state=0;shot_error=1;ui_message("保存失败, 请重新尝试");
    runtime_eventf("SCREENSHOT_FAIL,%s,%u\r\n",stage,code);
}
static int dma_reset_arm(unsigned base,unsigned address,unsigned bytes){
    Xil_Out32(base+0x30,4);
    for(unsigned n=0;Xil_In32(base+0x30)&4U;++n){if(n>=10000)return -1;usleep(1);}
    Xil_Out32(base+0x34,0x7000);Xil_Out32(base+0x30,0x1001);
    Xil_Out32(base+0x48,address);Xil_Out32(base+0x58,bytes);return 0;
}
static void shot_request(void){
    if(arm_motion_busy()){ui_message("ARM BUSY / SAVE LATER");return;}
    if(shot_state){ui_message("正在保存, 请稍后");return;}
    if(!runtime_log_ready){ui_message("SD卡不可用");return;}
    

    gpio_word&=~10U;Xil_Out32(GPIO_BASE,gpio_word);usleep(10);
    if(dma_reset_arm(SCREEN_DMA_BASE,SCREEN_FRAME_BASE,SCREEN_BYTES)){shot_fail("DMA_RESET",0);return;}
    gpio_word|=8U;Xil_Out32(GPIO_BASE,gpio_word);usleep(10);
    shot_start=runtime_ms();shot_state=1;shot_error=0;
    gpio_word|=2U;Xil_Out32(GPIO_BASE,gpio_word);ui_dirty=1;
    runtime_eventf("SCREENSHOT_REQUEST,%u\r\n",shot_start);
}
#include "joystick_app.h"
static void ui_poll(void){
    joystick_poll();
    unsigned scene=ui_read(4);
    unsigned pending_coordinates=coordinate_ready;
    coordinate_publish(scene,ui_read(8));
    recognition_scene_published();
    auto_pick_refresh_view();
    if(pending_coordinates && !coordinate_ready)ui_dirty=1;
    if(scene!=ui_scene_seen){ui_scene_seen=scene;ui_dirty=1;}
    ui_render();
    joystick_reset_service();
}
static void ui_wait(unsigned milliseconds){
    unsigned begin=runtime_ms();do{
        fusion_service();
        if(!arm_motion_urgent()){ui_poll();usleep(1000);}
    }while((unsigned)(runtime_ms()-begin)<milliseconds);
}
static void put_le32(u8 *p,u32 value){for(unsigned k=0;k<4;++k)p[k]=(u8)(value>>(8*k));}
static void shot_service(void){
    if(!shot_state)return;
    if(shot_state==1){
        unsigned status=Xil_In32(SCREEN_DMA_BASE+0x34),pins=Xil_In32(GPIO_BASE+8);
        if((status&0x770U) || (pins&(1U<<18))){shot_fail("CAPTURE",status);return;}
        if(!(status&0x1000U)){if((unsigned)(runtime_ms()-shot_start)>1500U)shot_fail("TIMEOUT",status);return;}
        gpio_word&=~2U;Xil_Out32(GPIO_BASE,gpio_word);
        Xil_DCacheInvalidateRange((INTPTR)SCREEN_FRAME_BASE,SCREEN_BYTES);
        FRESULT result=f_mkdir("0:/SCREENS");
        if(result!=FR_OK && result!=FR_EXIST){shot_fail("DIRECTORY",result);return;}
        FILINFO info;
        for(;shot_index<=99999;++shot_index){
            snprintf(shot_path,sizeof(shot_path),"0:/SCREENS/LCD%05u.TMP",shot_index);
            snprintf(shot_final,sizeof(shot_final),"0:/SCREENS/LCD%05u.BMP",shot_index);
            result=f_stat(shot_final,&info);if(result==FR_OK)continue;
            if(result!=FR_NO_FILE){shot_fail("STAT",result);return;}
            result=f_open(&shot_file,shot_path,FA_WRITE|FA_CREATE_NEW);
            if(result==FR_EXIST)continue;
            if(result!=FR_OK){shot_fail("OPEN",result);return;}
            shot_open=1;break;
        }
        if(!shot_open){shot_fail("FULL",0);return;}
         
        u8 header[66]={0};header[0]='B';header[1]='M';
        put_le32(header+2,66+SCREEN_WIDTH*SCREEN_HEIGHT*2);put_le32(header+10,66);
        put_le32(header+14,40);put_le32(header+18,SCREEN_WIDTH);put_le32(header+22,0U-SCREEN_HEIGHT);
        header[26]=1;header[28]=16;put_le32(header+30,3);put_le32(header+34,SCREEN_WIDTH*SCREEN_HEIGHT*2);
        put_le32(header+54,0xf800);put_le32(header+58,0x07e0);put_le32(header+62,0x001f);
        UINT written=0;result=f_write(&shot_file,header,sizeof(header),&written);
        if(result!=FR_OK || written!=sizeof(header)){shot_fail("HEADER",result);return;}
        shot_row=0;shot_state=2;
    }
     
    if(shot_state==2){
        unsigned rows=SCREEN_HEIGHT-shot_row;if(rows>8)rows=8;
        const u32 *pixels=(const u32 *)sl_phys_ptr(SCREEN_FRAME_BASE,SCREEN_BYTES)+shot_row*SCREEN_WIDTH;
        for(unsigned k=0;k<rows*SCREEN_WIDTH;++k){u32 value=pixels[k];shot_chunk[k*2]=(u8)value;shot_chunk[k*2+1]=(u8)(value>>8);}
        UINT written=0;unsigned bytes=rows*SCREEN_WIDTH*2;
        FRESULT result=f_write(&shot_file,shot_chunk,bytes,&written);
        if(result!=FR_OK || written!=bytes){shot_fail("PIXELS",result);return;}
        shot_row+=rows;
        if(shot_row==SCREEN_HEIGHT){
            result=f_sync(&shot_file);FRESULT closed=f_close(&shot_file);shot_open=0;
            if(result!=FR_OK || closed!=FR_OK){shot_fail("CLOSE",result!=FR_OK?result:closed);return;}
            result=f_rename(shot_path,shot_final);
            if(result!=FR_OK){shot_fail("RENAME",result);return;}
            ++shot_saved;++shot_index;shot_state=0;ui_message("画面保存成功");
            runtime_eventf("SCREENSHOT_SAVED,%s,elapsed_ms,%u\r\n",shot_final,runtime_ms()-shot_start);
        }
    }
}
#endif
