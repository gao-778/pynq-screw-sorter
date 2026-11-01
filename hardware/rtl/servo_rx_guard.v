`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Project owner
// Engineer:        Codex generated
//
// Create Date:     2026-10-29
// Design Name:     Servo receive isolation
// Module Name:     servo_rx_guard
// Description:     rtl/servo_rx_guard_spec.md
// Simulations:     output/uart_rx_guard_20261029/rtl_test (Vivado 2026.1)
//
// Referrences:
// File Format      File Name
// 1.Book           spec/servo_rx_guard_requirements.md
//
// Dependencies:
// Module Name      Version
// Existing four-stage UART input synchronizer
// 已有四级串口输入同步器
//
// Version:         V1.0
// Revision Date:   2026-10-29
// History:
// Time             Version     Revised by        Contents
// 2026-10-29       V1.0        Codex generated              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        项目所有者
// 开发人员:        Codex generated
//
// 创建日期:        2026-10-29
// 设计名称:        Servo receive isolation
// 模块名称:        servo_rx_guard
// 模块说明:        rtl/servo_rx_guard_spec.md
// 仿真工程:        output/uart_rx_guard_20261029/rtl_test (Vivado 2026.1)
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           spec/servo_rx_guard_requirements.md
//
// 依赖文件:
// 模块名称         版本
// Existing four-stage UART input synchronizer
// 已有四级串口输入同步器
//
// 当前版本:        V1.0
// 修订日期:        2026-10-29
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月29日 V1.0        Codex generated              创建文件

module servo_rx_guard
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 百兆接收资格采样时钟
	input i_rstn,                               // 低有效复位清除所有开启历史

	//-----------------输入信号-----------------//
	input i_rx_enable,                          // 方向互锁后的板外接收使能
	input i_rx_sync,                            // 四级同步器输出的串行电平

	//---------------串行接收接口---------------//
	output o_uart_sin                           // 送入串口内核的受控接收数据
);

	//----------------寄存器信号----------------//
	// 每一位表示连续接收开启资格的一个采样周期。
	reg [7:0]reg_enable_history = 8'd0;         // 八级历史排除关闭期间的同步残留

	//-----------------其他信号-----------------//
	// 接收资格与当前方向共同构成放行条件。
	wire sig_gate_product;                      // 已排空历史采样且当前允许接收

	//-----------------输出信号-----------------//
	//串行接收接口
	// 输出组合节点仅依赖使能、末级历史及同步电平。
	wire uart_sin_o;                            // 内部空闲钳位结果

	//---------------其他信号连线---------------//
	//其他信号连线
	assign sig_gate_product = i_rx_enable && reg_enable_history[7]; // 当前使能直接参与禁止通路
	assign uart_sin_o = !sig_gate_product || i_rx_sync; // 非合格窗口始终保持停止位电平

	//---------------输出信号连线---------------//
	//串行接收接口
	assign o_uart_sin = uart_sin_o;             // 将隔离后的串行电平连接至端口

	//-------------主要任务处理区域-------------//
	// 连续开启八拍后允许接收，任意关闭周期重新开始等待。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_enable_history <= 8'd0;         // 复位使未完成的接收窗口立即失效
		end else if(i_rx_enable == 1'b0)begin
			reg_enable_history <= 8'd0;         // 关闭后不沿用上一次开启资格
		end else begin
			reg_enable_history <= {reg_enable_history[6:0], 1'b1}; // 当前开启采样逐拍向末级推进
		end
	end

endmodule
