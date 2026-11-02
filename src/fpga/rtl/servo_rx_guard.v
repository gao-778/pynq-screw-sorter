`timescale 1ns / 1ps

module servo_rx_guard
(
	 
	input i_clk,                                 
	input i_rstn,                                

	 
	input i_rx_enable,                           
	input i_rx_sync,                             

	 
	output o_uart_sin                            
);

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
			reg_enable_history <= {reg_enable_history[6:0], 1'b1};  
		end
	end

endmodule
