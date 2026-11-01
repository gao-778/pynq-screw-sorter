"""Run protocol and motion regressions without connecting any board."""
import subprocess,sys
from project_common import ROOT,materialize_software
def main():
 src=materialize_software()
 for name in ('test_query_quiet.py','test_motion_recovery.py','test_joint_recovery.py'):
  subprocess.run([sys.executable,str(ROOT/'tests'/name),'--source',str(src)],cwd=ROOT,check=True)
 print('ALL_HOST_TESTS_PASS; no hardware accessed')
if __name__=='__main__':main()
