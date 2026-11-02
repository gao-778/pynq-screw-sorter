"""Project source and interface utilities."""
from pathlib import Path
import argparse,subprocess,os,json
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--vivado-bin',required=True);args=p.parse_args()
out=root/'sim/output/rtl';out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['PROCESSOR_ARCHITECTURE']='AMD64'
bin=Path(args.vivado_bin);suffix='.bat' if os.name=='nt' else ''
test=root/'sim/tests/tb_pynq_memory.v';top='tb_pynq_memory';passed='PASS PYNQ_MEMORY'
commands=[['xvlog',str(root/'src/fpga/rtl/preview_area_average.v'),str(root/'src/fpga/rtl/ddr_gray_reader.v'),str(root/'src/fpga/rtl/ddr_preview.v'),str(test),str(bin.parent/'data/verilog/src/glbl.v')],
 ['xelab',top,'glbl','-L','xpm','-L','unisims_ver','-s',top,'--debug','typical'],
 ['xsim',top,'-runall']]
report={'hardware_access':False,'commands':[]}
for command in commands:
    name=command[0];command[0]=str(bin/(name+suffix))
    run=subprocess.run(command,cwd=out,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace')
    log=run.stdout+run.stderr;(out/f'{name}_console.log').write_text(log,encoding='utf-8')
    report['commands'].append({'command':command,'returncode':run.returncode})
    (out/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    if run.returncode:print(log[-4000:]);run.check_returncode()
    print(name,log[-700:])
    if name=='xsim' and (passed not in log or 'Fatal:' in log):raise RuntimeError('RTL assertions failed; inspect simulation log.')
report['status']='PASS';(out/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
