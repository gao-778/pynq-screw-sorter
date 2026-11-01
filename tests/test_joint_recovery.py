"""Actual bus + motion + IK with the historical register-level servo model."""
from pathlib import Path
import argparse,hashlib,json,subprocess,os,shutil
ROOT=Path(__file__).resolve().parents[1]
NEW=ROOT/'software'
PRIOR=ROOT/'tests/fixtures/test_arm_integration_baseline.c'
OUT=ROOT/'build/tests/joint_recovery'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
INJECT=r'''
typedef struct {const char *phase;unsigned id,remaining,kind;} FaultEpisode;
static FaultEpisode injected[2];
static unsigned injection_count,injection_index,injection_hits;
static void inject_fault(DeviceModel *m,unsigned id){
 if(injection_index<injection_count){
  FaultEpisode *f=&injected[injection_index];
  if(id==f->id && !strcmp(arm_motion_phase_name(),f->phase)){
   ++injection_hits;
   if(f->kind==1U)m->reply_size=7U;
   else if(f->kind==2U)m->pending_query_error=0x08U;
   else m->reply_size=0U;
   if(--f->remaining==0U)++injection_index;
  }
 }
}
'''
BODY=r'''
static MoveRecord good_moves[MOVE_CAPACITY];
static unsigned good_count;
static void case_reset(void){reset();memset(injected,0,sizeof(injected));injection_count=injection_index=injection_hits=0;}
static void fault(unsigned n,const char *phase,unsigned id,unsigned count,unsigned kind){
 assert(n<2U);injected[n]=(FaultEpisode){phase,id,count,kind};if(n>=injection_count)injection_count=n+1U;
}
static void start_case(void){
 visual_target=(VisualPickTarget){-17.3,143.436,0.6,0.8,0,1,1000};
 assert(!arm_motion_start_visual_place(&visual_target,1U,device.now));
}
static void compare_moves(void){
 assert(device.moves==good_count && !device.stops && !strcmp(arm_motion_state_name(),"COMPLETED"));
 for(unsigned i=0;i<good_count;++i){
  assert(device.move[i].id==good_moves[i].id);
  assert(device.move[i].position==good_moves[i].position);
  assert(device.move[i].duration==good_moves[i].duration);
 }
}
static void log_case(const char *name){
 printf("JOINT_CHECK name=%s state=%s moves=%u queries=%u stops=%u inject_hits=%u retries=%u\n",name,
  arm_motion_state_name(),device.moves,device.queries,device.stops,injection_hits,arm_motion_query_retries());++tests;
}
int main(int argc,char **argv){
 (void)argv;unsigned fixed=argc>1;ArmReadRecovery recovery;
 setbuf(stdout,NULL);
 case_reset();start_case();finish();assert(!strcmp(arm_motion_state_name(),"COMPLETED") && !device.stops);
 good_count=device.moves;memcpy(good_moves,device.move,good_count*sizeof(MoveRecord));
 FILE *trace=fopen("baseline_move_trace.csv","w");assert(trace);
 fprintf(trace,"id,raw,duration_ms\n");for(unsigned i=0;i<good_count;++i)
  fprintf(trace,"%u,%u,%u\n",good_moves[i].id,good_moves[i].position,good_moves[i].duration);
 fclose(trace);log_case("no_fault_reference");

 for(unsigned id=5U;id<=6U;++id){
  case_reset();fault(0,"initial_home",id,3,0);start_case();finish();assert(injection_hits==3U);
  if(fixed){compare_moves();assert(arm_motion_get_read_recovery(&recovery) && recovery.succeeded);}
  else assert(!strcmp(arm_motion_state_name(),"ERROR") && !device.moves && !device.stops);
  log_case(id==5?"initial_S5_three_no_reply":"initial_S6_three_no_reply");
 }
 case_reset();fault(0,"place_approach_above",5U,3,0);fault(1,"place_leave_vertical",6U,3,0);
 start_case();finish();assert(injection_hits==6U && injection_index==2U);
 if(fixed){
  compare_moves();assert(arm_motion_get_read_recovery(&recovery) && recovery.succeeded);
#ifdef ARM_READ_RECOVERY_MAX_PER_REQUEST
  assert(recovery.attempts_total==2U && recovery.successes_total==2U);
#endif
 }else assert(!strcmp(arm_motion_state_name(),"ERROR") && device.moves<good_count && device.stops==6U && device.stop_mask==0x7eU);
 log_case("BIN_APPROACH_S5_then_BIN_DEPART_S6_two_episodes");

 for(unsigned id=1U;id<=2U;++id){
  case_reset();fault(0,id==1U?"place_release":"align_gripper_above",id,3,0);start_case();finish();
  assert(injection_hits==3U);
  if(fixed){compare_moves();assert(arm_motion_get_read_recovery(&recovery) && recovery.succeeded);}
  else assert(!strcmp(arm_motion_state_name(),"ERROR") && device.stops==6U);
  log_case(id==1U?"gripper_S1_read_only_recovery":"wrist_S2_read_only_recovery");
 }

 case_reset();fault(0,"initial_home",5U,1000,0);start_case();finish();
 assert(!strcmp(arm_motion_state_name(),"ERROR") && !device.moves && !device.stops);
 assert(device.now<4000000U);log_case("permanent_initial_no_reply_no_MOVE");
 case_reset();fault(0,"place_leave_vertical",6U,1000,0);start_case();finish();
 assert(!strcmp(arm_motion_state_name(),"ERROR") && device.moves<good_count && device.stops==6U && device.stop_mask==0x7eU);
 for(unsigned i=0;i<device.moves;++i)assert(device.move[i].id==good_moves[i].id &&
  device.move[i].position==good_moves[i].position && device.move[i].duration==good_moves[i].duration);
 log_case("permanent_depart_no_reply_six_STOP_no_replay");

 for(unsigned kind=1;kind<=2;++kind){
  case_reset();fault(0,"place_approach_above",5U,3,kind);start_case();finish();
  assert(injection_hits==3U && !strcmp(arm_motion_state_name(),"ERROR") && device.stops==6U);
  assert(!arm_motion_get_read_recovery(&recovery));
  log_case(kind==1?"partial_reply_strict_fail":"UART_LINE_strict_fail");
 }
 printf("JOINT_RECOVERY_%s_PASS groups=%u hardware_access=false full_MOVE_trace=%u\n",fixed?"FIXED":"BASELINE",tests,good_count);
 return 0;
}
'''

def main():
 p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=NEW);p.add_argument('--expect-fixed',action='store_true',default=True);args=p.parse_args()
 src=args.source.resolve();run=OUT/('fixed' if args.expect_fixed else 'baseline');run.mkdir(parents=True,exist_ok=True)
 source={p.name:sha(p) for p in src.glob('*.[ch]')}
 old=PRIOR.read_text(encoding='utf8');prefix=old[:old.index('static void set_reference_home_duration(')]
 prefix=prefix.replace('static void update_positions(',INJECT+'\nstatic void update_positions(')
 anchor='        m->reply_start=m->tx_end+m->reply_delay_us;'
 assert prefix.count(anchor)==1
 prefix=prefix.replace(anchor,'        inject_fault(m,id);\n'+anchor)
 prefix=prefix.replace('static ArmAction reference[ARM_PLAN_CAPACITY];\nstatic unsigned reference_count;\n','')
 (run/'xiltimer.h').write_text('#include <stdint.h>\n#define COUNTS_PER_SECOND 325000000U\n',encoding='utf8')
 harness=run/'joint_recovery.c';harness.write_text(prefix+BODY,encoding='utf8')
 command=[(os.environ.get('CC') or shutil.which('gcc') or 'gcc'),'-std=c11','-O1','-Wall','-Wextra','-Werror','-I',str(src),'-I',str(run),str(harness),str(src/'arm_bus.c'),str(src/'arm_motion.c'),str(src/'arm_kinematics.c'),'-lm','-o',str(run/'joint_recovery.exe')]
 report={'status':'RUNNING','source':str(src),'source_sha256':source,'expect_fixed':args.expect_fixed,
  'real_production_bus_motion_ik':True,'hardware_access':False,'prior_device_model_sha256':sha(PRIOR),
  'script_sha256':sha(Path(__file__)),'harness_sha256':sha(harness),
  'mock_boundaries':'MMIO UART/GPIO/servo reply and feedback physics; production state machines, protocol parser and IK compiled unchanged.'}
 try:
  build=subprocess.run(command,capture_output=True,text=True,encoding='utf8',errors='replace');(run/'compile.log').write_text(build.stdout+build.stderr,encoding='utf8');build.check_returncode()
  result=subprocess.run([str(run/'joint_recovery.exe')]+(['fixed'] if args.expect_fixed else []),cwd=run,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=60)
  (run/'result.log').write_text(result.stdout+result.stderr,encoding='utf8');print(result.stdout+result.stderr);result.check_returncode()
  assert source=={n:sha(src/n) for n in source}
  report.update(status='PASS',stdout=result.stdout,compiler_command=command,baseline_move_trace_sha256=sha(run/'baseline_move_trace.csv'))
 except Exception as error:
  report.update(status='FAIL',error=str(error));raise
 finally:(run/'report.json').write_text(json.dumps(report,indent=2),encoding='utf8')

if __name__=='__main__':main()
