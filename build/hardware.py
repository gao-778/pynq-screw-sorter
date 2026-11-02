"""Generate and implement the shared Vivado design from RTL and BD Tcl."""

from pathlib import Path
import argparse, hashlib, json, os, re, shutil, subprocess

ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def tcl_path(path):
    value = path.as_posix()
    require(not any(c in value for c in '{}\n\r'), 'Tcl paths must not contain braces or newlines')
    return '{' + value + '}'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New short build directory outside this repository')
    parser.add_argument('--vivado', help='Vivado executable; otherwise XILINX_VIVADO/bin or PATH')
    parser.add_argument('--font-dir', type=Path, default=ROOT/'src/fpga/data')
    parser.add_argument('--external-rtl-dir', type=Path, default=ROOT/'src/fpga/rtl')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--allow-source-changes', action='store_true', help='Allow edited public source files; record build as modified, not the audited release')
    a = parser.parse_args()
    src = ROOT/'src/fpga'
    run = a.output.resolve()
    require(not run.exists(), 'Output must be a new directory; existing work is never reset')
    require(not run.is_relative_to(ROOT), 'Output must be outside this repository')
    manifest = json.loads((src/'source_manifest.json').read_text(encoding='utf8'))
    inputs = {}
    modified = []
    for item in manifest['rtl'] + manifest['constraints'] + manifest['scripts']:
        file = src/item['path']
        require(file.is_file(), 'Required public hardware source missing: ' + item['path'])
        inputs[item['path']] = sha(file)
        if inputs[item['path']] != item['sha256']:
            modified.append(item['path'])
    require(not modified or a.allow_source_changes, 'Packaged FPGA sources differ from the release manifest: ' + ', '.join(modified) + '; use --allow-source-changes for an explicitly modified build')
    external = {}
    for category, directory in [('external_rom', a.font_dir), ('external_rtl', a.external_rtl_dir)]:
        for item in manifest[category]:
            file = directory/item['filename']
            require(file.is_file(), 'Missing local dependency: ' + str(file) + '. See docs/local-dependencies.md and import_local_dependencies.py; external assets are not redistributed.')
            require(sha(file) == item['sha256'], 'Local asset SHA256 differs from the expected release: ' + str(file))
            external[item['filename']] = sha(file)
    if not a.vivado:
        install = os.environ.get('XILINX_VIVADO')
        a.vivado = str(Path(install)/'bin'/('vivado.bat' if os.name == 'nt' else 'vivado')) if install else (shutil.which('vivado.bat') or shutil.which('vivado'))
    require(bool(a.vivado), 'Pass --vivado or configure XILINX_VIVADO/PATH')
    
    
    (run/'project').mkdir(parents=True)
    local = run/'hardware_sources'
    for relative in inputs:
        dst = local/relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src/relative, dst)
    for item in manifest['external_rtl']:
        shutil.copyfile(a.external_rtl_dir/item['filename'], local/'rtl'/item['filename'])
    (local/'data').mkdir()
    for item in manifest['external_rom']:
        name = item['filename']
        shutil.copyfile(a.font_dir/name, local/'data'/name)
        shutil.copyfile(a.font_dir/name, run/'project'/name)
    def launch(tcl, name):
        with (run/(name+'.console.log')).open('w', encoding='utf8') as log:
            subprocess.run([a.vivado, '-mode', 'batch', '-source', str(tcl), '-log', str(run/(name+'.log')), '-nojournal'],
                           cwd=run, stdout=log, stderr=subprocess.STDOUT, check=True)
    lines = ['set build_output_root ' + tcl_path(run), 'set hardware_source_root ' + tcl_path(local)]
    lines.append('set rtl_files {' + ' '.join(x['path'] for x in manifest['rtl']) + ' ' + ' '.join('rtl/'+x['filename'] for x in manifest['external_rtl']) + '}')
    entries = ['{' + x['path'] + ' ' + str(int('synthesis' in x['used_in'])) + ' ' + str(int('implementation' in x['used_in'])) + '}' for x in manifest['constraints']]
    lines.append('set constraint_entries {' + ' '.join(entries) + '}')
    lines.append('set rom_files {' + ' '.join(x['filename'] for x in manifest['external_rom']) + '}')
    lines.append('source ' + tcl_path(local/'tcl/create_project.tcl'))
    prep = run/'prepare.tcl'
    prep.write_text('\n'.join(lines)+'\n', encoding='utf8')
    launch(prep, 'prepare')
    require('MC18_OPEN_SOURCE_PREPARE_PASS' in (run/'prepare.log').read_text(encoding='utf8', errors='replace'), 'Vivado preparation did not report success')
    files = {str(Path(f).relative_to(run)):sha(Path(f)) for f in (run/'source_audit.txt').read_text(encoding='utf8').splitlines()}
    require(all(sha(src/name) == digest for name,digest in inputs.items()), 'Public sources changed during preparation')
    result = dict(status='PREPARED', hardware_access=False, source_inputs_sha256=inputs,
                  source_files_sha256=files, external_assets_sha256=external,
                  modified_public_sources=modified, baseline_source_match=not modified,
                  verification_scope='BD/IP regeneration and compile-source closure; no timing or hardware claim',
                  rebuild_script_sha256=sha(Path(__file__)), project=str(run/'project/screw_sort_ui.xpr'))
    (run/'rebuild.json').write_text(json.dumps(result,indent=2), encoding='utf8')
    if a.prepare_only:
        print('MC18_OPEN_SOURCE_PREPARE_PASS')
        return
    boiler=(run/'hardware_sources/tcl/vivado_appinit.tcl').read_text(encoding='utf8')
    for stage in ('synth_1','impl_1'):
        folder=run/'project/screw_sort_ui.runs'/stage
        script=boiler+'\ncd {'+folder.as_posix()+'}\nsource {'+(folder/'camera_sd_system_wrapper.tcl').as_posix()+'}\n'
        if stage=='impl_1':
            script+='''
source {@RUN@/hardware_sources/tcl/check_classcolor_cdc.tcl}
report_bus_skew -warn_on_violation -file multiclass_bus_skew.rpt
report_timing -from $color_source -to $color_meta -max_paths 27 -nworst 1 -file classcolor_payload_timing.rpt
report_utilization -file multiclass_utilization.rpt
report_timing_summary -file multiclass_timing.rpt
report_methodology -file multiclass_methodology.rpt
report_drc -file multiclass_drc.rpt
foreach delay {max min} {
 set paths [get_timing_paths -delay_type $delay -max_paths 1]
 if {[llength $paths]!=1 || [get_property SLACK $paths]<0} {error "Timing not closed: $delay"}
}
write_checkpoint -force final_implemented.dcp
write_hw_platform -fixed -include_bit -force -file camera_sd.xsa
'''
        script=script.replace('@RUN@',run.as_posix())
        script+='\nputs "MC18_PORTABLE_'+stage+'_PASS"\n'
        tcl=run/(stage+'.tcl');tcl.write_text(script,encoding='utf8');launch(tcl,stage)
        assert 'MC18_PORTABLE_'+stage+'_PASS' in (run/(stage+'.log')).read_text(encoding='utf8',errors='replace')
    impl=run/'project/screw_sort_ui.runs/impl_1'
    
    target=run/'hardware';target.mkdir(exist_ok=True)
    timing=(impl/'multiclass_timing.rpt').read_text()
    summary=timing.split('WNS(ns)',1)[1]
    row=next(line for line in summary.splitlines() if re.match(r'^\s*-?\d+\.\d+\s+',line));cells=row.split()
    timing_ns=dict(wns=float(cells[0]),tns=float(cells[1]),whs=float(cells[4]),ths=float(cells[5]))
    assert timing_ns['wns']>=0 and timing_ns['whs']>=0 and timing_ns['tns']==timing_ns['ths']==0
    coverage=(impl/'multiclass_timing_coverage.rpt').read_text()
    count=lambda name:int(re.search(r'checking '+name+r' \((\d+)\)',coverage).group(1))
    assert count('no_clock')==count('unconstrained_internal_endpoints')==0
    clocks={line.split('\t')[0]:float(line.split('\t')[1]) for line in (impl/'multiclass_clocks.tsv').read_text().splitlines()}
    assert len(clocks)==7 and clocks['clk_fpga_0']==10.0
    margins=re.findall(r'Slack \((MET|VIOLATED)\)\s*:\s*([-\d.]+)ns',(impl/'multiclass_bus_skew.rpt').read_text())
    assert len(margins)==8 and all(state=='MET' and float(value)>=0 for state,value in margins)
    util=(impl/'multiclass_utilization.rpt').read_text();resources={}
    for key,title in [('lut','Slice LUTs'),('ff','Slice Registers'),('slices','Slice'),('bram','Block RAM Tile'),('dsp','DSPs')]:
        row=re.search(r'^\| '+re.escape(title)+r'\s+\|([^\n]+)',util,re.M)
        cells=[v.strip() for v in row.group(1).split('|') if v.strip()]
        resources[key]=dict(used=float(cells[0]),total=float(cells[3]),available=float(cells[3]),percent=float(cells[4]))
        assert resources[key]['used']<=resources[key]['total']
    shutil.copy2(impl/'camera_sd_system_wrapper.bit',target/'camera_sd.bit');shutil.copy2(impl/'camera_sd.xsa',target/'camera_sd.xsa')
    for path in impl.glob('multiclass_*.rpt'):shutil.copy2(path,target/path.name)
    shutil.copy2(impl/'classcolor_payload_timing.rpt',target/'classcolor_payload_timing.rpt')
    manifest=dict(status='PASS',hardware_access=False,project=str(run/'project/screw_sort_ui.xpr'),
        bit_sha256=sha(target/'camera_sd.bit'),xsa_sha256=sha(target/'camera_sd.xsa'),timing_ns=timing_ns,resources=resources,
        timing_coverage=dict(status='PASS',no_clock=0,unconstrained_internal_endpoints=0,fclk0_period_ns=10.0,clocks_period_ns=clocks),
        bus_skew=dict(status='PASS',constraints=8,minimum_slack_ns=min(float(v) for _,v in margins)),
        source_sha256={path.name:sha(path) for path in (run/'hardware_sources/rtl').iterdir() if path.is_file() and path.suffix in ('.v','.vh','.hex','.mem')},
        source_closure_sha256={str(Path(name).relative_to(run)):sha(Path(name)) for name in (run/'source_audit.txt').read_text().splitlines()},
        board_test='NOT_RUN')
    (target/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    result.update(status='PASS',bit_sha256=sha(impl/'camera_sd_system_wrapper.bit'),xsa_sha256=sha(impl/'camera_sd.xsa'),board_test='NOT_RUN')
    (run/'rebuild.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    print('MC18_OPEN_SOURCE_BUILD_PASS')

if __name__ == '__main__':
    main()
