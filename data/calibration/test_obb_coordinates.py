"""Project source and interface utilities."""
from pathlib import Path
import hashlib,json,math,subprocess,os,shutil
import numpy as np

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
SRC=HERE.parents[1]/'src/common'
OUT=HERE/'obb_coordinate_test'
OUT.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(SRC/'platform_calibration.h')==sha(HERE/'platform_calibration.h')
h=np.array(json.loads((HERE/'calibration.json').read_text())['H_raw_px_to_mm'])
def project(p):
    q=h@np.array([p[0],p[1],1.])
    return q[:2]/q[2]
cos=[256,251,237,212,181,143,98,50,0,-50,-98,-143,-181,-212,-237,-251]
sin=[0,50,98,143,181,212,237,251,256,251,237,212,181,143,98,50]
rows=[]
for angle in range(16):
    c,s=cos[angle]/256,sin[angle]/256
    for vertical in (0,1):
        u0,u1,v0,v1=(-23,38,-10,5) if not vertical else (-10,5,-23,38)
        u,v=(u0+u1)/2,(v0+v1)/2
        center=np.array([626+c*u-s*v,459+s*u+c*v])
        mm=project(center)
        ideal_angle=angle*math.pi/16+vertical*math.pi/2
        ideal_direction=np.array([math.cos(ideal_angle),math.sin(ideal_angle)])
        direction=project(center+ideal_direction*10)-project(center-ideal_direction*10)
        direction/=np.linalg.norm(direction)
        rows.append('{'+','.join(map(str,[angle,u0,v0,u1,v1,*mm,*direction]))+'}')
harness=r'''
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <assert.h>
static unsigned rec_read(unsigned address){(void)address;return 0;}
static unsigned Xil_In32(unsigned address){(void)address;return 0;}
static unsigned runtime_ms(void){return 0;}
#include "platform_coordinates.h"
static const double cases[][9]={@ROWS@};
static unsigned bounds(int bound,unsigned pixel){return ((unsigned)(unsigned short)bound<<16)|pixel;}
int main(void){
    for(unsigned n=0;n<32;++n){
        const double *c=cases[n];
        unsigned words[6]={bounds((int)c[1],600),bounds((int)c[2],420),
                           bounds((int)c[3],652),bounds((int)c[4],498),0,((unsigned)c[0]<<8)|4};
        PlatformPosition p=coordinate_from_words(words);
        assert(p.valid && p.axis_valid && p.class_id==4);
        assert(fabs(p.x_tenth_mm/10.0-c[5])<=.05000001);
        assert(fabs(p.y_tenth_mm/10.0-c[6])<=.05000001);
        assert(fabs(hypot(p.axis_x,p.axis_y)-1)<1e-10);
        assert(p.axis_x*c[7]+p.axis_y*c[8]>.99998);
    }
    puts("OBB_COORDINATES_PASS cases=32 angles=16 orientations=2 asymmetric_local_center=1 axis_sign_and_units=1");
    return 0;
}
'''.replace('@ROWS@',',\n'.join(rows))
(OUT/'test_obb_coordinates.c').write_text(harness,encoding='utf-8')
command=[os.environ.get('CC') or shutil.which('gcc') or 'gcc','-std=c11','-O2','-I'+str(SRC),str(OUT/'test_obb_coordinates.c'),'-lm','-o',str(OUT/'test_obb_coordinates.exe')]
compiled=subprocess.run(command,capture_output=True,text=True)
(OUT/'compile.log').write_text(compiled.stdout+compiled.stderr,encoding='utf-8')
assert compiled.returncode==0,compiled.stderr
run=subprocess.run([str(OUT/'test_obb_coordinates.exe')],capture_output=True,text=True)
(OUT/'execution.log').write_text(run.stdout+run.stderr,encoding='utf-8')
assert run.returncode==0,run.stderr
report={'status':'PASS','hardware_access':False,'cases':32,'angles':16,
        'source_sha256':{n:sha(SRC/n) for n in ['platform_calibration.h','platform_coordinates.h','workstation_config.h']},
        'test_sha256':sha(Path(__file__)),'stdout':run.stdout,
        'limits':['Checks software coordinates and direction arithmetic; not mechanical gripper accuracy.']}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(run.stdout.strip())
