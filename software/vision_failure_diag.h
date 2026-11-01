#ifndef VISION_FAILURE_DIAG_H
#define VISION_FAILURE_DIAG_H
/* Read-only diagnostic export. Called only after aborting inference/capture,
 * with no arm motion active. At most two attempts per boot, no overwrite. */
static unsigned vision_diag_attempts,vision_diag_index=1;
static void vision_failure_save(unsigned bank,unsigned frame)
{
    if(arm_motion_busy() || shot_state || !runtime_log_ready || vision_diag_attempts>=2)return;
    ++vision_diag_attempts;
    FRESULT result=f_mkdir("0:/DIAG");
    if(result!=FR_OK && result!=FR_EXIST){runtime_eventf("VISION_DIAG_FAIL,DIRECTORY,%u\r\n",result);return;}
    FIL file;FILINFO info;char temporary[48],final[48];unsigned opened=0;
    for(;vision_diag_index<=99999;++vision_diag_index){
        snprintf(temporary,sizeof(temporary),"0:/DIAG/F%05u.TMP",vision_diag_index);
        snprintf(final,sizeof(final),"0:/DIAG/F%05u.BMP",vision_diag_index);
        result=f_stat(final,&info);
        if(result==FR_OK)continue;
        if(result!=FR_NO_FILE)break;
        result=f_open(&file,temporary,FA_WRITE|FA_CREATE_NEW);
        if(result==FR_EXIST)continue;
        if(result==FR_OK)opened=1;
        break;
    }
    if(!opened){runtime_eventf("VISION_DIAG_FAIL,OPEN,%u\r\n",result);return;}
    unsigned index=vision_diag_index++;
    u8 header[1078];memset(header,0,sizeof(header));
    header[0]='B';header[1]='M';put_le32(header+2,1078U+GRAY_FRAME_BYTES);
    put_le32(header+10,1078);put_le32(header+14,40);put_le32(header+18,1280);
    put_le32(header+22,0U-960U);header[26]=1;header[28]=8;
    put_le32(header+34,GRAY_FRAME_BYTES);put_le32(header+46,256);
    for(unsigned k=0;k<256;++k)header[54+4*k]=header[55+4*k]=header[56+4*k]=(u8)k;
    UINT written=0;
    result=f_write(&file,header,sizeof(header),&written);
    unsigned ok=result==FR_OK && written==sizeof(header);
    unsigned address=GRAY_FRAME_BASE+(bank&1U)*0x200000U;
    if(ok){
        Xil_DCacheInvalidateRange((INTPTR)address,GRAY_FRAME_BYTES);
        result=f_write(&file,(const void *)(UINTPTR)address,GRAY_FRAME_BYTES,&written);
        ok=result==FR_OK && written==GRAY_FRAME_BYTES;
    }
    if(ok)ok=f_sync(&file)==FR_OK;
    FRESULT close_result=f_close(&file);if(close_result!=FR_OK)ok=0;
    if(ok)ok=f_rename(temporary,final)==FR_OK;
    runtime_eventf("VISION_DIAG_%s,index,%u,frame,%u,bank,%u,address,%08x,file,%s\r\n",
                   ok?"SAVED":"FAILED",index,frame,bank,address,ok?final:temporary);
}
#endif
