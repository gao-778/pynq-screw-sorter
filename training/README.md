# 最终 MC18 训练源码

`legacy/` 保存与最终 18 类、255,912 参数模型有关的历史训练源文件。核心 Python 文件按原内容复制，便于审阅训练与量化逻辑；**这里不是已改造完成的“一次 clone 即完整重训”工具**。原始照片、标注清单、大型 NPZ 缓存、虚拟环境、下载轮子和运行日志没有复制进仓库。

## 源码入口

| 文件 | 作用 |
|---|---|
| `legacy/model_contract.py` | 网络结构、整数兼容量化、教师扩宽、数组导出 |
| `legacy/prepare_data.py` | 保持旧螺丝划分，分组筛选新增螺母，按硬件前处理形成训练/测试 ROI |
| `legacy/train_model.py` | 分类头/联合 QAT，验证保护门槛和最佳模型选择 |
| `legacy/warmup_nut_head.py` | 新螺母分类头量化预训练 |
| `legacy/freeze_validated_progress.py` | 从已完成的合格训练进度冻结模型 |
| `legacy/export_model.py` | 独立整数参考核对，导出 NPZ/HEX/FNET/C 头，冻结后测试 |
| `legacy/audit_latent_dither.py` | 检查浮点潜变量扰动没有改变初始化整数模型 |
| `legacy/generate_hardware_case.py` | 从已准备的数据生成硬件回归样例 |
| `legacy/finalize_training_reports.py` / `summarize_dataset.py` | 汇总训练与数据报告 |
| `legacy/prepare_reproduction_inputs.py` | 从旧工作树收集依赖；不会从互联网下载缺失数据 |
| `legacy/reproducibility_inputs/legacy/*.py` | 固定的阈值、OBB、裁剪和光照增强参考实现 |

复制来源、文件哈希、未公开依赖与最终权重证据在 [source_manifest.json](source_manifest.json)。这些脚本没有在本次开源整理中再次训练；检查仅包含内容哈希与 Python 语法解析。

## 与部署模型的关联

原训练目录的 `output/training/selected_candidate.pt` 与发布模型 `best_qat.pt` 字节完全相同，SHA-256 为：

`7778e099183dcc2e23537d170259b4c52a18f740febf3e11e63362384234ee17`

`export_model.py` 从该候选读取 `state_dict`，与 `selected_candidate.npz` 核对后输出参数。最终 `model.bin` SHA-256 为：

`334794129d1a22f804646550d26a5ec613a87c317f978a6852cc120449f08772`

导出 `shape_model.h` 与工程活动 PS 源码中的参数头哈希一致。完整结构、类别顺序和使用方式见 [模型文档](../docs/MODEL.md)。

## 尚需恢复的外部输入

原脚本保留历史目录关系，其 `ROOT` 是脚本所在目录，不是这个 Git 仓库的根目录。直接在 `training/legacy` 运行，脚本会找同级的历史训练/工程目录，目前不能找到全部输入。

```text
复现工作区/
├── multiclass_training_20261101/       # 将 legacy 源码放到这里
│   ├── classes.json
│   ├── label_mapping_status.json
│   ├── nut_scan.json                   # 未公开：原图路径与候选标注
│   ├── reproducibility_inputs/
│   │   ├── legacy_teacher.npz          # 未公开：冻结的旧 15 类教师
│   │   ├── head_selected.pt            # 未公开：已选择的头初始化
│   │   └── legacy/                     # 参考源码已提供；相关清单未提供
│   └── output/                        # 数据缓存、筛选/划分/选模报告
├── highlight_dual_training/            # 未公开：旧划分、旧缓存和原图树
│   ├── inputs/fixed_split_manifest.json
│   └── output/dataset_{trainval,test}.npz
└── live_obb_hd_multiclass_20261101/
    ├── architecture_contract.json      # 与当前 MC18 一致
    └── model/reference.py              # 使用当前独立整数参考
```

原始数据路径写在清单中，迁移时必须显式映射，保持图像内容和划分一致。只有最终 `best_qat.pt` 不足以复现全部训练历史：旧教师、头初始化、原图、分组/标注与增广缓存也是输入。清单内图像标签不能用当前模型预测替代。

公开的 `label_mapping_status.json` 只保留大中小螺母映射已确认这一事实，删除了交互记录标识，不用于声称新的数据已经确认。更换数据时要重新核对自己的标签。

## 记录的训练环境

历史环境为 Python 3.11、PyTorch 2.7.1+cu128；最终联合训练使用 CPU 四线程、严格 FP32，关闭 TF32、半精度和非确定性 cuDNN。`legacy/requirements.txt` 记录 NumPy、PyTorch、Pillow、OpenCV 的历史版本，不保证任意平台用默认 PyPI 索引即可安装相同 CUDA wheel。应按目标操作系统从各项目正式发布渠道安装匹配版本；本仓库不附运行时或 CUDA 安装包。

## 恢复输入后的执行顺序

只在独立副本运行下列历史命令，避免覆盖冻结模型。它们需要上一节列出的完整数据与依赖，不是对当前精简仓库可直接执行的承诺。

```powershell
python prepare_data.py --initialize
python train_model.py --device cpu --batch 64 --epochs 8 --stop-after 3 --min-epochs 3 --patience 2 --resume-head --conv-lr 0.000001 --head-lr 0.000001 --teacher-weight 3 --freeze-screw-head --latent-dither 0.45
python export_model.py --publish
python prepare_data.py --test
python export_model.py --evaluate --device cpu --batch 64
```

流程是先准备并冻结分组划分，恢复已选头模型，以三轮保守联合 QAT 比较验证表现，然后冻结合格候选、整数逐层核对、导出，最后评估测试集。`--epochs 8` 保留当时学习率调度，`--stop-after 3` 在三轮后结束；不表示最终训练了八轮。

使用新的数据集时，应保留独立测试场景，先匹配硬件预处理再考虑增广。不要为了提高测试数字反复用测试集选参。模型导出后仍需软件参数集成、硬件 ABI 核对、构建及板上验收，不是导出成功就等于完整机械臂系统已验证。
