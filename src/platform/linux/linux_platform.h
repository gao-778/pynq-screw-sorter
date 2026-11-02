#ifndef SCREWLAB_PORT_PLATFORM_H
#define SCREWLAB_PORT_PLATFORM_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
typedef uint8_t u8;typedef uint16_t u16;typedef uint32_t u32;typedef int32_t s32;
typedef uintptr_t UINTPTR;typedef intptr_t INTPTR;typedef uint64_t XTime;
#define COUNTS_PER_SECOND UINT64_C(1000000)
extern uint32_t sl_gray_address,sl_screen_address;
extern int sl_motion_enabled,sl_stop_requested,sl_initialized,sl_mmio_fault;
uint64_t sl_now_us(void);
void sl_usleep(unsigned usec);
void *sl_phys_ptr(uint32_t address,size_t bytes);
uint32_t Xil_In32(uintptr_t address);
void Xil_Out32(uintptr_t address,uint32_t value);
void Xil_DCacheInvalidateRange(intptr_t address,unsigned bytes);
void Xil_DCacheFlush(void);
static inline void XTime_GetTime(XTime *t){*t=sl_now_us();}
#define xil_printf printf
#define usleep sl_usleep
typedef unsigned UINT;typedef unsigned long FSIZE_t;typedef int FRESULT;
typedef struct {FILE *file;} FIL;
typedef struct {int unused;} FATFS;
typedef struct {unsigned fattrib;} FILINFO;
enum {FR_OK=0,FR_DISK_ERR=1,FR_NO_FILE=4,FR_DENIED=7,FR_EXIST=8};
enum {FA_READ=1,FA_WRITE=2,FA_CREATE_NEW=4,FA_OPEN_ALWAYS=16,AM_DIR=16};
FRESULT f_mount(FATFS *fs,const char *path,int immediate);
FRESULT f_open(FIL *f,const char *path,unsigned mode);
FRESULT f_close(FIL *f);FRESULT f_sync(FIL *f);
FRESULT f_write(FIL *f,const void *src,UINT bytes,UINT *written);
FRESULT f_read(FIL *f,void *dst,UINT bytes,UINT *read);
FRESULT f_lseek(FIL *f,FSIZE_t offset);FSIZE_t f_size(FIL *f);
FRESULT f_stat(const char *path,FILINFO *info);
FRESULT f_mkdir(const char *path);FRESULT f_rename(const char *old,const char *newname);
int sl_map_register(uint32_t address,uintptr_t pointer,uint32_t bytes);
int sl_bind_buffer(unsigned kind,uint32_t address,uintptr_t pointer,uint32_t bytes);
int sl_set_output_dir(const char *path);
void sl_set_cache_callback(void (*callback)(uint32_t,unsigned));
#endif
