# 验证状态与复现检查

维护者于 2026-11-03 明确确认：本 GitHub 版本由已上板验收通过的文件整理。公开整理不修改模型、RTL、标定和机械臂核心。该确认记录在 [board_acceptance_20261103.json](board_acceptance_20261103.json)，本轮电脑端复现检查另列记录；不将维护者实机结果冒称为本次自动复测。

## 证据分层

本次发布整理没有改动 CNN、RTL、机械臂运动参数或共享 C 应用。新的 GitHub 检查、打包和文档修订应使用本轮发布回归记录说明；历史实现和实机记录保留原有含义。

| 层次 | 记录 | 能说明什么 |
|---|---|---|
| 本轮复现复核 | [reproduction_review_20261103.json](reproduction_review_20261103.json) | 干净源码、126 项依赖导入、同版 HWH、10 组主机检查、ARM 共享库和裸机 ELF/BOOT 重建 |
| 首次发布整理复核 | [publication_review_20261103.json](publication_review_20261103.json) | 本轮实际完成的检查及未执行项目，独立于原归档结果 |
| 归档与文件对应 | `build/release_manifest.json`、`report/correspondence.json` | 发行范围内文件、模型、软件和硬件记录的对应关系 |
| 原统一包离线回归 | `sim/results/`、[validation.json](validation.json) | API、状态机、串口、坐标、内存/RTL 等列出的测试结果 |
| 原统一包编译/工程生成 | `build/reports/` | 既有 ARM 编译、BOOT 构建及工程生成；不代表本轮完整重新实现 |
| 配套硬件既有实现 | `build/reports/hardware/` | 特定位流的资源和时序报告；不能直接推广到自行更改后的设计 |
| 参考系统实机 | `reference_hardware_sessions` | 维护者确认的既有裸机/PYNQ fix 实机联调记录 |
| GitHub 整理版的上板依据 | `board_acceptance_20261103.json` | 维护者确认所用基线已验收通过；文件对应及实际证据范围单独列明 |

`full_implementation_this_release: NOT_RUN` 表示原统一包本次未完整重跑实现。Notebook 中示例没有执行输出，可以用于教学和调试，不能当作板上成功截图或日志。离线验证不会控制实际机械臂。

## 先做不接板检查

```bash
python build/verify.py
python -m unittest discover -s sim/tests -p test_release_packaging.py -v
# 补齐本地依赖和同版 HWH 后，再运行完整主机回归
python sim/run_checks.py --cc /path/to/gcc
```

硬件完整重建需要 AMD 工具、匹配依赖和独立输出目录。`--prepare-only` 成功仅表示工程生成，不能写为综合、实现和时序均已重跑通过。未经修改的旧运行产物可以保留，但应标明来源和哈希。

## 在另一装置上复现的检查步骤

1. **固定文件与环境。** 记录 Git 提交、发行清单、BOOT 或 BIT/HWH 的 SHA-256、模型 ID；记录板卡和外设。PYNQ 另记 SD 镜像来源/版本、Linux 内核、Python、PYNQ、NumPy、gcc 版本和 Jupyter 使用的解释器路径。
2. **仅视觉启动。** 先停用机械臂运动，启动相机、预览和识别；核对 18 类映射、12 目标容量、完整画面及坐标方向。持续记录异常、实际新帧率、识别频率和服务间隔，三者分别计量。
3. **会话生命周期。** 在 PYNQ 中正常 `close()`，然后新建对象再次启动；再测试识别期间取消。关闭应成功排空并释放缓冲区，没有重复占用、坏帧持续累积或工作线程错误。若关闭报排空失败，保留诊断并按错误提示处理，不能强行释放仍在访问的内存。
4. **核对机械参数再启用运动。** 验证平台坐标、标定、底座位置、拾取高度和四个投放点。按单目标、单类别、自动分拣的顺序测试；每种操作记录尝试数、成功数和失败原因。螺母不进入抓取队列。
5. **验证动作前后识别。** 运动期间暂停分类；动作结束后使用新帧确认下一目标，不能沿用旧位置。再测试停止和失败后的恢复行为。
6. **保存最终证据。** 用本次文件重新完成冷启动和连续运行，保存原始日志、带执行输出的 Notebook、短视频及环境信息。用这些记录关联实际文件与现场结果。

板上先记录软件环境；该命令只读取环境，不加载 Overlay、不触发机械臂：

```bash
mkdir -p board/output
python3 board/environment.py > board/output/environment.json
```

镜像下载文件名/发行号仍需手动补充；环境探测不能自动证明某个镜像已经完整验收。识别证据可通过已有脚本采集：

```bash
python3 board/capture_evidence.py --seconds 60 --label recognition
```

输出在 `board/output/<时间>/`，含环境和逐次观测记录；该脚本不启用机械臂运动。`COMPLETED` 表示脚本完成，不自动等价于分类准确率或抓取成功率达标。分类准确率需人工真值、样本量和统计口径，不能用模型自己的预测充当标签。

## 技术报告建议口径

可以表述为“裸机 C 与 PYNQ/Linux 共享业务核心，新增 Python/Jupyter 调试和复现入口，PL 执行图像处理与 CNN”。同时注明“公开源码基于维护者已验收通过版本整理”，并分别引用上板确认与本轮可重复的离线检查。

不把 HDMI 60 Hz 扫描写成相机 60 fps，不把旧参考相机约 11.67 fps 写成本统一版本的最新测量，也不把历史资源/时序和完整主机回归写成本轮重新综合实现或整机测试。
