# Vivado 硬件重建

本目录包含 34 份公开 RTL/VH、10 份约束、BD Tcl 和构建脚本。器件为 `xc7z020clg400-1`，工具为 Vivado 2026.1。不提交原 XPR、`.gen/`、厂商实现 HDL 或缓存；工程和 IP 由本机 Vivado 重新生成。

先按 [本地依赖说明](../docs/local-dependencies.md) 准备五个 ROM 和相机配置模块，然后使用一个**尚不存在、位于源码目录以外**的短输出目录：

```powershell
python scripts/rebuild_hardware.py --output C:/fpga/mc18_prepare --vivado C:/AMD/2026.1/Vivado/bin/vivado.bat --prepare-only
```

成功后打开 `C:/fpga/mc18_prepare/project/screw_sort_ui.xpr`。`--prepare-only` 会创建工程、重建 BD、校验连接、生成 IP/wrapper、核对编译源闭包；不会综合、实现或操作开发板。

要执行综合实现，换一个不存在的目录并去掉 `--prepare-only`：

```powershell
python scripts/rebuild_hardware.py --output C:/fpga/mc18_full --vivado C:/AMD/2026.1/Vivado/bin/vivado.bat
```

成功输出为该目录的 `hardware/camera_sd.bit`、`hardware/camera_sd.xsa` 和时序报告。时序不满足时脚本报错。当前开源整理已验证空目录工程重建与结构核对，**未重跑完整综合实现，也未进行上板验证**。

`source_manifest.json` 保存基线哈希。修改公开 RTL/约束后可以加 `--allow-source-changes`，结果会明确标记为修改版；外部 ROM/模块仍要求基线哈希，不静默替换。

## 已核对的迁移差异

- 34 份公开 RTL 与原发布包逐字节一致。
- 10 份 XDC 中只有 `dont_touch.xdc` 的历史私人路径注释被脱敏，实际约束命令一致。
- 从空目录创建时不依赖 TUL board.xml，PS 参数由 BD 配置恢复。
- Vivado 会正规化部分 SmartConnect 接口与 PS 功耗派生元数据；实际连接、地址、可配置 IP 参数及 PS 初始化 C/H/Tcl 已核对。它不意味着新 bit 文件与旧 bit 二进制相同。
- 继承的异步复位、BD 时钟及板卡 DDR DQS 提示仍需按工程约束理解，本次不宣称零警告。

默认软件 BOOT 打包使用已接受的本地原 bit。若改用这里重新实现的新 bit，应单独检查 XSA/BSP、寄存器 ABI、模型接口和新实现时序，再集成应用，不能只把文件覆盖进去。
