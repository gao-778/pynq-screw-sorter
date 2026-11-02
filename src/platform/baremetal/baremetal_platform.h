#ifndef SCREWLAB_PORT_PLATFORM_H
#define SCREWLAB_PORT_PLATFORM_H
#include <stdint.h>
#include <stddef.h>
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xiltimer.h"
#include "sleep.h"
#include "ff.h"
extern uint32_t sl_gray_address,sl_screen_address;
extern int sl_motion_enabled,sl_stop_requested,sl_initialized,sl_mmio_fault;
uint64_t sl_now_us(void);
void *sl_phys_ptr(uint32_t address,size_t bytes);
int sl_baremetal_prepare(void);
int sl_baremetal_drain(void);
#endif
