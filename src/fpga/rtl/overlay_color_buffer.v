`timescale 1ns / 1ps
 
 
module overlay_color_buffer (
    input wire i_clk,
    input wire i_write_enable,
    input wire [17:0] i_write_address,
    input wire [2:0] i_write_color,
    input wire [17:0] i_read_address,
    output wire [2:0] o_read_color
);
     
     
    (* ram_style = "block" *) reg [2:0] reg_block_low [0:65535];
    (* ram_style = "block" *) reg [2:0] reg_block_high [0:32767];
    (* ram_style = "distributed" *) reg [2:0] reg_tail [0:55295];
    reg [2:0] reg_low_read;
    reg [2:0] reg_high_read;
    reg [2:0] reg_tail_read;
    reg [1:0] reg_segment;
    reg flag_valid;
    wire [15:0] wire_read_tail;
    wire [15:0] wire_write_tail;
    assign wire_read_tail = i_read_address[15:0] - 16'h8000;
    assign wire_write_tail = i_write_address[15:0] - 16'h8000;
    assign o_read_color = !flag_valid ? 3'd0 :
                          reg_segment == 0 ? reg_low_read :
                          reg_segment == 1 ? reg_high_read : reg_tail_read;

    // Memory is not reset; renderer publishes a bank only after every pixel is written.
    // 中文：不复位RAM；上层完整绘制后才发布，前台绝不读尚未初始化的帧。
    always @(posedge i_clk) begin
        flag_valid <= i_read_address < 18'd153600;
        reg_segment <= i_read_address < 18'd65536 ? 2'd0 :
                       i_read_address < 18'd98304 ? 2'd1 : 2'd2;
        reg_low_read <= reg_block_low[i_read_address[15:0]];
        reg_high_read <= reg_block_high[i_read_address[14:0]];
        reg_tail_read <= reg_tail[wire_read_tail];
        if (i_write_enable && i_write_address < 18'd65536)
            reg_block_low[i_write_address[15:0]] <= i_write_color;
        if (i_write_enable && i_write_address >= 18'd65536 && i_write_address < 18'd98304)
            reg_block_high[i_write_address[14:0]] <= i_write_color;
        if (i_write_enable && i_write_address >= 18'd98304 && i_write_address < 18'd153600)
            reg_tail[wire_write_tail] <= i_write_color;
    end
endmodule
