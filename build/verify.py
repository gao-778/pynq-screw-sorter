"""Verify project structure, shared sources, model views, and deployment artifacts."""
from pathlib import Path
import argparse,ast,hashlib,json,os,re,struct,sys,zipfile,zlib
from project import ROOT,CONFIG,read,sha,sources

TRANSIENT=('build/output/','sim/output/','board/output/')
REQUIRED_DIRS={'src','sim','build','board','data','skill','report'}
REPOSITORY_FILES={'README.md','.gitignore','.gitattributes','LICENSE','CHANGELOG.md'}
VCS_NAMES={'.git','.hg','.svn'}

def selected(path):
 name=path.relative_to(ROOT).as_posix()
 parts=path.relative_to(ROOT).parts
 return not name.startswith(TRANSIENT) and not (VCS_NAMES|{'__pycache__','.Xil'})&set(parts) and name!='build/release_manifest.json'

def release_files():
 """Walk release inputs without entering VCS or generated output directories."""
 for parent,dirs,files in os.walk(ROOT,followlinks=False):
  parent=Path(parent)
  kept=[]
  for name in sorted(dirs):
   path=parent/name
   if name in VCS_NAMES or name in {'__pycache__','.Xil'}:continue
   if path.relative_to(ROOT).as_posix()+'/' in TRANSIENT:continue
   if path.is_symlink():raise ValueError('Symlink directory is not a release input: '+path.relative_to(ROOT).as_posix())
   kept.append(name)
  dirs[:]=kept
  for name in sorted(files):
   path=parent/name
   if not selected(path):continue
   if path.is_symlink():raise ValueError('Symlink file is not a release input: '+path.relative_to(ROOT).as_posix())
   yield path

def layout_errors():
 """Preserve the seven project directories while permitting Git checkout metadata."""
 errors=[]
 for name in sorted(REQUIRED_DIRS):
  if not (ROOT/name).is_dir():errors.append('Required project directory missing: '+name)
 if not (ROOT/'README.md').is_file():errors.append('Required README.md missing')
 for path in ROOT.iterdir():
  if path.name in VCS_NAMES:continue
  if path.name in REQUIRED_DIRS and path.is_dir():continue
  if path.name in REPOSITORY_FILES and path.is_file():continue
  errors.append('Unexpected top-level item: '+path.name)
 return errors

def valid_filename(name):
 if name in REPOSITORY_FILES:return True
 return all(re.fullmatch(r'[a-z0-9_][a-z0-9_.-]*|README\.md|SKILL\.md',part) for part in Path(name).parts)

def public_name(name):
 import fnmatch
 excluded=read(ROOT/'build/dependencies.json')['public_exclude']
 return not any(name.startswith(x) if x.endswith('/') else fnmatch.fnmatch(name,x) for x in excluded)
def npy_values(data):
 version=data[6];width=2 if version==1 else 4
 count=int.from_bytes(data[8:8+width],'little');start=8+width
 header=ast.literal_eval(data[start:start+count].decode('latin1').strip());payload=data[start+count:]
 dtype=header['descr'];code={'|i1':'b','|u1':'B','<i4':'i','<u4':'I','<i8':'q','<u8':'Q'}[dtype]
 return list(struct.unpack('<'+str(len(payload)//struct.calcsize(code))+code,payload))

def check(manifest=True,distribution=None):
 errors=[];checks=[];path=ROOT/'build/release_manifest.json'
 release=read(path) if path.exists() else {}
 mode=distribution or release.get('distribution','local')
 if mode not in ('source','local'):errors.append('Unknown distribution: '+str(mode))
 public=mode=='source'
 errors.extend(layout_errors())
 try:paths=list(release_files())
 except ValueError as exc:errors.append(str(exc));paths=[]
 files={p.relative_to(ROOT).as_posix():sha(p) for p in paths if not public or public_name(p.relative_to(ROOT).as_posix())}
 for name in files:
  if not valid_filename(name):errors.append('Invalid filename: '+name)
 checks.append('repository_layout_and_english_names')
 if manifest:
  if not release:errors.append('Release manifest missing')
  else:
   for name,digest in release['files'].items():
    if files.get(name)!=digest:errors.append('Missing or modified release file: '+name)
   if set(files)-set(release['files']):errors.append('Unlisted release files: '+', '.join(sorted(set(files)-set(release['files']))))
  checks.append('release_integrity')
 deps=read(ROOT/'build/dependencies.json');missing=[]
 for name,digest in deps['local_inputs'].items():
  p=ROOT/name
  if not p.is_file():
   if public and not public_name(name):missing.append(name)
   else:errors.append('Required dependency missing: '+name)
  elif sha(p)!=digest:errors.append('Dependency differs: '+name)
 checks.append('explicit_build_dependencies')
 for target in ('baremetal','linux'):
  names=[p.relative_to(ROOT).as_posix() for p in sources(target)]
  if len(names)!=len(set(names)):errors.append('Duplicate compiler input: '+target)
  for name in names:
   if not (ROOT/name).is_file() and not (public and name in missing):errors.append('Source missing: '+name)
  if any('src/baremetal/' in n or 'src/pynq/native/source/' in n for n in names):errors.append('Independent application copy in '+target)
 checks.append('one_shared_application_source_list')
 binary=(ROOT/'data/model/model.bin').read_bytes();fields=struct.unpack_from('<4s5I',binary)
 if fields[:5]!=(b'FNET',1,255510,402,3) or zlib.crc32(binary[24:])!=fields[5]:errors.append('FNET format or CRC mismatch')
 words=list(struct.unpack('<'+str((len(binary)-24)//4)+'I',binary[24:]))
 h=(ROOT/'src/common/shape_model.h').read_text(encoding='utf-8')
 section=h.split('shape_model_words',1)[1].split('{',1)[1].split('}',1)[0]
 embedded=[int(x,16) for x in re.findall(r'0x[0-9a-fA-F]+',section)]
 if words!=embedded:errors.append('C embedded model differs from FNET')
 for name,start,end in [('weights',0,255510),('biases',255510,255912),('shifts',255912,255915)]:
  values=[int(x,16) for x in (ROOT/'data/model'/(name+'.hex')).read_text().split()]
  if values!=words[start:end]:errors.append('HEX model differs: '+name)
 with zipfile.ZipFile(ROOT/'data/model/quantized_model.npz') as z:
  for name,start,end,mask in [('weights',0,255510,255),('biases',255510,255912,0xffffffff),('shifts',255912,255915,0xffffffff)]:
   if [x&mask for x in npy_values(z.read(name+'.npy'))]!=words[start:end]:errors.append('NPZ model differs: '+name)
 model=read(ROOT/'data/model/model_manifest.json')
 if sha(ROOT/'data/model/model.bin')!=model['model_sha256'] or read(ROOT/'data/model/classes.json')!=model['class_names']:errors.append('Model identity or class order mismatch')
 checks.append('fnet_crc_c_header_npz_hex_and_class_order')
 hw=ROOT/'board/hardware';available=all((hw/('screwsort.'+e)).is_file() for e in ('bit','hwh','xsa'))
 if available:
  identity=read(hw/'hardware_manifest.json')
  for ext in ('bit','hwh','xsa'):
   if sha(hw/('screwsort.'+ext))!=identity[ext+'_sha256']:errors.append('Hardware digest mismatch: '+ext)
  with zipfile.ZipFile(hw/'screwsort.xsa') as z:
   if z.read('camera_sd.bit')!=(hw/'screwsort.bit').read_bytes() or z.read('camera_sd_system.hwh')!=(hw/'screwsort.hwh').read_bytes():errors.append('Hardware artifacts are not one XSA export')
  sys.path.insert(0,str(ROOT/'skill/pynq-overlay-contract/scripts'))
  from check_contract import check as overlay_check
  result=overlay_check(hw/'screwsort.hwh',ROOT/'board/overlay_contract.json',hw/'screwsort.bit')
  errors.extend(result['errors'])
 elif not public:errors.append('Shared hardware artifacts missing')
 checks.append('shared_bit_hwh_xsa_contract')
 firmware=ROOT/'board/baremetal/manifest.json'
 if firmware.is_file():
  m=read(firmware);folder=firmware.parent
  for key,name in [('elf_sha256','screwsort.elf'),('boot_sha256','boot.bin'),('fsbl_sha256','fsbl.elf')]:
   if sha(folder/name)!=m[key]:errors.append('Firmware digest mismatch: '+name)
  if available and sha(hw/'screwsort.bit')!=m['bit_sha256']:errors.append('BOOT uses different hardware from PYNQ')
  if model['model_sha256']!=m['model_sha256']:errors.append('BOOT uses different model from Python')
  if available:
   from boot_format import verify_boot
   verify_boot((folder/'boot.bin').read_bytes(),(folder/'fsbl.elf').read_bytes(),(hw/'screwsort.bit').read_bytes(),(folder/'screwsort.elf').read_bytes())
 elif not public:errors.append('Standalone deployment manifest missing')
 checks.append('boot_elf_model_and_shared_hardware_correspondence')
 for record in (ROOT/'build/reports/software').glob('*_build.json'):
  value=read(record)
  for name,digest in value.get('source_snapshot',{}).items():
   p=ROOT/name
   if p.is_file() and sha(p)!=digest:errors.append('Compiled source correspondence mismatch: '+name)
  common={n:d for n,d in value.get('shared_sources',{}).items() if n in CONFIG['shared_sources']}
  if set(common)!=set(CONFIG['shared_sources']):errors.append('Target did not compile all shared sources: '+record.name)
 checks.append('compiler_inputs_match_delivered_shared_sources_and_headers')
 for p in paths:
  if p.suffix=='.py' and not p.relative_to(ROOT).as_posix().startswith('build/local/'):ast.parse(p.read_text(encoding='utf-8-sig'),filename=str(p))
 for p in paths:
  if p.suffix!='.md':continue
  for target in re.findall(r'\]\(([^)]+)\)',p.read_text(encoding='utf-8-sig')):
   if not re.match(r'https?://|#',target) and not (p.parent/target.split('#')[0]).exists():errors.append('Broken documentation link: '+p.relative_to(ROOT).as_posix()+' -> '+target)
 checks.append('python_syntax_and_documentation_links')
 return dict(status='PASS' if not errors else 'FAIL',distribution=mode,checks=checks,
             local_dependencies_to_supply=missing,hardware_artifacts_present=available,
             standalone_manifest_present=firmware.is_file(),
             verification_scope='Source/archive consistency only; PASS is not a board or runtime acceptance result.',
             hardware_access=False,errors=errors)


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--no-manifest',action='store_true');a=p.parse_args()
 result=check(not a.no_manifest);print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(result['status']!='PASS')
if __name__=='__main__':main()
