"""Build the accepted standalone Cortex-A9 software with Vitis 2026.1."""
from pathlib import Path
from datetime import datetime
import argparse,json,shutil,subprocess
from project_common import ROOT,read,sha,require,model_check,verify_baseline,materialize_software
from boot_format import loads

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--vitis-root',type=Path,required=True)
 p.add_argument('--verify-baseline',action='store_true')
 p.add_argument('--check-only',action='store_true')
 a=p.parse_args();vitis=a.vitis_root.resolve()
 if a.verify_baseline:verify_baseline()
 model=model_check();src=materialize_software();bsp=ROOT/'external/firmware/bsp'
 require((bsp/'include/xparameters.h').is_file(),'Import the local BSP first')
 # Accepted BSP identity prevents accidentally linking an unrelated hardware map.
 for name,item in read(ROOT/'config/local_dependencies.json')['files'].items():
  if name.startswith('firmware/bsp/'):
   require(sha(ROOT/'external'/item['target'])==item['sha256'],'BSP differs: '+name)
 run=ROOT/'build/firmware'/datetime.now().strftime('%Y%m%d_%H%M%S_%f');run.mkdir(parents=True)
 shutil.copy2(ROOT/'software/lscript.ld',run/'lscript.ld')
 cfg=read(ROOT/'config/build_commands.json');objects={};commands=[]
 def relocate(t):
  return t.replace('${VITIS}',vitis.as_posix()).replace('${AMD_VERSION}',vitis.parent.as_posix()).replace('${BSP}',bsp.as_posix())
 for row in cfg['compile']:
  obj=run/(row['name']+'.obj');objects[row['original_object']]=obj.as_posix()
  cmd=[relocate(t) for t in row['command'] if not t.startswith('-I${OLD_APP}')]
  cmd[1:1]=['-I'+src.as_posix(),'-fstack-usage']
  cmd[cmd.index('-o')+1]=obj.as_posix();cmd[cmd.index('-c')+1]=(src/row['name']).as_posix()
  require(all('${' not in t for t in cmd),'Unresolved compile template')
  commands.append(cmd)
 elf=run/'screw_sorter.elf'
 link=[objects[t] if t in objects else relocate(t) for t in cfg['link'] if t!='-L/']
 link=[t.replace('${OLD_APP}/src/lscript.ld',(run/'lscript.ld').as_posix()).replace('${OLD_APP}/src',src.as_posix()) for t in link]
 link[link.index('-o')+1]=elf.as_posix()
 require(all('${' not in t for t in link),'Unresolved link template')
 require(Path(commands[0][0]).is_file(),'Vitis A9 compiler not found')
 (run/'commands.json').write_text(json.dumps({'compile':commands,'link':link},indent=2))
 if a.check_only:print('BUILD_INPUTS_CHECKED');return
 for i,cmd in enumerate(commands+[link]):
  result=subprocess.run(cmd,cwd=run,capture_output=True,text=True,encoding='utf8',errors='replace')
  (run/(str(i)+'.log')).write_text(result.stdout+result.stderr,encoding='utf8');result.check_returncode()
 app=elf.read_bytes();require(model[24:] in app,'ELF lacks full accepted model payload')
 require(all(s[3]+s[5]<=0x08000000 for s in loads(app)),'ELF overlaps vision DDR')
 record={'status':'BUILT_NOT_LOADED','elf':elf.relative_to(ROOT).as_posix(),'elf_sha256':sha(elf),
         'source_sha256':{f.name:sha(f) for f in src.glob('*.[ch]')},'hardware_access':False}
 (ROOT/'build/firmware.json').write_text(json.dumps(record,indent=2))
 print('SOFTWARE_BUILD_PASS',elf.relative_to(ROOT).as_posix())
if __name__=='__main__':main()
