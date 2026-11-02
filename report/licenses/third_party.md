# 许可与发行范围

项目原创 C、RTL、Python、脚本、文档及本项目生成的部署模型使用 license.txt 中的 MIT 条款。文件原有版权与许可声明继续有效。

| 组件 | 范围与条款 |
|---|---|
| TMDS 编码器 | 保留 Hirosh Dabui 的版权与 ISC 条款，见 notices/isc-tmds.txt |
| AMD standalone 头文件与链接脚本 | 保留各文件 SPDX 与版权通知，见 notices/mit-amd.txt |
| FatFs | 保留 ChaN 的源/二进制再分发通知，见 notices/fatfs.txt |
| Python 依赖 | 通过包管理器安装，分别遵循各依赖许可 |

build/dependencies.json 定义本地构建输入，包括 SDK/BSP/FSBL、运动规划源文件、相机配置和字体 ROM。这些材料不统一改用项目 MIT。公开源码归档排除清单中的本地输入及包含它们的硬件/启动二进制；完整本地发行包保留这些输入以支持现有装置构建。导入程序只校验与复制使用者有权使用的材料。

原始训练与标定照片不因代码 MIT 自动获得再分发许可。公开包保留算法、参数及元数据，外部图像按各自授权提供。
