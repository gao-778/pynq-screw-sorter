# 源代码

| 目录 | 责任 |
|---|---|
| common/ | 唯一 C 业务核心：识别、坐标、UI、串口、运动、分拣与模型参数 |
| platform/baremetal/ | standalone 计时、固定 DDR 绑定与启动入口 |
| platform/linux/ | MMIO 映射、连续内存绑定、POSIX 文件与计时 |
| python/ | PYNQ Overlay 与缓冲区所有权、线程服务、Python API |
| fpga/ | 两种运行方式共用的 RTL、时序约束与 BD Tcl |
| training/ | MC18 训练、量化、导出及前处理参考 |
| dependencies/ | 由依赖清单管理的本地运动规划输入 |

所有构建目标读取 ../build/project.json 中的 shared_sources；新增业务模块时在该列表注册，使两种目标同步构建。
