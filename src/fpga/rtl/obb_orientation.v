`timescale 1ns / 1ps
 
 
module obb_orientation #(
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
    input [7:0] i_threshold,
    input i_bright,
    input i_manual,
    input [3:0] i_manual_angle,
    output [20:0] o_read_address,
    output o_read_enable,
    input [7:0] i_read_data,
    input i_read_valid,
    output [3:0] o_angle_index,
    output signed [15:0] o_local_xmin,
    output signed [15:0] o_local_ymin,
    output signed [15:0] o_local_xmax,
    output signed [15:0] o_local_ymax,
    output [6:0] o_length,
    output [6:0] o_head_width,
    output [6:0] o_tail_width,
    output o_done
);
localparam ST_IDLE=0, ST_ADDRESS=1, ST_WAIT=2, ST_DELTA=3,
    ST_MOMENT_MUL=4, ST_MOMENT_ACC=5, ST_NEXT=6,
    ST_AXES=7, ST_COEFFICIENT=8, ST_SCORE_MUL=9,
    ST_SCORE_SUM=10, ST_SCORE_SELECT=11, ST_PROJECT_INIT=12,
    ST_PROJECT_MUL=13, ST_PROJECT_SUM=14, ST_PROJECT_BOUND=15,
    ST_FINISH=16, ST_DONE=17, ST_LENGTH=18, ST_END_LIMIT=19,
    ST_WIDTH_INIT=20, ST_WIDTH_SUM=21, ST_GEOMETRY=22;
reg [4:0] state_current,state_next;
reg [10:0] reg_xmin,reg_ymin,reg_xmax,reg_ymax;
reg [10:0] reg_center_x,reg_center_y,cnt_x,cnt_y;
reg [7:0] reg_threshold;
reg flag_bright,flag_manual,flag_foreground,flag_project;
 
 
reg [1:0] reg_foreground_history;
reg [3:0] reg_manual_angle,reg_angle_o,cnt_angle;
reg [20:0] reg_address_o,cnt_foreground;
reg signed [15:0] reg_dx,reg_dy;
reg signed [31:0] reg_xx,reg_yy,reg_xy;
reg signed [39:0] reg_mxx,reg_myy,reg_mxy;
reg signed [40:0] reg_axis_a,reg_axis_b;
reg signed [9:0] dec_cos_double,dec_sin_double;
reg signed [50:0] reg_score_a,reg_score_b;
reg signed [51:0] reg_score,reg_best_score;
reg signed [15:0] dec_cos,dec_sin;
reg signed [15:0] reg_cos,reg_sin;
reg signed [31:0] reg_xc,reg_ys,reg_xs,reg_yc;
reg signed [32:0] reg_project_x,reg_project_y;
reg signed [15:0] reg_local_xmin_o,reg_local_ymin_o;
reg signed [15:0] reg_local_xmax_o,reg_local_ymax_o;
 
reg flag_width,flag_left_seen,flag_right_seen;
reg [15:0] reg_length,reg_width_left,reg_width_right;
reg signed [15:0] reg_left_limit,reg_right_limit;
reg signed [15:0] reg_left_min,reg_left_max,reg_right_min,reg_right_max;
reg [6:0] reg_length_o,reg_head_o,reg_tail_o;
wire [15:0] dec_quarter=reg_length<4 ? 16'd1 : reg_length>>2;
wire [15:0] dec_head=reg_width_left>reg_width_right ? reg_width_left : reg_width_right;
wire [15:0] dec_tail=reg_width_left>reg_width_right ? reg_width_right : reg_width_left;
assign o_length=reg_length_o;
assign o_head_width=reg_head_o;
assign o_tail_width=reg_tail_o;
wire flag_last=cnt_x==reg_xmax && cnt_y==reg_ymax;
wire flag_foreground_now=flag_bright ? i_read_data>reg_threshold : i_read_data<reg_threshold;
wire signed [15:0] dec_local_x=reg_project_x >>> 8;
wire signed [15:0] dec_local_y=reg_project_y >>> 8;
assign o_read_address=reg_address_o;
assign o_read_enable=state_current==ST_WAIT;
assign o_angle_index=reg_angle_o;
assign o_local_xmin=reg_local_xmin_o;
assign o_local_ymin=reg_local_ymin_o;
assign o_local_xmax=reg_local_xmax_o;
assign o_local_ymax=reg_local_ymax_o;
assign o_done=state_current==ST_DONE;

// Double-angle constants implement the second-moment principal-axis score.
always @(*) begin
    dec_cos_double=10'sd256; dec_sin_double=10'sd0;
    case(cnt_angle)
        0: begin dec_cos_double=256; dec_sin_double=0; end
        1: begin dec_cos_double=237; dec_sin_double=98; end
        2: begin dec_cos_double=181; dec_sin_double=181; end
        3: begin dec_cos_double=98; dec_sin_double=237; end
        4: begin dec_cos_double=0; dec_sin_double=256; end
        5: begin dec_cos_double=-98; dec_sin_double=237; end
        6: begin dec_cos_double=-181; dec_sin_double=181; end
        7: begin dec_cos_double=-237; dec_sin_double=98; end
        8: begin dec_cos_double=-256; dec_sin_double=0; end
        9: begin dec_cos_double=-237; dec_sin_double=-98; end
        10: begin dec_cos_double=-181; dec_sin_double=-181; end
        11: begin dec_cos_double=-98; dec_sin_double=-237; end
        12: begin dec_cos_double=0; dec_sin_double=-256; end
        13: begin dec_cos_double=98; dec_sin_double=-237; end
        14: begin dec_cos_double=181; dec_sin_double=-181; end
        default: begin dec_cos_double=237; dec_sin_double=-98; end
    endcase
end
always @(*) begin
    dec_cos=16'sd256; dec_sin=16'sd0;
    case(reg_angle_o)
        0: begin dec_cos=256; dec_sin=0; end
        1: begin dec_cos=251; dec_sin=50; end
        2: begin dec_cos=237; dec_sin=98; end
        3: begin dec_cos=212; dec_sin=143; end
        4: begin dec_cos=181; dec_sin=181; end
        5: begin dec_cos=143; dec_sin=212; end
        6: begin dec_cos=98; dec_sin=237; end
        7: begin dec_cos=50; dec_sin=251; end
        8: begin dec_cos=0; dec_sin=256; end
        9: begin dec_cos=-50; dec_sin=251; end
        10: begin dec_cos=-98; dec_sin=237; end
        11: begin dec_cos=-143; dec_sin=212; end
        12: begin dec_cos=-181; dec_sin=181; end
        13: begin dec_cos=-212; dec_sin=143; end
        14: begin dec_cos=-237; dec_sin=98; end
        default: begin dec_cos=-251; dec_sin=50; end
    endcase
end
always @(posedge i_clk) begin
    if(!i_rstn) state_current<=ST_IDLE;
    else state_current<=state_next;
end
always @(*) begin
    state_next=state_current;
    case(state_current)
        ST_IDLE: if(i_start) state_next=ST_ADDRESS;
        ST_ADDRESS: state_next=ST_WAIT;
        ST_WAIT: if(i_read_valid) state_next=ST_DELTA;
        ST_DELTA: if(!flag_foreground) state_next=ST_NEXT;
                  else if(flag_project) state_next=ST_PROJECT_MUL;
                  else state_next=ST_MOMENT_MUL;
        ST_MOMENT_MUL: state_next=ST_MOMENT_ACC;
        ST_MOMENT_ACC: state_next=ST_NEXT;
        ST_NEXT: if(flag_last) begin
                    if(flag_width) state_next=ST_WIDTH_SUM;
                    else if(flag_project) state_next=ST_LENGTH;
                    else state_next=ST_AXES;
                 end else state_next=ST_ADDRESS;
        ST_AXES: if(flag_manual) state_next=ST_PROJECT_INIT;
                 else state_next=ST_COEFFICIENT;
        ST_COEFFICIENT: state_next=ST_SCORE_MUL;
        ST_SCORE_MUL: state_next=ST_SCORE_SUM;
        ST_SCORE_SUM: state_next=ST_SCORE_SELECT;
        ST_SCORE_SELECT: if(cnt_angle==15) state_next=ST_PROJECT_INIT;
                         else state_next=ST_COEFFICIENT;
        ST_PROJECT_INIT: state_next=ST_ADDRESS;
        ST_PROJECT_MUL: state_next=ST_PROJECT_SUM;
        ST_PROJECT_SUM: state_next=ST_PROJECT_BOUND;
        ST_PROJECT_BOUND: state_next=ST_NEXT;
        ST_LENGTH: state_next=ST_END_LIMIT;
        ST_END_LIMIT: state_next=ST_WIDTH_INIT;
        ST_WIDTH_INIT: state_next=ST_ADDRESS;
        ST_WIDTH_SUM: state_next=ST_GEOMETRY;
        ST_GEOMETRY: state_next=ST_FINISH;
        ST_FINISH: state_next=ST_DONE;
        ST_DONE: state_next=ST_IDLE;
        default: state_next=ST_IDLE;
    endcase
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        flag_width<=0;flag_left_seen<=0;flag_right_seen<=0;
        reg_length<=0;reg_width_left<=0;reg_width_right<=0;
        reg_left_limit<=0;reg_right_limit<=0;
        reg_left_min<=0;reg_left_max<=0;reg_right_min<=0;reg_right_max<=0;
        reg_length_o<=0;reg_head_o<=0;reg_tail_o<=0;
        reg_xmin<=0; reg_ymin<=0; reg_xmax<=0; reg_ymax<=0;
        reg_center_x<=0; reg_center_y<=0; cnt_x<=0; cnt_y<=0;
        reg_threshold<=0; flag_bright<=1; flag_manual<=0;
        flag_foreground<=0; flag_project<=0;
        reg_foreground_history<=0;
        reg_manual_angle<=0; reg_angle_o<=0; cnt_angle<=0;
        reg_address_o<=0; cnt_foreground<=0;
        reg_dx<=0; reg_dy<=0; reg_xx<=0; reg_yy<=0; reg_xy<=0;
        reg_mxx<=0; reg_myy<=0; reg_mxy<=0;
        reg_axis_a<=0; reg_axis_b<=0;
        reg_score_a<=0; reg_score_b<=0; reg_score<=0; reg_best_score<=0;
        reg_cos<=256; reg_sin<=0;
        reg_xc<=0; reg_ys<=0; reg_xs<=0; reg_yc<=0;
        reg_project_x<=0; reg_project_y<=0;
        reg_local_xmin_o<=0; reg_local_ymin_o<=0;
        reg_local_xmax_o<=0; reg_local_ymax_o<=0;
    end else begin
        case(state_current)
            ST_IDLE: if(i_start) begin
                reg_xmin<=i_xmin; reg_ymin<=i_ymin;
                reg_xmax<=i_xmax; reg_ymax<=i_ymax;
                reg_center_x<=({1'b0,i_xmin}+{1'b0,i_xmax})>>1;
                reg_center_y<=({1'b0,i_ymin}+{1'b0,i_ymax})>>1;
                cnt_x<=i_xmin; cnt_y<=i_ymin;
                reg_threshold<=i_threshold; flag_bright<=i_bright;
                flag_manual<=i_manual; reg_manual_angle<=i_manual_angle;
                flag_width<=0;
                flag_project<=0; reg_mxx<=0; reg_myy<=0; reg_mxy<=0;
                cnt_foreground<=0; reg_angle_o<=0; cnt_angle<=0;
                reg_foreground_history<=0;
                reg_best_score<=0;
                reg_local_xmin_o<=16'sd32767; reg_local_ymin_o<=16'sd32767;
                reg_local_xmax_o<=-16'sd32767; reg_local_ymax_o<=-16'sd32767;
            end
            ST_ADDRESS: reg_address_o<=cnt_y*C_WIDTH+cnt_x;
            ST_WAIT: if(i_read_valid) begin
                flag_foreground<=flag_foreground_now && (&reg_foreground_history);
                reg_foreground_history<={reg_foreground_history[0],flag_foreground_now};
            end
            ST_DELTA: begin
                reg_dx<=$signed({5'd0,cnt_x})-16'sd1-$signed({5'd0,reg_center_x});
                reg_dy<=$signed({5'd0,cnt_y})-$signed({5'd0,reg_center_y});
            end
            ST_MOMENT_MUL: begin
                reg_xx<=reg_dx*reg_dx; reg_yy<=reg_dy*reg_dy; reg_xy<=reg_dx*reg_dy;
            end
            ST_MOMENT_ACC: begin
                reg_mxx<=reg_mxx+reg_xx; reg_myy<=reg_myy+reg_yy; reg_mxy<=reg_mxy+reg_xy;
                cnt_foreground<=cnt_foreground+1'b1;
            end
            ST_NEXT: begin
                if(cnt_x==reg_xmax) begin cnt_x<=reg_xmin; cnt_y<=cnt_y+1'b1; reg_foreground_history<=0; end
                else cnt_x<=cnt_x+1'b1;
            end
            ST_AXES: begin
                reg_axis_a<=$signed({reg_mxx[39],reg_mxx})-$signed({reg_myy[39],reg_myy});
                reg_axis_b<={reg_mxy,1'b0};
                if(flag_manual) reg_angle_o<=reg_manual_angle;
            end
            ST_SCORE_MUL: begin
                reg_score_a<=reg_axis_a*dec_cos_double;
                reg_score_b<=reg_axis_b*dec_sin_double;
            end
            ST_SCORE_SUM: reg_score<=$signed({reg_score_a[50],reg_score_a})+$signed({reg_score_b[50],reg_score_b});
            ST_SCORE_SELECT: begin
                if(cnt_angle==0 || reg_score>reg_best_score) begin
                    reg_best_score<=reg_score; reg_angle_o<=cnt_angle;
                end
                cnt_angle<=cnt_angle+1'b1;
            end
            ST_PROJECT_INIT: begin
                reg_foreground_history<=0;
                cnt_x<=reg_xmin; cnt_y<=reg_ymin; flag_project<=1;
                reg_cos<=dec_cos; reg_sin<=dec_sin;
            end
            ST_PROJECT_MUL: begin
                reg_xc<=reg_dx*reg_cos; reg_ys<=reg_dy*reg_sin;
                reg_xs<=reg_dx*reg_sin; reg_yc<=reg_dy*reg_cos;
            end
            ST_PROJECT_SUM: begin
                reg_project_x<=$signed({reg_xc[31],reg_xc})+$signed({reg_ys[31],reg_ys});
                reg_project_y<=-$signed({reg_xs[31],reg_xs})+$signed({reg_yc[31],reg_yc});
            end
            ST_PROJECT_BOUND: begin
                if(flag_width) begin
                    if(dec_local_x<reg_left_limit) begin
                        flag_left_seen<=1;
                        if(dec_local_y<reg_left_min) reg_left_min<=dec_local_y;
                        if(dec_local_y>reg_left_max) reg_left_max<=dec_local_y;
                    end
                    if(dec_local_x>reg_right_limit) begin
                        flag_right_seen<=1;
                        if(dec_local_y<reg_right_min) reg_right_min<=dec_local_y;
                        if(dec_local_y>reg_right_max) reg_right_max<=dec_local_y;
                    end
                end else begin
                if(dec_local_x<reg_local_xmin_o) reg_local_xmin_o<=dec_local_x;
                if(dec_local_x>reg_local_xmax_o) reg_local_xmax_o<=dec_local_x;
                if(dec_local_y<reg_local_ymin_o) reg_local_ymin_o<=dec_local_y;
                if(dec_local_y>reg_local_ymax_o) reg_local_ymax_o<=dec_local_y;
                end
            end
            ST_LENGTH: reg_length<=reg_local_xmax_o-reg_local_xmin_o+16'd1;
            ST_END_LIMIT: begin
                reg_left_limit<=reg_local_xmin_o+$signed(dec_quarter);
                reg_right_limit<=reg_local_xmax_o-$signed(dec_quarter);
            end
            ST_WIDTH_INIT: begin
                reg_foreground_history<=0;
                cnt_x<=reg_xmin;cnt_y<=reg_ymin;flag_width<=1;
                flag_left_seen<=0;flag_right_seen<=0;
                reg_left_min<=16'sd32767;reg_right_min<=16'sd32767;
                reg_left_max<=-16'sd32767;reg_right_max<=-16'sd32767;
            end
            ST_WIDTH_SUM: begin
                reg_width_left<=flag_left_seen ? reg_left_max-reg_left_min+16'd1 : 16'd0;
                reg_width_right<=flag_right_seen ? reg_right_max-reg_right_min+16'd1 : 16'd0;
            end
            ST_GEOMETRY: begin
                reg_length_o<=cnt_foreground==0 ? 7'd0 : (reg_length>=254 ? 7'd127 : reg_length[7:1]);
                reg_head_o<=cnt_foreground==0 ? 7'd0 : (dec_head>=64 ? 7'd127 : {dec_head[5:0],1'b0});
                reg_tail_o<=cnt_foreground==0 ? 7'd0 : (dec_tail>=64 ? 7'd127 : {dec_tail[5:0],1'b0});
            end
            ST_FINISH: if(cnt_foreground==0) begin
                reg_local_xmin_o<=0; reg_local_ymin_o<=0;
                reg_local_xmax_o<=0; reg_local_ymax_o<=0;
            end
            default: begin end
        endcase
    end
end
endmodule
