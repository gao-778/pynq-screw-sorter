"""Project source and interface utilities."""
from pathlib import Path
import hashlib,json,os,subprocess
ROOT=Path(__file__).resolve().parents[1]
CONFIG=json.loads((ROOT/'build/project.json').read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def require(condition,message):
 if not condition:raise RuntimeError(message)
def write_json(p,value):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sources(target):
 return [ROOT/p for p in CONFIG['shared_sources']+CONFIG['targets'][target]['sources']]
def include_dirs(target):
 return [ROOT/'src/common',ROOT/'src/platform',ROOT/('src/platform/'+target)]
def source_snapshot(target):
 files=set(sources(target))
 for folder in (ROOT/'src/common',ROOT/('src/platform/'+target)):
  files.update(p for p in folder.rglob('*') if p.is_file() and p.suffix in ('.c','.h','.ld'))
 files.add(ROOT/'src/platform/port_platform.h');files.add(ROOT/'build/project.json')
 return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(files)}
def run(command,out,env=None):
 result=subprocess.run(list(map(str,command)),cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace')
 out.parent.mkdir(parents=True,exist_ok=True);out.write_text(result.stdout+result.stderr,encoding='utf-8')
 if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
 return result
