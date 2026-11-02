`timescale 1ns/1ps
 
 
module temporal_object_filter #(
    parameter integer C_MAX_OBJECTS=12,
    parameter integer C_CLASSES=18
) (
    input i_clk,input i_rstn,input i_frame_begin,
    input i_query,input i_commit,input i_bypass,
    input [10:0] i_xmin,input [10:0] i_ymin,input [10:0] i_xmax,input [10:0] i_ymax,
    input [20:0] i_area,input [3:0] i_angle,input [4:0] i_raw_class,
    input signed [15:0] i_lxmin,input signed [15:0] i_lymin,
    input signed [15:0] i_lxmax,input signed [15:0] i_lymax,
    output [4:0] o_score_index,input signed [31:0] i_score,
    output o_done,output [3:0] o_angle,output [4:0] o_class,output [3:0] o_flags,
    output [10:0] o_xmin,output [10:0] o_ymin,output [10:0] o_xmax,output [10:0] o_ymax,
    output signed [15:0] o_lxmin,output signed [15:0] o_lymin,
    output signed [15:0] o_lxmax,output signed [15:0] o_lymax
);
localparam ST_IDLE=0,ST_LOAD=1,ST_DIFF=2,ST_MATCH=3,ST_SELECT=4,ST_ANGLE=5,
 ST_QUERY_DONE=6,ST_SCORE_ADDR=7,ST_SCORE_READ=8,ST_SCORE_WRITE=9,ST_DECIDE=10,
 ST_COMMIT=11,ST_DONE=12,ST_SIZE_MEASURE=13,ST_SIZE_BLEND=14,ST_SIZE_BOUNDS=15;
reg [3:0] state_current,state_next;
reg flag_bank,flag_matched,flag_smooth,flag_motion;
reg [3:0] cnt_previous,cnt_current,cnt_scan,reg_best_index;
reg [4:0] cnt_score;
reg [C_MAX_OBJECTS-1:0] reg_used;
reg [4:0] reg_best_slot,reg_previous_slot,reg_current_slot;
reg [10:0] reg_center_x,reg_center_y,reg_width,reg_height;
reg [10:0] reg_old_x,reg_old_y,reg_old_width,reg_old_height;
reg [20:0] reg_old_area;
reg [10:0] reg_dx,reg_dy,reg_dw,reg_dh;
reg [20:0] reg_da;
reg [11:0] reg_best_distance,reg_second_distance;
reg [3:0] reg_angle_o,reg_flags_o;
reg [4:0] reg_class_o;
reg [10:0] reg_xmin_o,reg_ymin_o,reg_xmax_o,reg_ymax_o;
reg signed [15:0] reg_lxmin_o,reg_lymin_o,reg_lxmax_o,reg_lymax_o;
reg [9:0] reg_score_address,reg_previous_address;
 
reg signed [16:0] reg_center_sum_x,reg_center_sum_y;
reg signed [16:0] reg_span_x,reg_span_y,reg_old_span_x,reg_old_span_y;
reg [16:0] reg_filtered_span_x,reg_filtered_span_y;
reg signed [15:0] reg_filtered_min_x,reg_filtered_max_x,reg_filtered_min_y,reg_filtered_max_y;
wire signed [18:0] wire_old_span_x={{2{reg_old_span_x[16]}},reg_old_span_x};
wire signed [18:0] wire_old_span_y={{2{reg_old_span_y[16]}},reg_old_span_y};
wire signed [18:0] wire_weighted_span_x=(wire_old_span_x<<<1)+wire_old_span_x+$signed({{2{reg_span_x[16]}},reg_span_x});
wire signed [18:0] wire_weighted_span_y=(wire_old_span_y<<<1)+wire_old_span_y+$signed({{2{reg_span_y[16]}},reg_span_y});
wire [16:0] wire_parity_span_x={reg_filtered_span_x[16:1],reg_center_sum_x[0]};
wire [16:0] wire_parity_span_y={reg_filtered_span_y[16:1],reg_center_sum_y[0]};
reg signed [32:0] reg_sum;
reg signed [31:0] reg_best_score,reg_previous_score;
reg [4:0] reg_best_class;
 
reg [10:0] reg_history_x[0:2*C_MAX_OBJECTS-1],reg_history_y[0:2*C_MAX_OBJECTS-1],reg_history_width[0:2*C_MAX_OBJECTS-1],reg_history_height[0:2*C_MAX_OBJECTS-1];
reg [20:0] reg_history_area[0:2*C_MAX_OBJECTS-1];
reg [3:0] reg_history_angle[0:2*C_MAX_OBJECTS-1],reg_angle_candidate[0:2*C_MAX_OBJECTS-1];
reg [4:0] reg_class_candidate[0:2*C_MAX_OBJECTS-1],reg_history_class[0:2*C_MAX_OBJECTS-1];
reg [1:0] reg_angle_count[0:2*C_MAX_OBJECTS-1],reg_class_count[0:2*C_MAX_OBJECTS-1];
reg [10:0] reg_display_xmin[0:2*C_MAX_OBJECTS-1],reg_display_ymin[0:2*C_MAX_OBJECTS-1],reg_display_xmax[0:2*C_MAX_OBJECTS-1],reg_display_ymax[0:2*C_MAX_OBJECTS-1];
reg signed [15:0] reg_display_lxmin[0:2*C_MAX_OBJECTS-1],reg_display_lymin[0:2*C_MAX_OBJECTS-1],reg_display_lxmax[0:2*C_MAX_OBJECTS-1],reg_display_lymax[0:2*C_MAX_OBJECTS-1];
(* ram_style="distributed" *) reg signed [31:0] reg_history_score[0:2*C_MAX_OBJECTS*C_CLASSES-1];
localparam [4:0] C_BANK_OFFSET=C_MAX_OBJECTS;
wire [4:0] wire_scan_slot=(flag_bank?5'd0:C_BANK_OFFSET)+{1'b0,cnt_scan};
wire [11:0] wire_distance={1'b0,reg_dx}+{1'b0,reg_dy};
wire flag_candidate=cnt_scan<cnt_previous && !reg_used[cnt_scan] && reg_dx<=32 && reg_dy<=32 &&
 wire_distance<=48 && ((reg_dw<=16 && reg_dh<=16) || wire_distance<=8) && {reg_da,2'b0}<={2'b0,reg_old_area};
wire [3:0] wire_angle_delta=i_angle-reg_history_angle[reg_previous_slot];
wire signed [31:0] wire_filtered_score=reg_sum>>>1;
wire signed [32:0] wire_margin=$signed({reg_best_score[31],reg_best_score})-$signed({reg_previous_score[31],reg_previous_score});
 
wire flag_change_confirmed=reg_class_candidate[reg_previous_slot]==reg_best_class &&
 reg_class_count[reg_previous_slot]>=2;
assign o_score_index=cnt_score;
assign o_done=state_current==ST_QUERY_DONE || state_current==ST_DONE;
assign o_angle=reg_angle_o;assign o_class=reg_class_o;assign o_flags=reg_flags_o;
assign o_xmin=reg_xmin_o;assign o_ymin=reg_ymin_o;assign o_xmax=reg_xmax_o;assign o_ymax=reg_ymax_o;
assign o_lxmin=reg_lxmin_o;assign o_lymin=reg_lymin_o;assign o_lxmax=reg_lxmax_o;assign o_lymax=reg_lymax_o;
always @(posedge i_clk) begin
    if(!i_rstn) state_current<=ST_IDLE;
    else state_current<=state_next;
end
always @(*) begin
    state_next=state_current;
    case(state_current)
    ST_IDLE:if(i_query) state_next=ST_LOAD;else if(i_commit) state_next=ST_SCORE_ADDR;
    ST_LOAD:state_next=ST_DIFF;
    ST_DIFF:state_next=ST_MATCH;
    ST_MATCH:state_next=cnt_scan==C_MAX_OBJECTS-1?ST_SELECT:ST_LOAD;
    ST_SELECT:state_next=ST_ANGLE;
    ST_ANGLE:state_next=ST_QUERY_DONE;
    ST_QUERY_DONE:state_next=ST_IDLE;
    ST_SCORE_ADDR:state_next=ST_SCORE_READ;
    ST_SCORE_READ:state_next=ST_SCORE_WRITE;
    ST_SCORE_WRITE:state_next=cnt_score==C_CLASSES-1?ST_DECIDE:ST_SCORE_ADDR;
    ST_DECIDE:state_next=ST_SIZE_MEASURE;
    ST_SIZE_MEASURE:state_next=ST_SIZE_BLEND;
    ST_SIZE_BLEND:state_next=ST_SIZE_BOUNDS;
    ST_SIZE_BOUNDS:state_next=ST_COMMIT;
    ST_COMMIT:state_next=ST_DONE;
    ST_DONE:state_next=ST_IDLE;
    default:state_next=ST_IDLE;
    endcase
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        flag_bank<=0;cnt_previous<=0;cnt_current<=0;reg_used<=0;
        cnt_scan<=0;cnt_score<=0;reg_best_index<=0;reg_best_slot<=0;reg_previous_slot<=0;reg_current_slot<=0;
        flag_matched<=0;flag_smooth<=0;flag_motion<=0;
        reg_center_x<=0;reg_center_y<=0;reg_width<=0;reg_height<=0;
        reg_old_x<=0;reg_old_y<=0;reg_old_width<=0;reg_old_height<=0;reg_old_area<=0;
        reg_dx<=0;reg_dy<=0;reg_dw<=0;reg_dh<=0;reg_da<=0;
        reg_best_distance<=4095;reg_second_distance<=4095;reg_angle_o<=0;reg_class_o<=0;reg_flags_o<=0;
        reg_xmin_o<=0;reg_ymin_o<=0;reg_xmax_o<=0;reg_ymax_o<=0;
        reg_lxmin_o<=0;reg_lymin_o<=0;reg_lxmax_o<=0;reg_lymax_o<=0;
        reg_score_address<=0;reg_previous_address<=0;reg_center_sum_x<=0;reg_center_sum_y<=0;reg_span_x<=0;reg_span_y<=0;
        reg_old_span_x<=0;reg_old_span_y<=0;reg_filtered_span_x<=0;reg_filtered_span_y<=0;
        reg_filtered_min_x<=0;reg_filtered_max_x<=0;reg_filtered_min_y<=0;reg_filtered_max_y<=0;reg_sum<=0;
        reg_best_score<=32'sh80000000;reg_previous_score<=0;reg_best_class<=0;
    end else begin
        if(i_frame_begin) begin
            flag_bank<=!flag_bank;cnt_previous<=cnt_current;cnt_current<=0;reg_used<=0;
        end
        case(state_current)
        ST_IDLE:begin
            if(i_query) begin
                reg_center_x<=({1'b0,i_xmin}+{1'b0,i_xmax})>>1;
                reg_center_y<=({1'b0,i_ymin}+{1'b0,i_ymax})>>1;
                reg_width<={1'b0,i_xmax}-{1'b0,i_xmin}+11'd1;
                reg_height<={1'b0,i_ymax}-{1'b0,i_ymin}+11'd1;
                cnt_scan<=0;reg_best_distance<=4095;reg_second_distance<=4095;reg_best_slot<=0;reg_best_index<=0;
                flag_motion<=0;reg_current_slot<=(flag_bank?C_BANK_OFFSET:5'd0)+{1'b0,cnt_current};
            end
            if(i_commit) begin cnt_score<=0;reg_best_score<=32'sh80000000;reg_best_class<=0;reg_previous_score<=0;end
        end
        ST_LOAD:begin
            reg_old_x<=reg_history_x[wire_scan_slot];reg_old_y<=reg_history_y[wire_scan_slot];
            reg_old_width<=reg_history_width[wire_scan_slot];reg_old_height<=reg_history_height[wire_scan_slot];reg_old_area<=reg_history_area[wire_scan_slot];
        end
        ST_DIFF:begin
            reg_dx<=reg_center_x>=reg_old_x?reg_center_x-reg_old_x:reg_old_x-reg_center_x;
            reg_dy<=reg_center_y>=reg_old_y?reg_center_y-reg_old_y:reg_old_y-reg_center_y;
            reg_dw<=reg_width>=reg_old_width?reg_width-reg_old_width:reg_old_width-reg_width;
            reg_dh<=reg_height>=reg_old_height?reg_height-reg_old_height:reg_old_height-reg_height;
            reg_da<=i_area>=reg_old_area?i_area-reg_old_area:reg_old_area-i_area;
        end
        ST_MATCH:begin
            if(flag_candidate) begin
                if(wire_distance<reg_best_distance) begin
                    reg_second_distance<=reg_best_distance;reg_best_distance<=wire_distance;reg_best_slot<=wire_scan_slot;reg_best_index<=cnt_scan;
                     
                    flag_motion<=reg_dx>6 || reg_dy>6;
                end else if(wire_distance<reg_second_distance) reg_second_distance<=wire_distance;
            end
            if(cnt_scan<C_MAX_OBJECTS-1)cnt_scan<=cnt_scan+1'b1;
        end
        ST_SELECT:begin
            flag_matched<=reg_best_distance<4095 && reg_second_distance>=reg_best_distance+12'd8;
            flag_smooth<=reg_best_distance<4095 && reg_second_distance>=reg_best_distance+12'd8 && !flag_motion && !i_bypass;
            reg_previous_slot<=reg_best_slot;
            if(reg_best_distance<4095 && reg_second_distance>=reg_best_distance+12'd8)reg_used[reg_best_index]<=1;
        end
        ST_ANGLE:begin
            reg_angle_o<=i_angle;reg_history_angle[reg_current_slot]<=i_angle;
            reg_angle_candidate[reg_current_slot]<=i_angle;reg_angle_count[reg_current_slot]<=0;
            reg_flags_o<={3'd0,flag_matched};
            reg_history_x[reg_current_slot]<=reg_center_x;reg_history_y[reg_current_slot]<=reg_center_y;
            reg_history_width[reg_current_slot]<=reg_width;reg_history_height[reg_current_slot]<=reg_height;reg_history_area[reg_current_slot]<=i_area;
            if(flag_smooth && (wire_angle_delta==1 || wire_angle_delta==15)) begin
                if(!(reg_angle_candidate[reg_previous_slot]==i_angle && reg_angle_count[reg_previous_slot]>=2)) begin
                    reg_angle_o<=reg_history_angle[reg_previous_slot];reg_history_angle[reg_current_slot]<=reg_history_angle[reg_previous_slot];reg_flags_o[1]<=1;
                    reg_angle_count[reg_current_slot]<=reg_angle_candidate[reg_previous_slot]==i_angle?reg_angle_count[reg_previous_slot]+1'b1:2'd1;
                end
            end
        end
        ST_SCORE_ADDR:begin
            reg_score_address<=reg_current_slot*C_CLASSES+{5'd0,cnt_score};
            reg_previous_address<=reg_previous_slot*C_CLASSES+{5'd0,cnt_score};
        end
        ST_SCORE_READ:begin
            if(flag_smooth)reg_sum<=$signed({i_score[31],i_score})+$signed({reg_history_score[reg_previous_address][31],reg_history_score[reg_previous_address]});
            else reg_sum<=$signed({i_score,1'b0});
        end
        ST_SCORE_WRITE:begin
            reg_history_score[reg_score_address]<=wire_filtered_score;
            if(cnt_score==0 || wire_filtered_score>reg_best_score)begin reg_best_score<=wire_filtered_score;reg_best_class<=cnt_score;end
            if(cnt_score==reg_history_class[reg_previous_slot])reg_previous_score<=wire_filtered_score;
            if(cnt_score<C_CLASSES-1)cnt_score<=cnt_score+1'b1;
        end
        ST_DECIDE:begin
            reg_class_o<=reg_best_class;reg_class_candidate[reg_current_slot]<=reg_best_class;reg_class_count[reg_current_slot]<=0;
            if(flag_smooth && reg_best_class!=reg_history_class[reg_previous_slot] && !flag_change_confirmed) begin
                reg_class_o<=reg_history_class[reg_previous_slot];
                reg_class_count[reg_current_slot]<=reg_class_candidate[reg_previous_slot]==reg_best_class?reg_class_count[reg_previous_slot]+1'b1:2'd1;
            end
        end
        ST_SIZE_MEASURE:begin
            reg_center_sum_x<=$signed({i_lxmin[15],i_lxmin})+$signed({i_lxmax[15],i_lxmax});
            reg_center_sum_y<=$signed({i_lymin[15],i_lymin})+$signed({i_lymax[15],i_lymax});
            reg_span_x<=$signed({i_lxmax[15],i_lxmax})-$signed({i_lxmin[15],i_lxmin});
            reg_span_y<=$signed({i_lymax[15],i_lymax})-$signed({i_lymin[15],i_lymin});
            reg_old_span_x<=$signed({reg_display_lxmax[reg_previous_slot][15],reg_display_lxmax[reg_previous_slot]})-$signed({reg_display_lxmin[reg_previous_slot][15],reg_display_lxmin[reg_previous_slot]});
            reg_old_span_y<=$signed({reg_display_lymax[reg_previous_slot][15],reg_display_lymax[reg_previous_slot]})-$signed({reg_display_lymin[reg_previous_slot][15],reg_display_lymin[reg_previous_slot]});
        end
        ST_SIZE_BLEND:begin
            reg_filtered_span_x<=wire_weighted_span_x>>>2;
            reg_filtered_span_y<=wire_weighted_span_y>>>2;
        end
        ST_SIZE_BOUNDS:begin
            reg_filtered_min_x<=($signed({reg_center_sum_x[16],reg_center_sum_x})-$signed({1'b0,wire_parity_span_x}))>>>1;
            reg_filtered_max_x<=($signed({reg_center_sum_x[16],reg_center_sum_x})+$signed({1'b0,wire_parity_span_x}))>>>1;
            reg_filtered_min_y<=($signed({reg_center_sum_y[16],reg_center_sum_y})-$signed({1'b0,wire_parity_span_y}))>>>1;
            reg_filtered_max_y<=($signed({reg_center_sum_y[16],reg_center_sum_y})+$signed({1'b0,wire_parity_span_y}))>>>1;
        end
        ST_COMMIT:begin
            reg_history_class[reg_current_slot]<=reg_class_o;
            reg_flags_o[2]<=reg_class_o!=i_raw_class;
            if(flag_smooth && reg_angle_o==reg_history_angle[reg_previous_slot]) begin
                reg_flags_o[3]<=1;
                reg_xmin_o<=i_xmin;reg_ymin_o<=i_ymin;reg_xmax_o<=i_xmax;reg_ymax_o<=i_ymax;
                reg_lxmin_o<=reg_filtered_min_x;reg_lymin_o<=reg_filtered_min_y;reg_lxmax_o<=reg_filtered_max_x;reg_lymax_o<=reg_filtered_max_y;
                reg_display_xmin[reg_current_slot]<=i_xmin;reg_display_ymin[reg_current_slot]<=i_ymin;reg_display_xmax[reg_current_slot]<=i_xmax;reg_display_ymax[reg_current_slot]<=i_ymax;
                reg_display_lxmin[reg_current_slot]<=reg_filtered_min_x;reg_display_lymin[reg_current_slot]<=reg_filtered_min_y;reg_display_lxmax[reg_current_slot]<=reg_filtered_max_x;reg_display_lymax[reg_current_slot]<=reg_filtered_max_y;
            end else begin
                reg_flags_o[3]<=0;
                reg_xmin_o<=i_xmin;reg_ymin_o<=i_ymin;reg_xmax_o<=i_xmax;reg_ymax_o<=i_ymax;
                reg_lxmin_o<=i_lxmin;reg_lymin_o<=i_lymin;reg_lxmax_o<=i_lxmax;reg_lymax_o<=i_lymax;
                reg_display_xmin[reg_current_slot]<=i_xmin;reg_display_ymin[reg_current_slot]<=i_ymin;reg_display_xmax[reg_current_slot]<=i_xmax;reg_display_ymax[reg_current_slot]<=i_ymax;
                reg_display_lxmin[reg_current_slot]<=i_lxmin;reg_display_lymin[reg_current_slot]<=i_lymin;reg_display_lxmax[reg_current_slot]<=i_lxmax;reg_display_lymax[reg_current_slot]<=i_lymax;
            end
            cnt_current<=cnt_current+1'b1;
        end
        default:begin end
        endcase
    end
end
endmodule
