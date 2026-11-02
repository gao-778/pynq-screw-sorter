"""Project source and interface utilities."""
from pathlib import Path
import argparse,hashlib,json,sys,xml.etree.ElementTree as ET

def integer(value):
    if isinstance(value,bool):raise ValueError('Boolean is not an address/size')
    if isinstance(value,int):return value
    if isinstance(value,str):return int(value,0)
    raise ValueError('Expected integer or decimal/0x-prefixed string')

def check(hwh,contract,bit=None):
    expected=json.loads(Path(contract).read_text(encoding='utf-8'))
    if expected.get('schema_version')!=1:raise ValueError('Unsupported schema_version')
    width=integer(expected['address_bits'])
    if width not in (32,64):raise ValueError('address_bits must be 32 or 64')
    regions=expected['regions']
    if not isinstance(regions,list) or not regions:raise ValueError('regions must be a nonempty list')
    actual={}
    for node in ET.parse(hwh).iter():
        if node.tag.rsplit('}',1)[-1]!='MEMRANGE':continue
        attrs=node.attrib
        if 'BASEVALUE' not in attrs or 'HIGHVALUE' not in attrs:continue
        base=integer(attrs['BASEVALUE']);high=integer(attrs['HIGHVALUE'])
        if high<base:raise ValueError('HWH contains reversed address range')
        actual[base]=max(actual.get(base,0),high-base+1)
    errors=[];checks=[];names=set();spans=[]
    for region in regions:
        name=region['name'];base=integer(region['base']);size=integer(region['bytes'])
        if not isinstance(name,str) or not name or name in names:raise ValueError('Region names must be nonempty and unique')
        names.add(name)
        if base<0 or size<=0 or base+size>1<<width:raise ValueError('Region exceeds address_bits or has invalid size')
        if any(base<hi and lo<base+size for lo,hi in spans):raise ValueError('Expected regions overlap; describe aliases as one region')
        spans.append((base,base+size))
        available=actual.get(base,0)
        ok=available>=size
        checks.append(dict(name=name,base=hex(base),required_bytes=size,hwh_bytes=available,covered=ok))
        if not ok:errors.append(f'{name}: missing/short HWH region at {base:#x}')
    hashes={}
    for label,path in (('hwh',hwh),('bit',bit)):
        key=label+'_sha256';wanted=expected.get(key)
        if wanted and path is None:errors.append(f'{key} requires --{label}');continue
        if path is not None:
            digest=hashlib.sha256(Path(path).read_bytes()).hexdigest();hashes[key]=digest
            if wanted and digest.lower()!=str(wanted).lower():errors.append(key+': mismatch')
    return dict(status='OK' if not errors else 'ERROR',scope='offline_metadata_and_hashes_only',
                hardware_access=False,regions=checks,hashes=hashes,errors=errors)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--hwh',required=True,type=Path);p.add_argument('--contract',required=True,type=Path)
    p.add_argument('--bit',type=Path);p.add_argument('--report',type=Path)
    args=p.parse_args()
    try:result=check(args.hwh,args.contract,args.bit)
    except (ValueError,KeyError,TypeError,OSError,ET.ParseError) as exc:
        result=dict(status='ERROR',scope='offline_metadata_and_hashes_only',hardware_access=False,errors=[str(exc)])
    content=json.dumps(result,ensure_ascii=False,indent=2)
    if args.report:args.report.write_text(content+'\n',encoding='utf-8')
    print(content)
    return 0 if result['status']=='OK' else 1

if __name__=='__main__':sys.exit(main())
