"""Project source and interface utilities."""
from pathlib import Path
import argparse,json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--cc',default=os.environ.get('CC','gcc'));p.add_argument('--vivado-bin');a=p.parse_args()
 out=ROOT/'sim/output';out.mkdir(parents=True,exist_ok=True);py=sys.executable
 env=os.environ.copy();env['CC']=a.cc;env['PYTHONDONTWRITEBYTECODE']='1'
 jobs=[('linux_build',[py,str(ROOT/'build/build.py'),'linux','--host','--cc',a.cc]),
  ('python_api',[py,'-m','unittest','discover','-s',str(ROOT/'sim/tests'),'-p','test_port.py','-v']),
  ('release_packaging',[py,'-m','unittest','discover','-s',str(ROOT/'sim/tests'),'-p','test_release_packaging.py','-v']),
  ('state_linux',[py,str(ROOT/'sim/test_state_machine.py'),'--cc',a.cc,'--target','linux']),
  ('state_baremetal',[py,str(ROOT/'sim/test_state_machine.py'),'--cc',a.cc,'--target','baremetal']),
  ('baremetal_platform',[py,str(ROOT/'sim/test_baremetal_platform.py'),'--cc',a.cc])]
 for name in ('query_quiet','motion_recovery','joint_recovery'):
  jobs.append((name,[py,str(ROOT/'sim/motion'/('test_'+name+'.py'))]))
 jobs.append(('coordinates',[py,str(ROOT/'data/calibration/test_obb_coordinates.py')]))
 if a.vivado_bin:jobs.append(('rtl',[py,str(ROOT/'sim/test_rtl.py'),'--vivado-bin',a.vivado_bin]))
 summary=dict(hardware_access=False,checks=[])
 for name,command in jobs:
  result=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace')
  (out/(name+'.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
  summary['checks'].append(dict(name=name,status='PASS' if result.returncode==0 else 'FAIL',command=command))
  summary['status']='PASS' if all(c['status']=='PASS' for c in summary['checks']) else 'FAIL'
  (out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
  print(name,summary['checks'][-1]['status'],flush=True)
  if result.returncode:print((result.stdout+result.stderr)[-4000:]);raise SystemExit(result.returncode)
if __name__=='__main__':main()
