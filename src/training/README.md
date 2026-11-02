# MC18 训练与导出

安装 mc18/requirements.txt 中的依赖。mc18/model_contract.py 定义网络、QAT 和整数参数；mc18/train_model.py 负责训练与验证集选模；mc18/export_model.py 负责整数参考比对和 FNET/HEX/NPZ/C 头导出。

## 输入与输出

- data/training/：使用者提供的照片、标注、分组清单与已准备的螺丝数据。
- mc18/reproducibility_inputs/teacher.npz：教师模型。
- build/output/training/dataset_trainval.npz：训练与验证 ROI、标签及划分。
- build/output/training/dataset_test.npz：独立测试 ROI。
- build/output/training/training/：训练进度与选定模型。
- data/model/：导出的部署模型。

通过环境变量 SCREWSORT_DATASET 和 SCREWSORT_TRAIN_OUTPUT 指定数据与输出目录。原始照片不随源码分发；运行冻结模型无需安装训练依赖或提供照片。

## 使用

```bash
python src/training/mc18/prepare_reproduction_inputs.py
python src/training/mc18/train_model.py --device cuda --epochs 24 --batch 64
python src/training/mc18/freeze_validated_progress.py --minimum-completed 3
python src/training/mc18/export_model.py --publish
python src/training/mc18/export_model.py --evaluate --device cuda
```

准备原始照片时，先按 data/training/README.md 的输入布局提供固定分组和螺母场景清单，再运行 prepare_data.py --initialize 与 prepare_data.py。测试划分仅在选模和冻结完成后生成并评估。导出 shape_model.h 后复制至 src/common/shape_model.h，并运行根目录验证命令。
