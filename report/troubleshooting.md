# 常见问题与排查

本页针对当前统一工程的脚本、接口和实际复现中遇到的问题。先记录运行方式、源码提交、完整错误文本，以及错误发生在“文件检查、编译、启动、识别、运动、关闭”哪个阶段，再定位对应条目。

系统基于维护者已验收通过的文件整理。换一个源码目录、工具链、Linux 镜像或物理装置后，仍应核对相应条件；原基线的验收来源见 [验收记录](board_acceptance_20261103.json)，本轮电脑端复现结果见 [复现核验](reproduction_review_20261103.json)。

## 先收集最少的信息

| 所处阶段 | 优先保留 |
|---|---|
| 公开源码或依赖导入 | 提交编号、`build/verify.py` 输出、导入器报错的具体文件名 |
| 主机回归 | `sim/output/summary.json` 和失败任务的 `.log` |
| 编译或打包 | `build/output/` 下对应任务的编译、链接或 Bootgen 日志 |
| PYNQ 板上 | `board/environment.py` 输出及 `status()`、`metrics()`、`messages()` |
| 裸机板上 | 当前 SD 卡的 `RUNLOG.TXT`，实际 BOOT 哈希 |
| 分类或定位问题 | 原始照片、真实型号、目标姿态、显示坐标及现场位置 |

## 1. GitHub 文档在哪里？为什么只有源码没有 BOOT？

说明文件按用途放在各目录中：

- [复现操作手册](quickstart.md)：从获取源码到两种启动方式。
- [系统架构](architecture.md)：PS/PL 和数据通路。
- [硬件接线](hardware_setup.md)：相机、摇杆、舵机和装置配置。
- [Python API](python_api.md)、[Notebook](../board/notebooks/screwsort.ipynb)：PYNQ 交互入口。
- [训练说明](../src/training/README.md)、[模型说明](../data/model/README.md)、[标定说明](../data/calibration/README.md)。

公开源码按许可范围排除部分本地输入和部署二进制。源码 ZIP 不等于完整 SD 卡镜像；仅克隆仓库不能直接得到裸机 BOOT 或可加载的完整 Overlay。需要兼容完整包，或取得合法依赖并按构建流程重建。完整边界见 [复现矩阵](reproducibility.md)。

## 2. `verify.py` 显示 PASS，同时又列出缺失依赖

这是 `distribution: source` 的正常行为。`PASS` 表示公开发行范围内的文件、模型和契约一致；`local_dependencies_to_supply` 列出的 126 项输入仍需在完整构建前提供。

先确认 `errors` 是空列表，再看你要进行的下一步。独立发布测试不需要板卡及这些运行依赖；完整主机回归、Linux 库或 BOOT 构建需要相应输入。不要用修改发行清单的方式让真实缺件“消失”。

## 3. 导入器报告 `Missing dependency`、`Different dependency` 或拒绝覆盖

导入器按清单逐项读取输入并验证 SHA-256，不以“文件名相同”作为版本一致的依据。

| 报错 | 含义 | 检查顺序 |
|---|---|---|
| `Missing dependency in unified or legacy release` | 指定目录下找不到清单中的文件 | 确认 `--release` 指向解压后的 `screwsort`，检查完整包是否确实包含该文件 |
| `Different dependency` | 来源文件的内容与本工程要求不同 | 核对完整包版本与哈希，不使用另一工程的同名文件 |
| `Refusing to replace an existing different dependency` | 工作副本已存在内容不同的输入 | 保存现有修改，使用新的干净工作副本导入，或明确审查差异后再决定如何迁移 |

导入器会先核验整个输入集合，核验通过后才复制。不要通过直接修改 `dependencies.json` 的哈希来把错误输入改成“通过”。

## 4. 126 项依赖已导入，但三个 `MetadataTests` 失败

检查是否出现 `board/hardware/screwsort.hwh` 的 `FileNotFoundError`。这是本轮真实复现中确认过的前置条件遗漏：`build/import_dependencies.py` 导入构建输入，**不自动复制 BIT/HWH/XSA**，而完整 Python API 回归要解析同版 HWH。

从同一完整包补齐 `board/hardware/`，核对 [Overlay 契约](../board/overlay_contract.json) 和 [文件对应](correspondence.json)，再执行：

```bash
python build/verify.py
python sim/run_checks.py --cc /path/to/gcc
```

不要创建空 HWH 或拿其他工程的 HWH 让文件检查通过。公开发行的 21 项测试不需要这些硬件文件，可独立执行。

## 5. Windows 测试出现临时目录 `PermissionError` / `WinError 5`

本轮在受限执行环境中遇到过临时目录读写或清理被拒绝，换到具有正常临时目录权限的本机环境后，原源码测试通过。

先看出错路径是否位于系统临时目录，以及失败是否发生在创建、读写或清理测试文件时。确认当前账户对自己的临时目录有读写权限，关闭占用该文件的工具，再在正常终端重跑失败测试。不要关闭测试断言，也不要把权限异常归因于 FPGA 算法。

可先用不访问硬件的发布工具测试确认环境：

```bash
python -m unittest discover -s sim/tests -p test_release_packaging.py -v
```

## 6. 找不到 gcc，或者 Windows 上直接执行 `linux` 构建被拒绝

`build/build.py linux` 默认编译当前系统的共享库。Windows 上必须明确选择电脑测试 `--host` 或 ARM 交叉编译 `--cross`；PYNQ 板上直接使用本机 gcc。

```powershell
# Windows：电脑端测试库
python build/build.py linux --host --cc C:/mingw64/bin/gcc.exe
```

```bash
# PYNQ 板上：实际 ARM 运行库
python3 build/build.py linux
```

本机没有 `gcc` 时，`--cc` 应指定真实编译器路径；命令里的 `C:/mingw64` 只是示例。Windows 主机 DLL、桌面 Linux 的 x86 共享库都不能加载到 PYNQ 的 ARM 进程。

## 7. 裸机构建提示 BSP、FSBL、ELF 或 BIT 缺失

按依赖顺序检查：

1. `build/local/bsp/include/xparameters.h` 存在，且 BSP 对应本版硬件。
2. `build/local/fsbl.elf` 已导入，或通过 `boot --fsbl` 指定匹配文件。
3. 先运行 `baremetal --vitis <Vitis安装目录>`，确认生成 `build/output/baremetal/screwsort.elf`。
4. 准备同版 `board/hardware/screwsort.bit`，再运行 `boot --vitis <Vitis安装目录>`。

`boot` 负责打包，不会替你先编译一个不存在的 ELF。重建后检查 `board/baremetal/manifest.json` 与 `build/output/boot/bootgen.log`。原始 BOOT 和重建 BOOT 分别记录哈希；文件哈希不同要分析来源，不能直接改原记录。

## 8. PYNQ 找不到 `screwsortmint`、`pynq` 或共享库

| 现象 | 首先检查 |
|---|---|
| `No module named screwsortmint` | 自己写的 Python 入口是否把工程 `src/python` 加入 `sys.path`；`board/run.py` 和配套 Notebook 已提供入口处理 |
| `No module named pynq` / `numpy` | 运行的是不是板上正确 Python/Jupyter 环境；不要将桌面电脑 Python 当作板上环境 |
| 提示先运行 `build/build.py linux` | `build/output/linux/libscrewlab.so` 是否已经在板上编译 |
| `wrong ELF class`、架构或动态加载错误 | 是否误用了 Windows DLL、x86 库或不匹配的 ARM 编译产物 |

先运行 `python3 board/environment.py`，记录解释器、依赖和平台。Notebook 可打印 `sys.executable`，与终端使用的解释器对照。默认实例会在 `build/output/linux/libscrewlab.so` 找库；交叉编译输出的 `linux_cross` 目录不会自动替代默认目录。

## 9. `prepare()` 报 BIT/HWH、地址、ABI 或模型容量不匹配

这些检查发生在开始识别前，用于拒绝错误的软硬件组合。

| 报错关键词 | 常见原因 | 处理依据 |
|---|---|---|
| `Build ... bit and matching ... hwh first` | 缺少文件或命名不配套 | 准备同一导出版本、同名的 `screwsort.bit` 与 `screwsort.hwh` |
| `HWH does not describe the expected MMIO region` | HWH 中地址或窗口大小与当前契约不一致 | 核对 `overlay_contract.json` 的七个地址窗口 |
| `legacy fixed-DDR bitstream` | 加载了早期固定 DDR 位流 | 使用当前动态基址 Overlay，ABI 为 `0x50594d32` |
| `Recognition hardware/model capacity mismatch` | 硬件 ID、MC18 或 12 目标容量不符 | 核对同版位流、18 类模型、软件与契约 |

不要删掉 ABI/容量判断来让程序继续。旧固定地址设计和 PYNQ 动态内存所有权的区别会直接影响 DDR 访问。

## 10. 连续内存分配失败或提示 DMA 缓冲区不符合要求

PYNQ 会分配三块独立缓冲区，容量见 [Overlay 契约](../board/overlay_contract.json)，分别为 4 MiB、768 KiB、3,686,400 字节。软件检查对齐、地址范围和互不重叠。

查看 `board/environment.py` 输出中的 `CmaTotal`、`CmaFree`，确认前一个会话是否正常关闭，是否还有其他进程占用 Overlay 或连续内存。先释放已经确认空闲的正常会话，再创建新对象。不要将电脑虚拟地址或裸机固定地址直接填给 Linux 下的 DMA。

## 11. `Another ScrewSortMint session owns this overlay`

同一时刻只能有一个应用会话控制这套 Overlay。检查是否同时运行 `board/run.py` 和 Notebook，或前一个 Notebook 会话仍然存在。

在原会话中完成 `stop()` / `close()`，确认返回成功，再创建新的 `ScrewSortMint()`。关闭后的同一个对象不能重新 `prepare()`；接口会提示新建实例。不要只删除锁文件来假定原进程已经停止访问硬件。

## 12. 屏幕无画面、只有界面，或者有画面但识别数量为零

先区分显示通路、相机通路和识别通路：

- **显示器没有信号：** 检查 HDMI 连接、显示器输入源和实际启动文件版本。
- **可以看到界面但相机区黑屏：** 显示输出已部分工作，继续看相机初始化、帧计数和 DMA 状态；核对当前 [相机接线](hardware_setup.md)，不先改 CNN 权重。
- **相机有新画面但目标为零：** 查看原始画面是否符合前景/背景、清晰度及目标分离条件，检查是否正处于运动期间的识别暂停。
- **运动结束仍不恢复：** 保留 `status()`、事件及日志，检查任务终态与新场景确认，不能只凭一张静态屏幕图判断。

HDMI 扫描刷新、相机新帧和识别完成频率不是同一个指标。历史约 11.67 fps 的相机记录不能当作任意重建版本或任何曝光条件下的保证值。

## 13. 型号跳动、框变化或同一零件换姿态后分类变化

先保存原始照片并记录真实型号，检查目标是否接触、反光过曝、虚焦、被机械臂遮挡，或相机/平台位置已改变。当前分类输入来自相机灰度 ROI；显示屏看起来清楚，不等于 ROI 中仍保留足够的型号差异。

区分三个问题：前景检测影响候选框，旋转 ROI 与几何特征影响输入一致性，CNN 输出与跨帧策略影响类别稳定性。先确认是哪一步变化，再讨论阈值、训练增强或稳定逻辑；不能把抖动统一当成“参数量太小”。

测试准确率必须提供人工真实类别和样本量。保留困难样本，按 [训练说明](../src/training/README.md) 对齐预处理与类别顺序，再考虑重训，不要把当前预测直接当作新标签。

## 14. 能看到坐标，但机械臂不动作或落点偏移

PYNQ 默认不允许运动。确认已调用 `enable_motion()`，之后才请求 `pick()`、`auto_pick()` 或 `sort_all()`。方法返回仅代表请求进入控制流程，实际进度看 `status()` 和 `messages()`。

螺母设计为只识别、定位和统计，不进入抓取队列。另检查是否选中了真实存在的可抓取目标，是否处于停止/失败状态，机械臂独立电源是否正常，以及当前相机标定、底座位置与料框坐标是否对应实际装置。

落点偏移时同时记录屏幕毫米坐标和实际夹爪落点。换相机位置或机械臂底座后，按 [标定教程](../data/calibration/README.md) 更新坐标对应关系；不要未经确认就把显示坐标、运动补偿和箱位一起平移。

## 15. 抓取报告目标刷新、路径不可达或总线错误

| 错误类别 | 应先区分的事实 | 下一步 |
|---|---|---|
| `TARGET REFRESH TIMEOUT`、目标过期 | 相机是否有新帧，目标是否移动/遮挡，是否完成动作后新场景确认 | 保存时间、状态、目标记录及事件，不重复使用旧坐标绕过刷新 |
| `PLAN`、`UNREACHABLE` | 目标坐标、夹取姿态、完整路径及装置几何是否一致 | 核对标定、底座位置和运动配置；手动能掰到一点不等于整条规划路径可执行 |
| `BUS_RESULT`、`RX_TIMEOUT`、`ARRIVAL` | 错误舵机 ID、动作阶段、收发事务或到位条件 | 保存原始日志，检查独立电源、共地、半双工收发及该舵机反馈；不把所有错误都当作“等待时间太短” |

排查资料见 [硬件安装](hardware_setup.md)、[串口诊断 Skill](../skill/servo-bus-diagnostics/SKILL.md) 和 [视觉/动作协调 Skill](../skill/vision-motion-gating/SKILL.md)。这些是诊断方法；当前 GitHub 文档扩充不会暗中改变原有机械臂参数。

## 16. `close()` 失败，能不能直接释放缓冲区或重载位流？

`close()` 会等待运动、后台服务以及已接受的 AXI/DMA 事务排空。如果报告停止或排空失败，接口会保留缓冲区所有者引用，避免 PL 继续访问已经释放的内存。

保留错误、状态和事件，处理设备状态后再尝试关闭；按实际错误提示恢复或重启板卡。不要把强制释放内存、删除锁文件、重载 Overlay 当作“已正常关闭”。正常关闭后，新建对象开始下一会话。接口语义见 [Python API](python_api.md)。

## 17. 修改文件后，发行清单检查失败

先确认差异是预期修改，而不是混入不同版本文件或丢失依赖。`build/verify.py` 的文件哈希检查用于发现这种差异。完成代码、接口及所需测试后，才更新你自己的发行清单：

```bash
python build/package.py --refresh
python build/verify.py
python build/package.py --public --output /path/outside/project/new_source.zip
```

输出 ZIP 路径必须在工程之外且尚不存在。`--refresh` 只更新清单，不会验证算法、让缺件自动出现或证明新硬件已经通过实测。保留新版本提交编号、产物哈希和对应验证记录，便于回退和复现。
