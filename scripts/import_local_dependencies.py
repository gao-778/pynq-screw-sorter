"""Import locally licensed dependencies; never download or publish them."""
from pathlib import Path
import argparse, hashlib, json, shutil

ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--release',type=Path,required=True,help='Root of your own complete 2026-11-01 ARM_BUS_FIX release')
 a=p.parse_args();source=a.release.resolve();target=ROOT/'external'
 manifest=json.loads((ROOT/'config/local_dependencies.json').read_text())
 checked=[]
 for name,item in manifest['files'].items():
  f=(source/name).resolve();out=(target/item['target']).resolve()
  if not f.is_relative_to(source) or not out.is_relative_to(target.resolve()):raise ValueError('Escaped dependency path')
  if not f.is_file() or hashlib.sha256(f.read_bytes()).hexdigest()!=item['sha256']:
   raise RuntimeError('Missing or different dependency: '+name)
  checked.append((f,out))
 for f,out in checked:
  out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,out)
 (target/'IMPORT.json').write_text(json.dumps({'status':'IMPORTED_LOCAL_ONLY','files':len(checked),'hardware_access':False},indent=2))
 print('Imported',len(checked),'local files into ignored external/. Nothing uploaded.')
if __name__=='__main__':main()
