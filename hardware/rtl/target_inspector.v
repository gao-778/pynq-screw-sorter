`timescale 1ns/1ps
// English: Spatial target selection and a temporary model-name overlay.
// 中文：按画面方向选择目标，通过位置关联保持选择，名称十秒后自动隐藏。
module target_inspector #(
    parameter integer C_LABEL_CYCLES=742500000,
    parameter integer C_MAX_OBJECTS=12
) (
    input wire i_clk, input wire i_rstn, input wire i_vblank,
    input wire i_overlays_hidden,
    input wire i_scene_toggle, input wire i_scene_valid,
    input wire [5:0] i_scene_count, input wire [C_MAX_OBJECTS*5-1:0] i_scene_classes,
    input wire [C_MAX_OBJECTS*44-1:0] i_scene_boxes,
    input wire i_command_toggle, input wire [3:0] i_command,
    output wire o_command_ack, output wire [15:0] o_status,
    input wire [8:0] i_pixel_x, input wire [7:0] i_pixel_y,
    input wire [15:0] i_pixel, output wire [15:0] o_pixel
);
    localparam ST_IDLE=0,ST_FETCH=1,ST_DISTANCE=2,ST_COMPARE=3,ST_FINISH=4;
    reg [2:0] state_current,state_next;
    (* ASYNC_REG="TRUE" *) reg [2:0] reg_command_sync;
    reg flag_command_ack,flag_scene_seen,flag_enabled,flag_selected;
    reg [3:0] reg_count;
    reg [4:0] reg_class[0:C_MAX_OBJECTS-1];
    reg [8:0] reg_left[0:C_MAX_OBJECTS-1],reg_right[0:C_MAX_OBJECTS-1];
    reg [7:0] reg_top[0:C_MAX_OBJECTS-1],reg_bottom[0:C_MAX_OBJECTS-1];
    reg [3:0] cnt_candidate,reg_best_slot,reg_selected_slot;
    reg [4:0] reg_selected_class;
    reg [3:0] reg_mode;
    reg flag_tracking,flag_candidate,flag_best;
    reg signed [11:0] reg_dx,reg_dy;
    reg [11:0] reg_score,reg_best_score;
    reg [8:0] reg_anchor_x,reg_selected_left,reg_selected_right;
    reg [7:0] reg_anchor_y,reg_selected_top,reg_selected_bottom;
    reg [29:0] cnt_label;
    integer idx;
    wire [9:0] wire_center_x={1'b0,reg_left[cnt_candidate]}+{1'b0,reg_right[cnt_candidate]};
    wire [8:0] wire_center_y={1'b0,reg_top[cnt_candidate]}+{1'b0,reg_bottom[cnt_candidate]};
    wire [11:0] wire_abs_x=reg_dx[11]?-reg_dx:reg_dx;
    wire [11:0] wire_abs_y=reg_dy[11]?-reg_dy:reg_dy;
    wire [11:0] wire_distance=wire_abs_x+wire_abs_y;
    wire flag_direction=(reg_mode==0) ||
        (reg_mode==1 && reg_dx < -12'sd2) ||
        (reg_mode==2 && reg_dx > 12'sd2) ||
        (reg_mode==3 && reg_dy < -12'sd2) ||
        (reg_mode==4 && reg_dy > 12'sd2);
    wire flag_scene_event=i_scene_toggle!=flag_scene_seen;
    wire flag_command_event=reg_command_sync[2]!=flag_command_ack;
    wire flag_start_scene=state_current==ST_IDLE && flag_scene_event && flag_enabled && flag_selected;
    wire flag_start_move=state_current==ST_IDLE && !flag_scene_event && i_vblank &&
        flag_command_event && ((i_command>=1 && i_command<=4 && flag_enabled)||i_command==6);
    assign o_command_ack=flag_command_ack;
    assign o_status={4'd0,reg_selected_class[4],(cnt_label!=0),flag_enabled,flag_selected,reg_selected_class[3:0],reg_selected_slot};
    always @(*) begin
        state_next=state_current;
        case(state_current)
            ST_IDLE:if(flag_start_scene || flag_start_move)state_next=ST_FETCH;
            ST_FETCH:if(cnt_candidate>=reg_count)state_next=ST_FINISH;
                     else state_next=ST_DISTANCE;
            ST_DISTANCE:state_next=ST_COMPARE;
            ST_COMPARE:state_next=ST_FETCH;
            ST_FINISH:state_next=ST_IDLE;
            default:state_next=ST_IDLE;
        endcase
    end
    always @(posedge i_clk) begin
        if(!i_rstn)state_current<=ST_IDLE;
        else state_current<=state_next;
    end
    always @(posedge i_clk) begin
        if(!i_rstn)begin
            reg_command_sync<=0;flag_command_ack<=0;flag_scene_seen<=0;
            flag_enabled<=0;flag_selected<=0;reg_count<=0;cnt_label<=0;
            cnt_candidate<=0;reg_best_slot<=0;reg_selected_slot<=0;reg_selected_class<=0;
            reg_mode<=0;flag_tracking<=0;flag_candidate<=0;flag_best<=0;
            reg_dx<=0;reg_dy<=0;reg_score<=0;reg_best_score<=12'hfff;
            reg_anchor_x<=160;reg_anchor_y<=120;
            reg_selected_left<=0;reg_selected_right<=0;reg_selected_top<=0;reg_selected_bottom<=0;
            for(idx=0;idx<C_MAX_OBJECTS;idx=idx+1)begin
                reg_left[idx]<=0;reg_right[idx]<=0;reg_top[idx]<=0;reg_bottom[idx]<=0;reg_class[idx]<=31;
            end
        end else begin
            reg_command_sync<={reg_command_sync[1:0],i_command_toggle};
            if(cnt_label!=0)cnt_label<=cnt_label-1'b1;
            case(state_current)
                ST_IDLE:begin
                    if(flag_scene_event)begin
                        flag_scene_seen<=i_scene_toggle;
                        reg_count<=i_scene_valid?(i_scene_count>C_MAX_OBJECTS?C_MAX_OBJECTS[3:0]:i_scene_count[3:0]):4'd0;
                        for(idx=0;idx<C_MAX_OBJECTS;idx=idx+1)begin
                            reg_left[idx]<=9'd319-i_scene_boxes[idx*44+24+:9];
                            reg_right[idx]<=9'd319-i_scene_boxes[idx*44+2+:9];
                            reg_top[idx]<=8'd239-i_scene_boxes[idx*44+35+:9];
                            reg_bottom[idx]<=8'd239-i_scene_boxes[idx*44+13+:9];
                            reg_class[idx]<=i_scene_classes[idx*5+:5];
                        end
                        // Do not acquire another target automatically after a loss.
                        reg_mode<=0;flag_tracking<=flag_selected;
                        cnt_candidate<=0;flag_best<=0;reg_best_score<=12'hfff;
                    end else if(i_vblank && flag_command_event)begin
                        flag_command_ack<=reg_command_sync[2];
                        if(i_command==7)begin flag_enabled<=0;flag_selected<=0;cnt_label<=0;end
                        else if(i_command==5 && flag_enabled && flag_selected)
                            cnt_label<=C_LABEL_CYCLES;
                        else if((i_command>=1 && i_command<=4 && flag_enabled)||i_command==6)begin
                            flag_enabled<=1;cnt_label<=0;cnt_candidate<=0;flag_best<=0;
                            reg_best_score<=12'hfff;flag_tracking<=0;
                            if(!flag_selected || i_command==6)begin
                                reg_anchor_x<=160;reg_anchor_y<=120;reg_mode<=0;
                            end else reg_mode<=i_command;
                        end
                    end
                end
                ST_FETCH:if(cnt_candidate<reg_count)begin
                    reg_dx<=$signed({3'd0,wire_center_x[9:1]})-$signed({3'd0,reg_anchor_x});
                    reg_dy<=$signed({4'd0,wire_center_y[8:1]})-$signed({4'd0,reg_anchor_y});
                end
                ST_DISTANCE:begin
                    reg_score<=wire_distance+
                        ((reg_mode==1 || reg_mode==2)?wire_abs_y:
                         (reg_mode==3 || reg_mode==4)?wire_abs_x:12'd0);
                    flag_candidate<=flag_direction && reg_class[cnt_candidate]<18 &&
                        (!flag_tracking || wire_distance<=40);
                end
                ST_COMPARE:begin
                    if(flag_candidate && (!flag_best || reg_score<reg_best_score))begin
                        flag_best<=1;reg_best_score<=reg_score;reg_best_slot<=cnt_candidate;
                    end
                    cnt_candidate<=cnt_candidate+1'b1;
                end
                ST_FINISH:begin
                    if(flag_best)begin
                        flag_selected<=1;reg_selected_slot<=reg_best_slot;
                        reg_selected_left<=reg_left[reg_best_slot];reg_selected_right<=reg_right[reg_best_slot];
                        reg_selected_top<=reg_top[reg_best_slot];reg_selected_bottom<=reg_bottom[reg_best_slot];
                        reg_anchor_x<=({1'b0,reg_left[reg_best_slot]}+{1'b0,reg_right[reg_best_slot]})>>1;
                        reg_anchor_y<=({1'b0,reg_top[reg_best_slot]}+{1'b0,reg_bottom[reg_best_slot]})>>1;
                        reg_selected_class<=reg_class[reg_best_slot];
                        if(reg_class[reg_best_slot]!=reg_selected_class)cnt_label<=0;
                    end else if(flag_tracking || reg_mode==0)begin
                        flag_selected<=0;cnt_label<=0;
                    end
                end
                default:begin end
            endcase
        end
    end
    // One registered coordinate evaluation matches the existing preview latency.
    wire [8:0] wire_screen_x=9'd319-i_pixel_x;
    wire [7:0] wire_screen_y=8'd239-i_pixel_y;
    wire [8:0] wire_label_x=reg_selected_right<282?reg_selected_right+9'd3:
        reg_selected_left>=38?reg_selected_left-9'd38:9'd0;
    wire [7:0] wire_label_y=reg_selected_top<16?8'd16:
        reg_selected_top>230?8'd230:reg_selected_top;
    wire [8:0] wire_text_x=wire_screen_x-wire_label_x;
    wire [7:0] wire_text_y=wire_screen_y-wire_label_y;
    reg flag_red,flag_paper,flag_ink;
    reg [7:0] dec_character;
    reg [3:0] dec_diameter,dec_length;
    reg [34:0] dec_glyph;
    always @(*)begin
        dec_diameter=0;dec_length=0;
        case(reg_selected_class)
            0:begin dec_diameter=3;dec_length=5;end
            1:begin dec_diameter=3;dec_length=4;end
            2:begin dec_diameter=3;dec_length=1;end
            3:begin dec_diameter=4;dec_length=5;end
            4:begin dec_diameter=4;dec_length=3;end
            5:begin dec_diameter=4;dec_length=1;end
            6:begin dec_diameter=5;dec_length=5;end
            7:begin dec_diameter=5;dec_length=4;end
            8:begin dec_diameter=5;dec_length=1;end
            9:begin dec_diameter=3;dec_length=2;end
            10:begin dec_diameter=3;dec_length=3;end
            11:begin dec_diameter=4;dec_length=2;end
            12:begin dec_diameter=4;dec_length=4;end
            13:begin dec_diameter=5;dec_length=2;end
            14:begin dec_diameter=5;dec_length=3;end
            default:begin end
        endcase
        case(wire_text_x[8:3])
            0:dec_character="M";
            1:dec_character=8'd48+dec_diameter;
            2:dec_character="_";
            3:dec_character=8'd48+dec_length;
            default:dec_character=" ";
        endcase
        if(reg_selected_class>=15 && reg_selected_class<18)begin
            case(wire_text_x[8:3])
                0:dec_character="N";
                1:dec_character="_";
                2:dec_character=reg_selected_class==15?"L":reg_selected_class==16?"M":"S";
                default:dec_character=" ";
            endcase
        end
        case(dec_character)
            "N":dec_glyph=35'b10001110011010110011100011000110001;
            "L":dec_glyph=35'b10000100001000010000100001000011111;
            "S":dec_glyph=35'b01111100001000001110000010000111110;
            "M":dec_glyph=35'b10001110111010110101100011000110001;
            "_":dec_glyph=35'b00000000000000000000000000000011111;
            "1":dec_glyph=35'b00100011000010000100001000010001110;
            "2":dec_glyph=35'b01110100010000100010001000100011111;
            "3":dec_glyph=35'b11110000010000101110000010000111110;
            "4":dec_glyph=35'b00010001100101010010111110001000010;
            "5":dec_glyph=35'b11111100001000011110000010000111110;
            default:dec_glyph=0;
        endcase
    end
    always @(posedge i_clk)begin
        flag_red<=i_rstn && flag_enabled && flag_selected &&
            wire_screen_x>=reg_selected_left && wire_screen_x<=reg_selected_right &&
            wire_screen_y>=reg_selected_top && wire_screen_y<=reg_selected_bottom &&
            (wire_screen_x==reg_selected_left || wire_screen_x==reg_selected_right ||
             wire_screen_y==reg_selected_top || wire_screen_y==reg_selected_bottom);
        flag_paper<=i_rstn && flag_enabled && flag_selected && cnt_label!=0 &&
            wire_text_x<34 && wire_text_y<9;
        flag_ink<=wire_text_y<7 && wire_text_x[2:0]<5 &&
            dec_glyph[34-wire_text_y*5-wire_text_x[2:0]];
    end
    assign o_pixel=i_overlays_hidden?i_pixel:flag_paper?(flag_ink?16'h8a49:16'hff7b):flag_red?16'hd26b:i_pixel;
endmodule
