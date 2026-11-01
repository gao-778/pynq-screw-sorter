"""Check Git's prospective public file list, without printing secret contents."""
from pathlib import Path
import hashlib,json,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]

def main():
 result=subprocess.run(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT,capture_output=True,check=True)
 names=sorted(set(x for x in result.stdout.decode('utf8').split('\0') if x))
 require=['README.md','LICENSE','LICENSE_SCOPE.md','docs/THIRD_PARTY.md','software/main.c','hardware/source_manifest.json','model/model.bin']
 errors=[]
 for n in require:
  if n not in names:errors.append({'file':n,'reason':'required publication file missing'})
 blocked_roots={'external','build','output','release_assets','backup','provenance','.git'}
 blocked_suffix={'.bit','.xsa','.dcp','.elf','.exe','.zip','.rar','.log','.jou','.pb','.xpr','.pyc'}
 patterns={
  'private_user_path':re.compile(r'(?i)[A-Z]:[\\/]+Users[\\/]+[^\\/\s]+'),
  'wechat_private_id':re.compile(r'wxid_[A-Za-z0-9_]+'),
  'private_key':re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
  'github_token':re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{40,})\b'),
 }
 manifest={};total=0
 for name in names:
  p=ROOT/name
  if not p.is_file():errors.append({'file':name,'reason':'missing tracked file'});continue
  if Path(name).parts[0] in blocked_roots or p.suffix.lower() in blocked_suffix:
   errors.append({'file':name,'reason':'local/generated artifact in public list'})
  size=p.stat().st_size;total+=size
  if size>=100*1024*1024:errors.append({'file':name,'reason':'file exceeds normal GitHub size limit'})
  data=p.read_bytes();manifest[name]=hashlib.sha256(data).hexdigest()
  if p.suffix.lower() not in {'.bin','.npz','.png','.jpg','.jpeg'}:
   body=data.decode('utf8',errors='replace')
   # Avoid matching this scanner's pattern literals; it contains no actual values.
   if name!='scripts/check_repository.py':
    for reason,pattern in patterns.items():
     if pattern.search(body):errors.append({'file':name,'reason':reason})
 report={'status':'FAIL' if errors else 'PASS','files':len(names),'bytes':total,'errors':errors,'sha256':manifest,
         'limits':'Pattern and publication-list checks; not a guarantee of complete license or secret detection.'}
 out=ROOT/'build/publication_check.json';out.parent.mkdir(parents=True,exist_ok=True)
 out.write_text(json.dumps(report,indent=2),encoding='utf8')
 print(json.dumps({k:report[k] for k in ('status','files','bytes','errors')},ensure_ascii=False))
 return 1 if errors else 0
if __name__=='__main__':sys.exit(main())
