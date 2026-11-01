`timescale 1ns / 1ps
// English: Mint sidebar with black glyphs and rounded, raised menu cards.
// 中文：浅绿色侧栏、黑色文字、深绿圆角边框和黄色悬浮选中卡片。
// Coordinates are delayed by two edges to match the text/font BRAM pipeline.
// 中文：几何图形延迟两拍，与文本及字体存储器保持逐像素对齐。
module sidebar_mint_theme (
    input i_clk, input i_rstn,
    input [8:0] i_pixel_x, input [9:0] i_pixel_y,
    input [3:0] i_style, input i_text_ink, input i_panel_active,
    output [23:0] o_pixel
);
reg [8:0] reg_x;
reg flag_menu,flag_menu_pipe,flag_accent,flag_accent_pipe;
reg flag_menu_text,flag_menu_text_pipe,flag_menu_band_pipe;
wire flag_text_ink=i_text_ink && (!flag_menu_band_pipe || flag_menu_text_pipe);
reg [23:0] dec_paper,dec_accent,dec_pixel_o;
wire [4:0] dec_menu_row=i_pixel_y[4:0]^5'd16;
reg [8:0] reg_normal_left,reg_normal_right; // normal圆角扫描线边界
reg flag_normal; // normal区域内部判定，与文字同拍
reg [8:0] reg_inner_left,reg_inner_right; // inner圆角扫描线边界
reg flag_inner; // inner区域内部判定，与文字同拍
reg [8:0] reg_selected_left,reg_selected_right; // selected圆角扫描线边界
reg flag_selected; // selected区域内部判定，与文字同拍
reg [8:0] reg_selected_inner_left,reg_selected_inner_right; // selected_inner圆角扫描线边界
reg flag_selected_inner; // selected_inner区域内部判定，与文字同拍
reg [8:0] reg_shadow_left,reg_shadow_right; // shadow圆角扫描线边界
reg flag_shadow; // shadow区域内部判定，与文字同拍
// 每行边界来自整数圆方程；没有运行时乘法、除法或额外帧缓存。
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_x<=0;flag_menu<=0;flag_accent<=0;flag_menu_text<=0;
        reg_normal_left<=511;reg_normal_right<=0;
        reg_inner_left<=511;reg_inner_right<=0;
        reg_selected_left<=511;reg_selected_right<=0;
        reg_selected_inner_left<=511;reg_selected_inner_right<=0;
        reg_shadow_left<=511;reg_shadow_right<=0;
    end else begin
        reg_x<=i_pixel_x;
        flag_menu<=i_pixel_y>=176 && i_pixel_y<400;
        flag_accent<=i_pixel_y>=432;
        flag_menu_text<=dec_menu_row>=6 && dec_menu_row<22;
        case(dec_menu_row)
            5'd0:begin
                reg_normal_left<=9'd511;reg_normal_right<=9'd0;
                reg_inner_left<=9'd511;reg_inner_right<=9'd0;
                reg_selected_left<=9'd22;reg_selected_right<=9'd295;
                reg_selected_inner_left<=9'd511;reg_selected_inner_right<=9'd0;
                reg_shadow_left<=9'd511;reg_shadow_right<=9'd0;
            end
            5'd1:begin
                reg_normal_left<=9'd511;reg_normal_right<=9'd0;
                reg_inner_left<=9'd511;reg_inner_right<=9'd0;
                reg_selected_left<=9'd19;reg_selected_right<=9'd298;
                reg_selected_inner_left<=9'd511;reg_selected_inner_right<=9'd0;
                reg_shadow_left<=9'd511;reg_shadow_right<=9'd0;
            end
            5'd2:begin
                reg_normal_left<=9'd22;reg_normal_right<=9'd297;
                reg_inner_left<=9'd511;reg_inner_right<=9'd0;
                reg_selected_left<=9'd18;reg_selected_right<=9'd299;
                reg_selected_inner_left<=9'd22;reg_selected_inner_right<=9'd295;
                reg_shadow_left<=9'd511;reg_shadow_right<=9'd0;
            end
            5'd3:begin
                reg_normal_left<=9'd19;reg_normal_right<=9'd300;
                reg_inner_left<=9'd511;reg_inner_right<=9'd0;
                reg_selected_left<=9'd17;reg_selected_right<=9'd300;
                reg_selected_inner_left<=9'd20;reg_selected_inner_right<=9'd297;
                reg_shadow_left<=9'd25;reg_shadow_right<=9'd297;
            end
            5'd4:begin
                reg_normal_left<=9'd18;reg_normal_right<=9'd301;
                reg_inner_left<=9'd22;reg_inner_right<=9'd297;
                reg_selected_left<=9'd17;reg_selected_right<=9'd300;
                reg_selected_inner_left<=9'd19;reg_selected_inner_right<=9'd298;
                reg_shadow_left<=9'd22;reg_shadow_right<=9'd300;
            end
            5'd5:begin
                reg_normal_left<=9'd17;reg_normal_right<=9'd302;
                reg_inner_left<=9'd20;reg_inner_right<=9'd299;
                reg_selected_left<=9'd17;reg_selected_right<=9'd300;
                reg_selected_inner_left<=9'd19;reg_selected_inner_right<=9'd298;
                reg_shadow_left<=9'd21;reg_shadow_right<=9'd301;
            end
            5'd6:begin
                reg_normal_left<=9'd17;reg_normal_right<=9'd302;
                reg_inner_left<=9'd19;reg_inner_right<=9'd300;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd20;reg_shadow_right<=9'd302;
            end
            5'd7:begin
                reg_normal_left<=9'd17;reg_normal_right<=9'd302;
                reg_inner_left<=9'd19;reg_inner_right<=9'd300;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd20;reg_shadow_right<=9'd302;
            end
            5'd8:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd20;reg_shadow_right<=9'd302;
            end
            5'd9:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd10:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd11:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd12:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd13:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd14:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd15:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd16:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd17:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd18:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd19:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd20:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd21:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd16;reg_selected_right<=9'd301;
                reg_selected_inner_left<=9'd18;reg_selected_inner_right<=9'd299;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd22:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd17;reg_selected_right<=9'd300;
                reg_selected_inner_left<=9'd19;reg_selected_inner_right<=9'd298;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd23:begin
                reg_normal_left<=9'd16;reg_normal_right<=9'd303;
                reg_inner_left<=9'd18;reg_inner_right<=9'd301;
                reg_selected_left<=9'd17;reg_selected_right<=9'd300;
                reg_selected_inner_left<=9'd19;reg_selected_inner_right<=9'd298;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd24:begin
                reg_normal_left<=9'd17;reg_normal_right<=9'd302;
                reg_inner_left<=9'd19;reg_inner_right<=9'd300;
                reg_selected_left<=9'd17;reg_selected_right<=9'd300;
                reg_selected_inner_left<=9'd20;reg_selected_inner_right<=9'd297;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd25:begin
                reg_normal_left<=9'd17;reg_normal_right<=9'd302;
                reg_inner_left<=9'd19;reg_inner_right<=9'd300;
                reg_selected_left<=9'd18;reg_selected_right<=9'd299;
                reg_selected_inner_left<=9'd22;reg_selected_inner_right<=9'd295;
                reg_shadow_left<=9'd19;reg_shadow_right<=9'd303;
            end
            5'd26:begin
                reg_normal_left<=9'd17;reg_normal_right<=9'd302;
                reg_inner_left<=9'd20;reg_inner_right<=9'd299;
                reg_selected_left<=9'd19;reg_selected_right<=9'd298;
                reg_selected_inner_left<=9'd511;reg_selected_inner_right<=9'd0;
                reg_shadow_left<=9'd20;reg_shadow_right<=9'd302;
            end
            5'd27:begin
                reg_normal_left<=9'd18;reg_normal_right<=9'd301;
                reg_inner_left<=9'd22;reg_inner_right<=9'd297;
                reg_selected_left<=9'd22;reg_selected_right<=9'd295;
                reg_selected_inner_left<=9'd511;reg_selected_inner_right<=9'd0;
                reg_shadow_left<=9'd20;reg_shadow_right<=9'd302;
            end
            5'd28:begin
                reg_normal_left<=9'd19;reg_normal_right<=9'd300;
                reg_inner_left<=9'd511;reg_inner_right<=9'd0;
                reg_selected_left<=9'd511;reg_selected_right<=9'd0;
                reg_selected_inner_left<=9'd511;reg_selected_inner_right<=9'd0;
                reg_shadow_left<=9'd20;reg_shadow_right<=9'd302;
            end
            5'd29:begin
                reg_normal_left<=9'd22;reg_normal_right<=9'd297;
                reg_inner_left<=9'd511;reg_inner_right<=9'd0;
                reg_selected_left<=9'd511;reg_selected_right<=9'd0;
                reg_selected_inner_left<=9'd511;reg_selected_inner_right<=9'd0;
                reg_shadow_left<=9'd21;reg_shadow_right<=9'd301;
            end
            5'd30:begin
                reg_normal_left<=9'd511;reg_normal_right<=9'd0;
                reg_inner_left<=9'd511;reg_inner_right<=9'd0;
                reg_selected_left<=9'd511;reg_selected_right<=9'd0;
                reg_selected_inner_left<=9'd511;reg_selected_inner_right<=9'd0;
                reg_shadow_left<=9'd22;reg_shadow_right<=9'd300;
            end
            5'd31:begin
                reg_normal_left<=9'd511;reg_normal_right<=9'd0;
                reg_inner_left<=9'd511;reg_inner_right<=9'd0;
                reg_selected_left<=9'd511;reg_selected_right<=9'd0;
                reg_selected_inner_left<=9'd511;reg_selected_inner_right<=9'd0;
                reg_shadow_left<=9'd25;reg_shadow_right<=9'd297;
            end
            default:begin
                reg_normal_left<=511;reg_normal_right<=0;
                reg_inner_left<=511;reg_inner_right<=0;
                reg_selected_left<=511;reg_selected_right<=0;
                reg_selected_inner_left<=511;reg_selected_inner_right<=0;
                reg_shadow_left<=511;reg_shadow_right<=0;
            end
        endcase
    end
end
// 第二级只比较列边界，保留原侧栏两拍读延迟。
always @(posedge i_clk) begin
    if(!i_rstn) begin
        flag_menu_pipe<=0;flag_accent_pipe<=0;flag_menu_text_pipe<=0;flag_menu_band_pipe<=0;
        flag_normal<=0;
        flag_inner<=0;
        flag_selected<=0;
        flag_selected_inner<=0;
        flag_shadow<=0;
    end else begin
        flag_menu_pipe<=flag_menu && reg_x>=16 && reg_x<304;
        flag_accent_pipe<=flag_accent && reg_x>=16 && reg_x<20;
        flag_menu_text_pipe<=flag_menu_text;
        flag_menu_band_pipe<=flag_menu;
        flag_normal<=reg_x>=reg_normal_left && reg_x<=reg_normal_right;
        flag_inner<=reg_x>=reg_inner_left && reg_x<=reg_inner_right;
        flag_selected<=reg_x>=reg_selected_left && reg_x<=reg_selected_right;
        flag_selected_inner<=reg_x>=reg_selected_inner_left && reg_x<=reg_selected_inner_right;
        flag_shadow<=reg_x>=reg_shadow_left && reg_x<=reg_shadow_right;
    end
end
// 所有文字固定黑色；色彩只用于底色、边框和类别标识。
always @(*) begin
    dec_paper=24'hE5F3E8;dec_accent=24'h276344;
    case(i_style)
        4'd0:begin dec_paper=24'he5f3e8;dec_accent=24'h276344;end
        4'd1:begin dec_paper=24'hd5ebdd;dec_accent=24'h276344;end
        4'd2:begin dec_paper=24'hf5dc73;dec_accent=24'h276344;end
        4'd3:begin dec_paper=24'hd4e8db;dec_accent=24'h276344;end
        4'd4:begin dec_paper=24'he5f3e8;dec_accent=24'h276344;end
        4'd5:begin dec_paper=24'hd3ebdd;dec_accent=24'h276344;end
        4'd6:begin dec_paper=24'hdeece2;dec_accent=24'h276344;end
        4'd7:begin dec_paper=24'hf2e8bb;dec_accent=24'h276344;end
        4'd8:begin dec_paper=24'hf0cec4;dec_accent=24'h276344;end
        4'd9:begin dec_paper=24'hdcefe3;dec_accent=24'h276344;end
        4'd10:begin dec_paper=24'hdcefe3;dec_accent=24'h276344;end
        4'd11:begin dec_paper=24'hd4eee7;dec_accent=24'h18aa94;end
        4'd12:begin dec_paper=24'hddecf7;dec_accent=24'h218ad6;end
        4'd13:begin dec_paper=24'he8e2f4;dec_accent=24'h9465de;end
        4'd14:begin dec_paper=24'hf4e8ce;dec_accent=24'he79a31;end
        4'd15:begin dec_paper=24'hf4ddda;dec_accent=24'hef494a;end
        default:begin dec_paper=24'hE5F3E8;dec_accent=24'h276344;end
    endcase
    dec_pixel_o=dec_paper;
    if(flag_text_ink) begin
        dec_pixel_o=24'h000000;
    end else if(flag_accent_pipe && (i_style==11 || i_style==12 || i_style==13 || i_style==14 || i_style==15)) begin
        dec_pixel_o=dec_accent;
    end
    if(flag_menu_pipe) begin
        dec_pixel_o=24'hE5F3E8;
        if(i_style==2) begin
            if(flag_shadow) begin dec_pixel_o=24'h91AD98;end
            if(flag_selected) begin
                dec_pixel_o=24'h276344;
                if(flag_selected_inner) begin
                    dec_pixel_o=flag_text_ink?24'h000000:24'hF5DC73;
                end
            end
        end else if(flag_normal) begin
            dec_pixel_o=24'h276344;
            if(flag_inner) begin
                dec_pixel_o=flag_text_ink?24'h000000:24'hE5F3E8;
            end
        end
    end
    if(!i_panel_active || !i_rstn) begin dec_pixel_o=24'hE5F3E8;end
end
assign o_pixel=dec_pixel_o;
endmodule
