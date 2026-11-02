"""Project source and interface utilities."""

from pathlib import Path
import argparse, hashlib, json, subprocess, os, shutil, re

ROOT=Path(__file__).resolve().parents[2]
DEFAULT=ROOT/'src/common'
BASE_TEST=ROOT/'sim/motion/fixtures/test_arm_bus_baseline.c'
OUT=ROOT/'sim/output/motion/query_quiet'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
EXTRA=r'''
static void test_query_quiet_boundaries(void)
{
 unsigned id;
 for(id=1U;id<=6U;++id){
  ArmBusDiagnostic d;unsigned resets;uint64_t start;
  reset_mock();response(id,500);resets=mock.fcr_writes;start=mock.now;
  assert(ARM_BUS_QUERY_QUIET_US==2000U);
  assert(!arm_bus_start_read(id,mock.now));arm_bus_service(mock.now);
  assert(!mock.tx_count && !mock.direction && mock.fcr_writes==resets);
  step(1999U);assert(!mock.tx_count && !mock.direction && mock.fcr_writes==resets);
  assert(arm_bus_get_diagnostic(&d) && !strcmp(arm_bus_phase_name(d.phase),"WAIT_IDLE"));
  step(1U);assert(!mock.tx_count && !mock.direction && mock.fcr_writes==resets+1U);
  finish_transaction(1000U);
  assert(arm_bus_result()==ARM_BUS_OK && arm_bus_position()==500);
  assert(mock.first_tx_at-start>=2000U && mock.tx_enabled_at-start>=2000U);
  assert(mock.rx_enabled_at<mock.reply_start_at && mock.reply_start_at==mock.tx_end+20U);
  assert(mock.wire_delivered==8U && !mock.wire_lost && !mock.tx_disable_before_empty);
 }
 ++tests;puts("ARM_BUS_CHECK_PASS query_quiet_0_1999_2000us_all_six_ids_fast_20us_reply");
}
static void test_repeated_query_quiet(void)
{
 unsigned id;reset_mock();
 for(id=1U;id<=6U;++id){
  uint64_t start=mock.now;mock.tx_count=0;mock.first_tx_at=0;response(id,(int)(400U+id));
  assert(!arm_bus_start_read(id,mock.now));
  step(1999U);assert(!mock.tx_count && !mock.direction);
  finish_transaction(1000U);
  assert(arm_bus_result()==ARM_BUS_OK && arm_bus_position()==(int)(400U+id));
  assert(mock.first_tx_at-start>=2000U && mock.rx_enabled_at<mock.reply_start_at);
  assert(mock.wire_delivered==8U && !mock.wire_lost);
 }
 ++tests;puts("ARM_BUS_CHECK_PASS consecutive_queries_each_wait_before_TX_no_reply_replay");
}
static void test_nonquery_no_added_quiet_and_cancel(void)
{
 uint64_t start;unsigned kind;
 for(kind=0;kind<2U;++kind){
  reset_mock();start=mock.now;
  assert(!(kind?arm_bus_start_move(2,500,300,mock.now):arm_bus_start_stop(2,mock.now)));
  finish_transaction(1000U);
  assert(arm_bus_result()==ARM_BUS_OK && mock.first_tx_at-start<2000U && !mock.rx_enables);
 }
 reset_mock();assert(!arm_bus_start_read(4,mock.now));step(1999U);
 assert(!mock.tx_count && !mock.direction);arm_bus_cancel();
 assert(!arm_bus_busy() && arm_bus_error()==ARM_BUS_ERROR_CANCELLED && !mock.direction);
 start=mock.now;assert(!arm_bus_start_stop(4,mock.now));finish_transaction(1000U);
 assert(arm_bus_result()==ARM_BUS_OK && mock.first_tx_at-start<2000U && !mock.rx_enables);
 ++tests;puts("ARM_BUS_CHECK_PASS MOVE_STOP_no_extra_quiet_and_cancel_preTX_sends_no_query");
}
static void test_query_quiet_timeout_bound(void)
{
 ArmBusDiagnostic d;reset_mock();mock.hold_busy=1U;
 assert(!arm_bus_start_read(6,mock.now));step(2000U);assert(!mock.tx_count && arm_bus_busy());
 step(47999U);assert(arm_bus_busy() && !mock.tx_count && !mock.rx_enables);
 step(1U);assert(!arm_bus_busy() && arm_bus_error()==ARM_BUS_ERROR_TX_TIMEOUT);
 assert(arm_bus_get_diagnostic(&d) && d.elapsed_us==50000U && !d.queued_bytes && !mock.direction);
 ++tests;puts("ARM_BUS_CHECK_PASS query_50ms_TX_deadline_includes_quiet_period");
}
'''

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,default=DEFAULT)
 args=parser.parse_args();src=args.source.resolve();OUT.mkdir(parents=True,exist_ok=True)
 identities={p.name:sha(p) for p in src.glob('*.[ch]')}
 text=BASE_TEST.read_text(encoding='utf8')
 text=text.replace('#include "../software/arm_bus.h"','#include "'+(src/'arm_bus.h').as_posix()+'"')
 anchor='    assert(arm_bus_start_read(1, mock.now) == 0);\n    step(10);'
 assert text.count(anchor)==1
 text=text.replace(anchor,anchor.replace('step(10);','step(2000);'))
 text=text.replace('int main(void)',EXTRA+'\nint main(void)')
 text=text.replace('    printf("ARM_BUS_TEST_PASS',
     '    test_query_quiet_boundaries();\n    test_repeated_query_quiet();\n    test_nonquery_no_added_quiet_and_cancel();\n    test_query_quiet_timeout_bound();\n    printf("ARM_BUS_TEST_PASS')
 code=OUT/'test_arm_bus_quiet.c';code.write_text(text,encoding='utf8')
 command=[(os.environ.get('CC') or shutil.which('gcc') or 'gcc'),'-std=c11','-O1','-Wall','-Wextra','-Werror','-I',str(src),str(code),str(src/'arm_bus.c'),'-o',str(OUT/'test_arm_bus_quiet.exe')]
 report={'status':'RUNNING','source':str(src),'source_sha256':identities,'prior_test_sha256':sha(BASE_TEST),
   'test_script_sha256':sha(Path(__file__)),'harness_sha256':sha(code),'hardware_access':False,
   'real_production_transport_compiled':True,'mock':'UART/GPIO, independently timed 20us servo replies with 87us bytes',
   'prior_test_adaptation':'Only QUERY stale-drain test waits 2000us instead of 10us before inserting FIFO noise; old byte budget and all other old assertions remain.'}
 try:
  build=subprocess.run(command,capture_output=True,text=True,encoding='utf8',errors='replace')
  (OUT/'compile.log').write_text(build.stdout+build.stderr,encoding='utf8');build.check_returncode()
  run=subprocess.run([str(OUT/'test_arm_bus_quiet.exe')],capture_output=True,text=True,encoding='utf8',errors='replace',timeout=60)
  (OUT/'result.log').write_text(run.stdout+run.stderr,encoding='utf8');print(run.stdout+run.stderr);run.check_returncode()
  assert identities=={n:sha(src/n) for n in identities}
  report.update(status='PASS',stdout=run.stdout,compiler_command=command,log_sha256=sha(OUT/'result.log'))
 except Exception as error:
  report.update(status='FAIL',error=str(error));raise
 finally:
  (OUT/'report.json').write_text(json.dumps(report,indent=2),encoding='utf8')

if __name__=='__main__':main()
