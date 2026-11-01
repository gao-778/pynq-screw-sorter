`timescale 1ns/1ps
// English: Published-scene ledger and double-buffered sidebar text renderer.
// 中文：18个32位累计寄存器只按已发布画面计数；文本在垂直消隐原子切换。
module screw_dashboard #(
    parameter integer C_MAX_OBJECTS=12
) (
    input i_clk, input i_rstn,
    input i_bus_enable, input [3:0] i_bus_write,
    input [15:0] i_bus_address, input [31:0] i_bus_data,
    output [31:0] o_bus_data,
    input i_scene_toggle, input i_scene_valid,
    input [5:0] i_scene_count, input [C_MAX_OBJECTS*5-1:0] i_scene_classes,
    input i_display_clk, input i_display_rstn, input i_vblank,
    input [8:0] i_pixel_x, input [9:0] i_pixel_y,
    input [11:0] i_axis_x, input [11:0] i_axis_y,
    input [4:0] i_keys, input [31:0] i_samples,
    // Same i_clk domain: observational video counters never control recognition.
    // 中文：同一总线时钟域的视频计数，只读且不参与识别或夹取决策。
    input wire [31:0] i_camera_frames,
    input wire [31:0] i_written_frames,
    input wire [31:0] i_display_frames,
    input wire [31:0] i_video_status,
    output o_command_toggle, output [3:0] o_command,
    input i_command_ack, input [15:0] i_selection_status,
    output [23:0] o_pixel,
    output o_axes_visible, output o_overlays_hidden,
    output [26:0] o_class_color_control
);
// Bus writes target the inactive text bank. Counters survive inference aborts.
reg [31:0] reg_total [0:17];
reg [3:0] reg_scene [0:17];
reg [3:0] reg_build [0:17];
reg [C_MAX_OBJECTS*5-1:0] reg_classes;
reg [5:0] reg_count,reg_pending_count;
reg flag_valid,flag_pending_valid,flag_scene_seen;
reg [3:0] cnt_object;
reg flag_building;
reg [31:0] cnt_scene,cnt_batches,reg_last_count,reg_record_status;
reg [31:0] reg_bus_data_o;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_scene_sync;
reg reg_text_request;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_text_sync;
reg reg_text_front;
// Bundled color metadata is held from text request until its returned ACK.
// 中文：颜色与文字共用消隐提交和确认；等待确认期间禁止改写暂存数据。
(* DONT_TOUCH="TRUE" *) reg [26:0] reg_color_stage;
(* ASYNC_REG="TRUE" *) reg [26:0] reg_color_meta,reg_color_sync;
reg [26:0] reg_color_front;
assign o_class_color_control=reg_color_front;
// Single-bit control crosses into the display clock, then commits in blanking.
reg reg_axes_request;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_axes_sync;
reg reg_axes_front;
assign o_axes_visible=reg_axes_front;
// Hide classification graphics only. Video and the optional axes keep running.
// 中文：单比特跨时钟域，消隐期提交；只隐藏识别叠加层，不暂停预览。
reg reg_hide_request;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_hide_sync;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_hide_ack_sync;
reg reg_hide_front;
assign o_overlays_hidden=reg_hide_front;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_front_sync;
(* rom_style="block" *) reg [7:0] reg_font [0:8191];
wire [15:0] reg_cell;
reg [7:0] reg_font_row;
reg [3:0] reg_row,reg_style;
reg [2:0] reg_column,reg_column_pipe;
reg flag_panel,flag_panel_pipe;
integer idx;
reg reg_command_toggle;
reg [3:0] reg_command;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_ack_sync;
(* ASYNC_REG="TRUE" *) reg [15:0] reg_selection_meta,reg_selection_sync;
assign o_command_toggle=reg_command_toggle;
assign o_command=reg_command;
wire flag_write=i_bus_enable && i_bus_write==4'hf;
wire flag_menu_row=i_pixel_y>=10'd176 && i_pixel_y<10'd400;
wire [5:0] wire_text_row=flag_menu_row && !i_pixel_y[4]?i_pixel_y[9:4]-6'd1:i_pixel_y[9:4];
wire [11:0] wire_text_address={reg_text_front,11'd0}
    +({6'd0,wire_text_row}*12'd40)+{6'd0,i_pixel_x[8:3]};
wire [4:0] wire_class=reg_classes[4:0];
reg [4:0] dec_index;
always @(*) begin
    case(wire_class)
        0:dec_index=4;1:dec_index=3;2:dec_index=0;
        3:dec_index=9;4:dec_index=7;5:dec_index=5;
        6:dec_index=14;7:dec_index=13;8:dec_index=10;
        9:dec_index=1;10:dec_index=2;11:dec_index=6;
        12:dec_index=8;13:dec_index=11;14:dec_index=12;
        15:dec_index=15;16:dec_index=16;17:dec_index=17;
        default:dec_index=31;
    endcase
end
assign o_bus_data=reg_bus_data_o;
sidebar_mint_theme sidebar_theme (
    .i_clk(i_display_clk), .i_rstn(i_display_rstn),
    .i_pixel_x(i_pixel_x), .i_pixel_y(i_pixel_y),
    .i_style(reg_style), .i_text_ink(reg_font_row[7-reg_column_pipe]),
    .i_panel_active(flag_panel_pipe), .o_pixel(o_pixel)
);
initial $readmemh("dashboard_font.hex",reg_font);
// Explicit independent-clock BRAM avoids a synthesized LUTRAM write-clock to
// display-clock path. The host writes only the inactive bank and waits for the
// synchronized front-bank acknowledgement before reusing the previous bank.
xpm_memory_sdpram #(
    .MEMORY_SIZE(65536), .MEMORY_PRIMITIVE("block"),
    .CLOCKING_MODE("independent_clock"), .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("dashboard_text.mem"), .USE_MEM_INIT(1),
    .WRITE_DATA_WIDTH_A(16), .BYTE_WRITE_WIDTH_A(16), .ADDR_WIDTH_A(12),
    .READ_DATA_WIDTH_B(16), .ADDR_WIDTH_B(12), .READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0020"), .WRITE_MODE_B("no_change"),
    .RST_MODE_B("SYNC"), .SIM_ASSERT_CHK(1)
) dashboard_text_bram (
    .clka(i_clk), .ena(1'b1),
    .wea(flag_write && i_bus_address[15:14]==2'b01 &&
         i_bus_address[13]!=reg_front_sync[2]),
    .addra(i_bus_address[13:2]), .dina(i_bus_data[15:0]),
    .clkb(i_display_clk), .rstb(!i_display_rstn), .enb(1'b1),
    .regceb(1'b1), .addrb(wire_text_address), .doutb(reg_cell),
    .sleep(1'b0), .injectsbiterra(1'b0), .injectdbiterra(1'b0),
    .sbiterrb(), .dbiterrb()
);
always @(posedge i_display_clk) begin
    reg_font_row<=reg_font[{reg_cell[8:0],reg_row}];
    reg_row<=flag_menu_row?i_pixel_y[3:0]-4'd6:i_pixel_y[3:0];reg_column<=i_pixel_x[2:0];
    reg_column_pipe<=reg_column;reg_style<=reg_cell[15:12];
    flag_panel<=i_pixel_x<320 && i_pixel_y<720;
    flag_panel_pipe<=flag_panel;
    if(!i_display_rstn) begin
        reg_text_sync<=0;reg_text_front<=0;
        reg_color_meta<=0;reg_color_sync<=0;reg_color_front<=0;
        reg_axes_sync<=3'b111;reg_axes_front<=1'b1;
        reg_hide_sync<=0;reg_hide_front<=0;
    end else begin
        reg_text_sync<={reg_text_sync[1:0],reg_text_request};
        reg_color_meta<=reg_color_stage;reg_color_sync<=reg_color_meta;
        reg_axes_sync<={reg_axes_sync[1:0],reg_axes_request};
        reg_hide_sync<={reg_hide_sync[1:0],reg_hide_request};
        if(i_vblank)begin
            reg_text_front<=reg_text_sync[2];
            if(reg_text_front!=reg_text_sync[2])reg_color_front<=reg_color_sync;
        end
        if(i_vblank)reg_axes_front<=reg_axes_sync[2];
        if(i_vblank)reg_hide_front<=reg_hide_sync[2];
    end
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_scene_sync<=0;flag_scene_seen<=0;reg_front_sync<=0;
        reg_hide_request<=0;reg_hide_ack_sync<=0;reg_color_stage<=0;
        reg_command_toggle<=0;reg_command<=0;reg_ack_sync<=0;
        reg_selection_meta<=0;reg_selection_sync<=0;
        reg_text_request<=0;reg_axes_request<=1'b1;cnt_scene<=0;cnt_batches<=0;reg_last_count<=0;
        reg_record_status<=0;flag_valid<=0;flag_pending_valid<=0;
        reg_classes<=0;reg_count<=0;reg_pending_count<=0;cnt_object<=0;flag_building<=0;
        reg_bus_data_o<=0;
        for(idx=0;idx<18;idx=idx+1)begin reg_total[idx]<=0;reg_scene[idx]<=0;reg_build[idx]<=0;end
    end else begin
        reg_scene_sync<={reg_scene_sync[1:0],i_scene_toggle};
        reg_ack_sync<={reg_ack_sync[1:0],i_command_ack};
        reg_selection_meta<=i_selection_status;reg_selection_sync<=reg_selection_meta;
        reg_front_sync<={reg_front_sync[1:0],reg_text_front};
        reg_hide_ack_sync<={reg_hide_ack_sync[1:0],reg_hide_front};
        // Source data stays fixed from publish until the next publish. Three sync
        // edges precede sampling; no independent per-bit synchronizers are used.
        if(reg_scene_sync[2]!=flag_scene_seen) begin
            flag_scene_seen<=reg_scene_sync[2];reg_classes<=i_scene_classes;
            reg_pending_count<=i_scene_count;
            flag_pending_valid<=i_scene_valid && i_scene_count<=C_MAX_OBJECTS;
            cnt_object<=0;flag_building<=1;
            for(idx=0;idx<18;idx=idx+1)reg_build[idx]<=0;
        end else if(flag_building) begin
            if(cnt_object==C_MAX_OBJECTS) begin
                for(idx=0;idx<18;idx=idx+1)reg_scene[idx]<=reg_build[idx];
                reg_count<=reg_pending_count;flag_valid<=flag_pending_valid;
                cnt_scene<=cnt_scene+1'b1;flag_building<=0;
            end else begin
                if(cnt_object<reg_pending_count) begin
                    if(dec_index<18)reg_build[dec_index]<=reg_build[dec_index]+1'b1;
                    else flag_pending_valid<=0;
                end
                reg_classes<=reg_classes>>5;cnt_object<=cnt_object+1'b1;
            end
        end
        if(i_bus_enable) begin
            case(i_bus_address)
                16'h0000:reg_bus_data_o<=32'h4a4f5931;
                16'h0020:reg_bus_data_o<={24'd0,reg_command,2'd0,reg_ack_sync[2],reg_command_toggle};
                16'h0024:reg_bus_data_o<={20'd0,i_axis_x};
                16'h0028:reg_bus_data_o<={20'd0,i_axis_y};
                16'h002c:reg_bus_data_o<={27'd0,i_keys};
                16'h0030:reg_bus_data_o<=i_samples;
                16'h0034:reg_bus_data_o<={16'd0,reg_selection_sync};
                16'h0038:reg_bus_data_o<={31'd0,reg_axes_request};
                16'h003c:reg_bus_data_o<=32'h56504631;
                16'h0040:reg_bus_data_o<=i_camera_frames;
                16'h0044:reg_bus_data_o<=i_written_frames;
                16'h0048:reg_bus_data_o<=i_display_frames;
                16'h004c:reg_bus_data_o<=i_video_status;
                16'h0050:reg_bus_data_o<={30'd0,reg_hide_ack_sync[2],reg_hide_request};
                16'h0054:reg_bus_data_o<={5'd0,reg_color_stage};
                16'h0004:reg_bus_data_o<=cnt_scene;
                16'h0008:reg_bus_data_o<={23'd0,flag_building,flag_valid,1'b0,reg_count};
                16'h0010:reg_bus_data_o<=cnt_batches;
                16'h0014:reg_bus_data_o<=reg_last_count;
                16'h0018:reg_bus_data_o<=reg_record_status;
                16'h001c:reg_bus_data_o<={30'd0,reg_text_request,reg_front_sync[2]};
                default: begin
                    if(i_bus_address>=16'h0100 && i_bus_address<16'h0148)
                        reg_bus_data_o<=reg_total[i_bus_address[6:2]];
                    else if(i_bus_address>=16'h0180 && i_bus_address<16'h01c8)
                        reg_bus_data_o<={28'd0,reg_scene[i_bus_address[6:2]]};
                    else reg_bus_data_o<=0;
                end
            endcase
        end
        if(flag_write && i_bus_address==16'h0020 && reg_ack_sync[2]==reg_command_toggle)begin
            reg_command<=i_bus_data[7:4];reg_command_toggle<=i_bus_data[0];
        end
        if(flag_write && i_bus_address==16'h001c)
            reg_text_request<=i_bus_data[0];
        if(flag_write && i_bus_address==16'h0050)
            reg_hide_request<=i_bus_data[0];
        if(flag_write && i_bus_address==16'h0054 && reg_text_request==reg_front_sync[2])
            reg_color_stage<=i_bus_data[26:0];
        if(flag_write && i_bus_address==16'h0038)
            reg_axes_request<=i_bus_data[0];
        if(flag_write && i_bus_address==16'h000c && i_bus_data==1) begin
            if(flag_building || reg_scene_sync[2]!=flag_scene_seen)reg_record_status<=4;
            else if(!flag_valid)reg_record_status<=2;
            else if(reg_count==0)reg_record_status<=3;
            else begin
                reg_record_status<=1;reg_last_count<={26'd0,reg_count};
                if(cnt_batches!=32'hffffffff)cnt_batches<=cnt_batches+1'b1;
                for(idx=0;idx<18;idx=idx+1)begin
                    if(reg_total[idx]>32'hffffffff-{28'd0,reg_scene[idx]})
                        reg_total[idx]<=32'hffffffff;
                    else reg_total[idx]<=reg_total[idx]+{28'd0,reg_scene[idx]};
                end
            end
        end
    end
end
endmodule
