# ScrewSort

基于 PYNQ-Z2 的螺丝识别、定位与机械臂分拣系统。PL 完成图像采集、目标检测、旋转 ROI、量化 CNN 和 HDMI 显示；PS 完成目标管理、坐标转换与运动控制。

本分支整理为 **裸机 C 部署 + PYNQ/Linux 调试与复现入口**。两种目标共用 C 业务核心、MC18 模型、RTL 和标定配置，通过平台适配层处理内存、文件、计时和控制台。Python/Jupyter 调用 C 共享库组织任务，CNN 仍在 PL 执行。

**本仓库基于维护者已上板验收通过的版本整理。** 维护者于 2026-11-03 确认该来源；公开整理保持模型、RTL、标定和机械臂核心不变，并提供裸机与 PYNQ/Linux 入口。上板确认来源与可重复检查见 [验收与复现记录](report/board_acceptance_20261103.json)。公开源码也不包含全部运行依赖，不能仅 clone 后直接启动。先读 [复现范围与依赖](report/reproducibility.md) 和 [验证状态](report/validation_scope.md)。

## 功能

- 15 类螺丝与 3 类螺母，最多同时显示 **12 个目标**；螺母只参与识别、定位和统计。
- 毫米坐标、目标选择、单目标抓取、指定类别抓取和最多四类自动分拣。
- 动作期间暂停识别；动作结束后用新采集场景确认下一目标与移除结果。
- HDMI 界面、摇杆和四按键、运行日志、截图，以及 Python/Jupyter 查询和控制接口。

## 硬件与环境

| 项目 | 要求或记录状态 |
|---|---|
| 开发板 | PYNQ-Z2，Zynq-7020，`xc7z020clg400-1` |
| 相机 | OV5640 DVP；参考装置为 ATK-MC5640 V1.2 |
| 显示 | HDMI 输出，1280×720；扫描刷新与相机新帧、识别频率分别计量 |
| 执行器 | 六个总线舵机，ID 1–6，半双工串口与独立供电 |
| PYNQ 入口 | 板卡对应的 PYNQ Linux 系统，Python 3.10+、NumPy、gcc、Jupyter；部署时记录实际镜像、PYNQ 和依赖版本 |
| FPGA 构建 | Vivado 2026.1 |
| 裸机构建 | Windows、Vitis 2026.1、与硬件接口匹配的 standalone BSP 和 FSBL |

接线和原机参数见 [硬件安装](report/hardware_setup.md)。更换相机、平台或机械臂位置后需要重新标定。

## 目录

| 目录 | 内容 |
|---|---|
| `src/` | 共享 C、平台适配、Python、RTL 与训练源码 |
| `sim/` | 仿真、回归脚本和历史验证结果 |
| `build/` | 构建入口、依赖清单、发布检查及实现报告 |
| `board/` | Notebook、板上运行入口；完整本地包另含硬件和裸机产物 |
| `data/` | MC18 部署模型、标定参数和参考元数据 |
| `skill/` | 可复用的 FPGA/PYNQ 方法与检查工具 |
| `report/` | 架构、接口、教程、验证范围和第三方许可说明 |

[build/project.json](build/project.json) 定义共享源码与两个编译目标。GitHub 根目录另含许可证、忽略规则和变更说明；它们不改变七个业务目录的结构。

## 先选择复现路径

| 你的材料 | 可直接做什么 | 完整运行还需什么 |
|---|---|---|
| 仅本 GitHub 源码 | 阅读算法和接口、检查公开文件一致性、运行独立发布测试 | 匹配的本地依赖，以及构建或取得成对的 BIT/HWH |
| 有权使用的完整统一发行包 | 按清单核验文件、使用配套构建输入与硬件产物 | 匹配开发环境、接线和装置标定 |
| 需要从数据重新训练 | 阅读训练和量化流程 | 原始照片、标注及训练环境；这些未随代码完整公开 |

公开包排除了 BSP/FSBL、部分运动学实现、相机配置、字库及含这些材料的运行二进制。目前没有这些缺件的公开下载地址。已有合法完整包的使用者可导入；不能取得依赖时，可复现范围以 [矩阵](report/reproducibility.md) 为准。

```bash
# --release 指向解压后的完整统一包中含 README.md、src/、build/ 的 screwsort 目录
python build/import_dependencies.py --release /path/to/full/screwsort
python build/verify.py
```

导入器也兼容清单列出的旧发行目录，并在复制前逐项验证 SHA-256。文件导入与实机运行是不同检查步骤。之后需按下节构建硬件，或使用同一完整包的匹配硬件产物；详细步骤见 [复现教程](report/reproducibility.md)。

## PYNQ 调试入口

先以 **PYNQ Linux 系统 SD 卡**启动开发板，再复制工程到板上，例如 `/home/xilinx/screwsort`。保留 PYNQ 系统自己的启动文件，**不要用本项目裸机 BOOT 覆盖它**。

以下步骤要求本地依赖已补齐、`board/hardware/screwsort.bit` 与同名 `.hwh` 配套，且当前 Python 环境有 PYNQ 和设备访问权限：

```bash
cd /home/xilinx/screwsort
python3 board/environment.py
python3 build/build.py linux
python3 board/run.py --seconds 30
```

默认只运行识别与显示。也可打开 [Notebook](board/notebooks/screwsort.ipynb) 分步调用：

```python
import sys
from pathlib import Path
root = Path('/home/xilinx/screwsort')
sys.path.insert(0, str(root / 'src/python'))
from screwsortmint import ScrewSortMint

app = ScrewSortMint()
try:
    app.prepare().initialize().start()
    print(app.results())
    print(app.status())
    # 核对实际坐标、工作区和料框后，再显式启用运动。
    # app.enable_motion()
    # app.auto_pick('M3_1')
    # app.sort_all()
finally:
    app.close()
```

`stop()` 请求取消当前任务；`close()` 等待运动、服务线程和 AXI/DMA 排空后释放缓冲区。关闭成功后，新会话创建新对象。方法和错误处理见 [Python API](report/python_api.md)。

## 裸机构建与启动

在 Windows 主机、依赖和匹配硬件准备好后运行：

```powershell
python build/build.py baremetal --vitis D:/AMD/2026.1/Vitis
python build/build.py boot --vitis D:/AMD/2026.1/Vitis
```

输出 ELF 位于 `build/output/baremetal/screwsort.elf`，BOOT 位于 `board/baremetal/boot.bin`。将 BOOT 复制到**裸机专用 FAT32 SD 卡**根目录并命名为 `BOOT.BIN`，选择 SD 启动。接线和操作见 [板上说明](board/README.md)。

裸机和 PYNQ 使用本统一版的同一硬件设计，但分别启动：裸机使用保留 DDR 地址，PYNQ 使用 `pynq.allocate` 动态分配。旧固定 DDR 位流不能直接配这版 PYNQ 包装器。

## 从源码构建 FPGA

先补齐私有/本地构建输入，输出目录使用项目外尚不存在的短英文路径：

```powershell
python build/build.py hardware --vivado D:/AMD/2026.1/Vivado/bin/vivado.bat --output C:/fpga/screwsort_build
```

脚本从 RTL、XDC、BD Tcl 生成工程与 IP，并执行综合、实现、检查和同次 XSA 的 BIT/HWH 导出。追加 `--prepare-only` 只生成工程，不完成综合实现或产生可启动位流。接口和地址见 [接口契约](report/interface.md)。重新生成部署产物后，应更新对应记录并执行 `python build/package.py --refresh` 更新本地发布清单。

## 验证与发布

```bash
# 对照所持发行包清单检查；source 包 PASS 不表示缺失依赖已具备
python build/verify.py
# 独立发布检查回归，不访问板卡
python -m unittest discover -s sim/tests -p test_release_packaging.py -v
# 以下完整主机回归需先补齐本地依赖和同版 HWH（见复现教程）
python sim/run_checks.py --cc /path/to/gcc
# 有 Vivado 时可追加 RTL 仿真
python sim/run_checks.py --cc /path/to/gcc --vivado-bin /path/to/Vivado/bin
```

原始发行验证记录保留在 `sim/results/` 和 `build/reports/`；新运行输出到 `sim/output/`。首次发布整理见 [发布复核](report/publication_review_20261103.json)，本轮重新导入、10 组主机回归和三项目标构建见 [复现核验](report/reproduction_review_20261103.json)。维护者的上板通过确认与本轮复现记录见 [验证说明](report/validation_scope.md)；更换装置时按其中步骤核对实际环境与机械参数。

公开源码应从经过核验的工作副本导出，输出文件放在项目目录外：

```bash
python build/package.py --public --output /path/to/new/screwsort_source.zip
```

## 模型、训练与标定

MC18 输入 64×64 灰度 ROI，通道 1→32→96→256，共 255,912 个可训练参数。类别顺序、量化与数据格式见 [模型说明](data/model/README.md)。更换模型必须同时满足软件和 PL 的结构与 ABI。

训练流程见 [训练教程](src/training/README.md)，原始照片及完整训练集未随本包公开。原机标定和复标步骤见 [标定教程](data/calibration/README.md)。

## 许可与贡献

原创源码、文档与部署模型采用 [MIT](LICENSE)。第三方文件保留原许可，未公开依赖、图像和运行二进制的范围见 [许可说明](report/licenses/third_party.md)。完整本地包包含某材料不代表该材料自动获得公开再分发授权。

反馈问题请附版本/提交编号、所用运行方式、环境版本、复现步骤和脱敏日志。保留已有稳定版历史；统一版的打包、文档和验证状态更新见 [变更记录](CHANGELOG.md)。
