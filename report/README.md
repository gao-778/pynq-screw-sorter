# ScrewSort 文档中心

[返回项目首页](../README.md) · [完整复现指南](quickstart.md) · [操作手册](user_guide.md) · [故障排查](troubleshooting.md)

这里集中列出仓库的说明、复现入口、源码位置和验证依据。文档不仅位于 `report/`：构建、板上运行、模型、标定与训练也在各自目录下提供 README，可从下面直接进入。

## 推荐阅读顺序

| 读者/任务 | 阅读路线 |
|---|---|
| 作品评审或第一次了解 | [首页](../README.md) → [功能与操作](user_guide.md) → [系统架构](architecture.md) → [设计报告](design_report.md) |
| 想用相同硬件复现 | [完整复现指南](quickstart.md) → [依赖范围](reproducibility.md) → [硬件安装](hardware_setup.md) → [板上运行](../board/README.md) |
| 想用 Python / Notebook 调试 | [PYNQ 路线](quickstart.md) → [Python API](python_api.md) → [Notebook](../board/notebooks/screwsort.ipynb) → [接口契约](interface.md) |
| 想修改 FPGA 或 PS 实现 | [系统架构](architecture.md) → [接口契约](interface.md) → [构建说明](../build/README.md) → [验证入口](../sim/README.md) |
| 想训练自己的类别 | [训练与部署](model_training.md) → [数据布局](../data/training/README.md) → [训练程序入口](../src/training/README.md) → [模型契约](../data/model/model_manifest.json) |
| 想复用工程经验 | [Skill 总览](../skill/README.md) → [本项目案例](../skill/examples/screw_sort_case.md) |

## 功能、部署与排错

| 文档 | 主要内容 |
|---|---|
| [完整复现指南](quickstart.md) | 从获取源码、导入依赖、回归测试到裸机/PYNQ 启动的完整步骤 |
| [功能与操作手册](user_guide.md) | 按键和摇杆、识别界面、统计、截图及三种抓取方式 |
| [复现范围与依赖](reproducibility.md) | 公开包与完整包分别能做什么；126 项输入和同版 HWH 的前置条件 |
| [硬件安装](hardware_setup.md) | 相机、显示器、摇杆、总线舵机、供电与接线 |
| [板上运行](../board/README.md) | 裸机 SD 启动、PYNQ 启动、任务停止及日志采集 |
| [故障排查](troubleshooting.md) | 缺文件、ABI/HWH、编译、相机、旧目标、机械臂与资源关闭问题 |
| [Python API](python_api.md) | 会话生命周期、查询和动作请求接口、结果字段与异常 |
| [构建与发布](../build/README.md) | Linux 共享库、ELF、BOOT、PL 重建、归档与清单 |

## 算法、训练与坐标

| 文档 | 主要内容 |
|---|---|
| [系统架构](architecture.md) | 识别和预览数据流、PS/PL 分工、DDR 与双平台适配 |
| [接口契约](interface.md) | 地址窗口、动态 DDR 基址、模型 ID、ABI 与排空协议 |
| [设计报告](design_report.md) | 设计动机、实现与资源、验证和交付范围 |
| [训练与权重部署](model_training.md) | 数据、ROI、QAT、整数参考、导出格式与更换模型步骤 |
| [模型文件说明](../data/model/README.md) | FNET、NPZ、HEX、C 头与类别映射 |
| [模型机器可读契约](../data/model/model_manifest.json) | 64×64 输入、355 维特征、量化、预处理与寄存器约束 |
| [平台标定](../data/calibration/README.md) | 像素/毫米坐标、方向转换、标定生成与多帧核验 |
| [协作与复核](collaboration.md) | 工程修改和复核的协作方式 |

## 验证记录在哪里

| 记录 | 作用与范围 |
|---|---|
| [验证状态与复现检查](validation_scope.md) | 如何分别阅读维护者实机确认、主机测试、编译和 FPGA 实现结果 |
| [上板验收来源](board_acceptance_20261103.json) | 维护者确认基线通过、原包与公开运行文件对应、产物哈希 |
| [重新复现记录](reproduction_review_20261103.json) | 干净源码、依赖导入、同版 HWH、10 组主机回归及三项目标构建 |
| [首次发布复核](publication_review_20261103.json) | 公开整理过程中的检查、打包和元数据处理 |
| [原统一包验证](validation.json) | 原包已有的 API、状态机、编译与 RTL 等检查记录 |
| [文件/模型/硬件对应](correspondence.json) | 共享源码、部署模型、BIT/HWH/XSA 的对应关系 |
| [FPGA 实现报告](../build/reports/hardware/implementation/) | 布局布线资源、时序、DRC 与相关报告 |
| [仿真与回归入口](../sim/README.md) | 重新执行检查的命令及输出目录 |

模型自身预测不是真实标签，主机测试通过也不是准确率测量。需要报告识别准确率、抓取成功率或延迟时，应同时提供真实类别、样本量、测试条件与测量范围。

## 常用源码入口

| 路径 | 看什么 |
|---|---|
| [共享应用](../src/common/app.c) | 相机初始化、识别调度、UI、任务与共享 C 主流程 |
| [共享 C ABI](../src/common/screwsort.h) | 平台调用所使用的初始化、状态与任务接口 |
| [裸机平台](../src/platform/baremetal/) | standalone 主入口与平台访问 |
| [Linux 平台](../src/platform/linux/) | Linux 地址、计时、文件等适配 |
| [Python 包](../src/python/screwsortmint/) | Overlay、内存、后台线程及 API 包装 |
| [FPGA RTL](../src/fpga/rtl/) | 采集、DDR、连通域、ROI、CNN、目标稳定与显示模块 |
| [目标与依赖配置](../build/project.json) | 两种 PS 编译目标共用的源码列表及接口参数 |
| [Notebook](../board/notebooks/screwsort.ipynb) | 分步骤实验入口 |
| [MC18 训练源码](../src/training/mc18/) | 训练、量化、整数参考与导出 |

## 下载、许可与交付

- [最新发布](https://github.com/gao-778/pynq-screw-sorter/releases/latest)：公开源码 ZIP 和校验文件；源码 ZIP 不包含完整运行依赖。
- [变更记录](../CHANGELOG.md)：各版本改动，历史标签可用于追溯。
- [交付清单](delivery_checklist.md)：核对代码、模型、硬件、复现和记录是否对应。
- [公开文件清单](open_source_files.json) 与 [依赖清单](../build/dependencies.json)：哪些已公开、哪些由兼容完整包提供。
- [MIT 许可](../LICENSE) 与 [第三方许可范围](licenses/third_party.md)：原创和第三方材料分别适用的规则。

更换装置时，按新相机视野与机械臂位置重新标定。文档中的原机坐标、舵机参数和硬件哈希是版本配置，不是任意装置的通用默认值。
