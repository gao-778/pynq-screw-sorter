"""Project source and interface utilities."""
from pathlib import Path
import argparse,json,os,subprocess
ROOT=Path(__file__).resolve().parents[1]
C=r'''
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <assert.h>
#include <stdio.h>
#define SCREWLAB_PORT_PLATFORM_H
#define FUSION_CLOCK_H
typedef uint64_t XTime;
static uint64_t now;
static unsigned abi=0x50594d32U,hardware=0x4d433138U,idle=3,gray=1,screen=1;
static unsigned writes,clear_count;
static uintptr_t addresses[16];static unsigned values[16];
static void XTime_GetTime(XTime *t){*t=now;now+=100;}
static uint64_t fusion_ticks_us(uint64_t t){return t;}
static void Xil_DCacheFlush(void){}
static uint32_t Xil_In32(uintptr_t a){
 if(a==0x4200009cU)return abi;if(a==0x42000038U)return hardware;
 if(a==0x420000a0U)return writes>=3?values[2]:0;
 if(a==0x420000a8U)return idle;if(a==0x40400034U)return gray;if(a==0x40410034U)return screen;
 return 0;
}
static void Xil_Out32(uintptr_t a,uint32_t v){addresses[writes]=a;values[writes++]=v;}
static void *clear_buffer(void *p,int c,size_t n){
 assert(c==0);uintptr_t a=(uintptr_t)p;
 assert((a==0x10000000U && n==0x400000U)||(a==0x11000000U && n==0xc0000U)||(a==0x11400000U && n==1280U*720U*4U));
 ++clear_count;return p;
}
#define memset clear_buffer
#include "@SOURCE@"
int main(void){
 abi=0;assert(sl_baremetal_prepare()<0 && !writes && !clear_count);abi=0x50594d32U;
 assert(!sl_baremetal_prepare() && clear_count==3 && writes==4);
 assert(addresses[0]==0x42000094U && values[0]==0x10000000U);
 assert(addresses[1]==0x42000098U && values[1]==0x11000000U);
 assert(addresses[2]==0x420000a0U && values[2]==1);
 assert(addresses[3]==0x420000a4U && values[3]==1);
 assert(sl_phys_ptr(0x103fffffU,1)==(void *)(uintptr_t)0x103fffffU);
 assert(!sl_phys_ptr(0x103fffffU,2) && sl_mmio_fault);
 assert(!sl_phys_ptr(0x08000000U,64));
 assert(!sl_baremetal_drain());
 idle=0;assert(sl_baremetal_drain()<0);idle=3;gray=0;assert(sl_baremetal_drain()<0);
 puts("BAREMETAL_PLATFORM_PASS abi memory_ranges address_binding_order and_axi_drain");return 0;
}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--cc',default=os.environ.get('CC','gcc'));a=p.parse_args()
 out=ROOT/'sim/output/baremetal_platform';out.mkdir(parents=True,exist_ok=True)
 source=out/'test.c';source.write_text(C.replace('@SOURCE@',(ROOT/'src/platform/baremetal/baremetal_platform.c').as_posix()),encoding='utf-8')
 command=[a.cc,'-std=c11','-O1','-I',str(ROOT/'src/common'),'-I',str(ROOT/'src/platform'),'-I',str(ROOT/'src/platform/linux'),str(source),'-o',str(out/'test.exe')]
 build=subprocess.run(command,capture_output=True,text=True);(out/'compile.log').write_text(build.stdout+build.stderr,encoding='utf-8');build.check_returncode()
 result=subprocess.run([str(out/'test.exe')],capture_output=True,text=True);(out/'result.log').write_text(result.stdout+result.stderr,encoding='utf-8');result.check_returncode()
 (out/'report.json').write_text(json.dumps(dict(status='PASS',hardware_access=False,command=command,stdout=result.stdout),indent=2),encoding='utf-8');print(result.stdout)
if __name__=='__main__':main()
