# 本地规划依赖

`arm_kinematics.c` 实现 [arm_kinematics.h](../common/arm_kinematics.h) 的逆解和路径规划接口，由裸机与 Linux 目标共同链接。公开包没有分发该实现，因此完整主机回归和 Linux/裸机构建都不是仅 clone 即可完成。

匹配文件的 SHA-256 和旧路径记录在 [依赖清单](../../build/dependencies.json)。已有合法完整统一包时，从项目根目录运行：

```bash
python build/import_dependencies.py --release /path/to/full/screwsort
```

当前没有此缺件的公开下载入口；导入程序核对使用者已有材料。自行实现替代接口时需要重新测试逆解、可达性、路径与运动，并记录为不同构建，不能仅改清单把它视为原版。来源与发行范围见 [第三方说明](../../report/licenses/third_party.md)。
