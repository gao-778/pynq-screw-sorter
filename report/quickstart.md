# 从获取源码到运行：复现操作手册

这份手册按实际操作顺序说明：手头只有 GitHub 源码时能做什么，拿到配套完整包后如何补齐输入，以及如何分别运行裸机版和 PYNQ 版。系统基于维护者已上板验收通过的版本整理；本轮源码、依赖导入、主机回归及目标编译记录见 [复现核验](reproduction_review_20261103.json)，验收来源见 [验收记录](board_acceptance_20261103.json)。

**先选路径，再执行命令。** 裸机和 PYNQ 使用同一套识别核心，但 SD 卡启动方式不同。仅研究算法或跑离线测试时，不需要连接开发板、相机和机械臂。

## 1. 选择你要完成的事情

| 目标 | 需要的材料 | 从哪里开始 | 完成后得到什么 |
|---|---|---|---|
| 看懂工程、检查公开源码 | GitHub 仓库、Python 3.10+ | 第 2 节 | 文件一致性结果、21 项发布工具测试结果 |
| 在电脑上运行完整回归 | 公开源码、126 项配套依赖、同版 HWH、C 编译器 | 第 3 节 | API、状态机、串口、运动、坐标等回归结果 |
| 用 SD 卡独立演示 | 同版 BOOT 或完整构建输入、PYNQ-Z2 与外设 | 第 4 节 | 上电后运行的裸机识别与交互系统 |
| 用 Python/Jupyter 调试 | 完整工程、同版 BIT/HWH、PYNQ Linux 系统 | 第 5 节 | Python 可查询、控制和关闭的板上会话 |
| 修改 RTL 后重建硬件 | 完整 FPGA 输入、Vivado 2026.1 | 第 6 节 | Vivado 工程及配套 BIT/HWH/XSA |

公开源码按许可范围排除了 BSP/FSBL、运动学实现、相机配置、部分字库和部署二进制。目前仓库没有这些缺件的公开下载入口。若没有兼容完整包，可以完成源码阅读与公开发行检查；不能把这一阶段的 `PASS` 理解为“已经具备全部启动文件”。具体边界见 [复现范围与依赖](reproducibility.md)。

## 2. 只有公开源码：先验证文件

### 2.1 获取并固定一个版本

在电脑终端中执行：

```bash
git clone https://github.com/gao-778/pynq-screw-sorter.git
cd pynq-screw-sorter
git rev-parse HEAD
```

记下最后输出的提交编号，后续的源码、日志和报告以它为依据。也可以从 [Releases](https://github.com/gao-778/pynq-screw-sorter/releases) 下载源码 ZIP，解压后进入包含 `README.md`、`src/`、`build/` 的工程根目录；ZIP 用户用附带 SHA-256 和发行清单记录版本。

本文的命令均从工程根目录运行。Windows 示例使用 `python`，PYNQ Linux 示例使用 `python3`；若本机命令不同，替换成实际 Python 3.10+ 解释器。首次查看环境：

```bash
python --version
python board/environment.py
```

`board/environment.py` 只读取软件环境，不下载位流、不访问机械臂。在电脑上没有 PYNQ 包是正常现象；PYNQ 运行阶段才要求对应板上环境。

### 2.2 检查公开发行文件

```bash
python build/verify.py
python -m unittest discover -s sim/tests -p test_release_packaging.py -v
```

本版的预期结果：

- `build/verify.py` 返回 `status: PASS`、`distribution: source`、空的 `errors`。
- `local_dependencies_to_supply` 列出公开包未携带的依赖，这是清单声明的范围。
- 发布工具回归输出 `Ran 21 tests` 和 `OK`。

这些检查会核对模型 BIN、C 头文件、NPZ、HEX、类别顺序、接口契约和公开文件哈希。它们不会加载 FPGA，也不会运行一次真实识别。若检查报告文件被修改，先比较所用版本，不要直接运行 `package.py --refresh` 来掩盖差异。

## 3. 拿到完整包：补齐输入并跑电脑端回归

### 3.1 两种工作方式

**已有完整统一包时，可以直接以其解压目录作为工作副本。** 其中的源码、`board/hardware/`、本地依赖和清单已经配套。先复制一份作为实验目录，保留原包用于回退与核验。

**希望在 GitHub 源码工作副本中复现时，先导入匹配输入。** 例如兼容完整包解压在 `C:/full/screwsort`，则运行：

```powershell
python build/import_dependencies.py --release C:/full/screwsort
```

Linux 路径示例：

```bash
python3 build/import_dependencies.py --release /path/to/full/screwsort
```

把示例路径换成真实路径。`--release` 指向的是含 `README.md`、`src/`、`build/` 的 `screwsort` 目录，不是 ZIP 文件本身，也不是它的上一级目录。导入器核验全部 126 项输入的 SHA-256，再复制缺失文件；已存在且相同的文件会保留，不同文件会拒绝覆盖。

### 3.2 补齐匹配硬件文件

依赖导入脚本**不会**复制 BIT/HWH/XSA。若使用公开源码工作副本，还需从同一完整包复制以下文件到同名位置：

| 文件 | 用途 |
|---|---|
| `board/hardware/screwsort.bit` | FPGA 配置位流；用于 Overlay 加载和裸机 BOOT 打包 |
| `board/hardware/screwsort.hwh` | 硬件地址元数据；PYNQ 加载及完整主机 API 回归都会使用 |
| `board/hardware/screwsort.xsa` | 与这次硬件导出对应的平台描述 |

核验依据是 [Overlay 契约](../board/overlay_contract.json) 和 [文件对应记录](correspondence.json)。BIT 与 HWH 必须来自同一版本，不要把旧固定 DDR 位流或另一个工程的 HWH 放进来。复制完成后重新执行：

```bash
python build/verify.py
```

这里特别保留 HWH 说明，是因为实际复现曾发现：126 项依赖导入成功后，三个 `MetadataTests` 仍会因缺少 `screwsort.hwh` 失败。HWH 不是只在真实上板时才需要。

### 3.3 运行完整主机回归

先确认 C 编译器可调用，再执行回归。Windows 示例：

```powershell
C:/mingw64/bin/gcc.exe --version
python sim/run_checks.py --cc C:/mingw64/bin/gcc.exe
```

Linux 示例：

```bash
gcc --version
python3 sim/run_checks.py --cc gcc
```

`--cc` 应替换成本机实际编译器路径。回归会构建主机测试库，再运行以下检查：

| 检查 | 覆盖内容 |
|---|---|
| 主机 Linux 适配库 | 共享 C 核心与 Linux 平台适配能否编译 |
| 18 项 Python/API | 生命周期、元数据、命令与接口约束 |
| 21 项发布工具 | Git 目录、归档、依赖导入与清单 |
| Linux / 裸机各 23 项状态机 | 同一业务核心在两种平台适配下的行为 |
| 裸机平台 | 计时、平台接口与相关边界 |
| 串口及运动恢复 | 查询、超时恢复、联合运动等逻辑 |
| 32 例坐标 | OBB 与平面坐标变换 |

完整流水线的 10 个检查任务应逐项显示 `PASS`。结果写入 `sim/output/summary.json`，各任务日志位于同一目录。2026-11-03 的实际重跑全部通过，见 [复现核验](reproduction_review_20261103.json)。主机测试 DLL/共享库仅用于电脑端回归，不能当作板上 ARM 运行库。

## 4. 裸机路径：用 BOOT 独立启动

### 4.1 已有配套 BOOT

使用同版完整包中的 `board/baremetal/boot.bin`。先核对 `board/baremetal/manifest.json` 中的 BOOT、位流和模型哈希；随后将文件复制到**裸机专用 FAT32 SD 卡根目录**，命名为 `BOOT.BIN`。

断电插卡，选择 SD 启动，连接相机与 HDMI，摇杆保持回中，再上电。接线以 [硬件安装](hardware_setup.md) 为准。不要直接套用早期双板工程的 UART 接线。

### 4.2 从源码编译裸机 ELF 和 BOOT

本步骤在 Windows 开发电脑执行，要求 Vitis 2026.1、同版 BSP/FSBL、位流和模型均已准备好。下列 `D:/AMD/2026.1/Vitis` 是示例安装路径：

```powershell
python build/build.py baremetal --vitis D:/AMD/2026.1/Vitis
python build/build.py boot --vitis D:/AMD/2026.1/Vitis
```

| 产物 | 路径 |
|---|---|
| 裸机应用 | `build/output/baremetal/screwsort.elf` |
| 编译记录 | `build/output/baremetal/build.json` 和各源文件日志 |
| BOOT 打包日志 | `build/output/boot/bootgen.log` |
| 最终启动文件 | `board/baremetal/boot.bin` |
| 产物与分区校验 | `board/baremetal/manifest.json` |

`boot` 命令使用已有 ELF，因此先执行 `baremetal`。构建会检查模型载荷、固件与保留 DDR 区的边界，以及 BOOT 分区对应关系。重建文件记录自己的哈希，不与原 BOOT 混写为同一个产物。

### 4.3 启动后依次检查什么

1. 先确认 HDMI 出图、相机有新画面，查看 `RUNLOG.TXT` 的启动和错误记录。
2. 放少量、互相分离的已知零件，检查型号、最多 12 目标容量及毫米坐标方向。
3. 用 SW1/SW3 移动侧栏、SW2 确认，检查摇杆 X/Y 与 Z 的交互。
4. 核对当前装置的标定、机械臂底座位置、拾取高度和四个料框，再启用机械臂独立电源，验证单目标及批次功能。

原装置的坐标参数不是通用机械臂配置。换相机位置或机械臂安装位置后，按 [标定教程](../data/calibration/README.md) 重新建立对应关系。操作细节见 [板上说明](../board/README.md)。

## 5. PYNQ 路径：Python/Jupyter 管理板上会话

### 5.1 系统与工程准备

1. 使用适配 PYNQ-Z2 的 **PYNQ Linux 系统卡**启动，保留系统自身的 BOOT 和分区。不要用本项目裸机 `BOOT.BIN` 覆盖 PYNQ 系统启动文件。
2. 将已补齐依赖和同版硬件的工程复制到板上，例如 `/home/xilinx/screwsort`。
3. 在板上终端进入工程目录，确认 Python 3.10+、PYNQ、NumPy、gcc 和设备访问权限；Notebook 要使用同一 Python 环境。

```bash
cd /home/xilinx/screwsort
mkdir -p board/output
python3 board/environment.py > board/output/environment.json
python3 -c "import sys, pynq, numpy; print(sys.executable); print(pynq.__version__, numpy.__version__)"
gcc --version
```

环境记录用于说明实际镜像和软件组合，不等于一次识别测量。镜像发行号另行记下；不同镜像的默认 Python 版本可能不同，应以实际输出为准。

### 5.2 在板上编译并只运行视觉

```bash
python3 build/build.py linux
python3 board/run.py --seconds 30
```

第一条命令产生 `build/output/linux/libscrewlab.so`。第二条命令加载 Overlay、检查地址与模型容量、申请连续内存、初始化 C 核心并运行约 30 秒，期间每秒输出状态、目标、服务统计及事件，最后关闭会话。默认不启用机械臂运动。

如果在 Windows 编译过 `--host` 测试 DLL，仍需执行板上 ARM 构建。也可以使用匹配工具链交叉编译，但板上本机编译是本手册的默认路径。

### 5.3 用 Notebook 观察结果

打开 [board/notebooks/screwsort.ipynb](../board/notebooks/screwsort.ipynb)，按单元格顺序操作。也可以在板上的 Python 会话中执行以下仅识别示例：

```python
import sys
import time
from pathlib import Path

root = Path('/home/xilinx/screwsort')
sys.path.insert(0, str(root / 'src/python'))
from screwsortmint import ScrewSortMint

app = ScrewSortMint()
try:
    app.prepare().initialize().start()
    time.sleep(3)
    print(app.status())
    print(app.results())
    print(app.metrics())
    print(app.messages())
finally:
    app.close()
```

这段示例会初始化相机、加载模型并运行 PL；“仅识别”指不允许运动，并非只读访问。正常关闭后，下一次会话创建新的 `ScrewSortMint()` 对象。

### 5.4 明确启用运动后再分拣

在仍处于打开状态的交互会话中，核对坐标与机械配置后执行 `app.enable_motion()`，它只允许运动，不直接发起抓取。再按需要调用：

| 请求 | Python 方法 | 说明 |
|---|---|---|
| 移动目标选择 | `app.select_direction('right')` | 方向还支持 `left`、`up`、`down` |
| 抓取已选目标 | `app.pick()` | 使用当前选中对象 |
| 抓取某一类 | `app.auto_pick('M3_1')` | 默认从左到右；螺母不参与夹取 |
| 分拣全部 | `app.sort_all()` | 最多四种可抓取类别，按现有箱位映射 |
| 请求停止 | `app.stop()` | 取消任务请求；不直接释放 DDR 缓冲区 |

这些方法返回不代表动作已经完成，持续查看 `status()` 和 `messages()`。任务结束后再 `close()`。不要在前一节已经关闭的对象上继续发命令；需要新建并初始化会话。

完成装置核验后，也可使用会触发分拣的命令行入口：

```bash
python3 board/run.py --enable-motion --sort-all --seconds 120
```

它请求分拣并在指定观察时长后关闭。时长应覆盖你的预期批次；到时不意味着所有目标必然分拣完成。完整 API 语义见 [Python API](python_api.md)。

## 6. 修改 RTL 后如何重建硬件

公开源码缺少的相机配置及字库必须先补齐。使用 Vivado 2026.1，在电脑端指定一个**项目外、尚不存在的短英文输出路径**：

```powershell
python build/build.py hardware --vivado D:/AMD/2026.1/Vivado/bin/vivado.bat --output C:/fpga/screwsort_build
```

该流程创建工程与 IP，运行综合、实现、检查，并导出同一次硬件的 BIT/HWH/XSA。若只想检查能否生成工程，使用另一个输出目录并追加 `--prepare-only`：

```powershell
python build/build.py hardware --vivado D:/AMD/2026.1/Vivado/bin/vivado.bat --output C:/fpga/screwsort_prepare --prepare-only
```

`--prepare-only` 不产生已完成实现的可启动位流。重新生成硬件后，必须检查接口契约、资源与时序，使用同次导出的 BIT/HWH 及匹配 XSA/BSP；不要只替换其中一个文件。更详细的产物对应关系见 [接口说明](interface.md) 和 [构建说明](../build/README.md)。

## 7. 保存一次可追踪的复现记录

建议每次记录以下内容，便于区分源码问题、环境问题和装置差异：

| 内容 | 位置或获取方法 |
|---|---|
| 源码版本 | `git rev-parse HEAD`，或源码 ZIP 的 SHA-256 |
| 文件一致性 | `build/verify.py` 的完整输出 |
| 电脑端回归 | `sim/output/summary.json` 与对应日志 |
| 编译结果 | `build/output/` 中的 `build.json`、编译和链接日志 |
| 运行产物 | BOOT 或 BIT/HWH 的哈希、`board/baremetal/manifest.json` |
| PYNQ 环境 | `board/output/environment.json`，另记镜像发行号 |
| 裸机运行 | SD 卡中的 `RUNLOG.TXT` 与按需保存的图像 |
| 视觉运行证据 | 下述脚本生成的环境及逐次观测记录 |

```bash
python3 board/capture_evidence.py --seconds 60 --label recognition
```

该命令在 PYNQ 板上运行，输出到 `board/output/<时间>/`，不启用机械臂。`COMPLETED` 只表示采集脚本完成；分类准确率还要对照人工真实标签统计，不能用模型自己的预测作标签。

遇到失败时，先看 [常见问题与排查](troubleshooting.md)。完成复现后修改源码、标定或硬件属于新的实验版本，应另存记录，不覆盖原有验收基线。
