`timescale 1ns/1ps
 
 
module preview_area_average #(
    parameter C_WIDTH = 1280,
    parameter C_HEIGHT = 960
)(
    input wire i_clk,
    input wire i_rstn,
    input wire i_frame_start,
    input wire i_line_start,
    input wire i_valid,
    input wire [23:0] i_rgb,
    output wire o_valid,
    output wire [23:0] o_rgb,
    output wire o_frame_error
);
     
     
    reg [10:0] cnt_column;
    reg [10:0] cnt_row;
    reg [9:0] reg_horizontal_red;
    reg [9:0] reg_horizontal_green;
    reg [9:0] reg_horizontal_blue;
    reg flag_frame_error_o;
    wire flag_short_line = i_line_start && cnt_row < C_HEIGHT && cnt_column != C_WIDTH;
    wire flag_long_line = i_valid && !i_line_start && cnt_row < C_HEIGHT && cnt_column >= C_WIDTH;
    wire flag_bad_line = flag_short_line || flag_long_line;
    wire flag_position = cnt_column < C_WIDTH && cnt_row < C_HEIGHT;
    wire flag_pixel = i_valid && flag_position && !i_frame_start && !i_line_start && !flag_frame_error_o;
    wire [9:0] dec_horizontal_red = reg_horizontal_red + {2'd0,i_rgb[23:16]};
    wire [9:0] dec_horizontal_green = reg_horizontal_green + {2'd0,i_rgb[15:8]};
    wire [9:0] dec_horizontal_blue = reg_horizontal_blue + {2'd0,i_rgb[7:0]};

    // One partial-sum row replaces three full source lines. First row ignores
    // stale RAM, so frame restart never requires resetting memory contents.
    // 一行竖向部分和代替三整行；每四行的首行忽略旧存储，无需复位BRAM。
    (* ram_style = "block" *) reg [35:0] reg_partial [0:C_WIDTH/4-1];
    reg [35:0] reg_partial_read;
    reg [8:0] reg_write_column;
    reg [11:0] reg_total_red;
    reg [11:0] reg_total_green;
    reg [11:0] reg_total_blue;
    reg flag_sum_pending;
    reg flag_final_row;
    wire [11:0] dec_previous_red = cnt_row[1:0] == 0 ? 12'd0 : reg_partial_read[35:24];
    wire [11:0] dec_previous_green = cnt_row[1:0] == 0 ? 12'd0 : reg_partial_read[23:12];
    wire [11:0] dec_previous_blue = cnt_row[1:0] == 0 ? 12'd0 : reg_partial_read[11:0];

    always @(posedge i_clk) begin
        if (i_rstn && flag_pixel && cnt_column[1:0] == 0)
            reg_partial_read <= reg_partial[cnt_column[10:2]];
        if (i_rstn && !i_frame_start && !flag_frame_error_o && !flag_bad_line && flag_sum_pending)
            reg_partial[reg_write_column] <= {reg_total_red,reg_total_green,reg_total_blue};
    end

    wire [11:0] dec_rounded_red = reg_total_red + 12'd8;
    wire [11:0] dec_rounded_green = reg_total_green + 12'd8;
    wire [11:0] dec_rounded_blue = reg_total_blue + 12'd8;
    reg flag_valid_o;
    reg [23:0] reg_rgb_o;
    assign o_valid = flag_valid_o;
    assign o_rgb = reg_rgb_o;
    assign o_frame_error = flag_frame_error_o;

    always @(posedge i_clk) begin
        if (!i_rstn || i_frame_start) begin
            cnt_column <= 0;
            cnt_row <= i_rstn && i_line_start ? 11'd0 : 11'd2047;
            reg_horizontal_red <= 0;
            reg_horizontal_green <= 0;
            reg_horizontal_blue <= 0;
            reg_write_column <= 0;
            reg_total_red <= 0;
            reg_total_green <= 0;
            reg_total_blue <= 0;
            flag_sum_pending <= 0;
            flag_final_row <= 0;
            flag_valid_o <= 0;
            flag_frame_error_o <= 0;
            reg_rgb_o <= 0;
        end else begin
            flag_sum_pending <= 0;
            flag_valid_o <= flag_sum_pending && flag_final_row && !flag_frame_error_o && !flag_bad_line;
            if (flag_bad_line) flag_frame_error_o <= 1;
            if (flag_sum_pending && flag_final_row)
                reg_rgb_o <= {dec_rounded_red[11:4],dec_rounded_green[11:4],dec_rounded_blue[11:4]};

            // A line boundary does not discard the previous line's pending
             
             
            if (i_line_start) begin
                cnt_column <= 0;
                if (cnt_row == 2047) cnt_row <= 0;
                else if (cnt_row < C_HEIGHT) cnt_row <= cnt_row + 1'b1;
                reg_horizontal_red <= 0;
                reg_horizontal_green <= 0;
                reg_horizontal_blue <= 0;
            end else if (flag_pixel) begin
                cnt_column <= cnt_column + 1'b1;
                if (cnt_column[1:0] == 0) begin
                    reg_horizontal_red <= {2'd0,i_rgb[23:16]};
                    reg_horizontal_green <= {2'd0,i_rgb[15:8]};
                    reg_horizontal_blue <= {2'd0,i_rgb[7:0]};
                end else begin
                    reg_horizontal_red <= dec_horizontal_red;
                    reg_horizontal_green <= dec_horizontal_green;
                    reg_horizontal_blue <= dec_horizontal_blue;
                end
                if (cnt_column[1:0] == 3) begin
                    reg_total_red <= {2'd0,dec_horizontal_red} + dec_previous_red;
                    reg_total_green <= {2'd0,dec_horizontal_green} + dec_previous_green;
                    reg_total_blue <= {2'd0,dec_horizontal_blue} + dec_previous_blue;
                    reg_write_column <= cnt_column[10:2];
                    flag_sum_pending <= 1;
                    flag_final_row <= cnt_row[1:0] == 3;
                end
            end
        end
    end
endmodule
