"""Shared local build utilities. No device, serial, network or SD access."""
from pathlib import Path
import hashlib,json,shutil,struct,zlib
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def require(ok,message):
 if not ok:raise RuntimeError(message)
def model_check():
 data=(ROOT/'model/model.bin').read_bytes()
 magic,version,weights,biases,shifts,crc=struct.unpack_from('<4s5I',data)
 require((magic,version,weights,biases,shifts)==(b'FNET',1,255510,402,3),'Model architecture mismatch')
 require(len(data)==24+4*(weights+biases+shifts),'Truncated model payload')
 require(zlib.crc32(data[24:])==crc,'Model CRC mismatch')
 return data
def verify_baseline():
 for name,digest in read(ROOT/'config/baseline.json')['source_and_model_sha256'].items():
  require(sha(ROOT/name)==digest,'Baseline input changed: '+name)
def materialize_software():
 dep=ROOT/'external/software/arm_kinematics.c'
 require(dep.is_file(),'Local IK dependency missing. See docs/THIRD_PARTY.md and run import_local_dependencies.py.')
 expected=read(ROOT/'config/local_dependencies.json')['files']['software/arm_kinematics.c']['sha256']
 require(sha(dep)==expected,'Local IK source is not the accepted baseline')
 out=ROOT/'build/software';out.mkdir(parents=True,exist_ok=True)
 files=list((ROOT/'software').glob('*.[ch]'))+[dep]
 for f in files:shutil.copy2(f,out/f.name)
 require(set(p.name for p in out.glob('*.[ch]'))==set(p.name for p in files),'Stale files in build/software; choose a clean build directory')
 return out
