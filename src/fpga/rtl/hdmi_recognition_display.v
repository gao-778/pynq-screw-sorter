`timescale 1ns/1ps

module hdmi_recognition_display (
    input wire clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 video_reset RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input wire reset,
    input wire camera_ready,
    input wire axes_visible,
    input wire [15:0] framebuffer_pixel,
    input wire [23:0] sidebar_pixel,
    output wire [8:0] sidebar_x,
    output wire [9:0] sidebar_y,
    output wire [16:0] framebuffer_address,
    output wire [8:0] framebuffer_x,
    output wire [7:0] framebuffer_y,
    output wire preview_vblank,
    output wire preview_row_start,
    output wire [7:0] preview_row,
    output wire frame_sent,
    output wire snapshot_start,
    output wire snapshot_valid,
    output wire [23:0] snapshot_rgb,
    output wire [9:0] q_blue,
    output wire [9:0] q_green,
    output wire [9:0] q_red
);
    reg [10:0] horizontal = 0;
    reg [9:0] vertical = 0;
    reg active_d = 0;
    reg active_dd=0,image_dd=0,start_dd=0,end_dd=0,hsync_dd=0,vsync_dd=0;
    reg [15:0] framebuffer_delayed;
    wire [10:0] sidebar_position=horizontal-11'd960;
    assign sidebar_x=horizontal>=960 && horizontal<1280?sidebar_position[8:0]:9'd511;
    assign sidebar_y=vertical;
    reg image_d = 0;
    reg start_d = 0;
    reg end_d = 0;
    reg hsync_d = 0;
    reg vsync_d = 0;
    reg [1:0] pattern_d = 0;
    wire active = horizontal < 1280 && vertical < 720;
    wire inside_image = horizontal < 960 && vertical < 720;
    reg [8:0] source_x = 0;
    reg [7:0] source_y = 0;
    reg [1:0] repeat_x = 0;
    reg [1:0] repeat_y = 0;
     
    assign preview_vblank = horizontal == 0 && vertical == 720;
    assign preview_row_start = horizontal == 0 && vertical < 720 && repeat_y == 0;
    assign preview_row = 8'd239-source_y;
    wire [16:0] forward_address = {9'd0,source_y} * 17'd320 + {8'd0,source_x};
    assign framebuffer_address = inside_image ? (17'd76799 - forward_address) : 17'd0;
    assign framebuffer_x = inside_image ? 9'd319-source_x : 9'd0;
    assign framebuffer_y = inside_image ? 8'd239-source_y : 8'd0;
     
    always @(posedge clk) begin
        if (reset) begin
            source_x <= 0;
            source_y <= 0;
            repeat_x <= 0;
            repeat_y <= 0;
        end else if (horizontal == 1649) begin
            source_x <= 0;
            repeat_x <= 0;
            if (vertical == 749) begin
                source_y <= 0;
                repeat_y <= 0;
            end else if (vertical < 720) begin
                if (repeat_y == 2) begin
                    repeat_y <= 0;
                    source_y <= source_y + 1'b1;
                end else repeat_y <= repeat_y + 1'b1;
            end
        end else if (inside_image) begin
            if (repeat_x == 2) begin
                repeat_x <= 0;
                source_x <= source_x + 1'b1;
            end else repeat_x <= repeat_x + 1'b1;
        end
    end
    wire [15:0] test_pixel = pattern_d == 0 ? 16'hdedd : pattern_d == 1 ? 16'hd6ba : 16'he71b;
    wire [15:0] selected_pixel = camera_ready ? framebuffer_delayed : test_pixel;
    wire [23:0] image_rgb = {selected_pixel[15:11],selected_pixel[15:13],
                            selected_pixel[10:5],selected_pixel[10:9],
                            selected_pixel[4:0],selected_pixel[4:2]};
    wire [23:0] raw_rgb = image_dd ? image_rgb : sidebar_pixel;
    wire [2:0] axes_alpha;
    platform_axes_overlay axes (
        .i_clk(clk), .i_reset(reset), .i_enable(axes_visible && camera_ready),
        .i_pixel_x(horizontal), .i_pixel_y(vertical), .o_alpha(axes_alpha)
    );
    // Keep recognition labels/boxes above the axes. Class colours and paper
    // bypass shadow chroma so the UI palette remains distinct on dark scenes.
    wire target_overlay = framebuffer_delayed == 16'h7496 ||
                          framebuffer_delayed == 16'hef5c ||
                          framebuffer_delayed == 16'hd26b ||
                          framebuffer_delayed == 16'h8a49 ||
                          framebuffer_delayed == 16'hff7b ||
                          framebuffer_delayed == 16'h245a ||
                          framebuffer_delayed == 16'hea49 ||
                          framebuffer_delayed == 16'h1d52 ||
                          framebuffer_delayed == 16'he4c6 ||
                          framebuffer_delayed == 16'h933b;
    wire [3:0] axes_weight = (!image_dd || target_overlay) ? 4'd0 :
                            axes_alpha == 7 ? 4'd8 : {1'b0,axes_alpha};
    wire [3:0] video_weight = 4'd8 - axes_weight;
    (* use_dsp = "no" *) wire [11:0] blend_red =
        raw_rgb[23:16] * video_weight + 8'h8c * axes_weight + 12'd4;
    (* use_dsp = "no" *) wire [11:0] blend_green =
        raw_rgb[15:8] * video_weight + 8'hae * axes_weight + 12'd4;
    (* use_dsp = "no" *) wire [11:0] blend_blue =
        raw_rgb[7:0] * video_weight + 8'hce * axes_weight + 12'd4;
    wire [23:0] composed_rgb = {blend_red[10:3],blend_green[10:3],blend_blue[10:3]};
    // Postprocess camera pixels only. Labels, axes and sidebar stay unchanged.
    // 仅相机本色进入暗部色度抑制，标注、坐标轴与侧栏逐像素原样旁路。
    wire shadow_enable = image_dd && camera_ready && !target_overlay && axes_weight == 0;
    wire [23:0] output_rgb;
    wire active_pipe;
    reg [23:0] reg_composed_rgb=0;
    reg flag_shadow_enable=0,flag_active_input=0;
    reg [5:0] reg_start_delay=0,reg_end_delay=0,reg_hsync_delay=0,reg_vsync_delay=0;
    wire start_pipe=reg_start_delay[5];
    wire end_pipe=reg_end_delay[5];
    wire hsync_pipe=reg_hsync_delay[5];
    wire vsync_pipe=reg_vsync_delay[5];
    preview_shadow_chroma shadow_chroma (
        .i_clk(clk),.i_rstn(!reset),.i_valid(flag_active_input),.i_enable(flag_shadow_enable),
        .i_rgb(reg_composed_rgb),.o_valid(active_pipe),.o_rgb(output_rgb)
    );
    always @(posedge clk) begin
        if (reset) begin
            active_dd<=0;image_dd<=0;start_dd<=0;end_dd<=0;hsync_dd<=0;vsync_dd<=0;
            framebuffer_delayed<=0;
            reg_composed_rgb<=0;flag_shadow_enable<=0;flag_active_input<=0;
            reg_start_delay<=0;reg_end_delay<=0;reg_hsync_delay<=0;reg_vsync_delay<=0;
        end else begin
            framebuffer_delayed<=framebuffer_pixel;
            active_dd<=active_d;image_dd<=image_d;start_dd<=start_d;end_dd<=end_d;
            hsync_dd<=hsync_d;vsync_dd<=vsync_d;
            reg_composed_rgb<=composed_rgb;
            flag_shadow_enable<=shadow_enable;flag_active_input<=active_dd;
            reg_start_delay<={reg_start_delay[4:0],start_dd};
            reg_end_delay<={reg_end_delay[4:0],end_dd};
            reg_hsync_delay<={reg_hsync_delay[4:0],hsync_dd};
            reg_vsync_delay<={reg_vsync_delay[4:0],vsync_dd};
        end
    end
    assign snapshot_valid = active_pipe;
    assign snapshot_start = start_pipe;
    assign snapshot_rgb = output_rgb;
    assign frame_sent = end_pipe;
    always @(posedge clk) begin
        if (reset) begin
            horizontal <= 0;
            vertical <= 0;
            active_d <= 0;
            image_d <= 0;
            start_d <= 0;
            end_d <= 0;
            hsync_d <= 0;
            vsync_d <= 0;
            pattern_d <= 0;
        end else begin
            if (horizontal == 1649) begin
                horizontal <= 0;
                if (vertical == 749) vertical <= 0;
                else vertical <= vertical + 1'b1;
            end else horizontal <= horizontal + 1'b1;
            active_d <= active;
            image_d <= inside_image;
            start_d <= horizontal == 0 && vertical == 0;
            end_d <= horizontal == 1279 && vertical == 719;
            hsync_d <= horizontal >= 1390 && horizontal < 1430;
            vsync_d <= vertical >= 725 && vertical < 730;
            if (vertical < 240) pattern_d <= 0;
            else if (vertical < 480) pattern_d <= 1;
            else pattern_d <= 2;
        end
    end
    tmds_encoder blue (.clk(clk),.DE(active_pipe),.D(output_rgb[7:0]),.C1(vsync_pipe),.C0(hsync_pipe),.q_out(q_blue));
    tmds_encoder green (.clk(clk),.DE(active_pipe),.D(output_rgb[15:8]),.C1(1'b0),.C0(1'b0),.q_out(q_green));
    tmds_encoder red (.clk(clk),.DE(active_pipe),.D(output_rgb[23:16]),.C1(1'b0),.C0(1'b0),.q_out(q_red));
endmodule

