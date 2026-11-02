"""Run shared production states for Linux and standalone configurations."""

from pathlib import Path
import argparse,hashlib,json,os,subprocess

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--cc',default=os.environ.get('CC','gcc'));p.add_argument('--target',choices=['linux','baremetal'],default='linux');args=p.parse_args()
fixture=json.loads((ROOT/'sim/tests/fixtures/mint_ui_regression.json').read_text(encoding='utf-8'))
out=ROOT/'sim/output'/('state_machine_'+args.target);out.mkdir(parents=True,exist_ok=True)
prefix=fixture['prefix'].replace(fixture['source_main'],(ROOT/'src/common/app.c').as_posix())
prefix=prefix.replace('#include <windows.h>','')

bridge='''
#define SCREWLAB_PORT_PLATFORM_H
static uint32_t sl_gray_address=0x10000000,sl_screen_address=0x12000000;
static int sl_motion_enabled=1,sl_stop_requested,sl_initialized,sl_mmio_fault;
static uint64_t sl_now_us(void){return now_us;}
static void *sl_phys_ptr(uint32_t a,size_t n){(void)n;return (void *)(uintptr_t)a;}
'''
prefix=prefix.replace('#define JOYSTICK_HOST_TEST 1',bridge+'\n#define JOYSTICK_HOST_TEST 1')
extra=r'''
 reset_case(2);sl_initialized=1;sl_motion_enabled=1;
 capture_active=inference_active=1;test_arm_busy=1;recognition_motion_sync();
 assert(recognition_motion_paused() && !capture_active && !inference_active);
 assert(!coordinate_valid && !fusion_ready && hide_writes && abort_writes && empty_writes);
 unsigned captures=capture_requests,starts=infer_starts;
 for(unsigned n=0;n<30;++n){now_us+=10000U;sl_service();}
 assert(capture_requests==captures && infer_starts==starts);
 assert(recognition_motion_paused() && !capture_active && !inference_active);
 unsigned words[24];assert(!sl_state(words,24) && words[2] && words[3]);
 check_done("migrated_sl_service_never_captures_or_infers_during_motion");

 test_arm_busy=0;test_arm_state="COMPLETED";recognition_motion_sync();
 assert(!recognition_motion_paused() && recognition_resume_waiting() && !fusion_ready);
 assert(recognition_pipeline_ready()==0); 
 ++ui_regs[1];ui_regs[2]=128U;assert(recognition_pipeline_ready()==1);
 publish_auto(1);coordinate_visible_source_ms=recognition_resume_ms;
 recognition_scene_published();assert(recognition_resume_waiting() && !fusion_ready);
 now_us+=300000U;publish_auto(1);recognition_scene_published();
 assert(!recognition_resume_waiting() && fusion_ready);
 check_done("only_coherent_new_capture_strictly_after_motion_releases_resume_gate");

 reset_case(2);sl_initialized=1;sl_motion_enabled=1;
 assert(sl_sort_all(0)==0);assert(auto_mode==AUTO_PICK_SORT_ALL);
 assert(sl_sort_all(0)==-2); 
 confirm_auto(2);assert(test_arm_busy && test_place_start==1 && auto_state==AUTO_PICK_MOVING);
 recognition_motion_sync();assert(recognition_motion_paused());
 finish_auto();assert(auto_state==AUTO_PICK_WAIT_REMOVAL);
 put_auto(0,2,200,-200,200,270);fresh_auto(1);auto_pick_service();
 for(unsigned n=0;n<10 && !test_arm_busy;++n){fresh_auto(1);auto_pick_service();}
 assert(test_arm_busy && test_place_start==2 && auto_state==AUTO_PICK_MOVING);
 assert(sl_state(words,24)==0 && words[9] && words[12]==1 && words[13]==1);
 check_done("python_native_sort_all_api_picks_second_object_after_new_scene_and_removal");

 reset_case(1);sl_initialized=1;sl_motion_enabled=1;
 test_arm_busy=1;recognition_motion_sync();
 assert(recognition_motion_paused());
 test_arm_busy=0;test_arm_state="ERROR";
 captures=capture_requests;starts=infer_starts;
 for(unsigned n=0;n<30;++n){now_us+=10000U;sl_service();}
 assert(recognition_motion_paused() && !recognition_resume_waiting());
 assert(!capture_active && !inference_active && !coordinate_valid && !fusion_ready);
 assert(capture_requests==captures && infer_starts==starts);
 assert(!sl_state(words,24) && !words[2] && words[3] && !words[4]);
 check_done("bus_failure_terminal_keeps_capture_inference_and_targets_paused");
 test_arm_state="CANCELLED";recognition_motion_sync();
 assert(!recognition_motion_paused() && recognition_resume_waiting());
 check_done("completed_explicit_stop_still_requires_a_new_scene_before_resume");

 reset_case(1);sl_motion_enabled=0;
 assert(sl_pick()==-1 && sl_sort_all(0)==-1 && sl_auto(0,0)==-1);
 sl_motion_enabled=1;assert(sl_auto(15,0)==-1 && sl_auto(17,0)==-1);
 assert(sl_state(words,23)==-1);
 check_done("native_api_rejects_disabled_motion_and_nut_picks");
'''
body=fixture['body'].replace(' printf("UI_SORT_FIX_PASS',extra+'\n printf("UI_SORT_FIX_PASS')
for name in ('ff.h','xil_io.h','xil_cache.h','xil_printf.h','sleep.h','xiltimer.h'):
    (out/name).write_text('#include "bsp.h"\n',encoding='ascii')
(out/'bsp.h').write_text(fixture['stub'],encoding='utf-8')
for name in ('xtimer_config.h','xparameters.h'):
    (out/name).write_bytes((ROOT/'sim/tests/fixtures'/name).read_bytes())
harness=out/'test_migrated.c'
harness.write_text(prefix+fixture['helpers'].replace('@@FIXTURE@@',out.as_posix())+body,encoding='utf-8')
command=[args.cc,'-std=c11','-O1','-Wall','-Wextra','-Wno-unused-function','-Wno-unused-variable',
         '-I',str(out),'-DSCREWSORT_'+args.target.upper()+'=1','-I',str(ROOT/'src/platform'),'-I',str(ROOT/('src/platform/'+args.target)),str(harness),'-lm','-o',str(out/'test_migrated.exe')]
report={'status':'RUNNING','hardware_access':False,'model_values_mocked':True,
        'production_entry':'src/common/app.c','compiler_command':command}
try:
    r=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace')
    (out/'compile.log').write_text(r.stdout+r.stderr,encoding='utf-8');r.check_returncode()
    r=subprocess.run([str(out/'test_migrated.exe')],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
    log=r.stdout+r.stderr;(out/'result.log').write_text(log,encoding='utf-8');print(log);r.check_returncode()
    assert 'UI_SORT_FIX_PASS' in log
    report.update(status='PASS',checks=[s for s in log.splitlines() if s.startswith('AUTO_CHECK_PASS')],
                  harness_sha256=hashlib.sha256(harness.read_bytes()).hexdigest())
except Exception as exc:
    report.update(status='FAIL',error=str(exc));raise
finally:(out/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
