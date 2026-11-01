`timescale 1ns/1ps
// Capture grayscale to DMA; completion requires camera handshake and DMA IOC.
// 灰度帧捕获至DDR：最后像素不等于DDR写完，必须等待DMA完成中断。
module frame_snapshot #(
    parameter C_WIDTH=1280, parameter C_HEIGHT=960,
    parameter integer C_CONTROL_HZ=100000000
) (
    input i_clk, input i_rstn, input i_start,
    input i_camera_clk, input i_frame_start, input i_line_start, input i_pixel_valid,
    input [23:0] i_rgb, input i_dma_done,
    output [31:0] o_stream_data, output [3:0] o_stream_keep,
    output o_stream_valid, input i_stream_ready, output o_stream_last,
    output o_camera_rstn, output o_done, output o_error,
    output o_capture_active, output o_preview_hold,
    output [30:0] o_capture_age_ms, output o_capture_age_valid
);
(* ASYNC_REG="TRUE" *) reg [1:0] reg_camera_reset;
(* ASYNC_REG="TRUE" *) reg [1:0] reg_request_sync;
(* ASYNC_REG="TRUE" *) reg [1:0] reg_complete_sync, reg_error_sync;
(* ASYNC_REG="TRUE" *) reg [1:0] reg_started_sync;
reg reg_started_token;
reg flag_age_valid;
reg [30:0] cnt_age_ms;
reg [31:0] cnt_age_tick;
localparam integer C_TICKS_PER_MS=C_CONTROL_HZ/1000;
reg reg_request, reg_seen, reg_complete, reg_dma_done;
reg flag_busy, flag_failed, flag_armed, flag_capturing;
reg [20:0] cnt_pixel;
reg [10:0] cnt_line_pixel,cnt_line;
reg [23:0] reg_partial;
reg [31:0] reg_stream_data;
reg flag_stream_valid, flag_stream_last;
wire [7:0] dec_gray={2'b0,i_rgb[23:18]}+{1'b0,i_rgb[15:9]}+{2'b0,i_rgb[7:2]};
assign o_stream_data=reg_stream_data;
assign o_stream_keep=4'hf;
assign o_stream_valid=flag_stream_valid;
assign o_stream_last=flag_stream_last;
assign o_camera_rstn=reg_camera_reset[1];
assign o_done=!flag_busy;
assign o_error=reg_error_sync[1];
assign o_capture_active=flag_capturing;
assign o_preview_hold=0;
assign o_capture_age_ms=cnt_age_ms;
assign o_capture_age_valid=flag_age_valid;
// The request may wait for VSYNC. Only the armed frame-start token starts age.
// The host reads age before the next capture and subtracts one extra ms for
// counter quantization and the two-stage clock-domain synchronization delay.
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_started_sync<=0;flag_age_valid<=0;cnt_age_ms<=0;cnt_age_tick<=0;
    end else begin
        reg_started_sync<={reg_started_sync[0],reg_started_token};
        if(i_start) begin
            flag_age_valid<=0;cnt_age_ms<=0;cnt_age_tick<=0;
        end else if(!flag_age_valid && flag_busy && reg_started_sync[1]==reg_request) begin
            flag_age_valid<=1;cnt_age_ms<=0;cnt_age_tick<=0;
        end else if(flag_age_valid && cnt_age_ms!=31'h7fffffff) begin
            if(cnt_age_tick==C_TICKS_PER_MS-1) begin
                cnt_age_tick<=0;cnt_age_ms<=cnt_age_ms+1'b1;
            end else cnt_age_tick<=cnt_age_tick+1'b1;
        end
    end
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_request<=0;reg_complete_sync<=0;reg_error_sync<=0;flag_busy<=0;reg_dma_done<=0;
    end else begin
        reg_complete_sync<={reg_complete_sync[0],reg_complete};
        reg_error_sync<={reg_error_sync[0],flag_failed};
        if(i_start) begin
            reg_request<=~reg_request;flag_busy<=1;reg_dma_done<=0;
        end else begin
            if(i_dma_done) reg_dma_done<=1;
            if(flag_busy && reg_complete_sync[1]==reg_request &&
               (reg_dma_done || i_dma_done || reg_error_sync[1])) flag_busy<=0;
        end
    end
end
always @(posedge i_camera_clk or negedge i_rstn) begin
    if(!i_rstn) reg_camera_reset<=0;
    else reg_camera_reset<={reg_camera_reset[0],1'b1};
end
always @(posedge i_camera_clk) begin
    if(!reg_camera_reset[1]) begin
        reg_request_sync<=0;reg_seen<=0;reg_complete<=0;reg_started_token<=0;
        flag_failed<=0;flag_armed<=0;flag_capturing<=0;cnt_pixel<=0;
        cnt_line_pixel<=0;cnt_line<=0;
        reg_partial<=0;reg_stream_data<=0;flag_stream_valid<=0;flag_stream_last<=0;
    end else begin
        reg_request_sync<={reg_request_sync[0],reg_request};
        if(flag_stream_valid && i_stream_ready) begin flag_stream_valid<=0;flag_stream_last<=0;end
        if(reg_request_sync[1]!=reg_seen) begin
            reg_seen<=reg_request_sync[1];flag_failed<=0;flag_armed<=1;
            flag_capturing<=0;cnt_pixel<=0;reg_partial<=0;
        end else if(i_frame_start && flag_armed) begin
            flag_armed<=0;flag_capturing<=1;cnt_pixel<=0;cnt_line_pixel<=0;
            // DVP may start the first line on the same edge as the frame.
            // 中文：场沿与首行沿同拍时保留首行；RGB565 首像素仍在后续拍到达。
            cnt_line<=i_line_start?11'd1:11'd0;
            reg_started_token<=reg_seen;
        end else if(flag_capturing) begin
            if(i_frame_start) begin
                flag_failed<=1;flag_capturing<=0;reg_complete<=reg_seen;
            end else if(i_line_start) begin
                if((cnt_line!=0 && cnt_line_pixel!=C_WIDTH) || cnt_line>=C_HEIGHT) begin
                    flag_failed<=1;flag_capturing<=0;reg_complete<=reg_seen;
                end
                cnt_line<=cnt_line+1'b1;cnt_line_pixel<=0;
            end else if(i_pixel_valid) begin
                cnt_line_pixel<=cnt_line_pixel+1'b1;
                if(cnt_line==0 || cnt_line_pixel>=C_WIDTH)begin
                    flag_failed<=1;flag_capturing<=0;reg_complete<=reg_seen;
                end
                case(cnt_pixel[1:0])
                    0: reg_partial[7:0]<=dec_gray;
                    1: reg_partial[15:8]<=dec_gray;
                    2: reg_partial[23:16]<=dec_gray;
                    3: begin
                        if(flag_stream_valid && !i_stream_ready) begin
                            flag_failed<=1;flag_capturing<=0;reg_complete<=reg_seen;
                        end else begin
                            reg_stream_data<={dec_gray,reg_partial};flag_stream_valid<=1;
                            flag_stream_last<=cnt_pixel==C_WIDTH*C_HEIGHT-1;
                        end
                    end
                endcase
                if(cnt_pixel==C_WIDTH*C_HEIGHT-1) begin
                    if(cnt_line!=C_HEIGHT || cnt_line_pixel!=C_WIDTH-1)flag_failed<=1;
                    flag_capturing<=0;reg_complete<=reg_seen;
                end else cnt_pixel<=cnt_pixel+1'b1;
            end
        end
    end
end
endmodule
