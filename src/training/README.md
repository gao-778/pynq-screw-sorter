# MC18 训练与导出

完整步骤、字段说明和代码依据见 [模型训练与权重部署指南](../../report/model_training.md)。本目录提供原 MC18 的训练、QAT 和导出程序；原始照片、完整标注、固定划分及部分本地数据清单不随源码公开。运行已有部署模型无需安装训练环境。

## 输入与输出

- 安装 `mc18/requirements.txt` 的训练依赖。
- `data/training/`：由使用者提供真实照片、标注、固定分组与已准备的螺丝数据。
- `mc18/reproducibility_inputs/teacher.npz`：与原流程匹配的教师模型。
- `build/output/training/dataset_trainval.npz`：训练与验证 ROI、几何量、标签及划分。
- `build/output/training/dataset_test.npz`：选模冻结之后使用的独立测试数据。
- `build/output/training/training/`：训练进度、选定模型及冻结标记。
- `data/model/`：本地导出的部署参数。

通过 `SCREWSORT_DATASET` 和 `SCREWSORT_TRAIN_OUTPUT` 指定数据和输出目录。字段、lighting 域与增强族等前提见 [数据布局](../../data/training/README.md) 和 [完整训练指南](../../report/model_training.md)，不能用任意 NPZ 冒充原数据契约。

## 已有完整准备数据时

从工程根目录执行：

```bash
python src/training/mc18/prepare_reproduction_inputs.py
python src/training/mc18/train_model.py --device cuda --epochs 24 --batch 64
```

第一条命令只检查教师模型和训练 NPZ 是否存在，不从照片自动生成数据。训练正常完成后会生成 `VALIDATION_FROZEN.json`，用于锁定只由训练/验证阶段选出的结果。先保留原部署模型，再执行本地导出：

```bash
python src/training/mc18/export_model.py --publish
```

这里的 `--publish` 是写入本地 `data/model/`，不是上传 GitHub。模型冻结后，原测试数据与元数据齐全时，才生成并评估独立测试集：

```bash
python src/training/mc18/prepare_data.py --test
python src/training/mc18/export_model.py --evaluate --device cuda
```

`freeze_validated_progress.py` 和 `finalize_training_reports.py` 带有历史训练轮次、命令或结论整理逻辑，不能作为任意新数据的一键必跑步骤，也不能将旧指标当作新训练结果。

## 从原始照片准备数据

先按数据契约提供 `inputs/fixed_split_manifest.json`、已有螺丝 NPZ、真实图像和本地 `nut_scan.json`，再运行：

```bash
python src/training/mc18/prepare_data.py --initialize
```

该步骤会初始化划分并生成训练/验证数据，不需要紧接着重复无参数准备命令。照片标注、目标剔除、场景分组、前景阈值及旋转 ROI 必须与 [完整指南](../../report/model_training.md) 对齐；OBB 标签本身不是 CNN 的训练张量。

## 部署前检查

`model_contract.py` 定义网络与量化契约，`export_model.py` 导出 FNET、HEX、NPZ 和 C 头，并执行整数参考核对。新模型须同步 `src/common/shape_model.h`、类别与接口契约、构建摘要及部署产物，之后再核验文件清单、重建相应目标。不能只替换一个权重文件，也不能把任意网络或通用 YOLO 权重直接放入当前加速核。

详见 [完整部署检查顺序](../../report/model_training.md)；修改发布文件后，先验证实际内容，再刷新发行清单，不用刷新哈希来掩盖不匹配。
