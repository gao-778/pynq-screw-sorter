# 第三方来源与公开范围

本仓库的 MIT 许可只覆盖项目原创部分，具体范围见根目录许可说明。第三方材料保留原有版权及许可；没有查明许可的材料不随公共 Git 仓库上传。本说明记录已查到的证据，不对全部历史代码作原创保证。

## 随公开源码保留的第三方内容

### TMDS 编码器：ISC

原发布工程中的 `project_sources/base/rtl/tmds_encoder.v` 明确说明移植自 Hirosh Dabui 的实现，文件中保留了 2020 实现版权与许可授权句。主源为作者的 [my_hdmi_device/tmds_encoder.v](https://github.com/splinedrive/my_hdmi_device/blob/master/tmds_encoder.v)，其头部含 2021 版权、完整 ISC 条款及独立的 2020 实现说明。

公共副本须保留作者通知，并随附 [ISC-TMDS.txt](../LICENSES/ISC-TMDS.txt)。不能改标为本项目原创 MIT。公开的作者版权通知和联系邮箱是归属信息，不作为私人路径删除。本地旧版与当前上游存在修改，不声称逐字节相同。上游于 2026-11-02 核查，链接指向 master，未宣称固定提交版本。

## 本地构建依赖中的已确认条款

本节不表示相应二进制库已随 Git 仓库分发。

| 内容 | 原发布工程中的证据 | 处理 |
|---|---|---|
| AMD/Xilinx standalone BSP 头、PS 初始化文件 | `firmware/bsp/include/xil_io.h:2-4`、`firmware/baseline_hardware/ps7_init.c:3-4` 等标明 `SPDX-License-Identifier: MIT` | 若单独保留这些文件，保留各文件的 AMD/Xilinx 版权及原有 MIT；附 [MIT-AMD.txt](../LICENSES/MIT-AMD.txt)。这不覆盖所有 Vivado IP，也不证明全部 BSP 二进制组成。 |
| FatFs R0.16 | `firmware/bsp/include/ff.h:1-18`，Copyright 2025 ChaN，自带源/二进制再分发条件 | 若单独保留此头，保留原通知；附 [FATFS.txt](../LICENSES/FATFS.txt)。不改标为项目 MIT。 |
| Python 运行依赖 | 训练 requirements 记录 PyTorch、NumPy、Pillow、OpenCV | 由使用者安装，不随仓库复制 Python 环境、wheel 或 site-packages；依赖包自身许可保持有效。 |

## 不直接随公共仓库上传

以下路径是**原完整发布包内的相对路径**，用于精确定位，不表示它们已经包含在公共仓库中。本地导入产生的 `external/` 应被 Git 忽略；导入只用于用户有权使用的本机材料，不表示改变其许可。

| 原文件或范围 | 未直接上传的原因及恢复方式 |
|---|---|
| `project_sources/camera_sd.gen/**`、各层 `ipshared/**` 的厂商实现/仿真文件 | 部分头部明确写 AMD confidential/proprietary，且说明免责声明不授予许可。公共包保留项目自己的 RTL、BD/XCI 配置和重建入口，由安装的 Vivado 生成厂商输出。不能把这些生成实现统一赋 MIT。 |
| `firmware/bsp/lib/*.a`、`firmware/fsbl.elf`、`output/*.elf`、`hardware/*.bit`、`hardware/*.xsa`、`output/BOOT.BIN`、`backup/*.BIN` | 预编译组成和再分发范围需分别核对；原 BOOT/bit 还包含下面的字库等内容。保留在用户原完整包或本地 external，公共仓库不因它们是二进制就视为原创源码。 |
| `software/arm_kinematics.c` | 注释明确关联原 `ArmMoveIK`；历史 vendor README 指明参考 `InverseKinematics.py` 原作者 Aiden，未附独立许可证。暂由本地导入，不重新授权、不改写行为。此决定依据来源记录，不把数学公式、连杆尺寸或通用 IK 算法本身认定为第三方代码。 |
| `project_sources/rtl/dashboard_font.hex`、`project/dashboard_font.hex` | 已通过 SHA 关联到读取 Windows 微软雅黑和 Consolas 的字形生成器；此次未核实该字形 ROM 的公开再分发权限，暂不上传。ROM SHA：`656f3c4c2127b957ea2bf72bfe774bdb3ea99904adf173d917aff6c39a48626d`。Unicode 到字槽的 `dashboard_font_map.h` 只是映射，不等同于字形文件。 |
| `project_sources/base/board/pynq-z2/A.0/board.xml`、`part0_pins.xml`、`preset.xml`、`pynq_z2.jpg`，以及 `project_sources/base/board/preset.xml` | board.xml 标明 TUL 板卡资料，当前副本未附明确许可。优先使用自行安装的官方 board files；板图不随源码包复制。 |
| `project_sources/base/rtl/ov5640_baseline_rom.v` 及 `ov5640_baseline_rom.before_zoom_20261001_105148.v` | 文件头指出相机配置表来自旧 prework 工程，但当前资料不足以确认更早来源或许可。暂按本地依赖处理，不自动将继承的配置表声明为原创 MIT；不据此对寄存器事实作版权判断。 |
| 原始数据集、联系表、增强缓存、训练 `.venv_gpu/**` | 原图公开范围与代码许可分开。数据记录可证明使用文件与内容哈希，不能代替摄影者/公开许可说明。运行环境依赖自行安装。 |
| 原始 RUNLOG、完整本机栈/构建日志、`.map`、`__pycache__`、测试 `.exe`、历史备份 | 不是必要源码；部分含 Windows 用户路径、电脑名或私人下载目录。使用脱敏摘要代替，不修改本地冻结证据。 |

## 模型、训练与标定

本工程 MC18 权重来自本项目十五类教师与新增螺母训练；所查记录没有外部 YOLO 权重导入的证据。参考网络思路不等于使用该网络的预训练文件。部署模型、训练代码和训练图像应分别标明许可/公开范围，不能仅以代码 MIT 推断照片也已开源。

训练来源记录包括 2404 张原始照片、文件内容哈希、场景分组及 train/val/test 划分。上下文说明照片由用户提供/补拍，但归档没有独立数据集许可证。公开元数据应保留内容哈希和相对样本 ID，移除私人下载路径、Windows 用户路径与内部对话 ID；未提供原图或原始缓存时，不声称数据训练流程开箱完整复现。

标定矩阵与脚本属于装置配置与测量结果。可以作为示例说明坐标约定，但它们仅适用于原相机/平台布局，不是另一台装置可直接使用的物理标定。

## 补充许可的流程

如后续取得来源方许可或改用有明确开放许可的替代资源，更新此表、保留原通知，并重新生成对应文件清单。替换字体、相机表或 IK 不应只为消除许可提示而未经功能回归；当前可用原版本继续在用户本地保留。
