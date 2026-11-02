`timescale 1ns / 1ps
 
module component_labeler #(
	parameter C_WIDTH=1280,
	parameter C_HEIGHT=960,
	parameter C_LABELS = 1024
	) (
	input i_clk,
	input i_rstn,
	input i_start,
	input [7:0] i_threshold,
	input i_bright,
	input [20:0] i_min_area,
	output [20:0] o_pixel_address,
	input [7:0] i_pixel,
	input i_pixel_ready,
	output o_box_valid,
	input i_box_ready,
	output [10:0] o_xmin,
	output [10:0] o_ymin,
	output [10:0] o_xmax,
	output [10:0] o_ymax,
	output [20:0] o_area,
	output o_done,
    output o_overflow,
    output [10:0] o_label_count,
    output [20:0] o_foreground_count,
    output [10:0] o_overflow_x,output [10:0] o_overflow_y,
    output [20:0] o_scan_address
);
localparam ST_IDLE=0, ST_CLEAR=1, ST_PIXEL=2, ST_PIXEL_WAIT=3,
ST_SELECT=4, ST_ALLOC=5, ST_STAT_READ=6, ST_STAT_WAIT=7,
ST_STAT_WRITE=8, ST_NEIGHBOR=9, ST_ROOT_A=10, ST_ROOT_B=11,
ST_UNION=12, ST_NEXT=13, ST_MERGE_BEGIN=14, ST_MERGE_ROOT=15,
ST_CHILD_READ=16, ST_CHILD_WAIT=17, ST_CHILD_SAVE=18,
ST_PARENT_READ=19, ST_PARENT_WAIT=20, ST_PARENT_WRITE=21,
ST_MERGE_NEXT=22, ST_EMIT_READ=23, ST_EMIT_WAIT=24,
ST_EMIT_CHECK=25, ST_EMIT=26, ST_EMIT_NEXT=27, ST_DONE=28;
reg [4:0] state_current, state_next;
 
(* ram_style="distributed" *) reg [9:0] reg_line [0:C_WIDTH-1];
(* ram_style="distributed" *) reg [9:0] reg_parent [0:C_LABELS-1];
reg flag_parent_write;
reg [9:0] dec_parent_write_address,dec_parent_write_data;
reg [9:0] reg_parent_read_address;
wire [9:0] wire_parent_read;
(* ram_style="block" *) reg [64:0] reg_stats [0:C_LABELS-1];
reg [9:0] reg_stat_address;
reg [64:0] reg_stat_read;
reg [64:0] reg_stat_write;
reg flag_stat_write;
reg [10:0] cnt_x, cnt_y, cnt_clear;
reg [20:0] cnt_address;
reg [9:0] reg_left, reg_upper_left, reg_up, reg_right;
reg [9:0] reg_selected, reg_root_a, reg_root_b;
reg [2:0] cnt_neighbor;
reg [10:0] cnt_labels, cnt_merge;
reg [64:0] reg_child;
reg flag_new;
reg flag_overflow_o;
reg [10:0] reg_xmin_o,reg_ymin_o,reg_xmax_o,reg_ymax_o;
reg [20:0] reg_area_o;
reg [7:0] reg_threshold;
reg reg_bright;
reg [20:0] reg_min_area;
reg [9:0] dec_min_label;
reg [9:0] reg_min_label;
reg [9:0] dec_min_left,dec_min_right;
reg [9:0] dec_neighbor;
reg flag_foreground;
 
reg [20:0] cnt_foreground;
reg [10:0] reg_overflow_x,reg_overflow_y;
assign o_label_count=cnt_labels-11'd1;
assign o_foreground_count=cnt_foreground;
assign o_overflow_x=reg_overflow_x;
assign o_overflow_y=reg_overflow_y;
assign o_scan_address=cnt_address;
assign o_pixel_address = cnt_address;
assign wire_parent_read = reg_parent[reg_parent_read_address];
assign o_box_valid = state_current == ST_EMIT;
assign o_done = state_current == ST_DONE;
assign o_overflow = flag_overflow_o;
assign o_xmin=reg_xmin_o;
assign o_ymin=reg_ymin_o;
assign o_xmax=reg_xmax_o;
assign o_ymax=reg_ymax_o;
assign o_area=reg_area_o;
// 统计字布局：area[64:44], ymax[43:33], xmax[32:22], ymin[21:11], xmin[10:0]。
always @(posedge i_clk) begin
	reg_stat_read <= reg_stats[reg_stat_address];
	if (flag_stat_write) begin
		reg_stats[reg_stat_address] <= reg_stat_write;
	end
end
always @(*) begin
    // 两两求非零最小值，再合并；避免四个邻居串行比较。
    dec_min_left = (reg_left==0 || (reg_upper_left!=0 && reg_upper_left<reg_left)) ? reg_upper_left : reg_left;
    dec_min_right = (reg_up==0 || (reg_right!=0 && reg_right<reg_up)) ? reg_right : reg_up;
    dec_min_label = (dec_min_left==0 || (dec_min_right!=0 && dec_min_right<dec_min_left)) ? dec_min_right : dec_min_left;
	case (cnt_neighbor)
		0: dec_neighbor = reg_left;
		1: dec_neighbor = reg_upper_left;
		2: dec_neighbor = reg_up;
		default: dec_neighbor = reg_right;
	endcase
end
always @(posedge i_clk) begin
	if (!i_rstn) begin
		state_current <= ST_IDLE;
	end
	else begin
		state_current <= state_next;
	end
end
always @(*) begin
	state_next = state_current;
	case (state_current)
		ST_IDLE: if(i_start) begin
			state_next=ST_CLEAR;
		end
		ST_CLEAR: if(cnt_clear==C_WIDTH-1) begin
			state_next=ST_PIXEL;
		end
		ST_PIXEL: state_next=ST_PIXEL_WAIT;
		ST_PIXEL_WAIT: if(i_pixel_ready) state_next=ST_SELECT;
		ST_SELECT: begin
			if(!flag_foreground) begin
				state_next=ST_NEXT;
			end
			else if(reg_min_label==0) begin
				if(cnt_labels==C_LABELS) begin
					state_next=ST_DONE;
				end
				else begin
					state_next=ST_ALLOC;
				end
			end
			else begin
				state_next=ST_STAT_READ;
			end
		end
		ST_ALLOC: state_next=ST_STAT_READ;
		ST_STAT_READ: state_next=ST_STAT_WAIT;
		ST_STAT_WAIT: state_next=ST_STAT_WRITE;
		ST_STAT_WRITE: state_next=ST_NEIGHBOR;
		ST_NEIGHBOR: begin
			if(cnt_neighbor==4) begin
				state_next=ST_NEXT;
			end
			else if(dec_neighbor!=0) begin
				state_next=ST_ROOT_A;
			end
		end
		ST_ROOT_A: if(wire_parent_read==reg_root_a) begin
			state_next=ST_ROOT_B;
		end
		ST_ROOT_B: if(wire_parent_read==reg_root_b) begin
			state_next=ST_UNION;
		end
		ST_UNION: state_next=ST_NEIGHBOR;
		ST_NEXT: begin
			if(cnt_address==C_WIDTH*C_HEIGHT-1) begin
				state_next=ST_MERGE_BEGIN;
			end
			else begin
				state_next=ST_PIXEL;
			end
		end
		ST_MERGE_BEGIN: begin
			if(cnt_merge>=cnt_labels) begin
				state_next=ST_EMIT_READ;
			end
			else begin
				state_next=ST_MERGE_ROOT;
			end
		end
		ST_MERGE_ROOT: if(wire_parent_read==reg_root_b) begin
			if(reg_root_b==cnt_merge) begin
				state_next=ST_MERGE_NEXT;
			end
			else begin
				state_next=ST_CHILD_READ;
			end
		end
		ST_CHILD_READ: state_next=ST_CHILD_WAIT;
		ST_CHILD_WAIT: state_next=ST_CHILD_SAVE;
		ST_CHILD_SAVE: state_next=ST_PARENT_READ;
		ST_PARENT_READ: state_next=ST_PARENT_WAIT;
		ST_PARENT_WAIT: state_next=ST_PARENT_WRITE;
		ST_PARENT_WRITE: state_next=ST_MERGE_NEXT;
		ST_MERGE_NEXT: state_next=ST_MERGE_BEGIN;
		ST_EMIT_READ: begin
			if(cnt_merge>=cnt_labels) begin
				state_next=ST_DONE;
			end
			else begin
				state_next=ST_EMIT_WAIT;
			end
		end
		ST_EMIT_WAIT: state_next=ST_EMIT_CHECK;
		ST_EMIT_CHECK: begin
			if(wire_parent_read==cnt_merge && reg_stat_read[64:44]>=reg_min_area) begin
				state_next=ST_EMIT;
			end
			else begin
				state_next=ST_EMIT_NEXT;
			end
		end
		ST_EMIT: if(i_box_ready) begin
			state_next=ST_EMIT_NEXT;
		end
		ST_EMIT_NEXT: state_next=ST_EMIT_READ;
		ST_DONE: state_next=ST_IDLE;
		default: state_next=ST_IDLE;
	endcase
end
always @(posedge i_clk) begin
	if(!i_rstn) begin
		cnt_x<=0;
		cnt_y<=0;
		cnt_clear<=0;
		cnt_address<=0;
		cnt_labels<=1;
        cnt_foreground<=0;reg_overflow_x<=0;reg_overflow_y<=0;
		cnt_merge<=1;
		cnt_neighbor<=0;
		reg_left<=0;
		reg_upper_left<=0;
		reg_up<=0;
		reg_right<=0;
		reg_selected<=0;
		reg_root_a<=0;
		reg_root_b<=0;
		reg_stat_address<=0;
		reg_stat_write<=0;
		flag_stat_write<=0;
		flag_new<=0;
		flag_overflow_o<=0;
		reg_child<=0;
		reg_xmin_o<=0;
		reg_ymin_o<=0;
		reg_xmax_o<=0;
		reg_ymax_o<=0;
		reg_area_o<=0;
		reg_threshold<=0;
		reg_bright<=0;
		reg_min_area<=0;
        reg_min_label<=0;
        flag_foreground<=0;
        reg_parent_read_address<=0;
	end
	else begin
		flag_stat_write<=0;
		case(state_current)
			ST_IDLE: if(i_start) begin
				cnt_clear<=0;
				cnt_x<=0;
				cnt_y<=0;
				cnt_address<=0;
				cnt_labels<=1;
                cnt_foreground<=0;reg_overflow_x<=0;reg_overflow_y<=0;
				cnt_merge<=1;
				reg_left<=0;
				reg_upper_left<=0;
				flag_overflow_o<=0;
				reg_threshold<=i_threshold;
				reg_bright<=i_bright;
				reg_min_area<=i_min_area;
			end
			ST_CLEAR: begin
				reg_line[cnt_clear]<=0;
				cnt_clear<=cnt_clear+1'b1;
			end
			ST_PIXEL: begin
				reg_up<=reg_line[cnt_x];
				if(cnt_x==C_WIDTH-1) begin
					reg_right<=0;
				end
				else begin
					reg_right<=reg_line[cnt_x+1'b1];
				end
			end
            // 利用已有等待拍寄存阈值判定和标签选择，隔开大帧RAM读出路径。
            ST_PIXEL_WAIT: if(i_pixel_ready) begin
                flag_foreground <= reg_bright ? i_pixel > reg_threshold : i_pixel < reg_threshold;
                reg_min_label <= dec_min_label;
            end
			ST_SELECT: begin
                if(flag_foreground)cnt_foreground<=cnt_foreground+1'b1;
				cnt_neighbor<=0;
				if(!flag_foreground) begin
					reg_selected<=0;
				end
				else if(reg_min_label==0) begin
					if(cnt_labels==C_LABELS) begin
						flag_overflow_o<=1;
                        reg_overflow_x<=cnt_x;reg_overflow_y<=cnt_y;
					end
					reg_selected<=cnt_labels[9:0];
					flag_new<=1;
				end
				else begin
					reg_selected<=reg_min_label;
					flag_new<=0;
				end
			end
			ST_ALLOC: begin
				cnt_labels<=cnt_labels+1'b1;
			end
			ST_STAT_READ: reg_stat_address<=reg_selected;
			ST_STAT_WRITE: begin
				flag_stat_write<=1;
				if(flag_new) begin
					reg_stat_write<={21'd1,cnt_y,cnt_x,cnt_y,cnt_x};
				end
				else begin
					reg_stat_write[64:44]<=reg_stat_read[64:44]+1'b1;
					reg_stat_write[10:0]<=cnt_x<reg_stat_read[10:0] ? cnt_x : reg_stat_read[10:0];
					reg_stat_write[21:11]<=reg_stat_read[21:11];
					reg_stat_write[32:22]<=cnt_x>reg_stat_read[32:22] ? cnt_x : reg_stat_read[32:22];
					reg_stat_write[43:33]<=cnt_y;
				end
			end
			ST_NEIGHBOR: begin
				reg_root_a<=reg_selected;
				reg_root_b<=dec_neighbor;
                reg_parent_read_address<=reg_selected;
				if(cnt_neighbor<4 && dec_neighbor==0) begin
					cnt_neighbor<=cnt_neighbor+1'b1;
				end
			end
            ST_ROOT_A: begin
                reg_root_a<=wire_parent_read;
                reg_parent_read_address<=wire_parent_read==reg_root_a ? reg_root_b : wire_parent_read;
            end
            ST_ROOT_B: begin
                reg_root_b<=wire_parent_read;
                reg_parent_read_address<=wire_parent_read;
            end
			ST_UNION: begin
				cnt_neighbor<=cnt_neighbor+1'b1;
			end
			ST_NEXT: begin
				reg_line[cnt_x]<=reg_selected;
				cnt_address<=cnt_address+1'b1;
				if(cnt_x==C_WIDTH-1) begin
					cnt_x<=0;
					cnt_y<=cnt_y+1'b1;
					reg_left<=0;
					reg_upper_left<=0;
				end
				else begin
					cnt_x<=cnt_x+1'b1;
					reg_left<=reg_selected;
					reg_upper_left<=reg_up;
				end
			end
			ST_MERGE_BEGIN: begin
				reg_root_b<=cnt_merge[9:0];
                reg_parent_read_address<=cnt_merge[9:0];
				if(cnt_merge>=cnt_labels) begin
					cnt_merge<=1;
				end
			end
            ST_MERGE_ROOT: begin
                reg_root_b<=wire_parent_read;
                reg_parent_read_address<=wire_parent_read;
            end
			ST_CHILD_READ: reg_stat_address<=cnt_merge[9:0];
			ST_CHILD_SAVE: begin
				reg_child<=reg_stat_read;
			end
			ST_PARENT_READ: reg_stat_address<=reg_root_b;
			ST_PARENT_WRITE: begin
				flag_stat_write<=1;
				reg_stat_write[64:44]<=reg_stat_read[64:44]+reg_child[64:44];
				reg_stat_write[10:0]<=reg_child[10:0]<reg_stat_read[10:0] ? reg_child[10:0] : reg_stat_read[10:0];
				reg_stat_write[21:11]<=reg_child[21:11]<reg_stat_read[21:11] ? reg_child[21:11] : reg_stat_read[21:11];
				reg_stat_write[32:22]<=reg_child[32:22]>reg_stat_read[32:22] ? reg_child[32:22] : reg_stat_read[32:22];
				reg_stat_write[43:33]<=reg_child[43:33]>reg_stat_read[43:33] ? reg_child[43:33] : reg_stat_read[43:33];
			end
			ST_MERGE_NEXT: cnt_merge<=cnt_merge+1'b1;
            ST_EMIT_READ: begin
                reg_stat_address<=cnt_merge[9:0];
                reg_parent_read_address<=cnt_merge[9:0];
            end
			ST_EMIT_CHECK: begin
				reg_xmin_o<=reg_stat_read[10:0];
				reg_ymin_o<=reg_stat_read[21:11];
				reg_xmax_o<=reg_stat_read[32:22];
				reg_ymax_o<=reg_stat_read[43:33];
				reg_area_o<=reg_stat_read[64:44];
			end
			ST_EMIT_NEXT: cnt_merge<=cnt_merge+1'b1;
			default: begin
			end
		endcase
	end
end
 
always @(*) begin
    flag_parent_write=0;
    dec_parent_write_address=0;
    dec_parent_write_data=0;
    case(state_current)
        ST_IDLE: if(i_start) begin flag_parent_write=1; end
        ST_ALLOC: begin
            flag_parent_write=1;
            dec_parent_write_address=reg_selected;
            dec_parent_write_data=reg_selected;
        end
        ST_UNION: if(reg_root_a!=reg_root_b) begin
            flag_parent_write=1;
            dec_parent_write_address=reg_root_a<reg_root_b ? reg_root_b : reg_root_a;
            dec_parent_write_data=reg_root_a<reg_root_b ? reg_root_a : reg_root_b;
        end
        ST_CHILD_SAVE: begin
            flag_parent_write=1;
            dec_parent_write_address=cnt_merge[9:0];
            dec_parent_write_data=reg_root_b;
        end
        default: begin end
    endcase
end
always @(posedge i_clk) begin
    if(i_rstn && flag_parent_write) begin
        reg_parent[dec_parent_write_address]<=dec_parent_write_data;
    end
end
endmodule
