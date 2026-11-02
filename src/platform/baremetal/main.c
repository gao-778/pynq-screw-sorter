#include "port_platform.h"
#include "screwsort.h"

int main(void){
    if(sl_baremetal_prepare() || sl_initialize())return 1;
    while(!sl_should_stop()){
        sl_service();
        if(!sl_urgent())usleep(500);
    }
    if(sl_shutdown() || sl_baremetal_drain())return 2;
    Xil_DCacheFlush();
    Xil_Out32(0xf8000008U,0xdf0dU);
    Xil_Out32(0xf8000200U,1U);
    for(;;){}
}
