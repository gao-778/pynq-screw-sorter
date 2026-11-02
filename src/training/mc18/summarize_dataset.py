"""Project source and interface utilities."""
from settings import REPO_ROOT,TRAIN_OUTPUT,DATASET_INPUT
from pathlib import Path
from collections import Counter, defaultdict
import json

ROOT = Path(__file__).resolve().parent
OUT = TRAIN_OUTPUT
manifest = json.loads((OUT / 'fixed_split_manifest.json').read_text(encoding='utf8'))
trainval = json.loads((OUT / 'dataset_report_trainval.json').read_text(encoding='utf8'))
nut = json.loads((OUT / 'nut_screening_report.json').read_text(encoding='utf8'))
legacy = DATASET_INPUT/'output'
reports = [json.loads((legacy / name).read_text(encoding='utf8')) for name in
           ['dataset_report_trainval.json', 'dataset_report_test.json']]
photos = Counter(row['split'] for row in manifest['records'])
domains = defaultdict(Counter)
for row in manifest['records']:
    domains[row['lighting']][row['split']] += 1
instances = Counter()
for report in reports:
    for key, cell in report['cells'].items():
        instances[key.split('/')[0]] += cell['accepted']
for key, cell in nut['counts'].items():
    if key.split('/')[0] != 'quarantine':
        instances[key.split('/')[0]] += cell['accepted']
result = dict(raw_photographs=sum(photos.values()), photographs_by_split=dict(photos),
              photographs_by_domain={k:dict(v) for k,v in domains.items()},
              accepted_original_instances_by_split=dict(instances),
              trainval_roi_rows_by_family=trainval['sample_counts'],
              trainval_roi_rows=sum(trainval['sample_counts'].values()),
              note='An augmented ROI is not a photograph or independent physical instance. Test instance counts are annotation metadata; no test predictions used here.')
(OUT / 'dataset_card.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps(result, ensure_ascii=True))
