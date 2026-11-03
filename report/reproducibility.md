# 复现范围与依赖

## 两种发行包

公开源码包与完整本地包共用七个业务目录、C 核心、RTL 和模型。公开包按 [依赖清单](../build/dependencies.json) 排除本地材料及含它们的部署二进制。它是可审阅的源码交付，不是无需依赖的启动镜像。

| 操作 | 仅公开源码 | 有权使用的完整包 | 当前证据 |
|---|---|---|---|
| 查看 RTL、共享 C、Python、模型和接口 | 可用 | 可用 | 文件和清单 |
| 检查公开发行完整性、发布工具回归 | 可用 | 可用 | `build/verify.py`、`test_release_packaging.py` |
| 完整主机状态机/API/运动回归 | 需补运动学输入及同版 HWH 元数据 | 可运行 | 原结果在 `sim/results/`；重跑输出另存 |
| 编译 Linux C 共享库 | 缺运动学编译输入 | 可编译 | 既有主机/ARM 交叉编译记录 |
| 在 PYNQ 中加载并运行 | 缺 BIT/HWH 和共享库构建输入 | 提供配套产物与入口 | 维护者确认基线通过；环境与入口范围见验收记录 |
| 从源码构建 FPGA | 缺相机配置和字库等输入 | 可发起构建 | 既有工程生成和硬件实现报告分别记录 |
| 构建裸机 ELF/BOOT | 缺 BSP/FSBL、运动学输入和位流 | 可发起构建 | 既有编译及分区校验记录 |
| 从原始数据完整重训 | 未包含完整数据集 | 也未包含完整数据集 | 训练源码、模型与元数据，不等于原始数据公开 |

`build/verify.py` 对 source 包允许清单声明的缺件，并列出待提供依赖。其 `PASS` 表示此发行范围内的一致性通过，不表示所有部署文件存在，也不代表实物测试通过。

## 补齐本地输入

1. 取得自己有权使用的兼容完整包；目前仓库没有这些缺件的公开下载入口。
2. 将包解压到另一个目录。`--release` 指向含 `README.md`、`src/`、`build/` 的 `screwsort` 目录。
3. 从源码工作目录运行：

```bash
python build/import_dependencies.py --release /path/to/full/screwsort
```

导入器还支持 [source_paths](../build/dependencies.json) 指定的旧发行目录布局。文件逐项 SHA-256 匹配后才复制；错误版本不能靠改哈希冒充匹配输入。

导入内容包括 BSP/FSBL、`arm_kinematics.c`、相机配置 ROM 和字库。它们保持原许可，不被根 MIT 重新授权。没有兼容完整包时，需先取得这些材料的合法来源，或独立替换实现并重新验证接口；不能按现有“同版复现”的哈希宣称一致。

## 取得匹配硬件

导入脚本处理构建输入，不自动导入 BIT/HWH/XSA。可以选择：

- 由已补齐依赖的源码完整构建，参见 [构建说明](../build/README.md)。
- 在有权本地使用完整统一包的情况下，使用该完整包本身作为工作副本；它已有配套 `board/hardware/`、`board/overlay_contract.json` 和清单。

不应混用旧固定地址位流、另一版本的 HWH 或另一模型/目标容量。Python 包装器检查 ABI `0x50594d32`、MC18 ID 和 12 目标容量；文件核验还应对照同次 XSA 和清单。自行更换位流后必须重新核对接口与配置，不能仅重写哈希消除报错。

## 完整主机回归也需要 HWH

本轮在干净源码目录复现时，确认 126 项构建输入导入成功后，Python 的三个 `MetadataTests` 仍会读取 `board/hardware/screwsort.hwh`。导入脚本不复制硬件产物，因此只导入构建输入不能满足完整回归的全部前置条件。

推荐直接使用同版完整统一包作为工作副本；若使用公开源码工作副本，则从同一完整包复制 `board/hardware/` 下的 BIT/HWH/XSA，并对照 `board/overlay_contract.json`、`report/correspondence.json` 核验 SHA-256。保持现有接口契约不变，不用另一版本 HWH 替代。然后执行：

```bash
python build/verify.py
python sim/run_checks.py --cc /path/to/gcc
```

不接板的元数据测试只解析 HWH，不加载 FPGA、不触发机械臂；单独运行发布工具的 21 项测试不需要硬件文件。本轮实际结果见 [复现核验](reproduction_review_20261103.json)。

## 两条板上路径

**裸机：** 以项目生成的 `BOOT.BIN` 放在裸机专用 FAT32 SD 卡根目录启动，PS 运行 standalone C。

**PYNQ：** 先用板卡对应的 PYNQ Linux 镜像启动，保留系统 BOOT；把工程复制到 Linux 文件系统，在板上编译 `.so`，由 Notebook/Python 加载本项目 BIT/HWH。不要把裸机 BOOT 覆盖到 PYNQ 系统卡。

跨装置复现需要记录 PYNQ 的镜像发行号、内核、PYNQ 包、NumPy 和 Python 环境。当前代码声明 Python 3.10+；这不意味着任意 PYNQ-Z2 镜像均满足依赖。首次部署应先运行 `python3 board/environment.py` 查看实际软件环境，再按 [验证说明](validation_scope.md) 补充镜像下载文件名/版本，使用能导入 PYNQ 且具有设备访问权限的 Python/Jupyter 环境。不要用另一虚拟环境的 `pip` 安装来替代当前内核环境核对。

## 训练与标定的边界

`data/model/` 的部署权重可核验；`src/training/` 提供训练思路与程序。公开包和完整本地包均未携带完整原始训练照片及全部标注，因此不能承诺相同随机种子即可从零恢复全部训练结果。

原机标定仅适用于当时相机、平台和机械臂关系。换装置时应先复标，记录像素坐标、平台毫米坐标和机械臂坐标三者的转换，再做低风险单目标验证。操作入口见 [标定教程](../data/calibration/README.md)。
