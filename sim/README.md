# 验证

从项目根目录执行 `python sim/run_checks.py --cc <gcc>`。需要 RTL 仿真时追加 `--vivado-bin <Vivado/bin>`。

同一份生产应用分别按 linux 和 baremetal 配置编译状态机测试；Python/C 桥接、裸机平台、串口协议、运动恢复和坐标检查共享同一项目输入。test_rtl.py 检查动态 DDR 基址和 AXI 事务排空。输出在 output/，发行版结果在 results/。
