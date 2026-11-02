`timescale 1ns / 1ps
 
module recognition_core_obb #(
	parameter C_WIDTH=1280,
	parameter C_HEIGHT=960,
	parameter C_TIMEOUT=500000000,
	parameter C_MAX_OBJECTS=12
	) (
	input i_clk,
    output reg [31:0] o_gray_base,
    output reg [31:0] o_preview_base,
    output o_preview_run,
    input i_preview_idle, input i_gray_idle,
	input i_rstn,
	input i_camera_clk,
	input i_frame_start, input i_line_start,
	input i_pixel_valid,
	input [23:0] i_rgb,
	input i_bus_enable,
	input [3:0] i_bus_write,
	input [15:0] i_bus_address,
	input [31:0] i_bus_data,
	output [31:0] o_bus_data,
	output o_busy,
	output o_done,
	output o_capture_active,
	output o_preview_hold,
	output o_results_valid,
	input [8:0] i_overlay_address,
	output [31:0] o_overlay_data,
	output [5:0] o_object_count,
    input i_dma_done,
    output [31:0] o_stream_data, output [3:0] o_stream_keep,
    output o_stream_valid, input i_stream_ready, output o_stream_last,
    output o_camera_rstn,
    output o_frame_bank,
    output [20:0] o_frame_address, output o_frame_enable, output o_frame_invalidate,
    input [7:0] i_frame_data, input i_frame_valid, input i_frame_error
);

localparam MODEL_WEIGHT_COUNT=255510;
localparam MODEL_BIAS_COUNT=402;
localparam MODEL_SHIFT_COUNT=3;
localparam MODEL_WEIGHT_PORT=16'h0070;
localparam MODEL_BIAS_BASE=16'he800;
 
localparam MODEL_SHIFT_BASE=16'hef00;
localparam ST_IDLE=0,ST_CAPTURE_START=1,ST_CAPTURE_ARM=2,ST_CAPTURE_WAIT=3,
ST_LABEL_START=4,ST_LABEL_WAIT=5,ST_ROI_START=6,ST_ROI_WAIT=7,
ST_CNN_START=8,ST_CNN_WAIT=9,ST_RESULT=10,ST_ACCEPT=11,ST_DONE=12,ST_GEOMETRY=13,ST_SKIP=14,
ST_ORIENT_START=15,ST_ORIENT_WAIT=16,ST_TRACK_START=17,ST_TRACK_WAIT=18,
ST_REORIENT_START=19,ST_REORIENT_WAIT=20,ST_FILTER_START=21,ST_FILTER_WAIT=22,ST_RESULT_PREP=23,ST_THRESHOLD_START=24,ST_THRESHOLD_WAIT=25;
reg [4:0] state_current,state_next;
reg reg_buffer_lock,reg_preview_run;
assign o_preview_run=reg_buffer_lock && reg_preview_run;
reg flag_start,flag_abort,flag_done,flag_error,flag_model,flag_load_error;
reg flag_external_frame,reg_frame_bank,flag_capture_start,flag_capture_abort;
wire flag_capture_reset=i_rstn && !flag_capture_abort && (flag_external_frame || !flag_abort);
assign o_frame_bank=reg_frame_bank;
reg flag_clear_results;
reg flag_label_overflow,flag_object_overflow,flag_capture_error;
reg [7:0] reg_threshold;
// A frame uses one latched threshold and one DDR bank from start to finish.
reg flag_auto_enable;
reg [7:0] reg_frame_threshold,reg_frame_p50,reg_frame_p90;
reg [15:0] reg_threshold_samples;
reg flag_threshold_done,flag_threshold_error;
wire [7:0] wire_threshold,wire_threshold_p50,wire_threshold_p90;
wire [15:0] wire_threshold_samples;
wire [20:0] wire_threshold_address;
wire flag_threshold_read,flag_threshold_busy,wire_threshold_done,wire_threshold_error;
wire flag_threshold_active=state_current==ST_THRESHOLD_START || state_current==ST_THRESHOLD_WAIT;
reg reg_bright;
reg [20:0] reg_min_area;
reg [31:0] cnt_frame,cnt_cycles,reg_last_cycles;
reg [5:0] cnt_objects;
reg [9:0] cnt_total_objects;
reg [5:0] cnt_result_word;
reg [17:0] cnt_weights;
reg [3:0] reg_angle_index;
reg flag_manual_angle;
reg [3:0] reg_object_angle;
reg [3:0] reg_raw_angle;
reg signed [15:0] reg_local_xmin,reg_local_ymin,reg_local_xmax,reg_local_ymax;
reg [8:0] cnt_biases;
reg [1:0] cnt_shifts;
reg flag_config_write;
reg [1:0] reg_config_kind;
reg [17:0] reg_config_address;
reg [31:0] reg_config_data;
(* ram_style="distributed" *) reg [31:0] reg_results [0:511];
reg [31:0] reg_bus_data_o;
reg [10:0] reg_xmin,reg_ymin,reg_xmax,reg_ymax;
reg [20:0] reg_area;
reg [31:0] reg_class;
wire flag_running = state_current!=ST_IDLE && state_current!=ST_DONE;
wire flag_reset = i_rstn && !flag_abort;
wire flag_bus_write = i_bus_enable && i_bus_write==4'hf;
wire [20:0] wire_label_address,wire_roi_address,wire_orient_address,wire_frame_address;
wire [7:0] wire_pixel;
wire flag_frame_done,flag_frame_error,flag_label_done,wire_label_overflow;
wire [30:0] wire_capture_age_ms;
wire flag_capture_age_valid;
wire flag_box_valid,flag_box_ready,flag_roi_done,flag_cnn_done,flag_orient_done;
wire flag_roi_read,flag_orient_read;
wire [10:0] wire_xmin,wire_ymin,wire_xmax,wire_ymax;
wire [11:0] wire_sample_address;
wire [20:0] wire_area;
wire [7:0] wire_sample;
wire flag_sample_write;
wire [6:0] wire_short,wire_long,wire_size;
wire [6:0] wire_length,wire_head_width,wire_tail_width;
wire [4:0] wire_class;
 
wire [3:0] wire_angle_index;
wire signed [15:0] wire_local_xmin,wire_local_ymin,wire_local_xmax,wire_local_ymax;
wire flag_roi_active=state_current==ST_ROI_START || state_current==ST_ROI_WAIT;
wire flag_reorient=state_current==ST_REORIENT_START || state_current==ST_REORIENT_WAIT;
wire flag_orient_active=state_current==ST_ORIENT_START || state_current==ST_ORIENT_WAIT || flag_reorient;
wire flag_filter_active=state_current==ST_FILTER_START || state_current==ST_FILTER_WAIT;
wire flag_temporal_done;
wire [3:0] wire_temporal_angle,wire_temporal_flags;
wire [4:0] wire_temporal_class,wire_temporal_score_index;
wire [10:0] wire_display_xmin,wire_display_ymin,wire_display_xmax,wire_display_ymax;
wire signed [15:0] wire_display_lxmin,wire_display_lymin,wire_display_lxmax,wire_display_lymax;
wire flag_label_active=state_current==ST_LABEL_START || state_current==ST_LABEL_WAIT;
wire [31:0] wire_score;
wire [4:0] dec_score_index = cnt_result_word>=24 ? cnt_result_word-24 : cnt_result_word-6;
assign o_bus_data=reg_bus_data_o;
assign o_busy=flag_running;
assign o_done=flag_done;
 
wire [8:0] dec_result_address = cnt_result_word[4] ? {1'b1,1'b0,cnt_objects[3:0],cnt_result_word[2:0]} : {cnt_objects[4:0],cnt_result_word[3:0]};
reg [31:0] dec_result_data;
 
reg [31:0] reg_result_write_data;
reg [8:0] reg_result_write_address;
 
(* ram_style="block" *) reg [31:0] reg_logits[0:511];
reg [8:0] reg_logit_write_address;
reg flag_logit_write;
wire [4:0] dec_logit_index=cnt_result_word-24;
wire [10:0] wire_label_count;
wire [20:0] wire_foreground_count,wire_scan_address;
wire [10:0] wire_overflow_x,wire_overflow_y;
reg [31:0] cnt_capture_cycles,cnt_label_cycles,cnt_orient_cycles;
reg [31:0] cnt_roi_cycles,cnt_cnn_cycles,cnt_other_cycles,cnt_ddr_wait_cycles;

always @(*) begin
    dec_result_data=0;
				case(cnt_result_word)
					0: dec_result_data=flag_model ? {wire_display_lxmin,5'd0,wire_display_xmin} : {reg_local_xmin,5'd0,reg_xmin};
					1: dec_result_data=flag_model ? {wire_display_lymin,5'd0,wire_display_ymin} : {reg_local_ymin,5'd0,reg_ymin};
					2: dec_result_data=flag_model ? {wire_display_lxmax,5'd0,wire_display_xmax} : {reg_local_xmax,5'd0,reg_xmax};
					3: dec_result_data=flag_model ? {wire_display_lymax,5'd0,wire_display_ymax} : {reg_local_ymax,5'd0,reg_ymax};
					4: dec_result_data={11'd0,reg_area};
					5: dec_result_data=reg_class;
					6,7,8,9,10,11,12,13,14,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41: dec_result_data=flag_model ? wire_score : 0;
                    16: dec_result_data={reg_local_xmin,5'd0,reg_xmin};
                    17: dec_result_data={reg_local_ymin,5'd0,reg_ymin};
                    18: dec_result_data={reg_local_xmax,5'd0,reg_xmax};
                    19: dec_result_data={reg_local_ymax,5'd0,reg_ymax};
                    20: dec_result_data={19'd0,wire_class[4],reg_raw_angle,reg_object_angle,wire_class[3:0]};
                    21: dec_result_data={8'd0,1'b0,wire_length,1'b0,wire_head_width,1'b0,wire_tail_width};
                    22: dec_result_data={11'd0,reg_area};
                    23: dec_result_data=cnt_frame;
					15: dec_result_data=cnt_frame;
					default: dec_result_data=0;
				endcase
end

assign o_overlay_data=reg_results[i_overlay_address];
// Display count includes eligible objects beyond the classified result slots.
assign o_object_count=cnt_total_objects>=63 ? 6'd63 : cnt_total_objects[5:0];
assign o_results_valid=flag_done && !flag_error;
assign wire_frame_address=flag_threshold_active ? wire_threshold_address : flag_orient_active ? wire_orient_address :
    (flag_roi_active ? wire_roi_address : wire_label_address);

 
assign o_frame_address=wire_frame_address;
assign wire_pixel=i_frame_data;
assign o_frame_enable=(wire_frame_address<C_WIDTH*C_HEIGHT) &&
    ((flag_threshold_active && flag_threshold_read) || flag_label_active || (flag_orient_active && flag_orient_read) || (flag_roi_active && flag_roi_read));
assign o_frame_invalidate=state_current==ST_CAPTURE_START || flag_abort;
wire [10:0] dec_box_width={1'b0,reg_xmax}-{1'b0,reg_xmin}+11'd1;
wire [10:0] dec_box_height={1'b0,reg_ymax}-{1'b0,reg_ymin}+11'd1;
reg [10:0] reg_short,reg_long;
reg [21:0] reg_box_area;
wire [21:0] dec_filled={3'b0,reg_area}*22'd5;
wire [22:0] dec_min_fill={reg_box_area,1'b0};
wire flag_border_touch=reg_xmin==0 || reg_ymin==0 ||
    reg_xmax==C_WIDTH-1 || reg_ymax==C_HEIGHT-1;
// The OBB variant is trained for fifteen screw classes.  Screws are
// deliberately long and thin, so the old circle/square aspect-ratio and
// fill-ratio gates would reject valid parts before the CNN sees them.
// Keep only the small-component and frame-border guards used by the
// segmentation stage.
wire flag_reject=reg_short<10 || flag_border_touch;
assign flag_box_ready=state_current==ST_ACCEPT ||
    (state_current==ST_SKIP && (flag_reject || cnt_objects>=C_MAX_OBJECTS));
frame_snapshot #(.C_WIDTH(C_WIDTH),.C_HEIGHT(C_HEIGHT)) frame_snapshot_Inst (
.i_clk(i_clk),.i_rstn(flag_capture_reset),
.i_start(flag_external_frame?flag_capture_start:state_current==ST_CAPTURE_START),
.i_camera_clk(i_camera_clk),.i_frame_start(i_frame_start),.i_line_start(i_line_start),.i_pixel_valid(i_pixel_valid),.i_rgb(i_rgb),
 .i_dma_done(i_dma_done),.o_stream_data(o_stream_data),.o_stream_keep(o_stream_keep),
.o_stream_valid(o_stream_valid),.i_stream_ready(i_stream_ready),.o_stream_last(o_stream_last),
.o_camera_rstn(o_camera_rstn),.o_done(flag_frame_done),.o_error(flag_frame_error),
.o_capture_active(o_capture_active),.o_preview_hold(o_preview_hold),
.o_capture_age_ms(wire_capture_age_ms),.o_capture_age_valid(flag_capture_age_valid));
frame_adaptive_threshold #(.C_WIDTH(C_WIDTH),.C_HEIGHT(C_HEIGHT)) frame_adaptive_threshold_Inst (
.i_clk(i_clk),.i_rstn(i_rstn),.i_start(state_current==ST_THRESHOLD_START),.i_abort(flag_abort || (flag_threshold_active && (cnt_cycles>=C_TIMEOUT || i_frame_error))),
.i_fallback_threshold(reg_threshold),.o_frame_address(wire_threshold_address),.o_frame_enable(flag_threshold_read),
.i_frame_data(wire_pixel),.i_frame_valid(i_frame_valid && flag_threshold_active),.i_frame_error(i_frame_error),
.o_threshold(wire_threshold),.o_p50(wire_threshold_p50),.o_p90(wire_threshold_p90),
.o_samples(wire_threshold_samples),.o_busy(flag_threshold_busy),.o_done(wire_threshold_done),.o_error(wire_threshold_error));
component_labeler #(.C_WIDTH(C_WIDTH),.C_HEIGHT(C_HEIGHT)) component_labeler_Inst (
.i_clk(i_clk),.i_rstn(flag_reset),.i_start(state_current==ST_LABEL_START),
.i_threshold(reg_frame_threshold),.i_bright(reg_bright),.i_min_area(reg_min_area),
.o_pixel_address(wire_label_address),.i_pixel(wire_pixel),.i_pixel_ready(i_frame_valid && flag_label_active),
.o_box_valid(flag_box_valid),.i_box_ready(flag_box_ready),
.o_xmin(wire_xmin),.o_ymin(wire_ymin),.o_xmax(wire_xmax),.o_ymax(wire_ymax),
.o_area(wire_area),.o_done(flag_label_done),.o_overflow(wire_label_overflow),
.o_label_count(wire_label_count),.o_foreground_count(wire_foreground_count),
.o_overflow_x(wire_overflow_x),.o_overflow_y(wire_overflow_y),.o_scan_address(wire_scan_address));
obb_orientation #(.C_WIDTH(C_WIDTH),.C_HEIGHT(C_HEIGHT)) obb_orientation_Inst (
.i_clk(i_clk),.i_rstn(flag_reset),.i_start(state_current==ST_ORIENT_START || state_current==ST_REORIENT_START),
.i_xmin(reg_xmin),.i_ymin(reg_ymin),.i_xmax(reg_xmax),.i_ymax(reg_ymax),
.i_threshold(reg_frame_threshold),.i_bright(reg_bright),
.i_manual(flag_manual_angle || flag_reorient),.i_manual_angle(flag_reorient?wire_temporal_angle:reg_angle_index),
.o_read_address(wire_orient_address),.o_read_enable(flag_orient_read),
.i_read_data(wire_pixel),.i_read_valid(i_frame_valid && flag_orient_active),
.o_angle_index(wire_angle_index),.o_local_xmin(wire_local_xmin),.o_local_ymin(wire_local_ymin),
.o_local_xmax(wire_local_xmax),.o_local_ymax(wire_local_ymax),
.o_length(wire_length),.o_head_width(wire_head_width),.o_tail_width(wire_tail_width),.o_done(flag_orient_done));
roi_sampler_obb #(.C_WIDTH(C_WIDTH),.C_HEIGHT(C_HEIGHT)) roi_sampler_Inst (
.i_clk(i_clk),.i_rstn(flag_reset),.i_start(state_current==ST_ROI_START),
.i_xmin(reg_xmin),.i_ymin(reg_ymin),.i_xmax(reg_xmax),.i_ymax(reg_ymax),.i_area(reg_area),.i_angle_index(reg_object_angle),.i_threshold(reg_frame_threshold),
.o_read_address(wire_roi_address),.o_read_enable(flag_roi_read),.i_read_data(wire_pixel),.i_read_valid(i_frame_valid && flag_roi_active),
.o_write(flag_sample_write),.o_write_address(wire_sample_address),.o_write_data(wire_sample),
.o_short_side(wire_short),.o_long_side(wire_long),.o_area(wire_size),.o_done(flag_roi_done));
cnn_classifier cnn_classifier_Inst (
.i_clk(i_clk),.i_rstn(flag_reset),.i_start(state_current==ST_CNN_START),
.i_input_write(flag_sample_write),.i_input_address(wire_sample_address),.i_input_data(wire_sample),
// Legacy CNN port names carry length, head width and tail width in this variant.
.i_short_side(wire_length),.i_long_side(wire_head_width),.i_area(wire_tail_width),
.i_config_write(flag_config_write),.i_config_kind(reg_config_kind),
.i_config_address(reg_config_address),.i_config_data(reg_config_data),
.i_score_index(flag_filter_active?wire_temporal_score_index:dec_score_index),.o_score(wire_score),.o_class(wire_class),.o_done(flag_cnn_done));
temporal_object_filter #(.C_MAX_OBJECTS(C_MAX_OBJECTS),.C_CLASSES(18)) temporal_object_filter_Inst (
.i_clk(i_clk),.i_rstn(flag_reset),.i_frame_begin(state_current==ST_CAPTURE_START),
.i_query(state_current==ST_TRACK_START),.i_commit(state_current==ST_FILTER_START),.i_bypass(flag_manual_angle),
.i_xmin(reg_xmin),.i_ymin(reg_ymin),.i_xmax(reg_xmax),.i_ymax(reg_ymax),.i_area(reg_area),
.i_angle(reg_object_angle),.i_raw_class(wire_class),
.i_lxmin(reg_local_xmin),.i_lymin(reg_local_ymin),.i_lxmax(reg_local_xmax),.i_lymax(reg_local_ymax),
.o_score_index(wire_temporal_score_index),.i_score(wire_score),.o_done(flag_temporal_done),
.o_angle(wire_temporal_angle),.o_class(wire_temporal_class),.o_flags(wire_temporal_flags),
.o_xmin(wire_display_xmin),.o_ymin(wire_display_ymin),.o_xmax(wire_display_xmax),.o_ymax(wire_display_ymax),
.o_lxmin(wire_display_lxmin),.o_lymin(wire_display_lymin),.o_lxmax(wire_display_lxmax),.o_lymax(wire_display_lymax));
// 本机地址由 AXI BRAM Controller 提供，所有写入要求 32 位整字。
always @(posedge i_clk) begin
	if(!i_rstn) begin
        o_gray_base<=0;o_preview_base<=0;
        reg_buffer_lock<=0;reg_preview_run<=0;
		flag_start<=0;
        flag_external_frame<=0;reg_frame_bank<=0;flag_capture_start<=0;flag_capture_abort<=0;
		flag_abort<=0;flag_clear_results<=0;
		flag_model<=0;
		flag_load_error<=0;
		reg_threshold<=40;flag_auto_enable<=1;
		reg_bright<=1;
		reg_min_area<=20;
		cnt_weights<=0;
		reg_angle_index<=0;
        flag_manual_angle<=0;
		cnt_biases<=0;
		cnt_shifts<=0;
		flag_config_write<=0;
		reg_config_kind<=0;
		reg_config_address<=0;
		reg_config_data<=0;
		reg_bus_data_o<=0;
	end
	else begin
		flag_start<=0;flag_capture_start<=0;flag_capture_abort<=0;
		flag_abort<=0;flag_clear_results<=0;
		flag_config_write<=0;
		if(i_bus_enable) begin
			case(i_bus_address)
				16'h0000: reg_bus_data_o<=32'h464e4554;
                16'h0074: reg_bus_data_o<={30'd0,reg_frame_bank,flag_external_frame};
                16'h0080: reg_bus_data_o<={31'd0,flag_auto_enable};
                16'h0084: reg_bus_data_o<={4'd0,flag_threshold_error,flag_threshold_done,flag_threshold_busy,flag_auto_enable,reg_frame_p90,reg_frame_p50,reg_frame_threshold};
                16'h0088: reg_bus_data_o<={16'd0,reg_threshold_samples};
                16'h007c: reg_bus_data_o<={30'd0,flag_frame_error,flag_frame_done};
				16'h0008: reg_bus_data_o<={24'd0,flag_load_error,flag_capture_error,flag_object_overflow,flag_label_overflow,flag_error,flag_model,flag_done,flag_running};
				16'h000c: reg_bus_data_o<={26'd0,cnt_objects};
				16'h0010: reg_bus_data_o<=cnt_frame;
				16'h0014: reg_bus_data_o<=reg_last_cycles;
				16'h0018: reg_bus_data_o<={23'd0,reg_bright,reg_threshold};
				16'h001c: reg_bus_data_o<={11'd0,reg_min_area};
				16'h0020: reg_bus_data_o<={14'd0,cnt_weights};
				16'h0024: reg_bus_data_o<={23'd0,cnt_biases};
				16'h0028: reg_bus_data_o<={30'd0,cnt_shifts};
				16'h0034: reg_bus_data_o<={22'd0,cnt_total_objects};
                16'h0038: reg_bus_data_o<=32'h4d433138;
                16'h008c: reg_bus_data_o<=C_MAX_OBJECTS;
                16'h0094: reg_bus_data_o<=o_gray_base;
                16'h0098: reg_bus_data_o<=o_preview_base;
                16'h009c: reg_bus_data_o<=32'h50594d32;
                16'h00a0: reg_bus_data_o<={31'd0,reg_buffer_lock};
                16'h00a4: reg_bus_data_o<={31'd0,reg_preview_run};
                16'h00a8: reg_bus_data_o<={30'd0,i_gray_idle,i_preview_idle};
                16'h0090: reg_bus_data_o<={flag_capture_age_valid,wire_capture_age_ms};
                16'h0040: reg_bus_data_o<=cnt_capture_cycles;
                16'h0044: reg_bus_data_o<=cnt_label_cycles;
                16'h0048: reg_bus_data_o<=cnt_orient_cycles;
                16'h004c: reg_bus_data_o<=cnt_roi_cycles;
                16'h0050: reg_bus_data_o<=cnt_cnn_cycles;
                16'h0054: reg_bus_data_o<=cnt_other_cycles;
                16'h0058: reg_bus_data_o<=cnt_ddr_wait_cycles;
                16'h005c: reg_bus_data_o<={21'd0,wire_label_count};
                16'h0060: reg_bus_data_o<={11'd0,wire_foreground_count};
                16'h0064: reg_bus_data_o<={5'd0,wire_overflow_y,5'd0,wire_overflow_x};
                16'h0068: reg_bus_data_o<={11'd0,wire_scan_address};
				16'h0030: reg_bus_data_o<={23'd0,flag_manual_angle,4'd0,reg_angle_index};
				default: begin
					if(i_bus_address>=16'hc000 && i_bus_address<16'hc600) begin
                        reg_bus_data_o<=reg_logits[i_bus_address[10:2]];
                    end
                    else if(i_bus_address>=16'hf000 && i_bus_address<16'hf800) begin
						reg_bus_data_o<=reg_results[i_bus_address[10:2]];
					end
					else begin
						reg_bus_data_o<=0;
					end
				end
			endcase
		end
		if(flag_bus_write) begin
             
            if(!reg_buffer_lock && !flag_running) begin
                if(i_bus_address==16'h0094 && i_bus_data[5:0]==0) o_gray_base<=i_bus_data;
                if(i_bus_address==16'h0098 && i_bus_data[5:0]==0) o_preview_base<=i_bus_data;
                if(i_bus_address==16'h00a0 && i_bus_data==1 && o_gray_base!=0 && o_preview_base!=0)
                    reg_buffer_lock<=1;
            end
            if(i_bus_address==16'h00a4 && reg_buffer_lock) reg_preview_run<=i_bus_data[0];
            if(i_bus_address==16'h0078) begin
                flag_capture_start<=i_bus_data==1;
                flag_capture_abort<=i_bus_data==2;
            end
            if(i_bus_address==16'h0004 && i_bus_data==8) begin
				flag_abort<=1;
			end
			else if(!flag_running) begin
				if(i_bus_address==16'h0030) begin
                    reg_angle_index<=i_bus_data[3:0]; flag_manual_angle<=i_bus_data[8];
                end
				case(i_bus_address)
					16'h0004: begin
						case(i_bus_data)
							1: if(!flag_error) begin
								flag_start<=1;
							end
							2: begin
								flag_model<=0;
								flag_load_error<=0;
								cnt_weights<=0;
								cnt_biases<=0;
								cnt_shifts<=0;
							end
							4: begin
								flag_model<=cnt_weights==MODEL_WEIGHT_COUNT && cnt_biases==MODEL_BIAS_COUNT && cnt_shifts==MODEL_SHIFT_COUNT && !flag_load_error;
								if(cnt_weights!=MODEL_WEIGHT_COUNT || cnt_biases!=MODEL_BIAS_COUNT || cnt_shifts!=MODEL_SHIFT_COUNT) begin
									flag_load_error<=1;
								end
							end
                            16: flag_clear_results<=1;
							default: begin
							end
						endcase
					end
					16'h0018: begin
						reg_threshold<=i_bus_data[7:0];
						reg_bright<=i_bus_data[8];
					end
					16'h0080: flag_auto_enable<=i_bus_data[0];
                    16'h0074: begin flag_external_frame<=i_bus_data[0];reg_frame_bank<=i_bus_data[1];end
					16'h001c: reg_min_area<=i_bus_data[20:0]==0 ? 21'd1 : i_bus_data[20:0];
					default: begin
						reg_config_data<=i_bus_data;
						if(i_bus_address==MODEL_WEIGHT_PORT) begin
							flag_model<=0;
							if(cnt_weights<MODEL_WEIGHT_COUNT) begin
								flag_config_write<=1;
								reg_config_kind<=0;
								reg_config_address<=cnt_weights;
								cnt_weights<=cnt_weights+1'b1;
							end
							else begin
								flag_load_error<=1;
							end
						end
						else if(i_bus_address>=MODEL_BIAS_BASE && i_bus_address<(MODEL_BIAS_BASE+MODEL_BIAS_COUNT*4)) begin
							flag_model<=0;
							if(((i_bus_address-MODEL_BIAS_BASE)>>2)==cnt_biases) begin
								flag_config_write<=1;
								reg_config_kind<=1;
								reg_config_address<={9'd0,cnt_biases};
								cnt_biases<=cnt_biases+1'b1;
							end
							else begin
								flag_load_error<=1;
							end
						end
						else if(i_bus_address>=MODEL_SHIFT_BASE && i_bus_address<(MODEL_SHIFT_BASE+MODEL_SHIFT_COUNT*4)) begin
							flag_model<=0;
							if(((i_bus_address-MODEL_SHIFT_BASE)>>2)==cnt_shifts && i_bus_data<=31) begin
								flag_config_write<=1;
								reg_config_kind<=2;
								reg_config_address<={16'd0,cnt_shifts};
								cnt_shifts<=cnt_shifts+1'b1;
							end
							else begin
								flag_load_error<=1;
							end
						end
					end
				endcase
			end
		end
	end
end
always @(posedge i_clk) begin
	if(!flag_reset) begin
		state_current<=ST_IDLE;
	end
	else begin
		state_current<=state_next;
	end
end
always @(*) begin
	state_next=state_current;
	case(state_current)
		ST_IDLE: if(flag_start) begin
			state_next=ST_CAPTURE_START;
		end
		ST_CAPTURE_START: state_next=ST_CAPTURE_ARM;
		ST_CAPTURE_ARM: if(flag_external_frame) begin
            state_next=flag_auto_enable?ST_THRESHOLD_START:ST_LABEL_START;
        end else if(!flag_frame_done) begin
			state_next=ST_CAPTURE_WAIT;
		end
		ST_CAPTURE_WAIT: if(flag_frame_done) begin
			if(flag_frame_error) begin
				state_next=ST_DONE;
			end
			else begin
				state_next=flag_auto_enable?ST_THRESHOLD_START:ST_LABEL_START;
			end
		end
		ST_THRESHOLD_START: state_next=ST_THRESHOLD_WAIT;
        ST_THRESHOLD_WAIT: if(wire_threshold_done) begin
            if(wire_threshold_error) state_next=ST_DONE;
            else state_next=ST_LABEL_START;
        end
        ST_LABEL_START: state_next=ST_LABEL_WAIT;
		ST_LABEL_WAIT: begin
			if(flag_label_done) begin
				state_next=ST_DONE;
			end
			else if(flag_box_valid) begin
				if(flag_model) begin
					state_next=ST_GEOMETRY;
				end
				else begin
					state_next=ST_GEOMETRY;
				end
			end
		end
		ST_GEOMETRY: state_next=ST_SKIP;
        ST_SKIP: if(flag_reject || cnt_objects>=C_MAX_OBJECTS) state_next=ST_LABEL_WAIT;
                 else if(flag_model) state_next=ST_ORIENT_START;
                 else state_next=ST_RESULT_PREP;
        ST_ORIENT_START: state_next=ST_ORIENT_WAIT;
        ST_ORIENT_WAIT: if(flag_orient_done) state_next=ST_TRACK_START;
        ST_TRACK_START: state_next=ST_TRACK_WAIT;
        ST_TRACK_WAIT: if(flag_temporal_done) state_next=wire_temporal_angle==reg_object_angle?ST_ROI_START:ST_REORIENT_START;
        ST_REORIENT_START: state_next=ST_REORIENT_WAIT;
        ST_REORIENT_WAIT: if(flag_orient_done) state_next=ST_ROI_START;
        ST_FILTER_START: state_next=ST_FILTER_WAIT;
        ST_FILTER_WAIT: if(flag_temporal_done) state_next=ST_RESULT_PREP;
        ST_ROI_START: state_next=ST_ROI_WAIT;
		ST_ROI_WAIT: if(flag_roi_done) begin
			state_next=ST_CNN_START;
		end
		ST_CNN_START: state_next=ST_CNN_WAIT;
		ST_CNN_WAIT: if(flag_cnn_done) begin
			state_next=ST_FILTER_START;
		end
        ST_RESULT_PREP: state_next=ST_RESULT;
        ST_RESULT: begin
            if(cnt_result_word==41) state_next=ST_ACCEPT;
            else state_next=ST_RESULT_PREP;
        end
		ST_ACCEPT: state_next=ST_LABEL_WAIT;
		ST_DONE: state_next=ST_IDLE;
		default: state_next=ST_IDLE;
	endcase
	if(flag_running && (cnt_cycles>=C_TIMEOUT || i_frame_error)) begin
		state_next=ST_DONE;
	end
end
always @(posedge i_clk) begin
	if(!flag_reset) begin
		flag_done<=0;
		flag_error<=0;
		flag_label_overflow<=0;
		flag_object_overflow<=0;
		flag_capture_error<=0;
        reg_frame_threshold<=40;reg_frame_p50<=0;reg_frame_p90<=0;
        reg_threshold_samples<=0;flag_threshold_done<=0;flag_threshold_error<=0;
		cnt_frame<=0;
		cnt_cycles<=0;
		reg_last_cycles<=0;
		cnt_objects<=0;cnt_total_objects<=0;
		cnt_result_word<=0;
        reg_result_write_address<=0;reg_result_write_data<=0;
        reg_logit_write_address<=0;flag_logit_write<=0;
		reg_xmin<=0;
		reg_ymin<=0;
		reg_xmax<=0;
		reg_ymax<=0;
		reg_area<=0;
		reg_class<=32'hffffffff;
        reg_short<=0;reg_long<=0;reg_box_area<=0;
        reg_object_angle<=0;reg_raw_angle<=0;
        reg_local_xmin<=0; reg_local_ymin<=0; reg_local_xmax<=0; reg_local_ymax<=0;
	end
	else begin
		if(flag_running) begin
			cnt_cycles<=cnt_cycles+1'b1;
		end
		if(flag_running && (cnt_cycles>=C_TIMEOUT || i_frame_error)) begin
			flag_error<=1;
		end
		case(state_current)
			ST_IDLE: if(flag_start) begin
				flag_done<=0;
				flag_error<=0;
				flag_label_overflow<=0;
				flag_object_overflow<=0;
				flag_capture_error<=0;
				cnt_objects<=0;cnt_total_objects<=0;
				cnt_cycles<=0;
				cnt_frame<=cnt_frame+1'b1;
                reg_frame_threshold<=reg_threshold;reg_frame_p50<=0;reg_frame_p90<=0;
                reg_threshold_samples<=0;flag_threshold_done<=0;flag_threshold_error<=0;
			end
			ST_THRESHOLD_WAIT: if(wire_threshold_done) begin
                reg_frame_threshold<=wire_threshold;reg_frame_p50<=wire_threshold_p50;reg_frame_p90<=wire_threshold_p90;
                reg_threshold_samples<=wire_threshold_samples;flag_threshold_done<=1;
                flag_threshold_error<=wire_threshold_error;
                if(wire_threshold_error)flag_error<=1;
            end
            ST_CAPTURE_WAIT: if(flag_frame_done && flag_frame_error) begin
				flag_capture_error<=1;
				flag_error<=1;
			end
			ST_LABEL_WAIT: begin
				cnt_result_word<=0;
				reg_class<=32'hffffffff;
				if(flag_label_done && wire_label_overflow) begin
					flag_label_overflow<=1;
					flag_error<=1;
				end
				if(flag_box_valid) begin
					reg_xmin<=wire_xmin;
					reg_ymin<=wire_ymin;
					reg_xmax<=wire_xmax;
					reg_ymax<=wire_ymax;
					reg_area<=wire_area;
                    reg_object_angle<=0;reg_raw_angle<=0;
                    reg_local_xmin<=0; reg_local_ymin<=0; reg_local_xmax<=0; reg_local_ymax<=0;

				end
			end
			ST_GEOMETRY: begin
                reg_short<=dec_box_width<dec_box_height ? dec_box_width : dec_box_height;
                reg_long<=dec_box_width>dec_box_height ? dec_box_width : dec_box_height;
                reg_box_area<=dec_box_width*dec_box_height;
            end
            ST_SKIP: if(!flag_reject) begin
                if(cnt_total_objects<1023) cnt_total_objects<=cnt_total_objects+1'b1;
                if(cnt_objects>=C_MAX_OBJECTS) flag_object_overflow<=1;
            end
            ST_ORIENT_WAIT,ST_REORIENT_WAIT: if(flag_orient_done) begin
                reg_object_angle<=wire_angle_index;
                if(state_current==ST_ORIENT_WAIT)reg_raw_angle<=wire_angle_index;
                reg_local_xmin<=wire_local_xmin; reg_local_ymin<=wire_local_ymin;
                reg_local_xmax<=wire_local_xmax; reg_local_ymax<=wire_local_ymax;
            end
            ST_CNN_WAIT: if(flag_cnn_done) begin
                reg_class<={14'd0,wire_class[4],wire_class[4],4'd0,reg_object_angle,wire_class[3:0],wire_class[3:0]};
			end
            ST_FILTER_WAIT: if(flag_temporal_done) begin
                reg_class<={14'd0,wire_class[4],wire_temporal_class[4],wire_temporal_flags,reg_object_angle,wire_class[3:0],wire_temporal_class[3:0]};
            end
            ST_RESULT_PREP: begin
                reg_result_write_address<=dec_result_address;
                flag_logit_write<=cnt_result_word>=24;
                reg_logit_write_address<={cnt_objects[3:0],dec_logit_index};
                reg_result_write_data<=dec_result_data;
            end
            ST_RESULT: begin
                if(flag_logit_write)reg_logits[reg_logit_write_address]<=reg_result_write_data;
                else reg_results[reg_result_write_address]<=reg_result_write_data;
				cnt_result_word<=cnt_result_word+1'b1;
			end
			ST_ACCEPT: cnt_objects<=cnt_objects+1'b1;
			ST_DONE: begin
				flag_done<=1;
				reg_last_cycles<=cnt_cycles;
			end
			default: begin
			end
		endcase
         
         
        if(flag_clear_results) begin
            flag_done<=1;flag_error<=0;flag_label_overflow<=0;
            flag_object_overflow<=0;flag_capture_error<=0;
            cnt_objects<=0;cnt_total_objects<=0;
        end

	end
end
 
 
always @(posedge i_clk) begin
    if(!flag_reset || (state_current==ST_IDLE && flag_start)) begin
        cnt_capture_cycles<=0;cnt_label_cycles<=0;cnt_orient_cycles<=0;
        cnt_roi_cycles<=0;cnt_cnn_cycles<=0;cnt_other_cycles<=0;cnt_ddr_wait_cycles<=0;
    end else if(flag_running) begin
        case(state_current)
        ST_CAPTURE_START,ST_CAPTURE_ARM,ST_CAPTURE_WAIT:cnt_capture_cycles<=cnt_capture_cycles+1'b1;
        ST_LABEL_START,ST_LABEL_WAIT:cnt_label_cycles<=cnt_label_cycles+1'b1;
        ST_ORIENT_START,ST_ORIENT_WAIT,ST_REORIENT_START,ST_REORIENT_WAIT:cnt_orient_cycles<=cnt_orient_cycles+1'b1;
        ST_ROI_START,ST_ROI_WAIT:cnt_roi_cycles<=cnt_roi_cycles+1'b1;
        ST_CNN_START,ST_CNN_WAIT:cnt_cnn_cycles<=cnt_cnn_cycles+1'b1;
        default:cnt_other_cycles<=cnt_other_cycles+1'b1;
        endcase
        if(o_frame_enable && !i_frame_valid)cnt_ddr_wait_cycles<=cnt_ddr_wait_cycles+1'b1;
    end
end
endmodule
