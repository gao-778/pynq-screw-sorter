# 共享 FPGA 设计

rtl/ 为采集、视觉计算、内存和显示逻辑；constraints/ 为引脚与时序约束；bd/ 为完整 Block Design Tcl；tcl/ 为项目创建与实现检查。两种 PS 架构使用同一动态地址硬件。

从根目录运行 `python build/build.py hardware --vivado <Vivado> --output <new_directory>`。相机表与 ROM 输入由 build/dependencies.json 管理，厂商 IP 由 Vivado 生成。输出位流、HWH 和 XSA 统一放入 board/hardware/。
