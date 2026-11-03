# Python API

入口为 `from screwsortmint import ScrewSortMint`，导入路径是项目 `src/python`。它通过 `ctypes` 调用同一 C 业务核心；相机图像处理与 CNN 继续位于 PL。

本接口复用维护者已确认上板通过基线的业务核心，并配有接口实现和离线测试；具体证据范围见 [验证记录](validation_scope.md)。运行前须具备匹配 BIT/HWH、在 ARM 环境编译的共享库、PYNQ 依赖和设备权限；公开源码的缺件说明见 [复现范围](reproducibility.md)。

| 方法 | 用法与返回含义 |
|---|---|
| `prepare()` | 加载成对 BIT/HWH，检查 ABI、模型和 12 目标容量，分配并绑定缓冲区 |
| `initialize()` | 初始化共享 C 应用、模型和相机 |
| `start()` | 启动后台 service 线程 |
| `results()` | 类别、毫米坐标、方向、有效性、采集时间和可抓取标志 |
| `status()` | 识别、运动、分拣、料框和工作线程状态 |
| `enable_motion(enabled=True)` | 初始化后显式允许运动；它不触发一次抓取 |
| `select_direction(direction)` | 以 `left` / `right` / `up` / `down` 选择目标 |
| `pick()` | 请求抓取所选目标 |
| `auto_pick(class_name, order='left_to_right')` | 按类别名选择螺丝；次序还支持 `top_to_bottom` |
| `sort_all(order='left_to_right')` | 请求分拣可抓取螺丝，最多四种类别 |
| `stop()` | 优先请求取消当前任务；不会立即释放硬件资源 |
| `close()` | 停止服务、等待运动与 AXI/DMA 排空，再释放缓冲区 |
| `metrics()` | 服务次数、最大服务间隔、工作线程异常；不是分类准确率 |
| `messages()` | 读取并清空当前已收集的事件文本 |

## 会话与结果

`prepare().initialize().start()` 可链式调用，推荐 `try/finally` 中调用 `close()`；完整示例见 [Notebook](../board/notebooks/screwsort.ipynb)。关闭成功后创建新对象，不重复使用已关闭的 C 会话。避免另一个进程/Notebook 同时占有同一 Overlay。

`class_id` 是 `data/model/classes.json` 中的模型内部索引，不是屏幕编号。`auto_pick()` 优先传递明确的类别名，例如 `M3_1`。前 15 个内部索引可抓取，螺母仅识别。坐标以原机标定的毫米体系输出，更换装置后必须复标。

方向、抓取与自动分拣请求进入后台队列，方法返回不代表动作完成；用 `status()` 和 `messages()` 确认状态与错误。`results()` 中的 `valid` 和 `captured_ms` 也需保留，不能把过期坐标当成当前测量。

## 异常与关闭

初始化错误会给出相机/硬件状态，读取事件定位。`metrics()['worker_error']` 非空时保留日志并检查任务状态。若 `close()` 报服务停止、运动关闭或 AXI/DMA 排空失败，代码保留缓冲区所有者引用，避免硬件访问已释放内存；处理设备状态后再尝试关闭，必要时按错误提示重启板卡。不要直接强制释放、重载位流或结束进程来假定设备已停止。

Linux 调度不提供硬实时保证。持续记录最大服务间隔和机械臂协议错误，完成 [板上验收](validation_scope.md) 后再给出实测时延。
