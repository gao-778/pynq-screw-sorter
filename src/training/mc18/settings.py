from pathlib import Path
import os
REPO_ROOT=Path(__file__).resolve().parents[3]
TRAIN_OUTPUT=Path(os.environ.get('SCREWSORT_TRAIN_OUTPUT',REPO_ROOT/'build/output/training')).resolve()
DATASET_INPUT=Path(os.environ.get('SCREWSORT_DATASET',REPO_ROOT/'data/training')).resolve()
TRAIN_OUTPUT.mkdir(parents=True,exist_ok=True)
