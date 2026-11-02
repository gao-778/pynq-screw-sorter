"""Build the shared C application, standalone BOOT, and FPGA design."""
from pathlib import Path
import argparse,os,shutil,sys,zipfile
from project import ROOT,CONFIG,read,write_json,sha,sources,include_dirs,source_snapshot,run

def linux(a):
 out=ROOT/'build/output'/('linux_cross' if a.cross else 'linux');out.mkdir(parents=True,exist_ok=True)
 target=out/('screwlab_host.dll' if os.name=='nt' and not a.cross else 'libscrewlab.so')
 if os.name=='nt' and not (a.host or a.cross):raise SystemExit('Use --host or --cross on Windows; production native builds run on the PYNQ board.')
 includes=include_dirs('linux')+[ROOT/'src/platform/linux/compat']
 cmd=[a.cc,'-std=c11','-O2','-shared','-Wall','-Wextra','-Wno-unused-function','-Wno-unused-variable','-DSCREWSORT_LINUX=1']
 for p in includes:cmd+=['-I',str(p)]
 if os.name!='nt' or a.cross:cmd+=['-fPIC','-D_DEFAULT_SOURCE']
 else:cmd+=['-Wl,--export-all-symbols']
 if a.cross:cmd+=['-mcpu=cortex-a9','-mfpu=neon','-mfloat-abi=hard']
 cmd+=list(map(str,sources('linux')))+['-lm','-o',str(target)]
 run(cmd,out/'compile.log')
 write_json(out/'build.json',dict(status='PASS',target='linux',cross=a.cross,host=a.host,command=cmd,
   shared_sources={p.relative_to(ROOT).as_posix():sha(p) for p in sources('linux')},source_snapshot=source_snapshot('linux'),output=str(target),sha256=sha(target)))
 print(target)

def firmware(a):
 vitis=a.vitis.resolve();bsp=(a.bsp or ROOT/'build/local/bsp').resolve()
 if not (bsp/'include/xparameters.h').is_file():raise SystemExit('BSP not found; use --bsp or import project dependencies.')
 cfg=read(ROOT/'build/baremetal_toolchain.json');template=cfg['compile'][0]['command']
 compiler=Path(template[0].replace('${VITIS}',vitis.as_posix()))
 flags=template[1:template.index('-o')]
 flags=[t for t in flags if not t.startswith('-I${OLD_APP}')]
 def expand(t):return t.replace('${VITIS}',vitis.as_posix()).replace('${AMD_VERSION}',vitis.parent.as_posix()).replace('${BSP}',bsp.as_posix())
 flags=list(map(expand,flags))+['-DSCREWSORT_BAREMETAL=1']
 for p in include_dirs('baremetal'):flags+=['-I',str(p)]
 out=ROOT/'build/output/baremetal';out.mkdir(parents=True,exist_ok=True);objects=[];commands=[]
 for p in sources('baremetal'):
  obj=out/(p.stem+'.o');cmd=[str(compiler)]+flags+['-c',str(p),'-o',str(obj)]
  run(cmd,out/(p.stem+'.log'));commands.append(cmd);objects.append(str(obj))
 old_objects={row['original_object'] for row in cfg['compile']}
 link=[expand(t) for t in cfg['link'] if t not in old_objects and t!='-L/']
 link=[t.replace('${OLD_APP}/src/lscript.ld',(ROOT/'src/platform/baremetal/lscript.ld').as_posix()).replace('${OLD_APP}/src',(ROOT/'src/common').as_posix()) for t in link]
 link[link.index('-o')+1]=str(out/'screwsort.elf')
 group=next(i for i,t in enumerate(link) if t.startswith('-Wl,--start-group'))
 link[group:group]=objects
 if any('${' in t for t in link):raise RuntimeError('Unresolved toolchain path')
 run(link,out/'link.log');commands.append(link)
 from boot_format import loads
 elf=(out/'screwsort.elf').read_bytes()
 if any(s[3]+s[5]>0x08000000 for s in loads(elf)):raise RuntimeError('Firmware overlaps the reserved DMA buffer region')
 if (ROOT/'data/model/model.bin').read_bytes()[24:] not in elf:raise RuntimeError('Firmware model payload differs')
 write_json(out/'build.json',dict(status='PASS',target='baremetal',commands=commands,
   shared_sources={p.relative_to(ROOT).as_posix():sha(p) for p in sources('baremetal')},source_snapshot=source_snapshot('baremetal'),elf_sha256=sha(out/'screwsort.elf')))
 print(out/'screwsort.elf')

def boot(a):
 from boot_format import verify_boot
 vitis=a.vitis.resolve();fsbl=(a.fsbl or ROOT/'build/local/fsbl.elf').resolve()
 elf=ROOT/'build/output/baremetal/screwsort.elf';bit=ROOT/'board/hardware/screwsort.bit'
 for p in (fsbl,elf,bit):
  if not p.is_file():raise SystemExit('Required input missing: '+str(p))
 out=ROOT/'build/output/boot';out.mkdir(parents=True,exist_ok=True)
 for src,name in [(fsbl,'fsbl.elf'),(elf,'app.elf'),(bit,'screwsort.bit')]:shutil.copyfile(src,out/name)
 (out/'boot.bif').write_text('the_ROM_image:\n{\n [bootloader] fsbl.elf\n screwsort.bit\n app.elf\n}\n',encoding='ascii')
 exe=vitis/('bin/unwrapped/win64.o/bootgen.exe' if os.name=='nt' else 'bin/bootgen')
 env=os.environ.copy()
 if os.name=='nt':env['PATH']=str(vitis/'lib/win64.o')+os.pathsep+str(exe.parent)+os.pathsep+env.get('PATH','')
 import subprocess
 command=[str(exe),'-arch','zynq','-image','boot.bif','-o','boot.bin','-w','on']
 result=subprocess.run(command,cwd=out,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace')
 (out/'bootgen.log').write_text(result.stdout+result.stderr,encoding='utf-8');result.check_returncode()
 parts=verify_boot((out/'boot.bin').read_bytes(),fsbl.read_bytes(),bit.read_bytes(),elf.read_bytes())
 target=ROOT/'board/baremetal';target.mkdir(parents=True,exist_ok=True)
 for p,name in [(out/'boot.bin','boot.bin'),(elf,'screwsort.elf'),(fsbl,'fsbl.elf')]:shutil.copyfile(p,target/name)
 write_json(target/'manifest.json',dict(status='PASS',bit_sha256=sha(bit),model_sha256=sha(ROOT/'data/model/model.bin'),
    elf_sha256=sha(elf),boot_sha256=sha(out/'boot.bin'),fsbl_sha256=sha(fsbl),partitions=parts))
 print(target/'boot.bin')

def main():
 p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='target',required=True)
 q=sub.add_parser('linux');q.add_argument('--cc',default=os.environ.get('CC','gcc'));q.add_argument('--host',action='store_true');q.add_argument('--cross',action='store_true')
 q=sub.add_parser('baremetal');q.add_argument('--vitis',type=Path,required=True);q.add_argument('--bsp',type=Path)
 q=sub.add_parser('boot');q.add_argument('--vitis',type=Path,required=True);q.add_argument('--fsbl',type=Path)
 q=sub.add_parser('hardware');q.add_argument('--vivado',required=True);q.add_argument('--output',required=True,type=Path);q.add_argument('--prepare-only',action='store_true')
 sub.add_parser('verify')
 a=p.parse_args()
 if a.target=='linux':
  if a.host and a.cross:p.error('--host and --cross are mutually exclusive')
  linux(a)
 elif a.target=='baremetal':firmware(a)
 elif a.target=='boot':boot(a)
 elif a.target=='verify':
  import json
  from verify import check
  result=check();print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(result['status']!='PASS')
 elif a.target=='hardware':
  import subprocess
  cmd=[sys.executable,str(ROOT/'build/export_hardware.py'),'--vivado',a.vivado,'--output',str(a.output)]
  if a.prepare_only:cmd+=['--prepare-only']
  subprocess.run(cmd,check=True)

if __name__=='__main__':main()
