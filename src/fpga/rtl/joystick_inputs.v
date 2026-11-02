`timescale 1ns/1ps
 
 
module joystick_inputs (
    input wire i_clk,
    input wire i_rstn,
    input wire i_axis_x_p,
    input wire i_axis_x_n,
    input wire i_axis_y_p,
    input wire i_axis_y_n,
    input wire [4:0] i_keys_n,
    output wire [11:0] o_axis_x,
    output wire [11:0] o_axis_y,
    output wire [4:0] o_keys,
    output wire [31:0] o_samples
);
    wire [15:0] wire_analog_p = {6'd0,i_axis_y_p,7'd0,i_axis_x_p,1'b0};
    wire [15:0] wire_analog_n = {6'd0,i_axis_y_n,7'd0,i_axis_x_n,1'b0};
    wire [4:0] wire_channel;
    wire [15:0] wire_data;
    wire flag_conversion,flag_ready;
    reg [4:0] reg_channel;
    reg [11:0] reg_axis_x,reg_axis_y;
    reg [31:0] cnt_samples;
    (* ASYNC_REG="TRUE" *) reg [4:0] reg_keys_meta,reg_keys_sync,reg_keys_stable;
    assign o_axis_x=reg_axis_x;
    assign o_axis_y=reg_axis_y;
    assign o_keys=~reg_keys_stable;
    assign o_samples=cnt_samples;
     
     
    XADC #(
        .INIT_40(16'h1000),.INIT_41(16'h2f0f),.INIT_42(16'h0400),
        .INIT_48(16'h0000),.INIT_49(16'h0202),
        .INIT_4A(16'h0000),.INIT_4B(16'h0202),
        .INIT_4C(16'h0000),.INIT_4D(16'h0000),
        .INIT_4E(16'h0000),.INIT_4F(16'h0202),
        .SIM_DEVICE("ZYNQ")
    ) analog_converter (
        .DCLK(i_clk),.RESET(!i_rstn),
        .DADDR({2'b00,wire_channel}),.DEN(flag_conversion),
        .DWE(1'b0),.DI(16'd0),.DO(wire_data),.DRDY(flag_ready),
        .EOC(flag_conversion),.CHANNEL(wire_channel),
        .VAUXP(wire_analog_p),.VAUXN(wire_analog_n),
        .VP(1'b0),.VN(1'b0),.CONVST(1'b0),.CONVSTCLK(1'b0),
        .ALM(),.BUSY(),.EOS(),.JTAGBUSY(),.JTAGLOCKED(),.JTAGMODIFIED(),
        .MUXADDR(),.OT()
    );
    always @(posedge i_clk) begin
        if(!i_rstn) begin
            reg_axis_x<=12'd2048;reg_axis_y<=12'd2048;
            cnt_samples<=0;reg_channel<=0;
            reg_keys_meta<=5'b11111;reg_keys_sync<=5'b11111;reg_keys_stable<=5'b11111;
        end else begin
            reg_keys_meta<=i_keys_n;
            reg_keys_sync<=reg_keys_meta;
            reg_keys_stable<=reg_keys_sync;
            if(flag_conversion)reg_channel<=wire_channel;
            if(flag_ready)begin
                if(reg_channel==5'h11)reg_axis_x<=wire_data[15:4];
                if(reg_channel==5'h19)begin
                    reg_axis_y<=wire_data[15:4];cnt_samples<=cnt_samples+1'b1;
                end
            end
        end
    end
endmodule
