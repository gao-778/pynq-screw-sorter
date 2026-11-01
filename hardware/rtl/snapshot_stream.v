`timescale 1ns/1ps
// One-shot RGB565 frame capture. A stalled downstream never corrupts silently:
// overflow or an early next frame latches error and the CPU discards the DMA.
module snapshot_stream #(
    parameter integer FRAME_PIXELS = 307200,
    parameter integer C_SOFT_RESET = 0
) (
    input wire clk,
    input wire reset_n,
    input wire [31:0] i_control,
    output wire o_fifo_rstn,
    input wire arm_async,
    input wire frame_start,
    input wire pixel_valid,
    input wire [23:0] pixel_rgb,
    output wire [31:0] m_axis_tdata,
    output wire [3:0] m_axis_tkeep,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,
    output wire busy,
    output wire done,
    output wire error
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] arm_sync = 0;
    reg active = 0;
    reg complete = 0;
    reg failed = 0;
    reg [20:0] pixel_count = 0;
    wire wire_reset_n=reset_n && (C_SOFT_RESET==0 || i_control[3]);
    (* ASYNC_REG="TRUE" *) reg [2:0] reg_local_reset=0;
    always @(posedge clk or negedge wire_reset_n) begin
        if(!wire_reset_n)reg_local_reset<=0;
        else reg_local_reset<={reg_local_reset[1:0],1'b1};
    end
    assign o_fifo_rstn=reg_local_reset[2];
    reg [31:0] stream_data = 0;
    reg stream_valid = 0;
    reg stream_last = 0;
    wire begin_frame = arm_sync[1] && !active && !complete && !failed && frame_start;
    wire slot_available = !stream_valid || m_axis_tready;
    assign m_axis_tdata = stream_data;
    assign m_axis_tkeep = 4'hf;
    assign m_axis_tvalid = stream_valid;
    assign m_axis_tlast = stream_last;
    assign busy = active;
    assign done = complete;
    assign error = failed;
    always @(posedge clk) begin
        if (!reg_local_reset[2]) begin
            arm_sync <= 0;
            active <= 0;
            complete <= 0;
            failed <= 0;
            pixel_count <= 0;
            stream_valid <= 0;
            stream_last <= 0;
        end else begin
            arm_sync <= {arm_sync[0], arm_async};
            if (stream_valid && m_axis_tready) begin
                stream_valid <= 0;
                stream_last <= 0;
            end
            if (!arm_sync[1] && !active) begin
                complete <= 0;
                failed <= 0;
                pixel_count <= 0;
            end
            if (begin_frame) begin
                active <= 1;
                pixel_count <= 0;
            end
            if (active && frame_start) begin
                failed <= 1;
                active <= 0;
            end else if ((active || begin_frame) && pixel_valid) begin
                if (!slot_available) begin
                    failed <= 1;
                    active <= 0;
                end else begin
                    stream_data <= {16'd0, pixel_rgb[23:19], pixel_rgb[15:10], pixel_rgb[7:3]};
                    stream_valid <= 1;
                    stream_last <= (pixel_count == FRAME_PIXELS-1);
                    pixel_count <= pixel_count + 1'b1;
                    if (pixel_count == FRAME_PIXELS-1) begin
                        active <= 0;
                        complete <= 1;
                    end
                end
            end
        end
    end
endmodule

