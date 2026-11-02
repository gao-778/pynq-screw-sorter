`timescale 1ns/1ps
 
 
module platform_axes_overlay (
    input wire i_clk,
    input wire i_reset,
    input wire i_enable,
    input wire [10:0] i_pixel_x,
    input wire [9:0] i_pixel_y,
    output wire [2:0] o_alpha
);
    `include "platform_axes_layout.vh"

     
    (* rom_style = "block" *) reg [45:0] reg_horizontal_rom [0:1023];
    (* rom_style = "block" *) reg [45:0] reg_vertical_rom [0:1023];
    (* rom_style = "block" *) reg [2:0] reg_glyph_rom [0:4095];
    reg [45:0] reg_horizontal_data;
    reg [45:0] reg_vertical_data;
    reg [2:0] reg_glyph_data;
    reg [10:0] reg_pixel_x;
    reg [9:0] reg_pixel_y;
    reg flag_enabled;
    reg flag_glyph;
    reg [2:0] reg_alpha_o;

    wire [10:0] dec_horizontal_offset = {1'b0, reg_pixel_y} -
                                                    {1'b0, reg_horizontal_data[9:0]};
    wire [10:0] dec_vertical_offset = reg_pixel_x - {1'b0, reg_vertical_data[9:0]};
    wire [2:0] dec_horizontal_alpha = dec_horizontal_offset < 12 ?
        reg_horizontal_data[10 + dec_horizontal_offset * 3 +: 3] : 3'd0;
    wire [2:0] dec_vertical_alpha = dec_vertical_offset < 12 ?
        reg_vertical_data[10 + dec_vertical_offset * 3 +: 3] : 3'd0;
    wire [2:0] dec_line_alpha = dec_horizontal_alpha > dec_vertical_alpha ?
                               dec_horizontal_alpha : dec_vertical_alpha;
    wire [2:0] dec_glyph_alpha = flag_glyph ? reg_glyph_data : 3'd0;
    wire [2:0] dec_alpha = dec_line_alpha > dec_glyph_alpha ? dec_line_alpha : dec_glyph_alpha;
    reg [11:0] dec_glyph_address;
    reg flag_glyph_inside;
    reg [10:0] dec_glyph_x;
    reg [9:0] dec_glyph_y;

    initial begin
        $readmemh("axes_horizontal.hex", reg_horizontal_rom);
        $readmemh("axes_vertical.hex", reg_vertical_rom);
        $readmemh("axes_glyphs.hex", reg_glyph_rom);
    end

     
    always @(*) begin
        dec_glyph_address = 12'd3072;
        flag_glyph_inside = 1'b0;
        dec_glyph_x = 0;
        dec_glyph_y = 0;
        if (i_pixel_x >= X_LEFT && i_pixel_x < X_LEFT + 32 &&
            i_pixel_y >= X_TOP && i_pixel_y < X_TOP + 32) begin
            flag_glyph_inside = 1'b1;
            dec_glyph_x = i_pixel_x - X_LEFT;
            dec_glyph_y = i_pixel_y - X_TOP;
            dec_glyph_address = {2'd0, dec_glyph_y[4:0], dec_glyph_x[4:0]};
        end else if (i_pixel_x >= Y_LEFT && i_pixel_x < Y_LEFT + 32 &&
                     i_pixel_y >= Y_TOP && i_pixel_y < Y_TOP + 32) begin
            flag_glyph_inside = 1'b1;
            dec_glyph_x = i_pixel_x - Y_LEFT;
            dec_glyph_y = i_pixel_y - Y_TOP;
            dec_glyph_address = {2'd1, dec_glyph_y[4:0], dec_glyph_x[4:0]};
        end else if (i_pixel_x >= ORIGIN_LEFT && i_pixel_x < ORIGIN_LEFT + 32 &&
                     i_pixel_y >= ORIGIN_TOP && i_pixel_y < ORIGIN_TOP + 32) begin
            flag_glyph_inside = 1'b1;
            dec_glyph_x = i_pixel_x - ORIGIN_LEFT;
            dec_glyph_y = i_pixel_y - ORIGIN_TOP;
            dec_glyph_address = {2'd2, dec_glyph_y[4:0], dec_glyph_x[4:0]};
        end
    end

     
    always @(posedge i_clk) begin
        reg_horizontal_data <= reg_horizontal_rom[i_pixel_x[9:0]];
        reg_vertical_data <= reg_vertical_rom[i_pixel_y];
        reg_glyph_data <= reg_glyph_rom[dec_glyph_address];
        if (i_reset) begin
            reg_pixel_x <= 0;
            reg_pixel_y <= 0;
            flag_enabled <= 0;
            flag_glyph <= 0;
            reg_alpha_o <= 0;
        end else begin
            reg_pixel_x <= i_pixel_x;
            reg_pixel_y <= i_pixel_y;
            flag_enabled <= i_enable && i_pixel_x < 960 && i_pixel_y < 720;
            flag_glyph <= flag_glyph_inside;
            reg_alpha_o <= flag_enabled ? dec_alpha : 3'd0;
        end
    end
    assign o_alpha = reg_alpha_o;
endmodule
