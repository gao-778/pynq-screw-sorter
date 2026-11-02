"""Create verified local or public-source distributions of the same project."""
from pathlib import Path
import argparse,hashlib,json,zipfile
from project import ROOT,CONFIG,sha,read,write_json
from verify import release_files,public_name,check


def distribution_mode(requested=None):
 """An ordinary refresh preserves whether this is a source or local checkout."""
 if requested is not None:return requested
 path=ROOT/'build/release_manifest.json'
 mode=read(path).get('distribution','local') if path.exists() else 'local'
 if mode not in ('local','source'):raise ValueError('Unknown release distribution: '+str(mode))
 return mode


def manifest(public=False):
 files={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(release_files())
        if not public or public_name(p.relative_to(ROOT).as_posix())}
 return dict(schema_version=1,project='screwsort',version=CONFIG['version'],
             distribution='source' if public else 'local',files=files)


def refresh_public_file_list():
 """Refresh the readable public inventory before hashing it in the release manifest."""
 name='report/open_source_files.json';path=ROOT/name
 value=read(path) if path.exists() else {'schema_version':1,'license_document':'report/licenses/third_party.md'}
 files={p.relative_to(ROOT).as_posix() for p in release_files()
        if public_name(p.relative_to(ROOT).as_posix())}
 files.add(name)
 value['files']=sorted(files)
 write_json(path,value)


def write_archive(destination,value):
 """Write an already verified release, then check archive CRC and every digest."""
 destination=destination.resolve()
 if destination.exists() or destination.is_relative_to(ROOT.resolve()):
  raise ValueError('Choose a new archive path outside this project')
 destination.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(destination,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for name in value['files']:z.write(ROOT/name,'screwsort/'+name)
  z.writestr('screwsort/build/release_manifest.json',json.dumps(value,ensure_ascii=False,indent=2)+'\n')
 with zipfile.ZipFile(destination) as z:
  if z.testzip():raise RuntimeError('Archive CRC failed')
  for name,digest in value['files'].items():
   if hashlib.sha256(z.read('screwsort/'+name)).hexdigest()!=digest:
    raise RuntimeError('Archive digest mismatch: '+name)
 destination.with_suffix(destination.suffix+'.sha256').write_text(sha(destination)+'  '+destination.name+'\n',encoding='ascii')
 return destination


def main():
 p=argparse.ArgumentParser(description=__doc__)
 group=p.add_mutually_exclusive_group()
 group.add_argument('--public',action='store_const',const='source',dest='distribution',help='Export or refresh the public-source file set.')
 group.add_argument('--local',action='store_const',const='local',dest='distribution',help='Require the complete local dependencies and deployment artifacts.')
 p.add_argument('--output',type=Path)
 p.add_argument('--refresh',action='store_true',help='Verify inputs, then refresh the selected distribution manifest; default preserves its kind.')
 a=p.parse_args()
 if not a.refresh and not a.output:p.error('Specify --refresh and/or --output.')
 mode=distribution_mode(a.distribution)
 if a.refresh:
  result=check(manifest=False,distribution=mode)
  if result['status']!='PASS':raise SystemExit(json.dumps(result,ensure_ascii=False,indent=2))
  refresh_public_file_list()
  write_json(ROOT/'build/release_manifest.json',manifest(mode=='source'))
  print('Release manifest refreshed:',mode)
 if a.output:
  result=check()
  if result['status']!='PASS':raise SystemExit(json.dumps(result,ensure_ascii=False,indent=2))
  # A source archive cannot masquerade as a complete local delivery.
  if mode=='local' and result['distribution']=='source':
   result=check(manifest=False,distribution='local')
   if result['status']!='PASS':raise SystemExit(json.dumps(result,ensure_ascii=False,indent=2))
  value=manifest(mode=='source');destination=write_archive(a.output,value)
  print(destination);print('files',len(value['files'])+1,'MiB',round(destination.stat().st_size/1048576,2))
if __name__=='__main__':main()
