# 板上运行与操作

统一版共用一套 RTL/C 核心，但裸机和 PYNQ/Linux 分别启动。当前包的整机实测仍待完成，状态见 [验证说明](../report/validation_scope.md)。

## PYNQ

先用 PYNQ Linux 系统卡启动；保留系统 BOOT，不要用本工程裸机 BOOT 覆盖。公开源码需要先补齐 [本地依赖与匹配硬件](../report/reproducibility.md)。

在板上工程根目录先运行 `python3 board/environment.py` 记录环境，再执行 `python3 build/build.py linux`，然后运行 `python3 board/run.py --seconds 30` 或打开 [Notebook](notebooks/screwsort.ipynb)。默认只识别与显示。检查实际坐标、抓取高度和料框位置后，显式调用 `enable_motion()`；自动分拣的命令行入口是 `python3 board/run.py --enable-motion --sort-all --seconds 120`。

`stop()` 请求取消任务；`close()` 停止服务并等待设备排空。关闭成功后新建对象开启下一会话。若排空失败，接口保留缓冲区并报告错误，需保留诊断并解决设备状态，不能把失败关闭当成已释放。

## 裸机

将完整统一包或本地构建得到的 `board/baremetal/boot.bin` 复制到裸机专用 FAT32 SD 卡根目录并命名 `BOOT.BIN`。断电插卡，选择 SD 启动，摇杆回中。

| 操作 | 功能 |
|---|---|
| SW1 / SW3 | 侧栏光标上 / 下 |
| SW2 | 确认侧栏选项 |
| 摇杆 X/Y | 目标选择或已打开列表中的导航 |
| 摇杆 Z | 确认选定目标/类别，可能触发运动 |
| SW4 | 按当前任务请求停止；空闲时关闭会话，裸机按程序重新启动 |

PYNQ 中的空闲 SW4 关闭应用会话，不重启 Linux。SW4 不是独立断电急停；板载 BTN0～BTN3 不承担这些功能。

## 分拣

先确认相机和 HDMI，再验证类别、毫米坐标、方向及单目标抓取。指定类别与自动分拣使用当前工程既定料框映射；螺母不进入抓取队列。自动模式在动作之间使用新帧重新确认目标，确认移除后再继续。

机械臂和平台配置是原装置参数；接线及复标要求见 [硬件说明](../report/hardware_setup.md)。

## 调试记录

Python 的 `status()`、`results()`、`metrics()` 和 `messages()` 提供状态、目标、服务统计和事件。输出保存到 `board/output/`。

```bash
python3 board/capture_evidence.py --seconds 60 --label recognition
```

该脚本记录环境和识别过程，不启用机械臂。输出完成不等于准确率自动达标，仍需真实类别和统计。截图、完整分拣验收及失败恢复证据按 [最终验收步骤](../report/validation_scope.md) 单独保存。
