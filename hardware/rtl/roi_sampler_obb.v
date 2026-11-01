`timescale 1ns / 1ps
// Sample a 64x64 rotated grid inside a diagonal-safe square around the AABB center.
// 旋转 ROI 边长取 AABB 对角线向上取整，以保护斜放目标。
module roi_sampler_obb #(
    parameter C_WIDTH=1280,
    parameter C_HEIGHT=960
    ) (
    input i_clk,
    input i_rstn,
    input i_start,
    input [10:0] i_xmin,
    input [10:0] i_ymin,
    input [10:0] i_xmax,
    input [10:0] i_ymax,
    input [20:0] i_area,
    input [3:0] i_angle_index,
    input [7:0] i_threshold,
    output [20:0] o_read_address,
    output o_read_enable,
    input [7:0] i_read_data,
    input i_read_valid,
    output o_write,
    output [11:0] o_write_address,
    output [7:0] o_write_data,
    output [6:0] o_short_side,
    output [6:0] o_long_side,
    output [6:0] o_area,
    output o_done
);
localparam ST_IDLE=0, ST_SIZE=1, ST_ORIGIN=2, ST_LOCAL=3,
           ST_MUL=4, ST_COORD=5, ST_ADDRESS=6, ST_WAIT=7,
           ST_WRITE=8, ST_NEXT=9, ST_DONE=10, ST_DIAGONAL=11,
           ST_SQRT_INIT=12, ST_SQRT_MUL=13, ST_SQRT_TEST=14,
           ST_SQRT_DONE=15;
reg [3:0] state_current, state_next;
reg [10:0] reg_width, reg_height, reg_side;
reg [10:0] reg_center_x, reg_center_y;
reg signed [15:0] reg_local_x, reg_local_y;
reg signed [31:0] reg_prod_xc, reg_prod_ys, reg_prod_xs, reg_prod_yc;
reg signed [11:0] reg_source_x, reg_source_y;
reg [10:0] reg_xmin, reg_ymin, reg_xmax, reg_ymax;
reg [11:0] cnt_destination;
reg [20:0] reg_read_address_o, reg_area;
reg flag_inside;
reg [6:0] reg_short_o, reg_long_o, reg_area_o;
reg [21:0] reg_width_square,reg_height_square,reg_diagonal_square;
reg [10:0] reg_root,reg_root_mask,reg_trial;
reg [21:0] reg_trial_square,reg_root_square;
reg [7:0] reg_gray,reg_threshold;
wire [16:0] dec_scaled_x = {11'd0,cnt_destination[5:0]} * {6'd0,reg_side};
wire [16:0] dec_scaled_y = {11'd0,cnt_destination[11:6]} * {6'd0,reg_side};
assign o_read_address=reg_read_address_o;
assign o_read_enable=state_current==ST_WAIT && flag_inside;
assign o_write=state_current==ST_WRITE;
assign o_write_address=cnt_destination;
assign o_write_data=flag_inside && reg_gray>reg_threshold ? {1'b0,reg_gray[7:1]} : 8'd0;
assign o_short_side=reg_short_o;
assign o_long_side=reg_long_o;
assign o_area=reg_area_o;
assign o_done=state_current==ST_DONE;

// Q1.8 sine/cosine table. Index 0..15 maps to 0..168.75 degrees
// in 11.25 degree steps. The 180 degree endpoint is equivalent to 0 for
// an unoriented rectangle and is intentionally not duplicated.
reg signed [15:0] dec_cos_q8, dec_sin_q8;
always @(*) begin
    dec_cos_q8=16'sd256;
    dec_sin_q8=16'sd0;
    case (i_angle_index)
        4'd0:  begin dec_cos_q8=16'sd256;  dec_sin_q8=16'sd0;   end
        4'd1:  begin dec_cos_q8=16'sd251;  dec_sin_q8=16'sd50;  end
        4'd2:  begin dec_cos_q8=16'sd237;  dec_sin_q8=16'sd98;  end
        4'd3:  begin dec_cos_q8=16'sd212;  dec_sin_q8=16'sd143; end
        4'd4:  begin dec_cos_q8=16'sd181;  dec_sin_q8=16'sd181; end
        4'd5:  begin dec_cos_q8=16'sd143;  dec_sin_q8=16'sd212; end
        4'd6:  begin dec_cos_q8=16'sd98;   dec_sin_q8=16'sd237; end
        4'd7:  begin dec_cos_q8=16'sd50;   dec_sin_q8=16'sd251; end
        4'd8:  begin dec_cos_q8=16'sd0;    dec_sin_q8=16'sd256; end
        4'd9:  begin dec_cos_q8=-16'sd50;  dec_sin_q8=16'sd251; end
        4'd10: begin dec_cos_q8=-16'sd98;  dec_sin_q8=16'sd237; end
        4'd11: begin dec_cos_q8=-16'sd143; dec_sin_q8=16'sd212; end
        4'd12: begin dec_cos_q8=-16'sd181; dec_sin_q8=16'sd181; end
        4'd13: begin dec_cos_q8=-16'sd212; dec_sin_q8=16'sd143; end
        4'd14: begin dec_cos_q8=-16'sd237; dec_sin_q8=16'sd98;  end
        default: begin dec_cos_q8=-16'sd251; dec_sin_q8=16'sd50; end
    endcase
end
wire signed [31:0] dec_rot_x=(reg_prod_xc-reg_prod_ys) >>> 8;
wire signed [31:0] dec_rot_y=(reg_prod_xs+reg_prod_yc) >>> 8;

always @(posedge i_clk) begin
    if(!i_rstn) state_current<=ST_IDLE;
    else state_current<=state_next;
end
always @(*) begin
    state_next=state_current;
    case(state_current)
        ST_IDLE: if(i_start) state_next=ST_SIZE;
        ST_SIZE: state_next=ST_DIAGONAL;
        ST_DIAGONAL: state_next=ST_SQRT_INIT;
        ST_SQRT_INIT: state_next=ST_SQRT_MUL;
        ST_SQRT_MUL: state_next=ST_SQRT_TEST;
        ST_SQRT_TEST: if(reg_root_mask==1) state_next=ST_SQRT_DONE;
                      else state_next=ST_SQRT_MUL;
        ST_SQRT_DONE: state_next=ST_ORIGIN;
        ST_ORIGIN: state_next=ST_LOCAL;
        ST_LOCAL: state_next=ST_MUL;
        ST_MUL: state_next=ST_COORD;
        ST_COORD: state_next=ST_ADDRESS;
        ST_ADDRESS: state_next=ST_WAIT;
        ST_WAIT: if(i_read_valid || !flag_inside) state_next=ST_WRITE;
        ST_WRITE: state_next=ST_NEXT;
        ST_NEXT: if(cnt_destination==4095) state_next=ST_DONE; else state_next=ST_LOCAL;
        ST_DONE: state_next=ST_IDLE;
        default: state_next=ST_IDLE;
    endcase
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_width<=0; reg_height<=0; reg_side<=0;
        reg_center_x<=0; reg_center_y<=0;
        reg_local_x<=0; reg_local_y<=0;
        reg_prod_xc<=0; reg_prod_ys<=0; reg_prod_xs<=0; reg_prod_yc<=0;
        reg_source_x<=0; reg_source_y<=0;
        reg_xmin<=0; reg_ymin<=0; reg_xmax<=0; reg_ymax<=0;
        cnt_destination<=0; reg_read_address_o<=0; reg_area<=0;
        flag_inside<=0; reg_short_o<=0; reg_long_o<=0; reg_area_o<=0;
        reg_width_square<=0; reg_height_square<=0; reg_diagonal_square<=0;
        reg_root<=0; reg_root_mask<=0; reg_trial<=0;
        reg_trial_square<=0; reg_root_square<=0; reg_gray<=0; reg_threshold<=0;
    end else begin
        case(state_current)
            ST_IDLE: if(i_start) begin
                reg_xmin<=i_xmin; reg_ymin<=i_ymin;
                reg_xmax<=i_xmax; reg_ymax<=i_ymax;
                reg_width<={1'b0,i_xmax}-{1'b0,i_xmin}+1'b1;
                reg_height<={1'b0,i_ymax}-{1'b0,i_ymin}+1'b1;
                reg_area<=i_area; cnt_destination<=0; reg_threshold<=i_threshold;
            end
            ST_SIZE: begin
                reg_width_square<=reg_width*reg_width;
                reg_height_square<=reg_height*reg_height;
                if(reg_width<reg_height) reg_short_o<=reg_width>=508 ? 127 : reg_width[8:2];
                else reg_short_o<=reg_height>=508 ? 127 : reg_height[8:2];
                reg_area_o<=reg_area>=2032 ? 127 : reg_area[10:4];
            end
            ST_DIAGONAL: reg_diagonal_square<=reg_width_square+reg_height_square;
            ST_SQRT_INIT: begin
                reg_root<=0; reg_root_square<=0; reg_root_mask<=11'd1024;
            end
            ST_SQRT_MUL: begin
                reg_trial<=reg_root|reg_root_mask;
                reg_trial_square<=(reg_root|reg_root_mask)*(reg_root|reg_root_mask);
            end
            ST_SQRT_TEST: begin
                if(reg_trial_square<=reg_diagonal_square) begin
                    reg_root<=reg_trial; reg_root_square<=reg_trial_square;
                end
                reg_root_mask<=reg_root_mask>>1;
            end
            ST_SQRT_DONE: reg_side<=reg_root+(reg_root_square<reg_diagonal_square ? 11'd1 : 11'd0);
            ST_ORIGIN: begin
                reg_center_x<=({1'b0,reg_xmin}+{1'b0,reg_xmax})>>1;
                reg_center_y<=({1'b0,reg_ymin}+{1'b0,reg_ymax})>>1;
                reg_long_o<=reg_side>=508 ? 127 : reg_side[8:2];
            end
            ST_LOCAL: begin
                reg_local_x<=$signed({1'b0,dec_scaled_x[16:6]})-$signed({1'b0,reg_side[10:1]});
                reg_local_y<=$signed({1'b0,dec_scaled_y[16:6]})-$signed({1'b0,reg_side[10:1]});
            end
            ST_MUL: begin
                reg_prod_xc<=reg_local_x*dec_cos_q8;
                reg_prod_ys<=reg_local_y*dec_sin_q8;
                reg_prod_xs<=reg_local_x*dec_sin_q8;
                reg_prod_yc<=reg_local_y*dec_cos_q8;
            end
            ST_COORD: begin
                reg_source_x <= $signed({1'b0,reg_center_x}) + $signed(dec_rot_x[11:0]);
                reg_source_y <= $signed({1'b0,reg_center_y}) + $signed(dec_rot_y[11:0]);
            end
            ST_ADDRESS: begin
                // Keep diagonal-safe sampling, but exclude neighboring objects
                // outside this target's source rectangle before CNN ingress.
                flag_inside <= reg_source_x>=0 && reg_source_x<C_WIDTH && reg_source_y>=0 && reg_source_y<C_HEIGHT &&
                    reg_source_x>=$signed({1'b0,reg_xmin}) && reg_source_x<=$signed({1'b0,reg_xmax}) &&
                    reg_source_y>=$signed({1'b0,reg_ymin}) && reg_source_y<=$signed({1'b0,reg_ymax});
                if(reg_source_x<0 || reg_source_y<0 || reg_source_x>=C_WIDTH || reg_source_y>=C_HEIGHT)
                    reg_read_address_o<=0;
                else reg_read_address_o<=reg_source_y*C_WIDTH+reg_source_x;
            end
            ST_WAIT: if(i_read_valid && flag_inside) reg_gray<=i_read_data;
            ST_NEXT: cnt_destination<=cnt_destination+1'b1;
            default: begin end
        endcase
    end
end
endmodule
