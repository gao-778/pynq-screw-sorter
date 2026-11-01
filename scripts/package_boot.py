"""Create a local BOOT only; this does not program the board or write an SD."""
from pathlib import Path
import argparse,json,shutil,subprocess
from datetime import datetime
from project_common import ROOT,read,sha,require,materialize_software
from boot_format import verify_boot
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--vitis-root',type=Path,required=True)
 a=p.parse_args();record=read(ROOT/'build/firmware.json');elf=ROOT/record['elf']
 require(sha(elf)==record['elf_sha256'],'ELF changed since build')
 src=materialize_software()
 require({f.name:sha(f) for f in src.glob('*.[ch]')}==record['source_sha256'],'Source changed; rebuild software')
 # This path intentionally uses the accepted baseline hardware. A new bitstream
 # needs a separate hardware/ABI review before swapping it into this package.
 files={'fsbl.elf':ROOT/'external/firmware/fsbl.elf','camera_sd.bit':ROOT/'external/hardware/camera_sd.bit','app.elf':elf}
 deps=read(ROOT/'config/local_dependencies.json')['files']
 for name in ('firmware/fsbl.elf','hardware/camera_sd.bit'):
  require(sha(ROOT/'external'/name)==deps[name]['sha256'],'Hardware/FSBL differs from baseline')
 run=ROOT/'build/boot'/datetime.now().strftime('%Y%m%d_%H%M%S_%f');run.mkdir(parents=True)
 for name,path in files.items():shutil.copy2(path,run/name)
 (run/'boot.bif').write_text('the_ROM_image:\n{\n [bootloader] fsbl.elf\n camera_sd.bit\n app.elf\n}\n')
 bootgen=a.vitis_root.resolve()/'bin/bootgen.bat'
 cmd=['cmd.exe','/d','/c',str(bootgen),'-arch','zynq','-image','boot.bif','-o','BOOT.BIN','-w','on']
 require(bootgen.is_file(),'Vitis Bootgen not found')
 result=subprocess.run(cmd,cwd=run,capture_output=True,text=True,encoding='utf8',errors='replace')
 (run/'bootgen.log').write_text(result.stdout+result.stderr,encoding='utf8');result.check_returncode()
 boot=run/'BOOT.BIN';parts=verify_boot(boot.read_bytes(),files['fsbl.elf'].read_bytes(),files['camera_sd.bit'].read_bytes(),elf.read_bytes())
 (run/'verification.json').write_text(json.dumps({'status':'PASS','boot_sha256':sha(boot),'partitions':parts,'hardware_access':False,'sd_written':False},indent=2))
 print('BOOT_PACKAGE_PASS',boot.relative_to(ROOT).as_posix())
if __name__=='__main__':main()
