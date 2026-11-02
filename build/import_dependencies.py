"""Import verified private inputs from a unified package or the legacy release layout."""
from pathlib import Path
import argparse,hashlib
from project import ROOT,read,sha


def import_dependencies(base):
 """Validate the entire input set before writing; never replace a differing file."""
 base=Path(base).resolve()
 root=ROOT.resolve()
 config=read(ROOT/'build/dependencies.json')
 pending=[];present=0
 for name,digest in config['local_inputs'].items():
  destination=(root/name).resolve()
  if not destination.is_relative_to(root):raise ValueError('Dependency destination outside project: '+name)
  # Prefer the exact layout in screwsort_unified*.zip; otherwise accept the
  # original ARM_BUS_FIX release paths recorded in the dependency contract.
  candidates=[base/name,base/config['source_paths'][name]]
  source=None
  for candidate in candidates:
   candidate=candidate.resolve()
   if not candidate.is_relative_to(base):raise ValueError('Dependency source outside release: '+name)
   if candidate.is_file():source=candidate;break
  if source is None:raise ValueError('Missing dependency in unified or legacy release: '+name)
  payload=source.read_bytes()
  if hashlib.sha256(payload).hexdigest()!=digest:raise ValueError('Different dependency: '+name)
  if destination.exists():
   if not destination.is_file() or sha(destination)!=digest:
    raise ValueError('Refusing to replace an existing different dependency: '+name)
   present+=1
  else:pending.append((destination,payload))
 for destination,payload in pending:
  destination.parent.mkdir(parents=True,exist_ok=True)
  with destination.open('xb') as stream:stream.write(payload)
 return dict(imported=len(pending),already_present=present,verified=len(config['local_inputs']))


def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--release',type=Path,required=True,help='Extracted unified screwsort directory, or original compatible ARM_BUS_FIX release directory.')
 a=p.parse_args()
 try:result=import_dependencies(a.release)
 except ValueError as exc:raise SystemExit(str(exc))
 print('Verified',result['verified'],'inputs; imported',result['imported'],'; already present',result['already_present'])
if __name__=='__main__':main()
