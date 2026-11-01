`timescale 1ns / 1ps
// English: Thirty-two output channels share each tap; weights are channel-banked.
// 中文：64×64 输入与 32/96/256 通道，深层 256 + 中层 96 + 几何 3 个特征。
// 中文：三层 dilation=2、padding=2；保持 INT32 量化，GAP 在写回时计算。
module cnn_classifier (
	input i_clk,
	input i_rstn,
	input i_start,
	input i_input_write,
	input [11:0] i_input_address,
	input [7:0] i_input_data,
	input [6:0] i_short_side,
	input [6:0] i_long_side,
	input [6:0] i_area,
	input i_config_write,
	input [1:0] i_config_kind,
	input [17:0] i_config_address,
	input [31:0] i_config_data,
	input [4:0] i_score_index,
	output [31:0] o_score,
	output [4:0] o_class,
	output o_done
);
localparam ST_IDLE=0, ST_SETUP=1, ST_BIAS=2, ST_TAP=3,
ST_READ=4, ST_MULTIPLY=5, ST_ACCUMULATE=6, ST_TAP_NEXT=7,
ST_QUANTIZE=8, ST_STORE=9, ST_PIXEL_NEXT=10,
ST_POOL=11, ST_POOL_WAIT=12, ST_POOL_COMPARE=13, ST_POOL_NEXT=14,
ST_GAP=15, ST_GAP_WAIT=16, ST_GAP_SUM=17, ST_GAP_NEXT=18,
ST_FC_BIAS=19, ST_FC_READ=20, ST_FC_WAIT=21, ST_FC_MULT=22,
ST_FC_ADD=23, ST_FC_NEXT=24, ST_FC_STORE=25, ST_DONE=26,ST_POOL_WRITE=27;
reg [4:0] state_current,state_next;
// 32768-byte feature RAM stores host ROI or the latest pooled tensor.
wire [7:0] wire_conv_read [0:31];
wire signed [7:0] wire_weight_read [0:31];
wire signed [31:0] wire_fc_bias [0:31];
wire [7:0] wire_fc_feature [0:31];
wire [7:0] wire_pool_maximum [0:31];
reg [4:0] reg_shift [0:2];
reg [7:0] reg_geometry [0:2];
// Weight upload is strictly sequential, checked by the enclosing CSR endpoint.
reg [4:0] reg_load_bank;
reg [12:0] reg_load_row,reg_load_group_base;
reg [9:0] cnt_load_tap,reg_load_stride;
wire [4:0] dec_load_bank=i_config_address==0 ? 5'd0 : reg_load_bank;
wire [12:0] dec_load_row=i_config_address==0 ? 13'd0 : reg_load_row;
reg [4:0] dec_bias_bank;
reg [3:0] dec_bias_row;
always @(*) begin
    dec_bias_bank=i_config_address[4:0];
    if(i_config_address<32)dec_bias_row=0;
    else if(i_config_address<128)dec_bias_row=1+((i_config_address-32)>>5);
    else if(i_config_address<384)dec_bias_row=4+((i_config_address-128)>>5);
    else begin dec_bias_bank=i_config_address-384;dec_bias_row=12;end
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_load_bank<=0;reg_load_row<=0;reg_load_group_base<=0;
        cnt_load_tap<=0;reg_load_stride<=9;
    end else if(i_config_write && i_config_kind==0) begin
        if(i_config_address==0) begin
            reg_load_bank<=0;reg_load_row<=1;reg_load_group_base<=0;
            cnt_load_tap<=1;reg_load_stride<=9;
        end else if(i_config_address==287) begin
            reg_load_bank<=0;reg_load_row<=9;reg_load_group_base<=9;
            cnt_load_tap<=0;reg_load_stride<=288;
        end else if(i_config_address==27935) begin
            reg_load_bank<=0;reg_load_row<=873;reg_load_group_base<=873;
            cnt_load_tap<=0;reg_load_stride<=864;
        end else if(i_config_address==249119) begin
            reg_load_bank<=0;reg_load_row<=7785;reg_load_group_base<=7785;
            cnt_load_tap<=0;reg_load_stride<=355;
        end else if(cnt_load_tap==reg_load_stride-1) begin
            cnt_load_tap<=0;reg_load_bank<=reg_load_bank+1'b1;
            if(reg_load_bank==31) begin
                reg_load_group_base<=reg_load_group_base+reg_load_stride;
                reg_load_row<=reg_load_group_base+reg_load_stride;
            end else reg_load_row<=reg_load_group_base;
        end else begin
            cnt_load_tap<=cnt_load_tap+1'b1;reg_load_row<=reg_load_row+1'b1;
        end
    end
end
reg signed [31:0] reg_scores [0:17];
reg [14:0] reg_feature_address;
reg [11:0] reg_conv_address;
reg [12:0] reg_weight_address;
wire [7:0] reg_feature_read;
wire signed [7:0] reg_weight_read;
(* use_dsp="yes" *) reg signed [17:0] reg_product;
reg [7:0] reg_fc_feature;
reg signed [7:0] reg_fc_weight;
reg signed [31:0] reg_accumulator;

wire [7:0] wire_activation [0:31];
reg flag_padding;
// 中文：valid[0]对应已寄存地址，valid[1]对应RAM读数，valid[2]对应乘积。
// English: Valid and final-tap tags follow the registered memory pipeline.
reg [2:0] reg_tap_valid,reg_tap_last;
reg flag_padding_ram;
reg [12:0] reg_tap_weight_address;
wire flag_last_tap;

reg [1:0] cnt_layer,cnt_kernel_x,cnt_kernel_y;
reg [6:0] cnt_channel;
reg [7:0] cnt_output;
reg [5:0] cnt_x,cnt_y;
reg [6:0] reg_width,reg_in_channels;
reg [8:0] reg_out_channels;
reg [3:0] reg_spatial_shift;
reg [2:0] reg_width_shift;
reg [12:0] reg_output_base;
reg [9:0] reg_kernel_stride;
reg [11:0] cnt_destination;
reg [3:0] reg_bias_base;
reg [2:0] cnt_pool;
reg [14:0] cnt_pool_destination;
reg [4:0] cnt_pool_lane;
reg [14:0] reg_pool_plane,reg_pool_group_base,reg_pool_spatial_offset;
reg [8:0] cnt_fc;
reg [4:0] cnt_class,reg_class_o;
assign reg_weight_read=wire_weight_read[cnt_class];
reg signed [31:0] reg_best;
reg signed [7:0] reg_source_x,reg_source_y;
wire [14:0] dec_plane = {8'd0,cnt_channel} << reg_spatial_shift;
wire [14:0] dec_row = {7'd0,reg_source_y[7:0]} << reg_width_shift;
// Merge mutually exclusive host/pool writes BEFORE the RAM port. Two indexed
// writes made Vivado infer an unsupported multi-write RAM in the baseline.
// 先选择写入来源，再使用单一写口，使特征缓存可映射到真正的BRAM。
wire flag_pool_write=state_current==ST_POOL_WRITE;
wire flag_feature_write=i_input_write || flag_pool_write;
wire [14:0] dec_feature_write_address=i_input_write?{3'b0,i_input_address}:cnt_pool_destination;
wire [7:0] dec_feature_write_data=i_input_write?i_input_data:wire_pool_maximum[cnt_pool_lane];
assign flag_last_tap=cnt_kernel_x==2 && cnt_kernel_y==2 && cnt_channel==reg_in_channels-1;
assign o_class=reg_class_o;
assign o_done=state_current==ST_DONE;
assign o_score=i_score_index<18 ? reg_scores[i_score_index] : 32'd0;
// Explicit simple dual-port RAM prevents accidental distributed-memory inference.
xpm_memory_sdpram #(
    .ADDR_WIDTH_A(15),.ADDR_WIDTH_B(15),.AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(8),.CASCADE_HEIGHT(0),.CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),.MEMORY_INIT_FILE("none"),.MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),.MEMORY_PRIMITIVE("block"),.MEMORY_SIZE(262144),
    .MESSAGE_CONTROL(0),.READ_DATA_WIDTH_B(8),.READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0"),.RST_MODE_A("SYNC"),.RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(1),.USE_EMBEDDED_CONSTRAINT(0),.USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),.WRITE_DATA_WIDTH_A(8),.WRITE_MODE_B("read_first")
) feature_memory_Inst (
    .clka(i_clk),.clkb(i_clk),.ena(flag_feature_write),.enb(1'b1),
    .wea(flag_feature_write),.addra(dec_feature_write_address),.dina(dec_feature_write_data),
    .addrb(reg_feature_address),.doutb(reg_feature_read),.rstb(!i_rstn),.regceb(1'b1),
    .sleep(1'b0),.injectdbiterra(1'b0),.injectsbiterra(1'b0),.dbiterrb(),.sbiterrb());
always @(posedge i_clk) begin
    if(i_config_write && i_config_kind==2 && i_config_address<3)
        reg_shift[i_config_address[1:0]]<=i_config_data[4:0];
end
always @(posedge i_clk) begin
	if(!i_rstn) begin
		state_current<=ST_IDLE;
	end
	else begin
		state_current<=state_next;
	end
end

genvar lane;
generate for(lane=0;lane<32;lane=lane+1) begin: gen_channel
    // One output-channel bank stores only the weights used by this MAC lane.
    (* ram_style="block" *) reg signed [7:0] reg_weights [0:8191];
    (* ram_style="block" *) reg [7:0] reg_convolved [0:4095];
    reg signed [7:0] reg_weight_read_lane;
    (* ram_style="distributed" *) reg signed [31:0] reg_bias [0:15];
    // A constant FC read alongside the dynamic convolution read prevents RAM
    // inference in Vivado. Keep the logical upload row 12, store it separately.
    // 中文：偏置地址和周期不变；卷积偏置单读口使用 LUTRAM，FC 偏置用寄存器。
    reg signed [31:0] reg_fc_bias_lane;
    reg [16:0] reg_gap_sum;
    reg [7:0] reg_features [0:10];
    assign wire_fc_bias[lane]=reg_fc_bias_lane;
    assign wire_fc_feature[lane]=cnt_fc<256 ? reg_features[cnt_fc[7:5]] : reg_features[8+cnt_fc[6:5]];
    reg [7:0] reg_conv_read_lane;
    (* use_dsp="yes" *) reg signed [17:0] reg_product_lane;
    reg signed [31:0] reg_accumulator_lane,reg_quantized_lane;
    reg [7:0] reg_activation_lane;
    reg [7:0] reg_pool_maximum_lane;
    wire [16:0] dec_gap_sum=(cnt_x==0 && cnt_y==0) ? {9'd0,reg_activation_lane} : reg_gap_sum+reg_activation_lane;
    wire signed [31:0] wire_sum=reg_accumulator_lane+reg_product_lane;
    assign wire_activation[lane]=reg_activation_lane;
    assign wire_pool_maximum[lane]=reg_pool_maximum_lane;
    assign wire_conv_read[lane]=reg_conv_read_lane;
    assign wire_weight_read[lane]=reg_weight_read_lane;
    always @(posedge i_clk) begin
        // reg_weight_address is already registered; lane offsets are layer constants.
        reg_weight_read_lane<=reg_weights[reg_weight_address];
        reg_conv_read_lane<=reg_convolved[reg_conv_address];
        if(i_config_write && i_config_kind==0 && dec_load_bank==lane)
            reg_weights[dec_load_row]<=i_config_data[7:0];
        if(i_config_write && i_config_kind==1 && i_config_address<402 && dec_bias_bank==lane) begin
            if(dec_bias_row==12) reg_fc_bias_lane<=i_config_data;
            else reg_bias[dec_bias_row]<=i_config_data;
        end
        if(state_current==ST_STORE)
            reg_convolved[cnt_destination]<=reg_activation_lane;
    end
    always @(posedge i_clk) begin
        if(!i_rstn) begin
            reg_product_lane<=0;reg_accumulator_lane<=0;
            reg_quantized_lane<=0;reg_activation_lane<=0;reg_gap_sum<=0;reg_pool_maximum_lane<=0;
        end else begin
            if(state_current==ST_BIAS)
                reg_accumulator_lane<=reg_bias[reg_bias_base+cnt_output[7:5]];
            if(reg_tap_valid[1]) begin
                if(flag_padding_ram) reg_product_lane<=0;
                else reg_product_lane<=$signed({1'b0,reg_feature_read})*reg_weight_read_lane;
            end
            if(reg_tap_valid[2]) begin
                reg_accumulator_lane<=wire_sum;
                if(reg_tap_last[2])reg_quantized_lane<=wire_sum>>>reg_shift[cnt_layer];
            end
            if(state_current==ST_STORE && cnt_layer!=0) begin
                reg_gap_sum<=dec_gap_sum;
                if(cnt_x==reg_width-1 && cnt_y==reg_width-1) begin
                    if(cnt_layer==1)reg_features[8+cnt_output[6:5]]<=dec_gap_sum[16:10];
                    else reg_features[cnt_output[7:5]]<=dec_gap_sum[14:8];
                end
            end
            // Four synchronous reads are shared by all thirty-two channel banks.
            if(state_current==ST_POOL_COMPARE && (cnt_pool==0 || reg_conv_read_lane>reg_pool_maximum_lane))
                reg_pool_maximum_lane<=reg_conv_read_lane;
            if(state_current==ST_QUANTIZE) begin
                if(reg_quantized_lane<0)reg_activation_lane<=0;
                else if(reg_quantized_lane>127)reg_activation_lane<=127;
                else reg_activation_lane<=reg_quantized_lane[7:0];
            end
        end
    end
end endgenerate

always @(*) begin
	state_next=state_current;
	case(state_current)
		ST_IDLE: if(i_start) begin
			state_next=ST_SETUP;
		end
		ST_SETUP: state_next=ST_BIAS;
		ST_BIAS: state_next=ST_TAP;
        // Issue all taps consecutively, then drain the final three stages.
        ST_TAP: if(flag_last_tap) state_next=ST_READ;
        ST_READ: if(reg_tap_valid[2] && reg_tap_last[2]) state_next=ST_QUANTIZE;
		ST_QUANTIZE: state_next=ST_STORE;
		ST_STORE: state_next=ST_PIXEL_NEXT;
		ST_PIXEL_NEXT: begin
			if(cnt_x==reg_width-1 && cnt_y==reg_width-1 && cnt_output==reg_out_channels-32) begin
				if(cnt_layer==2) begin
					state_next=ST_FC_BIAS;
				end
				else begin
					state_next=ST_POOL;
				end
			end
			else begin
				state_next=ST_BIAS;
			end
		end
		ST_POOL: state_next=ST_POOL_WAIT;
		ST_POOL_WAIT: state_next=ST_POOL_COMPARE;
		ST_POOL_COMPARE: state_next=ST_POOL_NEXT;
		ST_POOL_NEXT: if(cnt_pool==3)state_next=ST_POOL_WRITE;else state_next=ST_POOL;
        ST_POOL_WRITE: if(cnt_pool_lane==31)begin
			if(cnt_x==(reg_width>>1)-1 && cnt_y==(reg_width>>1)-1 && cnt_output==reg_out_channels-32) begin
				state_next=ST_SETUP;
			end
			else begin
				state_next=ST_POOL;
			end
		end
		ST_FC_BIAS: state_next=ST_FC_READ;
		ST_FC_READ: state_next=ST_FC_WAIT;
		ST_FC_WAIT: state_next=ST_FC_MULT;
		ST_FC_MULT: state_next=ST_FC_ADD;
		ST_FC_ADD: state_next=ST_FC_NEXT;
		ST_FC_NEXT: begin
			if(cnt_fc==354) begin
				state_next=ST_FC_STORE;
			end
			else begin
				state_next=ST_FC_READ;
			end
		end
		ST_FC_STORE: begin
			if(cnt_class==17) begin
				state_next=ST_DONE;
			end
			else begin
				state_next=ST_FC_BIAS;
			end
		end
		ST_DONE: state_next=ST_IDLE;
		default: state_next=ST_IDLE;
	endcase
end
// 核坐标单独寄存，消除取数地址与上一拍乘法数据之间的歧义。
always @(*) begin
	reg_source_x=$signed({2'b0,cnt_x})+$signed({5'b0,cnt_kernel_x,1'b0})-2;
	reg_source_y=$signed({2'b0,cnt_y})+$signed({5'b0,cnt_kernel_y,1'b0})-2;
end
always @(posedge i_clk) begin
	if(!i_rstn) begin
		cnt_layer<=0;
		cnt_kernel_x<=0;
		cnt_kernel_y<=0;
		cnt_channel<=0;
		cnt_output<=0;
		cnt_x<=0;
		cnt_y<=0;
		cnt_destination<=0;
		reg_width<=64;
		reg_in_channels<=1;
		reg_out_channels<=32;
		reg_width_shift<=6;
		reg_spatial_shift<=12;
		reg_output_base<=0;
		reg_bias_base<=0;
		reg_feature_address<=0;
		reg_conv_address<=0;
		reg_weight_address<=0;
		reg_product<=0;
		reg_fc_feature<=0;
        reg_fc_weight<=0;
		reg_accumulator<=0;
		reg_kernel_stride<=9;
        flag_padding<=0;
        flag_padding_ram<=0;
        reg_tap_valid<=0;
        reg_tap_last<=0;
        reg_tap_weight_address<=0;
		cnt_pool<=0;
		cnt_pool_destination<=0;
        cnt_pool_lane<=0;reg_pool_plane<=1024;reg_pool_group_base<=0;reg_pool_spatial_offset<=0;
		cnt_fc<=0;
		cnt_class<=0;
		reg_class_o<=0;
		reg_best<=0;
	end
    else begin
        // Tags advance during drain as well as issue; idle inserts bubbles.
        reg_tap_valid<={reg_tap_valid[1:0],state_current==ST_TAP};
        reg_tap_last<={reg_tap_last[1:0],state_current==ST_TAP && flag_last_tap};
        flag_padding_ram<=flag_padding;
        case(state_current)
			ST_IDLE: if(i_start) begin
				cnt_layer<=0;cnt_class<=0;reg_class_o<=0;
				reg_geometry[0]<={1'b0,i_short_side};
				reg_geometry[1]<={1'b0,i_long_side};
				reg_geometry[2]<={1'b0,i_area};
			end
			ST_SETUP: begin
				cnt_x<=0;
				cnt_y<=0;
				cnt_output<=0;
				cnt_destination<=0;
                reg_pool_group_base<=0;reg_pool_spatial_offset<=0;cnt_pool_lane<=0;
                case(cnt_layer)
                    0: begin
                        reg_width<=64;reg_in_channels<=1;reg_out_channels<=32;
                        reg_output_base<=0;reg_bias_base<=0;
                        reg_width_shift<=6;reg_spatial_shift<=12;reg_kernel_stride<=9;reg_pool_plane<=1024;
                    end
                    1: begin
                        reg_width<=32;reg_in_channels<=32;reg_out_channels<=96;
                        reg_output_base<=9;reg_bias_base<=1;
                        reg_width_shift<=5;reg_spatial_shift<=10;reg_kernel_stride<=288;reg_pool_plane<=256;
                    end
                    default: begin
                        reg_width<=16;reg_in_channels<=96;reg_out_channels<=256;
                        reg_output_base<=873;reg_bias_base<=4;
                        reg_width_shift<=4;reg_spatial_shift<=8;reg_kernel_stride<=864;
                    end
				endcase
			end
			ST_BIAS: begin
				cnt_channel<=0;
				cnt_kernel_x<=0;
				cnt_kernel_y<=0;
				reg_weight_address<=reg_output_base;
                reg_tap_weight_address<=reg_output_base;
			end
            ST_TAP: begin
                flag_padding<=reg_source_x<0 || reg_source_y<0 || reg_source_x>=reg_width || reg_source_y>=reg_width;
                reg_feature_address<=dec_plane+dec_row+reg_source_x[7:0];
                reg_weight_address<=reg_tap_weight_address;
                reg_tap_weight_address<=reg_tap_weight_address+1'b1;
                if(cnt_kernel_x==2) begin
                    cnt_kernel_x<=0;
                    if(cnt_kernel_y==2) begin
                        cnt_kernel_y<=0;
                        cnt_channel<=cnt_channel+1'b1;
                    end else cnt_kernel_y<=cnt_kernel_y+1'b1;
                end else cnt_kernel_x<=cnt_kernel_x+1'b1;
            end
			ST_PIXEL_NEXT: begin
				cnt_destination<=cnt_destination+1'b1;
				if(cnt_x==reg_width-1) begin
					cnt_x<=0;
					if(cnt_y==reg_width-1) begin
						cnt_y<=0;
						cnt_output<=cnt_output+32;
						reg_output_base<=reg_output_base+reg_kernel_stride;
					end
					else begin
						cnt_y<=cnt_y+1'b1;
					end
				end
				else begin
					cnt_x<=cnt_x+1'b1;
				end
				if(cnt_x==reg_width-1 && cnt_y==reg_width-1 && cnt_output==reg_out_channels-32) begin
					cnt_x<=0;
					cnt_y<=0;
					cnt_output<=0;
					cnt_pool<=0;
					cnt_pool_destination<=0;
				end
			end
			ST_POOL: begin
                reg_conv_address<=({9'd0,cnt_output[7:5]}<<reg_spatial_shift)
                + (({7'd0,cnt_y,1'b0}+cnt_pool[1])<<reg_width_shift)
                + {7'd0,cnt_x,1'b0}+cnt_pool[0];
            end
			ST_POOL_NEXT: begin
				if(cnt_pool==3) begin
					cnt_pool<=0;
                    cnt_pool_lane<=0;
                    cnt_pool_destination<=reg_pool_group_base+reg_pool_spatial_offset;
                end else cnt_pool<=cnt_pool+1'b1;
            end
            // Scatter one maximum per cycle into the single CHW feature write port.
            ST_POOL_WRITE: begin
                if(cnt_pool_lane==31)begin
                    cnt_pool_lane<=0;
                    reg_pool_spatial_offset<=reg_pool_spatial_offset+1'b1;
					if(cnt_x==(reg_width>>1)-1) begin
						cnt_x<=0;
						if(cnt_y==(reg_width>>1)-1) begin
							cnt_y<=0;
							cnt_output<=cnt_output+32;
                            reg_pool_spatial_offset<=0;
                            reg_pool_group_base<=reg_pool_group_base+(reg_pool_plane<<5);
							if(cnt_output==reg_out_channels-32) begin
								cnt_layer<=cnt_layer+1'b1;
							end
						end
						else begin
							cnt_y<=cnt_y+1'b1;
						end
					end
					else begin
						cnt_x<=cnt_x+1'b1;
					end
				end
				else begin
                    cnt_pool_lane<=cnt_pool_lane+1'b1;
                    cnt_pool_destination<=cnt_pool_destination+reg_pool_plane;
                end
			end
			ST_FC_BIAS: begin
				reg_accumulator<=wire_fc_bias[cnt_class];
                reg_weight_address<=7785;
				cnt_fc<=0;
			end
			// Register the 355-way feature selection before the multiply stage.
			// 特征选择与乘法分拍，切断原来全连接层的长组合路径。
			ST_FC_WAIT: begin
                reg_fc_feature<=cnt_fc<352 ? wire_fc_feature[cnt_fc[4:0]] : reg_geometry[cnt_fc-352];
                // The BRAM address has already passed through FC_READ.
                // Register the class-bank mux before multiplication, in the
                // existing wait cycle: no additional inference latency.
                reg_fc_weight<=reg_weight_read;
            end
			ST_FC_MULT: reg_product<=$signed({1'b0,reg_fc_feature})*reg_fc_weight;
			ST_FC_ADD: reg_accumulator<=reg_accumulator+reg_product;
			ST_FC_NEXT: begin
				cnt_fc<=cnt_fc+1'b1;
				reg_weight_address<=reg_weight_address+1'b1;
			end
			ST_FC_STORE: begin
				reg_scores[cnt_class]<=reg_accumulator;
				if(cnt_class==0 || reg_accumulator>reg_best) begin
					reg_best<=reg_accumulator;
					reg_class_o<=cnt_class;
				end
				cnt_class<=cnt_class+1'b1;
			end
			default: begin
			end
		endcase


	end
end
endmodule
