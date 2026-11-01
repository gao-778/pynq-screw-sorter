# 本地依赖

公开仓库不重新授权或分发许可未完整核对的原文件。你已经拥有原 `ARM_BUS_FIX` 完整工程且有权在本机使用时，可执行：

```powershell
python scripts/import_local_dependencies.py --release C:/fpga/private_release
```

脚本先检查 `config/local_dependencies.json` 中全部 SHA，再复制到 Git 忽略的 `external/`：

- `external/software/arm_kinematics.c`：原运动学和规划实现，保持原行为；
- `external/rtl/ov5640_baseline_rom.v`：原相机寄存器配置表；
- `external/fonts/`：五个原字形、坐标轴及布局 ROM；
- `external/firmware/`：原 Cortex-A9 BSP 和 FSBL；
- `external/hardware/`：原已实现的 bit/XSA，供软件复建与 BOOT 打包核验使用。

导入后，本机可以完成同版编译和回归；Git 提交与公开 ZIP 都不包含这些文件。不要把本说明理解为从任意来源复制文件的许可。来源与条款见 [THIRD_PARTY.md](THIRD_PARTY.md)。

没有原完整包的使用者需要自行取得相应依赖，或开发具有明确开放许可的替代版本，再做接口、时序及实物验证。当前仓库不承诺缺省依赖下载器，也不把不完整来源包装成一键可用的开源发布。
