/* Linux MMIO, owned-buffer translation, timing, and filesystem adapters. */
#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#include <io.h>
#define mkdir_one(p) _mkdir(p)
#define sync_file(f) _commit(_fileno(f))
#define open_fd _open
#define fdopen_file _fdopen
#else
#include <unistd.h>
#define mkdir_one(p) mkdir(p,0775)
#define sync_file(f) fsync(fileno(f))
#define open_fd open
#define fdopen_file fdopen
#endif
#ifndef O_BINARY
#define O_BINARY 0
#endif
#include "port_platform.h"
uint32_t sl_gray_address,sl_screen_address;
int sl_motion_enabled,sl_stop_requested,sl_initialized,sl_mmio_fault;
struct region {uint32_t address,bytes;uintptr_t pointer;};
static struct region registers[16],buffers[3];static unsigned register_count;
static char output_root[768]=".";
static void (*cache_callback)(uint32_t,unsigned);
uint64_t sl_now_us(void){
#ifdef _WIN32
 LARGE_INTEGER f,t;QueryPerformanceFrequency(&f);QueryPerformanceCounter(&t);
 return (uint64_t)(t.QuadPart/f.QuadPart)*1000000+(uint64_t)(t.QuadPart%f.QuadPart)*1000000/(uint64_t)f.QuadPart;
#else
 struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint64_t)t.tv_sec*1000000+(uint64_t)t.tv_nsec/1000;
#endif
}
void sl_usleep(unsigned usec){
 if(usec<=100){uint64_t until=sl_now_us()+usec;while(sl_now_us()<until){};return;}
#ifdef _WIN32
 Sleep((usec+999)/1000);
#else
 struct timespec t={usec/1000000,(long)(usec%1000000)*1000};while(nanosleep(&t,&t)&&errno==EINTR){}
#endif
}
int sl_map_register(uint32_t address,uintptr_t pointer,uint32_t bytes){
 if(!pointer || !bytes || (address&3) || (pointer&3) || (bytes&3) || register_count>=16 || sl_initialized)return -1;
 for(unsigned i=0;i<register_count;++i)if((uint64_t)address< (uint64_t)registers[i].address+registers[i].bytes && (uint64_t)registers[i].address<(uint64_t)address+bytes)return -2;
 registers[register_count++]=(struct region){address,bytes,pointer};return 0;
}
int sl_bind_buffer(unsigned kind,uint32_t address,uintptr_t pointer,uint32_t bytes){
 const uint32_t minimum[3]={0x400000,0xc0000,1280*720*4};
 if(kind>=3 || !pointer || (address&63) || !address || bytes<minimum[kind] || sl_initialized || (uint64_t)address+bytes>0x20000000ULL)return -1;
 buffers[kind]=(struct region){address,bytes,pointer};
 if(kind==0)sl_gray_address=address;else if(kind==2)sl_screen_address=address;return 0;
}
void *sl_phys_ptr(uint32_t address,size_t bytes){
 for(unsigned i=0;i<3;++i)if(address>=buffers[i].address && (uint64_t)address+bytes<=(uint64_t)buffers[i].address+buffers[i].bytes && buffers[i].pointer)
  return (void *)(buffers[i].pointer+(address-buffers[i].address));
 sl_mmio_fault=1;return NULL;
}
static volatile uint32_t *reg_ptr(uintptr_t address){
 if(address&3){sl_mmio_fault=1;return NULL;}
 for(unsigned i=0;i<register_count;++i)if(address>=registers[i].address && address+4<=(uintptr_t)registers[i].address+registers[i].bytes)
  return (volatile uint32_t *)(registers[i].pointer+address-registers[i].address);
 sl_mmio_fault=1;return NULL;
}
uint32_t Xil_In32(uintptr_t address){volatile uint32_t *p=reg_ptr(address);__sync_synchronize();return p?*p:0;}
void Xil_Out32(uintptr_t address,uint32_t value){volatile uint32_t *p=reg_ptr(address);if(p)*p=value;__sync_synchronize();}
void sl_set_cache_callback(void (*callback)(uint32_t,unsigned)){cache_callback=callback;}
void Xil_DCacheInvalidateRange(intptr_t address,unsigned bytes){if(cache_callback)cache_callback((uint32_t)address,bytes);__sync_synchronize();}
void Xil_DCacheFlush(void){__sync_synchronize();}
int sl_set_output_dir(const char *path){if(!path || strlen(path)>=sizeof(output_root) || sl_initialized)return -1;strcpy(output_root,path);return 0;}
static int path_for(char *dst,size_t size,const char *src){
 if(strncmp(src,"0:/",3) || strstr(src,"..") || strchr(src+3,':') || strchr(src+3,'\\'))return -1;
 int n=snprintf(dst,size,"%s/%s",output_root,src+3);return n>=0&&(size_t)n<size?0:-1;
}
FRESULT f_mount(FATFS *fs,const char *path,int immediate){(void)fs;(void)path;(void)immediate;return FR_OK;}
FRESULT f_open(FIL *f,const char *path,unsigned mode){
 char p[1024];if(path_for(p,sizeof(p),path))return FR_DENIED;
 int flags=(mode&FA_WRITE)?O_RDWR:O_RDONLY;
 if(mode&FA_CREATE_NEW)flags|=O_CREAT|O_EXCL;else if(mode&FA_OPEN_ALWAYS)flags|=O_CREAT;
 int fd=open_fd(p,flags|O_BINARY,0664);if(fd<0)return errno==EEXIST?FR_EXIST:(errno==ENOENT?FR_NO_FILE:FR_DISK_ERR);
 f->file=fdopen_file(fd,(mode&FA_WRITE)?"r+b":"rb");return f->file?FR_OK:FR_DISK_ERR;
}
FRESULT f_close(FIL *f){if(!f->file)return FR_DISK_ERR;int r=fclose(f->file);f->file=NULL;return r?FR_DISK_ERR:FR_OK;}
FRESULT f_sync(FIL *f){return !f->file || fflush(f->file) || sync_file(f->file)?FR_DISK_ERR:FR_OK;}
FRESULT f_write(FIL *f,const void *src,UINT bytes,UINT *written){*written=(UINT)fwrite(src,1,bytes,f->file);return *written==bytes?FR_OK:FR_DISK_ERR;}
FRESULT f_read(FIL *f,void *dst,UINT bytes,UINT *read){*read=(UINT)fread(dst,1,bytes,f->file);return ferror(f->file)?FR_DISK_ERR:FR_OK;}
FRESULT f_lseek(FIL *f,FSIZE_t offset){return fseek(f->file,(long)offset,SEEK_SET)?FR_DISK_ERR:FR_OK;}
FSIZE_t f_size(FIL *f){long pos=ftell(f->file);fseek(f->file,0,SEEK_END);long size=ftell(f->file);fseek(f->file,pos,SEEK_SET);return (FSIZE_t)size;}
FRESULT f_stat(const char *path,FILINFO *info){char p[1024];struct stat s;if(path_for(p,sizeof(p),path))return FR_DENIED;if(stat(p,&s))return errno==ENOENT?FR_NO_FILE:FR_DISK_ERR;info->fattrib=(s.st_mode&S_IFDIR)?AM_DIR:0;return FR_OK;}
FRESULT f_mkdir(const char *path){char p[1024];if(path_for(p,sizeof(p),path))return FR_DENIED;return mkdir_one(p)==0?FR_OK:(errno==EEXIST?FR_EXIST:FR_DISK_ERR);}
FRESULT f_rename(const char *old,const char *newname){char a[1024],b[1024];if(path_for(a,sizeof(a),old)||path_for(b,sizeof(b),newname))return FR_DENIED;return rename(a,b)?FR_DISK_ERR:FR_OK;}
