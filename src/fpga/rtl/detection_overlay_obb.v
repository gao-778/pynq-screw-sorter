`timescale 1ns/1ps

module detection_overlay_obb #(
    parameter integer C_MAX_OBJECTS=12
) (
    input i_clk, input i_rstn, input i_frame_start,
    input i_overlays_hidden,
    input [26:0] i_class_color_control,
    input i_done_async, input [5:0] i_count_async,
    output [8:0] o_result_address, input [31:0] i_result_data,
    input [8:0] i_pixel_x, input [7:0] i_pixel_y,
    input [15:0] i_pixel, output [15:0] o_pixel,
    output reg o_scene_toggle, output reg o_scene_valid,
    output reg [5:0] o_scene_count, output reg [C_MAX_OBJECTS*5-1:0] o_scene_classes,
    output reg [C_MAX_OBJECTS*44-1:0] o_scene_boxes
);
localparam ST_IDLE=0, ST_COPY=1, ST_PIXEL=2, ST_LOCAL=3, ST_MUL=4,
           ST_ROT=5, ST_BORDER=6, ST_FONT=7, ST_WRITE=8, ST_NEXT=9, ST_PUBLISH=10;
reg [3:0] state_current;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_done_sync;
reg flag_seen,flag_result,flag_front_valid,flag_front_bank;
reg [7:0] cnt_result;
reg [3:0] reg_count,cnt_box;
reg [5:0] reg_total_count;
reg [10:0] reg_xmin[0:C_MAX_OBJECTS-1],reg_xmax[0:C_MAX_OBJECTS-1],reg_ymin[0:C_MAX_OBJECTS-1],reg_ymax[0:C_MAX_OBJECTS-1];
reg signed [15:0] reg_lxmin[0:C_MAX_OBJECTS-1],reg_lxmax[0:C_MAX_OBJECTS-1],reg_lymin[0:C_MAX_OBJECTS-1],reg_lymax[0:C_MAX_OBJECTS-1];
reg [4:0] reg_class[0:C_MAX_OBJECTS-1];
reg [3:0] reg_angle[0:C_MAX_OBJECTS-1];
reg [8:0] cnt_x;
reg [7:0] cnt_y;
reg [16:0] cnt_pixel;
reg [27:0] cnt_age;
 
 
wire [2:0] wire_color_read;
reg [2:0] reg_border_color,reg_label_color,dec_label_color;
reg [15:0] dec_pixel_color;
reg [26:0] reg_draw_control;
reg flag_publish_scene;
wire signed [16:0] dec_center_local_x=($signed(reg_lxmin[cnt_box[3:0]])+$signed({reg_lxmax[cnt_box[3:0]][15],reg_lxmax[cnt_box[3:0]]}))>>>1;
wire signed [16:0] dec_center_local_y=($signed(reg_lymin[cnt_box[3:0]])+$signed({reg_lymax[cnt_box[3:0]][15],reg_lymax[cnt_box[3:0]]}))>>>1;
reg [1:0] reg_border;
reg [3:0] reg_front_count;
reg signed [11:0] reg_front_left[0:C_MAX_OBJECTS-1],reg_front_top[0:C_MAX_OBJECTS-1];
reg flag_black,dec_black;
integer idx_background,idx_publish;
integer dec_screen_x,dec_screen_y;
reg flag_visible;
reg signed [11:0] reg_dx,reg_dy;
reg signed [9:0] reg_cos,reg_sin;
reg signed [23:0] reg_xc,reg_ys,reg_xs,reg_yc;
reg signed [15:0] reg_lx,reg_ly;
wire signed [17:0] dec_center_delta_x=$signed(reg_lx)-dec_center_local_x;
wire signed [17:0] dec_center_delta_y=$signed(reg_ly)-dec_center_local_y;
wire [10:0] dec_cx=({1'b0,reg_xmin[cnt_box[3:0]]}+{1'b0,reg_xmax[cnt_box[3:0]]})>>1;
wire [10:0] dec_cy=({1'b0,reg_ymin[cnt_box[3:0]]}+{1'b0,reg_ymax[cnt_box[3:0]]})>>1;
wire [16:0] dec_read_pixel={9'd0,i_pixel_y}*17'd320+{8'd0,i_pixel_x};
wire [17:0] dec_read_address={1'b0,dec_read_pixel}+(flag_front_bank?18'd76800:18'd0);
wire [17:0] dec_write_address={1'b0,cnt_pixel}+(flag_front_bank?18'd0:18'd76800);
reg [7:0] reg_character,dec_character;
reg [2:0] reg_column,dec_column;
reg [3:0] reg_row,dec_row;
reg [1:0] reg_background,reg_ink,dec_background,dec_ink;
integer idx_box,screen_x,screen_y,dx,dy,anchor_x,anchor_y;
function [34:0] glyph;
    input [7:0] character;
    begin
        case(character)
            8'd68: glyph=35'b11110100011000110001100011000111110;
            8'd70: glyph=35'b11111100001000011110100001000010000;
            8'd71: glyph=35'b01111100001000010111100011000101110;
            8'd72: glyph=35'b10001100011000111111100011000110001;
            8'd58: glyph=35'b00000001000010000000001000010000000;
            8'd43: glyph=35'b00000001000010011111001000010000000;
            8'd32: glyph=35'b00000000000000000000000000000000000;
            8'd65: glyph=35'b01110100011000111111100011000110001;
            8'd67: glyph=35'b01111100001000010000100001000001111;
            8'd69: glyph=35'b11111100001000011110100001000011111;
            8'd73: glyph=35'b11111001000010000100001000010011111;
            8'd74: glyph=35'b00111000100001000010100101001001100;
            8'd75: glyph=35'b10001100101010011000101001001010001;
            8'd76: glyph=35'b10000100001000010000100001000011111;
            8'd79: glyph=35'b01110100011000110001100011000101110;
            8'd81: glyph=35'b01110100011000110001101011001001101;
            8'd82: glyph=35'b11110100011000111110101001001010001;
            8'd83: glyph=35'b01111100001000001110000010000111110;
            8'd84: glyph=35'b11111001000010000100001000010000100;
            8'd85: glyph=35'b10001100011000110001100011000101110;
            8'd86: glyph=35'b10001100011000110001100010101000100;
            8'd88: glyph=35'b10001100010101000100010101000110001;
            8'd87: glyph=35'b10001100011000110101101011010101010;
            8'd63: glyph=35'b01110100010000100010001000000000100;
            8'd48: glyph=35'b01110100011001110101110011000101110;
            8'd49: glyph=35'b00100011000010000100001000010001110;
            8'd50: glyph=35'b01110100010000100010001000100011111;
            8'd51: glyph=35'b11110000010000101110000010000111110;
            8'd52: glyph=35'b00010001100101010010111110001000010;
            8'd53: glyph=35'b11111100001000011110000010000111110;
            8'd54: glyph=35'b01110100001000011110100011000101110;
            8'd55: glyph=35'b11111000010001000100010000100001000;
            8'd56: glyph=35'b01110100011000101110100011000101110;
            8'd66: glyph=35'b11110100011000111110100011000111110;
            8'd77: glyph=35'b10001110111010110101100011000110001;
            8'd78: glyph=35'b10001110011010110011100011000110001;
            8'd95: glyph=35'b00000000000000000000000000000011111;
            8'd57: glyph=35'b01110100011000101111000010000101110;
            default: glyph=0;
        endcase
    end
endfunction
function signed [9:0] cosine;
    input [3:0] a;
    begin
        case(a)
        0:cosine=256;1:cosine=251;2:cosine=237;3:cosine=212;
        4:cosine=181;5:cosine=143;6:cosine=98;7:cosine=50;
        8:cosine=0;9:cosine=-50;10:cosine=-98;11:cosine=-143;
        12:cosine=-181;13:cosine=-212;14:cosine=-237;default:cosine=-251;
        endcase
    end
endfunction
function signed [9:0] sine;
    input [3:0] a;
    begin
        case(a)
        0:sine=0;1:sine=50;2:sine=98;3:sine=143;
        4:sine=181;5:sine=212;6:sine=237;7:sine=251;
        8:sine=256;9:sine=251;10:sine=237;11:sine=212;
        12:sine=181;13:sine=143;14:sine=98;default:sine=50;
        endcase
    end
endfunction
function [7:0] class_character;
    input [4:0] c;
    input [1:0] pos;
    reg [4:0] number;
    begin
        case(c)
        0:number=5;1:number=4;2:number=1;3:number=10;4:number=8;
        5:number=6;6:number=15;7:number=14;8:number=11;9:number=2;
        10:number=3;11:number=7;12:number=9;13:number=12;14:number=13;15:number=16;16:number=17;17:number=18;
        default:number=0;
        endcase
        case(pos)
        0:class_character=number>=10?"1":" ";
        1:class_character=48+(number>=10?number-10:number);
        default:class_character=" ";
        endcase
    end
endfunction
function [2:0] class_color;
    input [4:0] c;
    input [26:0] control;
    begin
        class_color=3'd1;
        if(control[1:0]==1 && c==control[6:2])class_color=3'd2;
        else if(control[1:0]==2)begin
            if(c==control[11:7])class_color=3'd1;
            else if(c==control[16:12])class_color=3'd3;
            else if(c==control[21:17])class_color=3'd4;
            else if(c==control[26:22])class_color=3'd5;
        end
    end
endfunction
wire [34:0] wire_glyph=glyph(reg_character);
wire [5:0] dec_glyph_index=6'd34-({2'd0,reg_row}*6'd5)-{3'd0,reg_column};
wire flag_glyph_ink=reg_row<7 && reg_column<5 && wire_glyph[dec_glyph_index];
wire [2:0] wire_color_write=flag_glyph_ink?(reg_ink==2?reg_label_color:3'd0):
                           (reg_background==2?reg_border_color:3'd0);
assign o_result_address={1'd0,cnt_result};
assign o_pixel=i_overlays_hidden?i_pixel:!flag_visible?i_pixel:wire_color_read!=0?dec_pixel_color:flag_black?16'hef5c:i_pixel;
overlay_color_buffer color_buffer (
    .i_clk(i_clk), .i_write_enable(i_rstn && state_current==ST_WRITE),
    .i_write_address(dec_write_address), .i_write_color(wire_color_write),
    .i_read_address(dec_read_address), .o_read_color(wire_color_read)
);
always @(*) begin
    case(wire_color_read)
    3'd2:dec_pixel_color=16'hea49;
    3'd3:dec_pixel_color=16'h1d52;
    3'd4:dec_pixel_color=16'he4c6;
    3'd5:dec_pixel_color=16'h933b;
    default:dec_pixel_color=16'h245a;
    endcase
end
always @(*) begin
    dec_screen_x=319-i_pixel_x;
    dec_screen_y=239-i_pixel_y;
    dec_black=1'b0;
    for(idx_background=0;idx_background<C_MAX_OBJECTS;idx_background=idx_background+1) begin
        if(idx_background<reg_front_count &&
           dec_screen_x>=reg_front_left[idx_background] &&
           dec_screen_x<reg_front_left[idx_background]+24 &&
           dec_screen_y>=reg_front_top[idx_background] &&
           dec_screen_y<reg_front_top[idx_background]+9)
            dec_black=1;
    end
end
always @(posedge i_clk) begin
    flag_black<=dec_black;
    flag_visible<=flag_front_valid;
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        state_current<=ST_PIXEL;
        reg_done_sync<=0;flag_seen<=0;flag_result<=0;flag_front_valid<=0;flag_front_bank<=0;
        o_scene_toggle<=0;o_scene_valid<=0;o_scene_count<=0;o_scene_classes<=0;o_scene_boxes<=0;
        cnt_result<=0;reg_count<=0;reg_total_count<=0;cnt_box<=0;cnt_x<=0;cnt_y<=0;cnt_pixel<=0;cnt_age<=0;
        reg_front_count<=0;
        for(idx_publish=0;idx_publish<C_MAX_OBJECTS;idx_publish=idx_publish+1) begin
            reg_front_left[idx_publish]<=0;
            reg_front_top[idx_publish]<=0;
        end
        reg_dx<=0;reg_dy<=0;reg_cos<=0;reg_sin<=0;
        reg_xc<=0;reg_ys<=0;reg_xs<=0;reg_yc<=0;reg_lx<=0;reg_ly<=0;reg_border<=0;
        reg_character<=0;reg_column<=0;reg_row<=0;reg_background<=0;reg_ink<=0;
        reg_border_color<=0;reg_label_color<=0;
        reg_draw_control<=0;flag_publish_scene<=1;
    end else begin
        reg_done_sync<={reg_done_sync[1:0],i_done_async};
        if(!reg_done_sync[2]) flag_seen<=0;
        if(cnt_age<148500000) cnt_age<=cnt_age+1'b1;
         
         
        if(reg_done_sync[2] && !flag_seen)begin
            flag_seen<=1;flag_result<=1;flag_publish_scene<=1;cnt_age<=0;cnt_result<=0;
            reg_total_count<=i_count_async;
            reg_count<=i_count_async>C_MAX_OBJECTS?C_MAX_OBJECTS[3:0]:i_count_async[3:0];
            cnt_x<=0;cnt_y<=0;cnt_pixel<=0;state_current<=ST_COPY;
        end else if(state_current!=ST_COPY && flag_result && cnt_age==148500000)begin
            flag_result<=0;flag_publish_scene<=1;reg_count<=0;reg_total_count<=0;
            reg_draw_control<=i_class_color_control;
            cnt_x<=0;cnt_y<=0;cnt_pixel<=0;state_current<=ST_PIXEL;
        end else if(state_current!=ST_COPY && i_class_color_control!=reg_draw_control)begin
            reg_draw_control<=i_class_color_control;
            cnt_x<=0;cnt_y<=0;cnt_pixel<=0;state_current<=ST_PIXEL;
        end else case(state_current)
        ST_IDLE:begin
            cnt_x<=0;cnt_y<=0;cnt_pixel<=0;
        end
        ST_COPY:begin
            case(cnt_result[3:0])
            0:begin reg_xmin[cnt_result[7:4]]<=i_result_data[10:0];reg_lxmin[cnt_result[7:4]]<=i_result_data[31:16];end
            1:begin reg_ymin[cnt_result[7:4]]<=i_result_data[10:0];reg_lymin[cnt_result[7:4]]<=i_result_data[31:16];end
            2:begin reg_xmax[cnt_result[7:4]]<=i_result_data[10:0];reg_lxmax[cnt_result[7:4]]<=i_result_data[31:16];end
            3:begin reg_ymax[cnt_result[7:4]]<=i_result_data[10:0];reg_lymax[cnt_result[7:4]]<=i_result_data[31:16];end
            5:begin reg_class[cnt_result[7:4]]<={i_result_data[16],i_result_data[3:0]};reg_angle[cnt_result[7:4]]<=i_result_data[11:8];end
            default:begin end
            endcase
            if(cnt_result==C_MAX_OBJECTS*16-1)begin
                reg_draw_control<=i_class_color_control;state_current<=ST_PIXEL;
            end
            else cnt_result<=cnt_result+1'b1;
        end
        ST_PIXEL:begin reg_border<=0;reg_border_color<=0;cnt_box<=0;state_current<=ST_LOCAL;end
        ST_LOCAL:begin
            if(cnt_box>=reg_count) state_current<=ST_FONT;
            else begin
                reg_dx<=$signed({1'b0,cnt_x,2'b0})-$signed({1'b0,dec_cx});
                reg_dy<=$signed({2'b0,cnt_y,2'b0})-$signed({1'b0,dec_cy});
                reg_cos<=cosine(reg_angle[cnt_box[3:0]]);reg_sin<=sine(reg_angle[cnt_box[3:0]]);
                state_current<=ST_MUL;
            end
        end
        ST_MUL:begin
            reg_xc<=reg_dx*reg_cos;reg_ys<=reg_dy*reg_sin;
            reg_xs<=reg_dx*reg_sin;reg_yc<=reg_dy*reg_cos;state_current<=ST_ROT;
        end
        ST_ROT:begin reg_lx<=(reg_xc+reg_ys)>>>8;reg_ly<=(reg_yc-reg_xs)>>>8;state_current<=ST_BORDER;end
        ST_BORDER:begin
            if(reg_lx>=reg_lxmin[cnt_box[3:0]]-2 && reg_lx<=reg_lxmax[cnt_box[3:0]]+2 &&
               reg_ly>=reg_lymin[cnt_box[3:0]]-2 && reg_ly<=reg_lymax[cnt_box[3:0]]+2 &&
              (reg_lx<=reg_lxmin[cnt_box[3:0]]+2 || reg_lx>=reg_lxmax[cnt_box[3:0]]-2 ||
               reg_ly<=reg_lymin[cnt_box[3:0]]+2 || reg_ly>=reg_lymax[cnt_box[3:0]]-2))
                begin reg_border<=2;reg_border_color<=class_color(reg_class[cnt_box[3:0]],reg_draw_control);end
            // A short cross marks the oriented rectangle center, not its AABB midpoint.
            if((dec_center_delta_x>=-2 && dec_center_delta_x<=2 &&
                dec_center_delta_y>=-12 && dec_center_delta_y<=12) ||
               (dec_center_delta_y>=-2 && dec_center_delta_y<=2 &&
                dec_center_delta_x>=-12 && dec_center_delta_x<=12))
                begin reg_border<=2;reg_border_color<=class_color(reg_class[cnt_box[3:0]],reg_draw_control);end
            cnt_box<=cnt_box+1'b1;state_current<=ST_LOCAL;
        end
        ST_FONT:begin
            reg_character<=dec_character;reg_column<=dec_column;reg_row<=dec_row;
            reg_background<=dec_background;reg_ink<=dec_ink;reg_label_color<=dec_label_color;state_current<=ST_WRITE;
        end
        ST_WRITE:state_current<=ST_NEXT;
        ST_NEXT:begin
            if(cnt_pixel==76799) state_current<=ST_PUBLISH;
            else begin
                cnt_pixel<=cnt_pixel+1'b1;
                if(cnt_x==319) begin cnt_x<=0;cnt_y<=cnt_y+1'b1;end else cnt_x<=cnt_x+1'b1;
                state_current<=ST_PIXEL;
            end
        end
        ST_PUBLISH:if(i_frame_start) begin
            flag_front_bank<=!flag_front_bank;flag_front_valid<=1;state_current<=ST_IDLE;
            reg_front_count<=reg_count;
            if(flag_publish_scene)o_scene_toggle<=~o_scene_toggle;
            flag_publish_scene<=0;o_scene_valid<=flag_result;
            // English: The published ledger describes the visible classified slots.
            // 中文：统计接口只发布已显示且已分类的目标数；候选总数仍供顶部提示使用。
            o_scene_count<={2'd0,reg_count};
            for(idx_publish=0;idx_publish<C_MAX_OBJECTS;idx_publish=idx_publish+1)begin
                o_scene_classes[idx_publish*5+:5]<=reg_class[idx_publish];
                o_scene_boxes[idx_publish*44+:44]<={
                    reg_ymax[idx_publish],reg_xmax[idx_publish],reg_ymin[idx_publish],reg_xmin[idx_publish]};
            end
            for(idx_publish=0;idx_publish<C_MAX_OBJECTS;idx_publish=idx_publish+1) begin
                reg_front_left[idx_publish]<=
                    reg_xmax[idx_publish][10:2]<24?12'sd295:
                    12'sd319-$signed({3'b0,reg_xmax[idx_publish][10:2]});
                reg_front_top[idx_publish]<=
                    reg_ymax[idx_publish][10:2]>223?12'sd16:
                    12'sd239-$signed({3'b0,reg_ymax[idx_publish][10:2]});
            end
        end
        default:state_current<=ST_PIXEL;
        endcase
    end
end
always @(*) begin
    dec_background=reg_border;dec_ink=0;dec_character=" ";dec_column=0;dec_row=0;dec_label_color=0;
    screen_x=319-cnt_x;screen_y=239-cnt_y;dx=0;dy=0;anchor_x=0;anchor_y=0;
    for(idx_box=0;idx_box<C_MAX_OBJECTS;idx_box=idx_box+1) begin
        anchor_x=319-(reg_xmax[idx_box]>>2);
        anchor_y=239-(reg_ymax[idx_box]>>2);
        if(anchor_x>295) anchor_x=295;
        if(anchor_y<16) anchor_y=16;
        dx=screen_x-anchor_x;dy=screen_y-anchor_y;
        if(idx_box<reg_count && dx>=0 && dx<24 && dy>=0 && dy<9) begin
            dec_background=3;dec_ink=2;dec_label_color=class_color(reg_class[idx_box],reg_draw_control);
            dec_character=dx<8?(8'd65+idx_box):class_character(reg_class[idx_box],(dx>>3)-1);
            dec_column=dx&7;dec_row=dy;
        end
    end

end
endmodule
