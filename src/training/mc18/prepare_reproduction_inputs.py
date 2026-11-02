"""Project source and interface utilities."""
from settings import TRAIN_OUTPUT
from model_contract import teacher_path
def main():
    inputs=[teacher_path(),TRAIN_OUTPUT/'dataset_trainval.npz']
    missing=[str(p) for p in inputs if not p.is_file()]
    if missing:raise SystemExit('Required training inputs: '+', '.join(missing))
    print('TRAINING_INPUTS_READY')
if __name__=='__main__':main()
