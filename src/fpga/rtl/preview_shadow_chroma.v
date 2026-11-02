`timescale 1ns/1ps
 
 
module preview_shadow_chroma (
    input wire i_clk,
    input wire i_rstn,
    input wire i_valid,
    input wire i_enable,
    input wire [23:0] i_rgb,
    output wire o_valid,
    output wire [23:0] o_rgb
);
    reg [3:0] reg_valid;
    reg [3:0] reg_enable;
    reg [23:0] reg_rgb0, reg_rgb1, reg_rgb2, reg_rgb3;
    (* use_dsp = "no" *) reg [15:0] reg_red_weight;
    (* use_dsp = "no" *) reg [15:0] reg_green_weight;
    (* use_dsp = "no" *) reg [15:0] reg_blue_weight;
    wire [15:0] dec_luma_sum = reg_red_weight + reg_green_weight + reg_blue_weight + 16'd128;
    reg [7:0] reg_luma;
    wire [8:0] dec_distance = 9'd160 - {1'b0,reg_luma};
    wire [9:0] dec_beta_middle = {dec_distance,1'b0} + {1'b0,dec_distance};
    reg signed [8:0] reg_beta;
    reg signed [8:0] reg_red_delta, reg_green_delta, reg_blue_delta;
    (* use_dsp = "yes" *) reg signed [17:0] reg_red_product;
    (* use_dsp = "yes" *) reg signed [17:0] reg_green_product;
    (* use_dsp = "yes" *) reg signed [17:0] reg_blue_product;
    wire signed [17:0] dec_red_rounded = $signed({2'b00,reg_rgb3[23:16],8'd0}) + reg_red_product + 18'sd128;
    wire signed [17:0] dec_green_rounded = $signed({2'b00,reg_rgb3[15:8],8'd0}) + reg_green_product + 18'sd128;
    wire signed [17:0] dec_blue_rounded = $signed({2'b00,reg_rgb3[7:0],8'd0}) + reg_blue_product + 18'sd128;
    reg flag_valid_o;
    reg [23:0] reg_rgb_o;
    assign o_valid = flag_valid_o;
    assign o_rgb = reg_rgb_o;

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            reg_valid <= 0; reg_enable <= 0;
            reg_rgb0 <= 0; reg_rgb1 <= 0; reg_rgb2 <= 0; reg_rgb3 <= 0;
            reg_red_weight <= 0; reg_green_weight <= 0; reg_blue_weight <= 0;
            reg_luma <= 0; reg_beta <= 0;
            reg_red_delta <= 0; reg_green_delta <= 0; reg_blue_delta <= 0;
            reg_red_product <= 0; reg_green_product <= 0; reg_blue_product <= 0;
            flag_valid_o <= 0; reg_rgb_o <= 0;
        end else begin
            reg_valid <= {reg_valid[2:0],i_valid};
            reg_enable <= {reg_enable[2:0],i_enable};
            reg_rgb0 <= i_rgb;
            reg_red_weight <= i_rgb[23:16] * 8'd77;
            reg_green_weight <= i_rgb[15:8] * 8'd150;
            reg_blue_weight <= i_rgb[7:0] * 8'd29;
            reg_rgb1 <= reg_rgb0;
            reg_luma <= dec_luma_sum[15:8];
            reg_rgb2 <= reg_rgb1;
            if (reg_luma <= 8'd96) reg_beta <= 9'sd192;
            else if (reg_luma >= 8'd160) reg_beta <= 0;
            else reg_beta <= $signed(dec_beta_middle[8:0]);
            reg_red_delta <= $signed({1'b0,reg_luma}) - $signed({1'b0,reg_rgb1[23:16]});
            reg_green_delta <= $signed({1'b0,reg_luma}) - $signed({1'b0,reg_rgb1[15:8]});
            reg_blue_delta <= $signed({1'b0,reg_luma}) - $signed({1'b0,reg_rgb1[7:0]});
            reg_rgb3 <= reg_rgb2;
            reg_red_product <= reg_beta * reg_red_delta;
            reg_green_product <= reg_beta * reg_green_delta;
            reg_blue_product <= reg_beta * reg_blue_delta;
            flag_valid_o <= reg_valid[3];
            if (reg_enable[3])
                reg_rgb_o <= {dec_red_rounded[15:8],dec_green_rounded[15:8],dec_blue_rounded[15:8]};
            else reg_rgb_o <= reg_rgb3;
        end
    end
endmodule
