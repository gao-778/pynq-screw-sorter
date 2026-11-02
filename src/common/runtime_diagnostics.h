 
#ifndef RUNTIME_DIAGNOSTICS_H
#define RUNTIME_DIAGNOSTICS_H
#include "workstation_config.h"
#define MANUAL_QUEUE_SIZE 8U
#define MANUAL_DEBOUNCE_MS 25U
static unsigned diagnostic_busy,diagnostic_open,diagnostic_disabled;
static unsigned diagnostic_index=1,diagnostic_row,diagnostic_attempt,diagnostic_frame_id;
static unsigned manual_active,manual_error,manual_press_ms,manual_capture_ms;
static unsigned manual_raw,manual_stable,manual_changed_ms,manual_released;
static unsigned manual_queue[MANUAL_QUEUE_SIZE],manual_head,manual_count;
static FIL diagnostic_file;
static char diagnostic_bmp_name[32],diagnostic_csv_name[32];
static u8 diagnostic_header[1078];
 
static u8 diagnostic_pixels[GRAY_FRAME_BYTES] __attribute__((aligned(64)));
static struct { u32 display[16],raw[8]; s32 logits[REC_CLASS_COUNT]; } manual_objects[REC_MAX_OBJECTS];
static char manual_csv[16384];
static unsigned manual_csv_used,manual_csv_error;

static void manual_update_led(int inference_failed) {
    if(diagnostic_disabled || manual_error || inference_failed)control(RGB_RED);
    else if(diagnostic_busy || manual_active || manual_count)control(RGB_BLUE);
    else control(RGB_GREEN);
}

 
static void manual_poll_button(void) {
    unsigned now=runtime_ms(),raw=Xil_In32(GPIO_BASE+8)&1U;
    if(raw!=manual_raw){manual_raw=raw;manual_changed_ms=now;}
    if((unsigned)(now-manual_changed_ms)<MANUAL_DEBOUNCE_MS)return;
    if(!raw){manual_stable=0;manual_released=1;return;}
    if(manual_stable || !manual_released)return;
    manual_stable=1;manual_released=0;
    if(diagnostic_disabled || !runtime_log_ready){
        manual_error=1;
        xil_printf("CAPTURE_REJECTED: SD unavailable; restart after checking card.\r\n");
        runtime_eventf("CAPTURE_REJECTED,SD_UNAVAILABLE,%u\r\n",now);
    } else if(manual_count>=MANUAL_QUEUE_SIZE){
        manual_error=1;
        xil_printf("CAPTURE_REJECTED: queue full; wait for green LED.\r\n");
        runtime_eventf("CAPTURE_REJECTED,QUEUE_FULL,%u\r\n",now);
    } else {
        manual_queue[(manual_head+manual_count)%MANUAL_QUEUE_SIZE]=now;
        ++manual_count;manual_error=0;
        runtime_eventf("BUTTON_REQUEST,%u,%u\r\n",now,manual_count);
    }
    manual_update_led(0);
}

static void manual_wait_ms(unsigned milliseconds) {
    for(unsigned n=0;n<milliseconds;++n){manual_poll_button();usleep(1000);}
}

static void diagnostic_init(void) {
    FILINFO info;
    FRESULT result=FR_NOT_READY;
    if(runtime_log_ready){
        result=f_mkdir("0:/PHOTOS");
        if(result==FR_EXIST){
            result=f_stat("0:/PHOTOS",&info);
            if(result==FR_OK && !(info.fattrib&AM_DIR))result=FR_DENIED;
        }
    }
    diagnostic_disabled=result!=FR_OK;
    manual_raw=manual_stable=Xil_In32(GPIO_BASE+8)&1U;
    manual_changed_ms=runtime_ms();manual_released=0;
    runtime_eventf("CAPTURE_MODE,BTN0_ONLY,debounce_ms,25,queue_depth,8,sd_status,%u\r\n",(unsigned)result);
    runtime_eventf("CAPTURE_RULE,next_frame_after_press,DIAG.ON_ignored,paired_BMP_CSV\r\n");
    unsigned size=1078U+GRAY_FRAME_BYTES;
    memset(diagnostic_header,0,sizeof(diagnostic_header));
    diagnostic_header[0]='B';diagnostic_header[1]='M';
    for(unsigned k=0;k<4;++k)diagnostic_header[2+k]=(u8)(size>>(8*k));
    diagnostic_header[10]=0x36;diagnostic_header[11]=0x04;diagnostic_header[14]=40;
    diagnostic_header[18]=0x00;diagnostic_header[19]=0x05;
     
    diagnostic_header[22]=0x40;diagnostic_header[23]=0xfc;diagnostic_header[24]=0xff;diagnostic_header[25]=0xff;
    diagnostic_header[26]=1;diagnostic_header[28]=8;
    for(unsigned k=0;k<4;++k)diagnostic_header[34+k]=(u8)(GRAY_FRAME_BYTES>>(8*k));
    diagnostic_header[47]=1;
    for(unsigned k=0;k<256;++k)for(unsigned c=0;c<3;++c)diagnostic_header[54+4*k+c]=(u8)k;
    runtime_log_sync();manual_update_led(0);
}

 
static void manual_begin_attempt(void) {
    manual_poll_button();
    manual_active=0;
    if(!diagnostic_busy && !diagnostic_disabled && manual_count){
        manual_press_ms=manual_queue[manual_head];
        manual_head=(manual_head+1U)%MANUAL_QUEUE_SIZE;--manual_count;
        manual_active=1;
        memset(manual_objects,0,sizeof(manual_objects));
        runtime_eventf("CAPTURE_ATTEMPT,%u,press_ms,%u\r\n",run_attempt,manual_press_ms);
    }
    runtime_detail_enabled=manual_active!=0;
    manual_update_led(0);
}

static void manual_attempt_failed(void) {
    if(manual_active){
        runtime_eventf("CAPTURE_FAILED,%u,press_ms,%u,RECOGNITION_FAILED\r\n",run_attempt,manual_press_ms);
        xil_printf("CAPTURE_FAILED: recognition failed; press again after recovery.\r\n");
        manual_active=0;manual_error=1;runtime_log_sync();
    }
}

static void manual_store_object(unsigned n,const u32 *display,const u32 *raw,const s32 *logits) {
    if(!manual_active || n>=REC_MAX_OBJECTS)return;
    memcpy(manual_objects[n].display,display,sizeof(manual_objects[n].display));
    memcpy(manual_objects[n].raw,raw,sizeof(manual_objects[n].raw));
    memcpy(manual_objects[n].logits,logits,sizeof(manual_objects[n].logits));
}

static void manual_csvf(const char *format,...) {
    va_list args;
    if(manual_csv_error)return;
    unsigned available=sizeof(manual_csv)-manual_csv_used;
    va_start(args,format);
    int count=vsnprintf(manual_csv+manual_csv_used,available,format,args);
    va_end(args);
    if(count<0 || (unsigned)count>=available){manual_csv_error=1;return;}
    manual_csv_used+=(unsigned)count;
}

 
static void manual_finish_frame(unsigned frame,unsigned objects,unsigned total,unsigned cycles,unsigned state) {
    if(!manual_active)return;
    unsigned dma=Xil_In32(GRAY_DMA_BASE+0x34);
    if(!(dma&0x1000U) || (dma&0x770U) || objects>REC_MAX_OBJECTS){
        runtime_eventf("CAPTURE_INVALID_FRAME,%u,%u,%u\r\n",run_attempt,frame,dma);
        manual_attempt_failed();return;
    }
    manual_capture_ms=runtime_ms();
    manual_csv_used=0;manual_csv_error=0;
    manual_csvf("BUILD,%s\r\n",BUILD_TAG);
    manual_csvf("FRAME,attempt,%u,frame,%u,objects,%u,total_detected,%u,cycles,%u,state,%u\r\n",run_attempt,frame,objects,total,cycles,state);
    manual_csvf("TIME,press_ms,%u,inference_done_ms,%u\r\n",manual_press_ms,manual_capture_ms);
    manual_csvf("IMAGE,width,1280,height,960,format,GRAY8,origin,top_left\r\n");
    manual_csvf("NOTE,predictions_are_not_ground_truth;display_fields_include_temporal_smoothing;raw_fields_belong_to_this_frame\r\n");
    manual_csvf("CLASSES");
    for(unsigned k=0;k<REC_CLASS_COUNT;++k)manual_csvf(",%u=%s",k,recognition_class_name(k));
    manual_csvf("\r\ntype,object_id,class_id,class_name,raw_class_id,raw_class_name,xmin,ymin,xmax,ymax,area,angle_index,angle_deg,local_xmin,local_ymin,local_xmax,local_ymax,raw_xmin,raw_ymin,raw_xmax,raw_ymax,raw_area,auto_angle_index,selected_angle_index,raw_local_xmin,raw_local_ymin,raw_local_xmax,raw_local_ymax,geometry_length_code,head_width_code,tail_width_code");
    for(unsigned k=0;k<REC_CLASS_COUNT;++k)manual_csvf(",logit_%s",recognition_class_name(k));
    manual_csvf("\r\n");
    for(unsigned n=0;n<objects;++n){
        const u32 *r=manual_objects[n].display,*raw=manual_objects[n].raw;
        unsigned cls=recognition_word_class(r[5]),raw_cls=(raw[4]&15U)|((raw[4]>>8)&16U),angle=(r[5]>>8)&15U;
        manual_csvf("OBJECT,%u,%u,%s,%u,%s,%u,%u,%u,%u,%u,%u,%u.%02u,%d,%d,%d,%d,",n,cls,recognition_class_name(cls),raw_cls,recognition_class_name(raw_cls),r[0]&2047U,r[1]&2047U,r[2]&2047U,r[3]&2047U,r[4],angle,angle*1125U/100U,angle*1125U%100U,(int)(s16)(r[0]>>16),(int)(s16)(r[1]>>16),(int)(s16)(r[2]>>16),(int)(s16)(r[3]>>16));
        manual_csvf("%u,%u,%u,%u,%u,%u,%u,%d,%d,%d,%d,%u,%u,%u",raw[0]&2047U,raw[1]&2047U,raw[2]&2047U,raw[3]&2047U,raw[6],(raw[4]>>8)&15U,(raw[4]>>4)&15U,(int)(s16)(raw[0]>>16),(int)(s16)(raw[1]>>16),(int)(s16)(raw[2]>>16),(int)(s16)(raw[3]>>16),(raw[5]>>16)&255U,(raw[5]>>8)&255U,raw[5]&255U);
        for(unsigned k=0;k<REC_CLASS_COUNT;++k)manual_csvf(",%d",(int)manual_objects[n].logits[k]);
        manual_csvf("\r\n");
    }
    manual_csvf("COMPLETE,1\r\n");
    if(manual_csv_error){
        runtime_eventf("CAPTURE_CSV_OVERFLOW,%u,%u\r\n",run_attempt,frame);
        manual_attempt_failed();return;
    }
    Xil_DCacheInvalidateRange((INTPTR)GRAY_FRAME_BASE,GRAY_FRAME_BYTES);
    memcpy(diagnostic_pixels,sl_phys_ptr(GRAY_FRAME_BASE,GRAY_FRAME_BYTES),GRAY_FRAME_BYTES);
    diagnostic_busy=1;diagnostic_open=0;diagnostic_row=0;
    diagnostic_attempt=run_attempt;diagnostic_frame_id=frame;manual_active=0;
    runtime_eventf("CAPTURE_SNAPSHOT,%u,%u,%u\r\n",run_attempt,frame,objects);
    manual_update_led(0);
}

static void diagnostic_failed(unsigned result) {
    if(diagnostic_open)(void)f_close(&diagnostic_file);
    diagnostic_open=0;diagnostic_busy=0;diagnostic_disabled=1;manual_active=0;
    runtime_eventf("CAPTURE_WRITE_FAILED,%u,%u,%u,pending_cancelled,%u\r\n",diagnostic_attempt,diagnostic_frame_id,result,manual_count);
    manual_count=0;
    xil_printf("CAPTURE_WRITE_FAILED=%u; check SD card and restart.\r\n",result);
    runtime_log_sync();manual_update_led(0);
}

 
static FRESULT manual_open_next(void) {
    FILINFO info;
    for(;diagnostic_index<=99999U;++diagnostic_index){
        snprintf(diagnostic_bmp_name,sizeof(diagnostic_bmp_name),"0:/PHOTOS/CAM%05u.BMP",diagnostic_index);
        snprintf(diagnostic_csv_name,sizeof(diagnostic_csv_name),"0:/PHOTOS/CAM%05u.CSV",diagnostic_index);
        FRESULT a=f_stat(diagnostic_bmp_name,&info),b=f_stat(diagnostic_csv_name,&info);
        if(a!=FR_OK && a!=FR_NO_FILE)return a;
        if(b!=FR_OK && b!=FR_NO_FILE)return b;
        if(a==FR_OK || b==FR_OK)continue;
        FRESULT result=f_open(&diagnostic_file,diagnostic_bmp_name,FA_WRITE|FA_CREATE_NEW);
        if(result==FR_EXIST)continue;
        if(result==FR_OK)diagnostic_open=1;
        return result;
    }
    return FR_DENIED;
}

static void diagnostic_service(void) {
    if(!diagnostic_busy)return;
    UINT written=0;FRESULT result;
    manual_poll_button();
    if(!diagnostic_open){
        result=manual_open_next();
        if(result!=FR_OK){diagnostic_failed(result);return;}
        result=f_write(&diagnostic_file,diagnostic_header,sizeof(diagnostic_header),&written);
        if(result!=FR_OK || written!=sizeof(diagnostic_header)){diagnostic_failed(result==FR_OK?100U:(unsigned)result);return;}
    }
    unsigned rows=960U-diagnostic_row;if(rows>128U)rows=128U;
    unsigned bytes=rows*1280U;
    result=f_write(&diagnostic_file,diagnostic_pixels+diagnostic_row*1280U,bytes,&written);
    if(result!=FR_OK || written!=bytes){diagnostic_failed(result==FR_OK?101U:(unsigned)result);return;}
    diagnostic_row+=rows;manual_poll_button();
    if(diagnostic_row==960U){
        result=f_close(&diagnostic_file);diagnostic_open=0;
        if(result!=FR_OK){diagnostic_failed(result);return;}
        result=f_open(&diagnostic_file,diagnostic_csv_name,FA_WRITE|FA_CREATE_NEW);
        if(result!=FR_OK){diagnostic_failed(result);return;}
        diagnostic_open=1;
        result=f_write(&diagnostic_file,manual_csv,manual_csv_used,&written);
        if(result!=FR_OK || written!=manual_csv_used){diagnostic_failed(result==FR_OK?102U:(unsigned)result);return;}
        result=f_close(&diagnostic_file);diagnostic_open=0;
        if(result!=FR_OK){diagnostic_failed(result);return;}
        diagnostic_busy=0;
        runtime_eventf("CAPTURE_SAVED,%u,%u,%s,%s\r\n",diagnostic_attempt,diagnostic_frame_id,diagnostic_bmp_name,diagnostic_csv_name);
        runtime_log_sync();
        xil_printf("CAPTURE_SAVED: %s + %s frame=%u\r\n",diagnostic_bmp_name,diagnostic_csv_name,diagnostic_frame_id);
        ++diagnostic_index;
        if(!runtime_log_ready)diagnostic_disabled=1;
        manual_update_led(0);
    }
}

static void recognition_diagnostics(unsigned state) {
    unsigned frame=rec_read(0x10),xy=rec_read(0x64);
    runtime_logf("ATTEMPT_FRAME,%u,%u,%u\r\n",run_attempt,frame,state);
    runtime_logf("PHASE,%u,%u,%u,%u,%u,%u,%u,%u,%u\r\n",run_attempt,frame,
        rec_read(0x40),rec_read(0x44),rec_read(0x48),rec_read(0x4c),rec_read(0x50),rec_read(0x54),rec_read(0x58));
    runtime_logf("CCL,%u,%u,%u,%u,%u,%u,%u,%u\r\n",run_attempt,frame,
        rec_read(0x5c),rec_read(0x60),xy&2047U,(xy>>16)&2047U,rec_read(0x68),state);
}
#endif
