"""Export matching BIT, HWH, and XSA artifacts after implementation checks."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys, zipfile, shutil
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--vivado',required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--prepare-only',action='store_true')
p.add_argument('--export-only',action='store_true',help='Validate and export an already completed build directory.')
a=p.parse_args();(ROOT/'build/reports/current').mkdir(parents=True,exist_ok=True);source=ROOT/'src/fpga';output=a.output.resolve()
cmd=[sys.executable,str(ROOT/'build/hardware.py'),
     '--output',str(output),'--vivado',a.vivado]
if a.prepare_only:cmd.append('--prepare-only')
env=os.environ.copy()
if os.name=='nt':env.setdefault('PROCESSOR_ARCHITECTURE','AMD64')
if not a.export_only:subprocess.run(cmd,check=True,env=env)
if not a.prepare_only:
    manifest=json.loads((output/'hardware/manifest.json').read_text(encoding='utf-8'))
    if manifest['status']!='PASS':raise SystemExit('Implementation validation failed')
    def payload(data):
        offset=2+int.from_bytes(data[:2],'big')
        if data[offset:offset+2]!=b'\x00\x01':raise ValueError('Invalid BIT header')
        offset+=2
        for expected in b'abcde':
            if data[offset]!=expected:raise ValueError('Invalid BIT tag')
            offset+=1;width=4 if expected==ord('e') else 2
            size=int.from_bytes(data[offset:offset+width],'big');offset+=width
            if expected==ord('e'):
                if offset+size!=len(data):raise ValueError('Invalid BIT payload length')
                return data[offset:]
            offset+=size
        raise ValueError('Missing BIT payload')
    routed_bit=(output/'hardware/camera_sd.bit').read_bytes()
    if hashlib.sha256(routed_bit).hexdigest()!=manifest['bit_sha256']:raise SystemExit('Routed BIT failed build-manifest hash verification')
    if hashlib.sha256((output/'hardware/camera_sd.xsa').read_bytes()).hexdigest()!=manifest['xsa_sha256']:raise SystemExit('XSA failed build-manifest hash verification')
    with zipfile.ZipFile(output/'hardware/camera_sd.xsa') as z:
        bit=z.read('camera_sd.bit')

        if payload(bit)!=payload(routed_bit):raise SystemExit('XSA and routed BIT configuration payloads differ')
        hwh=z.read('camera_sd_system.hwh')
    if b'o_gray_base' not in hwh or b'i_base_address' not in hwh:raise SystemExit('Dynamic memory ports absent from HWH')
    audit=output/'pynq_cdc_audit.tcl'
    audit.write_text(r'''
open_checkpoint {@DCP@}
set base {.*preview_ddr/inst/reg_run_camera_reg}
set meta [get_pins -hier -regexp "${base}\\\[0\\\]/D"]
if {[llength $meta]!=1} {error "PYNQ first CDC receiving pin missing or ambiguous"}
set path [get_timing_paths -quiet -to $meta -max_paths 1]
# Explicit -to queries can return a False Path witness without SLACK in Vivado.
if {[llength $path]!=1 || [get_property EXCEPTION $path] ne "False Path"} {error "First CDC stage is not excepted"}
foreach {from to} {0 1 1 2} {
 set q [get_pins -hier -regexp "${base}\\\[$from\\\]/Q"]
 set d [get_pins -hier -regexp "${base}\\\[$to\\\]/D"]
 if {[llength $q]!=1 || [llength $d]!=1} {error "PYNQ CDC chain missing"}
 set path [get_timing_paths -quiet -from $q -to $d -max_paths 1]
 if {[llength $path]!=1 || ![string is double -strict [get_property SLACK $path]] || [get_property SLACK $path]<0} {error "Later CDC stage was waived or fails timing"}
}
puts "PYNQ_MEMORY_CDC_AUDIT_PASS"
'''.replace('@DCP@',manifest.get('final_checkpoint',(output/'project/screw_sort_ui.runs/impl_1/final_implemented.dcp').as_posix())),encoding='utf-8')
    with (ROOT/'build/reports/current/pynq_cdc_audit.log').open('w',encoding='utf-8') as log:
        subprocess.run([a.vivado,'-mode','batch','-source',str(audit),'-log',str(output/'pynq_cdc_audit.log'),'-nojournal'],cwd=output,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    if 'PYNQ_MEMORY_CDC_AUDIT_PASS' not in (ROOT/'build/reports/current/pynq_cdc_audit.log').read_text(encoding='utf-8'):raise SystemExit('PYNQ CDC audit failed')
    (ROOT/'board/hardware/screwsort.bit').write_bytes(bit)
    (ROOT/'board/hardware/screwsort.hwh').write_bytes(hwh)
    (ROOT/'board/hardware/screwsort.xsa').write_bytes((output/'hardware/camera_sd.xsa').read_bytes())
    sha=lambda b:hashlib.sha256(b).hexdigest()
    data={'status':'PASS','project':'screwsort','version':'1.0.0',
          'runtime_targets':['baremetal','linux'],'abi':'0x50594d32','hardware_id':'0x4d433138',
          'bit_sha256':sha(bit),'hwh_sha256':sha(hwh),'timing_ns':manifest['timing_ns'],
          'configuration_payload_sha256':sha(payload(bit)),'cdc_audit':'PASS',
          'routed_bit_sha256':sha(routed_bit),'xsa_sha256':manifest['xsa_sha256'],
          'resources':manifest['resources'],'build_directory':str(output),'board_tested':False}
    (ROOT/'board/hardware/hardware_manifest.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    contract_path=ROOT/'board/overlay_contract.json'
    contract=json.loads(contract_path.read_text(encoding='utf-8'))
    contract.update(bit_sha256=sha(bit),hwh_sha256=sha(hwh))
    contract_path.write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    reports=ROOT/'build/reports/hardware/implementation';reports.mkdir(parents=True,exist_ok=True)
    for report in (output/'hardware').glob('*.rpt'):shutil.copy2(report,reports/report.name)
    print('Shared MC18 hardware exported:',ROOT/'board/hardware/screwsort.bit')
