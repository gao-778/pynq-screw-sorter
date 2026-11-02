"""Project source and interface utilities."""
from pathlib import Path
import argparse, hashlib, json, subprocess, os, shutil

ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'sim/output/motion/motion_recovery'
BASE=ROOT/'src/common'
SHA=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

C=r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "@@SOURCE@@/arm_motion.c"

typedef struct { unsigned purpose,phase,id,remaining; } Rule;
static Rule rules[8];static unsigned nrules,rule_index;
static uint64_t mock_now,finish_at;
static unsigned pending,pending_cmd,pending_id,pending_pos,pending_failure;
static unsigned reads,moves,stops,stop_mask,delay_observed;
static unsigned move_id[4096],move_pos[4096],move_duration[4096];
static unsigned gold_id[4096],gold_pos[4096],gold_duration[4096],gold_moves;
static int servo_pos[7],reply_pos;
static unsigned corrupt_bytes,corrupt_lsr,position_fault,arrival_fault,fail_move;
static arm_bus_result_t bus_result=ARM_BUS_NONE;
static ArmBusDiagnostic diagnostic;

int arm_bus_busy(void){return pending;}
arm_bus_result_t arm_bus_result(void){return bus_result;}
arm_bus_error_t arm_bus_error(void){return (arm_bus_error_t)diagnostic.error_code;}
const char *arm_bus_error_name(void){return "RX_TIMEOUT";}
unsigned arm_bus_last_lsr(void){return diagnostic.lsr;}
int arm_bus_position(void){return reply_pos;}
int arm_bus_get_diagnostic(ArmBusDiagnostic *out){if(out)*out=diagnostic;return diagnostic.valid;}
void arm_bus_cancel(void){pending=0;bus_result=ARM_BUS_NONE;}
int arm_bus_start_read(unsigned id,uint64_t now){
 assert(!pending);++reads;pending=pending_cmd=28U;pending_id=id;pending_failure=0;
 if(rule_index<nrules){Rule *r=&rules[rule_index];
  if(r->purpose==(unsigned)read_purpose && r->phase==plan[action_index].phase && r->id==id){
   assert(r->remaining);pending_failure=1;if(!--r->remaining)++rule_index;
  }
 }
 finish_at=now+(pending_failure?100000U:1000U);bus_result=ARM_BUS_BUSY;
 memset(&diagnostic,0,sizeof(diagnostic));diagnostic.valid=1;diagnostic.command=28;diagnostic.servo_id=id;
 return 0;
}
int arm_bus_start_move(unsigned id,unsigned position,unsigned duration,uint64_t now){
 assert(!pending && moves<4096);assert(arm_position_allowed(id,(int)position));
 move_id[moves]=id;move_pos[moves]=position;move_duration[moves]=duration;++moves;
 pending=1;pending_cmd=1;pending_id=id;pending_pos=position;finish_at=now+1000U;bus_result=ARM_BUS_BUSY;return 0;
}
int arm_bus_start_stop(unsigned id,uint64_t now){
 assert(!pending);++stops;stop_mask|=1U<<id;pending=1;pending_cmd=12;pending_id=id;finish_at=now+1000U;bus_result=ARM_BUS_BUSY;return 0;
}
void arm_bus_service(uint64_t now){
 if(!pending || now<finish_at)return;
 pending=0;bus_result=ARM_BUS_OK;
 if(pending_cmd==1){servo_pos[pending_id]=(int)pending_pos;if(fail_move){bus_result=ARM_BUS_ERR;fail_move=0;}return;}
 if(pending_cmd!=28)return;
 if(pending_failure){
  bus_result=ARM_BUS_RX_TIMEOUT;diagnostic.error_code=ARM_BUS_ERROR_RX_TIMEOUT;
  diagnostic.lsr=0x60U|corrupt_lsr;diagnostic.received_bytes=corrupt_bytes;diagnostic.elapsed_us=100000U;return;
 }
 diagnostic.error_code=ARM_BUS_ERROR_NONE;diagnostic.lsr=0x60;diagnostic.received_bytes=8;
 reply_pos=servo_pos[pending_id];
 if(read_recovery.active && position_fault && pending_id==position_fault)reply_pos=1201;
 if(read_recovery.active && arrival_fault && pending_id==arrival_fault)reply_pos+=41;
}
static void reset_test(void){
 const int initial[7]={0,552,499,145,781,689,481};memcpy(servo_pos,initial,sizeof(initial));
 mock_now=1000000U;pending=reads=moves=stops=stop_mask=nrules=rule_index=0;
 corrupt_bytes=corrupt_lsr=position_fault=arrival_fault=fail_move=delay_observed=0;
 bus_result=ARM_BUS_NONE;memset(&diagnostic,0,sizeof(diagnostic));arm_motion_init();
}
static void rule(unsigned purpose,unsigned phase,unsigned id){
 assert(nrules<8);rules[nrules++]=(Rule){purpose,phase,id,3};
}
static void start_test(void){
 VisualPickTarget t={-17.3,143.436,1,0,4,1,1000};
 assert(arm_motion_start_visual_place(&t,1,mock_now)==0);
}
static void tick(void){mock_now+=1000U;arm_motion_service(mock_now);}
static void finish_test(void){
 unsigned budget=600001;
 while(arm_motion_busy() && budget--){
  if(state==MOTION_READ_RECOVERY_WAIT){
   unsigned mr=moves,rr=reads,ss=stops;uint64_t until=deadline_us;
   assert(until>=mock_now);mock_now=until-1;arm_motion_service(mock_now);
   assert(moves==mr && reads==rr && stops==ss && state==MOTION_READ_RECOVERY_WAIT);
   ++mock_now;arm_motion_service(mock_now);assert(moves==mr && reads==rr && stops==ss);
   ++delay_observed;
  }else tick();
 }
 assert(budget && !arm_motion_busy());
}
static void save_gold(void){
 reset_test();start_test();finish_test();assert(!strcmp(arm_motion_state_name(),"COMPLETED"));
 assert(moves && !stops);gold_moves=moves;
 memcpy(gold_id,move_id,moves*sizeof(unsigned));memcpy(gold_pos,move_pos,moves*sizeof(unsigned));memcpy(gold_duration,move_duration,moves*sizeof(unsigned));
}
static void exact_moves(void){
 assert(moves==gold_moves && !stops);
 assert(!memcmp(move_id,gold_id,moves*sizeof(unsigned)));
 assert(!memcmp(move_pos,gold_pos,moves*sizeof(unsigned)));
 assert(!memcmp(move_duration,gold_duration,moves*sizeof(unsigned)));
}
static void await_recovery(void){
 unsigned limit=200000;while(state!=MOTION_READ_RECOVERY_WAIT && arm_motion_busy() && limit--)tick();
 assert(limit && state==MOTION_READ_RECOVERY_WAIT && read_recovery.active);
}
static void initial_cases(unsigned fixed){
 for(unsigned id=1;id<=6;++id){
  reset_test();rule(READ_INITIAL,ARM_PHASE_HOME,id);start_test();finish_test();
  if(fixed){assert(!strcmp(arm_motion_state_name(),"COMPLETED"));exact_moves();assert(delay_observed==1);}
  else{assert(!strcmp(arm_motion_last_error(),"BUS_RESULT") && !moves && !stops && !delay_observed);}
 }
 puts(fixed?"PASS initial_all_six_ids_recover_full_group_before_motion":"REPRO initial_all_six_ids_excluded_from_recovery");
}
static void repeated_episode(unsigned fixed){
 reset_test();rule(READ_ARRIVAL,ARM_PHASE_PLACE_APPROACH,5);rule(READ_ARRIVAL,ARM_PHASE_PLACE_LEAVE,6);start_test();finish_test();
 assert(rule_index==2);
 if(fixed){assert(!strcmp(arm_motion_state_name(),"COMPLETED"));exact_moves();assert(delay_observed==2);}
 else{assert(!strcmp(arm_motion_last_error(),"BUS_RESULT") && stop_mask==0x7e && delay_observed==1);}
 puts(fixed?"PASS two_separate_read_group_failures_recover_no_MOVE_replay":"REPRO second_group_error_stops_after_first_recovery");
}
static void bounded_cases(void){
 reset_test();rule(READ_ARRIVAL,ARM_PHASE_HOME,5);rule(READ_ARRIVAL,ARM_PHASE_HOME,6);start_test();finish_test();
 assert(!strcmp(arm_motion_last_error(),"BUS_RESULT") && stop_mask==0x7e && delay_observed==1);
 puts("PASS same_group_second_timeout_cannot_restart_recovery");
 for(unsigned bad=0;bad<2;++bad){
  reset_test();rule(READ_ARRIVAL,ARM_PHASE_HOME,5);if(bad)corrupt_lsr=0x80;else corrupt_bytes=1;
  start_test();finish_test();assert(!strcmp(arm_motion_last_error(),"BUS_RESULT") && !delay_observed && stop_mask==0x7e);
 }
 puts("PASS partial_packet_or_line_error_not_eligible_for_extra_recovery");
 reset_test();rule(READ_ARRIVAL,ARM_PHASE_HOME,5);arrival_fault=3;start_test();finish_test();
 assert(!strcmp(arm_motion_last_error(),"ARRIVAL") && stop_mask==0x7e && arm_motion_fault_servo()==3);
 puts("PASS earlier_axis_rechecked_and_arrival_mismatch_stops");
 reset_test();rule(READ_ARRIVAL,ARM_PHASE_HOME,5);position_fault=2;start_test();finish_test();
 assert(!strcmp(arm_motion_last_error(),"POSITION_RANGE") && stop_mask==0x7e);
 puts("PASS recovered_feedback_outside_range_stops");
 reset_test();fail_move=1;start_test();finish_test();
 assert(!strcmp(arm_motion_last_error(),"BUS_RESULT") && moves==1 && stops==6 && !delay_observed);
 puts("PASS MOVE_failure_never_replayed");
 for(unsigned how=0;how<3;++how){
  reset_test();rule(READ_ARRIVAL,ARM_PHASE_HOME,5);start_test();await_recovery();unsigned n=moves,r=reads;
  if(how==0)arm_motion_cancel();else if(how==1)mock_now-=2000;else mock_now+=600000001U;
  arm_motion_service(mock_now);
  finish_test();assert(moves==n && reads==r && stop_mask==0x7e);
  assert(!strcmp(arm_motion_last_error(),how==0?"CANCELLED":how==1?"CLOCK":"RUN_TIMEOUT"));
 }
 puts("PASS cancel_clock_and_watchdog_during_recovery_stop_without_later_motion");
}
static void fixed_cases(void){
 reset_test();rule(READ_INITIAL,ARM_PHASE_HOME,1);start_test();
 for(unsigned attempt=0;attempt<2;++attempt){
  unsigned limit=1000;while(state!=MOTION_RETRY_WAIT && limit--)tick();assert(limit);
  unsigned n=reads;assert(deadline_us-mock_now==(attempt?50000U:20000U));
  mock_now=deadline_us-1U;arm_motion_service(mock_now);assert(state==MOTION_RETRY_WAIT && reads==n);
  ++mock_now;arm_motion_service(mock_now);assert(state==MOTION_READ_START && reads==n);
  tick();assert(reads==n+1U);
 }
 finish_test();assert(!strcmp(arm_motion_state_name(),"COMPLETED"));exact_moves();
 puts("PASS first_retry_20ms_second_retry_50ms_exact_boundaries");
 for(unsigned k=0;k<2;++k){
  reset_test();rule(READ_ARRIVAL,k?ARM_PHASE_ORIENT:ARM_PHASE_OPEN,k?2:1);start_test();finish_test();
  assert(rule_index==1 && !strcmp(arm_motion_state_name(),"COMPLETED"));exact_moves();assert(delay_observed==1);
 }
 puts("PASS gripper_only_and_wrist_only_read_groups_recover");
 reset_test();rule(READ_INITIAL,ARM_PHASE_HOME,5);start_test();await_recovery();
 assert(!strcmp(arm_motion_state_name(),"PREFLIGHT") && !moves);unsigned r=reads;
 ArmReadRecovery before_busy=read_recovery;unsigned count_busy=action_count;
 VisualPickTarget busy_t={0,155,1,0,4,1,1000};
 assert(arm_motion_start_visual_place(&busy_t,1,mock_now)==-1);
 assert(!memcmp(&before_busy,&read_recovery,sizeof(read_recovery)) && action_count==count_busy && reads==r);
 arm_motion_cancel();arm_motion_service(mock_now);finish_test();
 assert(!moves && !stops && reads==r && !strcmp(arm_motion_state_name(),"CANCELLED"));
 puts("PASS preflight_recovery_cancel_has_no_servo_motion");
 reset_test();rule(READ_INITIAL,ARM_PHASE_HOME,1);rule(READ_ARRIVAL,ARM_PHASE_HOME,2);
 rule(READ_ARRIVAL,ARM_PHASE_OPEN,1);rule(READ_ARRIVAL,ARM_PHASE_APPROACH,3);rule(READ_ARRIVAL,ARM_PHASE_DESCEND,4);
 start_test();finish_test();assert(rule_index==5 && delay_observed==4 && !strcmp(arm_motion_last_error(),"BUS_RESULT") && stop_mask==0x7e);
#ifdef ARM_READ_RECOVERY_MAX_PER_REQUEST
 assert(ARM_READ_RECOVERY_MAX_PER_REQUEST==4U && read_recovery.attempts_total==4U && read_recovery.successes_total==4U);
#endif
 puts("PASS four_recovery_budget_then_fifth_stops");
 VisualPickTarget next_t={-17.3,143.436,1,0,4,2,(unsigned)(mock_now/1000U)};
 assert(!arm_motion_start_visual_place(&next_t,1,mock_now));
 assert(!read_recovery.attempted);
#ifdef ARM_READ_RECOVERY_MAX_PER_REQUEST
 assert(!read_group_recovery_used && !read_recovery.attempts_total && !read_recovery.successes_total);
#endif
 arm_motion_cancel();arm_motion_service(mock_now);finish_test();
 puts("PASS new_explicit_request_resets_budget_BUSY_does_not");
 
 reset_test();start_test();mock_now=1751000U;arm_motion_service(mock_now);
 assert(!strcmp(arm_motion_last_error(),"TARGET_STALE") && !moves && !reads && !stops);
 assert(!arm_motion_action_count() && !arm_motion_completed_actions() && !strcmp(arm_motion_phase_name(),"none"));
 ArmMotionFailure f;assert(arm_motion_get_last_failure(&f) && !f.action_valid && !f.action_count);
 puts("PASS postplan_target_expiry_specific_error_no_action_no_bus");
 
 reset_test();start_test();finish_test();assert(arm_motion_action_count());
 VisualPickTarget bad={1000,1000,1,0,4,1,1000};unsigned m=moves,rr=reads;
 assert(arm_motion_start_visual_place(&bad,1,mock_now)==-2);
 assert(!strcmp(arm_motion_last_error(),"PLAN") && !arm_motion_action_count() && !arm_motion_completed_actions());
 assert(!arm_motion_fault_servo() && !arm_motion_query_retries() && moves==m && reads==rr);
 puts("PASS rejected_new_plan_clears_prior_action_summary");
}
int main(int argc,char **argv){
 (void)argv;setbuf(stdout,NULL);unsigned fixed=argc>1;
 save_gold();initial_cases(fixed);repeated_episode(fixed);bounded_cases();if(fixed)fixed_cases();
 puts(fixed?"MOTION_RECOVERY_FIXED_PASS":"MOTION_RECOVERY_BASELINE_REPRODUCED");return 0;
}
'''

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=BASE);p.add_argument('--fixed',action='store_true',default=True);args=p.parse_args()
    source=args.source.resolve();out=HERE/('fixed' if args.fixed else 'baseline');out.mkdir(parents=True,exist_ok=True)
    code=out/'motion_recovery.c';code.write_text(C.replace('@@SOURCE@@',source.as_posix()),encoding='utf8')
    cmd=[(os.environ.get('CC') or shutil.which('gcc') or 'gcc'),'-std=c11','-Wall','-Wextra','-Werror','-O1','-I',str(source),str(code),str(ROOT/'src/dependencies/arm_kinematics.c'),'-lm','-o',str(out/'motion_recovery.exe')]
    built=subprocess.run(cmd,capture_output=True,text=True,encoding='utf8',errors='replace');(out/'compile.log').write_text(built.stdout+built.stderr,encoding='utf8');built.check_returncode()
    run=subprocess.run([str(out/'motion_recovery.exe')]+(['fixed'] if args.fixed else []),capture_output=True,text=True,encoding='utf8',errors='replace',timeout=120)
    (out/'result.log').write_text(run.stdout+run.stderr,encoding='utf8');print(run.stdout+run.stderr)
    report={'status':'PASS' if run.returncode==0 else 'FAIL','hardware_access':False,'production_motion_and_ik_executed':True,'bus_and_clock_mocked':True,'fixed':args.fixed,
      'source_sha256':{q.name:SHA(q) for q in source.glob('*.[ch]')},'test_sha256':SHA(Path(__file__)),'harness_sha256':SHA(code),'command':cmd,'stdout':run.stdout}
    (out/'report.json').write_text(json.dumps(report,indent=2),encoding='utf8');run.check_returncode()

if __name__=='__main__':main()
