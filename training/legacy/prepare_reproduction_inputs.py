"""Pin small dependencies; never bundle raw datasets, caches or Python runtimes."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parent
DEST=ROOT/'reproducibility_inputs'
DEST.mkdir(exist_ok=True)
sources={
 'legacy/auto_obb_reference.py': ROOT.parent/'highlight_dual_training/support/auto_obb_reference.py',
 'legacy/shape_obb_reference.py': ROOT.parent/'highlight_dual_training/support/shape_obb_reference.py',
 'legacy/photometric_source.py': ROOT.parent/'highlight_dual_training/support/photometric_source.py',
 'legacy/adaptive_threshold_reference.py': ROOT.parent/'highlight_dual_training/scripts/adaptive_threshold_reference.py',
 'legacy/prepare_dataset.py': ROOT.parent/'highlight_dual_training/scripts/prepare_dataset.py',
 'legacy/fixed_split_manifest.json': ROOT.parent/'highlight_dual_training/inputs/fixed_split_manifest.json',
 'legacy/dataset_report_trainval.json': ROOT.parent/'highlight_dual_training/output/dataset_report_trainval.json',
 'legacy/dataset_report_test.json': ROOT.parent/'highlight_dual_training/output/dataset_report_test.json',
 'legacy_teacher.npz':ROOT.parent/'live_obb_hd_highlight_v2/model/quantized_model.npz',
 'head_selected.pt':ROOT/'output/training/head_selected.pt',
}
result={}
for name,src in sources.items():
    dst=DEST/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
    result[name]=dict(source=str(src),sha256=hashlib.sha256(src.read_bytes()).hexdigest(),bytes=src.stat().st_size)
(DEST/'manifest.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf8')
print('REPRODUCTION_SMALL_INPUTS',len(result))
