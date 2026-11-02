/* Standalone memory binding and shared-device lifecycle. */
#include "port_platform.h"
#include "fusion_clock.h"
#include <string.h>

uint32_t sl_gray_address=0x10000000U,sl_screen_address=0x11400000U;
int sl_motion_enabled=1,sl_stop_requested,sl_initialized,sl_mmio_fault;
static const uint32_t preview_address=0x11000000U;

uint64_t sl_now_us(void){XTime now;XTime_GetTime(&now);return fusion_ticks_us(now);}

void *sl_phys_ptr(uint32_t address,size_t bytes){
    const uint32_t bases[3]={sl_gray_address,preview_address,sl_screen_address};
    const uint32_t sizes[3]={0x400000U,0xc0000U,1280U*720U*4U};
    for(unsigned k=0;k<3;++k)
        if(address>=bases[k] && (uint64_t)address+bytes<=(uint64_t)bases[k]+sizes[k])
            return (void *)(uintptr_t)address;
    sl_mmio_fault=1;return NULL;
}

int sl_baremetal_prepare(void){
    const uintptr_t rec=0x42000000U;
    if(Xil_In32(rec+0x9c)!=0x50594d32U || Xil_In32(rec+0x38)!=0x4d433138U)return -1;
    memset((void *)(uintptr_t)sl_gray_address,0,0x400000U);
    memset((void *)(uintptr_t)preview_address,0,0xc0000U);
    memset((void *)(uintptr_t)sl_screen_address,0,1280U*720U*4U);
    Xil_DCacheFlush();
    Xil_Out32(rec+0x94,sl_gray_address);
    Xil_Out32(rec+0x98,preview_address);
    Xil_Out32(rec+0xa0,1U);
    Xil_Out32(rec+0xa4,1U);
    return Xil_In32(rec+0xa0)==1U?0:-2;
}

int sl_baremetal_drain(void){
    uint64_t deadline=sl_now_us()+UINT64_C(2000000);
    while(sl_now_us()<deadline){
        unsigned idle=Xil_In32(0x420000a8U);
        unsigned gray=Xil_In32(0x40400034U),screen=Xil_In32(0x40410034U);
        if((idle&3U)==3U && (gray&1U) && (screen&1U))return 0;
    }
    return -1;
}
