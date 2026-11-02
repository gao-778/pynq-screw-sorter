`timescale 1ns/1ps
 
 
module ddr_preview (
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 i_clk CLK" *)
    (* X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF M_AXI, ASSOCIATED_RESET i_rstn" *) input wire i_clk,
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 i_rstn RST" *)
    (* X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input wire i_rstn,
    input wire [31:0] i_base_address, input wire i_run, output wire o_idle,
    input wire camera_clk, input wire frame_start, input wire line_start,
    input wire pixel_valid, input wire [23:0] pixel_rgb,
    input wire display_clk, input wire display_vblank, input wire display_row_start,
    input wire [7:0] display_next_row,
    input wire [8:0] display_x, input wire [7:0] display_y,
    output wire [15:0] display_pixel, output wire frame_complete,
    output wire [2:0] camera_status, output wire [2:0] screen_status,
     
    output wire [31:0] o_camera_frames, output wire [31:0] o_written_frames,
    output wire [31:0] o_display_frames, output wire [31:0] o_video_status,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *) output wire [31:0] m_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *) output wire [7:0] m_axi_arlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *) output wire [2:0] m_axi_arsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *) output wire [1:0] m_axi_arburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *) output wire m_axi_arlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *) output wire [3:0] m_axi_arcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *) output wire [2:0] m_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *) output wire [3:0] m_axi_arqos,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *) output wire m_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *) input wire m_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI RDATA" *) input wire [31:0] m_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI RRESP" *) input wire [1:0] m_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI RLAST" *) input wire m_axi_rlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI RVALID" *) input wire m_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI RREADY" *) output wire m_axi_rready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *) output wire [31:0] m_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *) output wire [7:0] m_axi_awlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *) output wire [2:0] m_axi_awsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *) output wire [1:0] m_axi_awburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *) output wire m_axi_awlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *) output wire [3:0] m_axi_awcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *) output wire [2:0] m_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *) output wire [3:0] m_axi_awqos,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *) output wire m_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *) input wire m_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI WDATA" *) output wire [31:0] m_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *) output wire [3:0] m_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI WLAST" *) output wire m_axi_wlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI WVALID" *) output wire m_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI WREADY" *) input wire m_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI BRESP" *) input wire [1:0] m_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI BVALID" *) input wire m_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 M_AXI BREADY" *) output wire m_axi_bready
);
 
localparam [1:0] W_IDLE=0,W_SEND=1,W_RESPONSE=2;
localparam [1:0] R_IDLE=0,R_ADDRESS=1,R_DATA=2;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_cam_reset=0,reg_video_reset=0;
always @(posedge camera_clk or negedge i_rstn) begin
    if(!i_rstn) reg_cam_reset<=0;
    else reg_cam_reset<={reg_cam_reset[1:0],1'b1};
end
always @(posedge display_clk or negedge i_rstn) begin
    if(!i_rstn) reg_video_reset<=0;
    else reg_video_reset<={reg_video_reset[1:0],1'b1};
end
(* ASYNC_REG="TRUE" *) reg [2:0] reg_run_camera;
always @(posedge camera_clk) begin
    if(!reg_cam_reset[2]) reg_run_camera<=0;
    else reg_run_camera<={reg_run_camera[1:0],i_run};
end
 
 
wire flag_average_valid;
wire flag_average_error;
wire [23:0] wire_average_rgb;
preview_area_average preview_filter (
    .i_clk(camera_clk),.i_rstn(reg_cam_reset[2]),
    .i_frame_start(frame_start),.i_line_start(line_start),
    .i_valid(pixel_valid),.i_rgb(pixel_rgb),
    .o_valid(flag_average_valid),.o_rgb(wire_average_rgb),.o_frame_error(flag_average_error)
);
reg [15:0] reg_half;
reg flag_half,flag_camera_bad,flag_camera_overflow,flag_camera_frame;
reg [15:0] cnt_camera_word;
wire [15:0] dec_rgb565={wire_average_rgb[23:19],wire_average_rgb[15:10],wire_average_rgb[7:3]};
wire [33:0] wire_fifo_in={cnt_camera_word==0,cnt_camera_word==38399,dec_rgb565,reg_half};
wire [33:0] wire_fifo_out;
wire flag_full,flag_empty,flag_wr_busy,flag_rd_busy;
 
// with line_start; frame_start deliberately discards a partial previous frame.
wire flag_fifo_push=reg_run_camera[2] && reg_cam_reset[2] && !frame_start && !flag_average_error && flag_average_valid && flag_half &&
                    !flag_camera_bad && !flag_full && !flag_wr_busy;
wire flag_fifo_pop;
always @(posedge camera_clk) begin
    if(!reg_cam_reset[2]) begin
        reg_half<=0;flag_half<=0;
        flag_camera_bad<=1;flag_camera_overflow<=0;cnt_camera_word<=0;flag_camera_frame<=0;
    end else if(frame_start) begin
        flag_half<=0;flag_camera_bad<=!reg_run_camera[2];cnt_camera_word<=0;
        flag_camera_frame<=!flag_camera_frame;
    end else if(flag_average_error) begin
        flag_camera_bad<=1;
    end else if(flag_average_valid && !flag_camera_bad) begin
        if(!flag_half) begin reg_half<=dec_rgb565;flag_half<=1;end
        else begin
            flag_half<=0;
            if(flag_full || flag_wr_busy) begin flag_camera_bad<=1;flag_camera_overflow<=1;end
            else cnt_camera_word<=cnt_camera_word+1'b1;
        end
    end
end
// Vendor FIFO supplies Gray-pointer CDC and reset-busy protection.
xpm_fifo_async #(.FIFO_MEMORY_TYPE("block"),.FIFO_WRITE_DEPTH(2048),
    .WRITE_DATA_WIDTH(34),.READ_DATA_WIDTH(34),.READ_MODE("fwft"),.FIFO_READ_LATENCY(0),
    .CDC_SYNC_STAGES(3),.DOUT_RESET_VALUE("0"),.ECC_MODE("no_ecc"),.FULL_RESET_VALUE(0),
    .PROG_EMPTY_THRESH(10),.PROG_FULL_THRESH(2000),.RD_DATA_COUNT_WIDTH(12),.WR_DATA_COUNT_WIDTH(12),
    .RELATED_CLOCKS(0),.USE_ADV_FEATURES("0000"),.WAKEUP_TIME(0)) capture_fifo (
    .rst(!reg_cam_reset[2]),.wr_clk(camera_clk),.rd_clk(i_clk),.din(wire_fifo_in),.wr_en(flag_fifo_push),
    .full(flag_full),.wr_rst_busy(flag_wr_busy),.dout(wire_fifo_out),.rd_en(flag_fifo_pop),
    .empty(flag_empty),.rd_rst_busy(flag_rd_busy),.sleep(1'b0),.injectsbiterr(1'b0),.injectdbiterr(1'b0));

 
reg [1:0] state_write,state_write_next;
reg [1:0] flag_write_bank,flag_offer_bank,reg_front_bank_axi;
reg flag_offer,flag_pending,flag_write_active,flag_write_bad,flag_write_error;
reg [15:0] cnt_write_word;
reg [31:0] reg_write_address;
 
 
reg [31:0] reg_write_burst[0:15];
reg [3:0] cnt_collect_word,cnt_send_word;
reg flag_aw_sent,flag_w_sent,flag_last_word;
reg flag_accept;
reg flag_read_error,flag_underflow;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_accept_sync;
 
 
wire flag_offer_accepted=flag_pending && reg_accept_sync[2]==flag_offer;
wire flag_publish_available=!flag_pending || flag_offer_accepted;
wire [1:0] dec_free_bank=(reg_front_bank_axi!=0 && (!flag_pending || flag_offer_bank!=0))?2'd0:
                        (reg_front_bank_axi!=1 && (!flag_pending || flag_offer_bank!=1))?2'd1:2'd2;
wire flag_good_frame=state_write==W_RESPONSE && m_axi_bvalid && flag_last_word &&
                    cnt_write_word==38384 && !flag_write_bad && m_axi_bresp==0;
assign flag_fifo_pop=state_write==W_IDLE && !flag_empty && !flag_rd_busy;
assign m_axi_awaddr=reg_write_address;
assign m_axi_awlen=15;assign m_axi_awsize=2;assign m_axi_awburst=1;
assign m_axi_awlock=0;assign m_axi_awcache=3;assign m_axi_awprot=0;assign m_axi_awqos=0;
assign m_axi_awvalid=state_write==W_SEND && !flag_aw_sent;
assign m_axi_wdata=reg_write_burst[cnt_send_word];assign m_axi_wstrb=15;
assign m_axi_wlast=cnt_send_word==15;
assign m_axi_wvalid=state_write==W_SEND && !flag_w_sent;
assign m_axi_bready=state_write==W_RESPONSE;
always @(*) begin
    state_write_next=state_write;
    case(state_write)
        W_IDLE: if(i_run && flag_fifo_pop && !wire_fifo_out[33] &&
                   flag_write_active && cnt_collect_word==15) state_write_next=W_SEND;
        W_SEND: if((flag_aw_sent || m_axi_awready) &&
                   (flag_w_sent || (m_axi_wready && cnt_send_word==15))) state_write_next=W_RESPONSE;
        W_RESPONSE: if(m_axi_bvalid) state_write_next=W_IDLE;
        default:state_write_next=W_IDLE;
    endcase
end
always @(posedge i_clk) begin
    if(!i_rstn) state_write<=W_IDLE;
    else state_write<=state_write_next;
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        flag_write_bank<=1;reg_front_bank_axi<=0;flag_offer<=0;flag_offer_bank<=0;flag_pending<=0;flag_write_active<=0;
        flag_write_bad<=0;flag_write_error<=0;cnt_write_word<=0;reg_write_address<=0;
        cnt_collect_word<=0;cnt_send_word<=0;
        flag_aw_sent<=0;flag_w_sent<=0;flag_last_word<=0;reg_accept_sync<=0;
    end else begin
        reg_accept_sync<={reg_accept_sync[1:0],flag_accept};
        if(flag_offer_accepted) begin
            flag_pending<=0;reg_front_bank_axi<=flag_offer_bank;
        end
        if(flag_fifo_pop) begin
            // A new SOF discards an incomplete candidate, including its partial
            // staging buffer. Previously issued bursts have already received B.
            if(!i_run) begin flag_write_active<=0;cnt_collect_word<=0;end
            else if(wire_fifo_out[33]) begin
                cnt_write_word<=0;flag_write_bad<=0;flag_write_active<=1;
                flag_write_bank<=dec_free_bank;
                reg_write_burst[0]<=wire_fifo_out[31:0];cnt_collect_word<=1;
                reg_write_address<=i_base_address+{12'd0,dec_free_bank,18'd0};
            end else if(flag_write_active) begin
                reg_write_burst[cnt_collect_word]<=wire_fifo_out[31:0];
                cnt_collect_word<=cnt_collect_word+1'b1;
                if(cnt_collect_word==15) begin
                    flag_aw_sent<=0;flag_w_sent<=0;cnt_send_word<=0;
                    flag_last_word<=wire_fifo_out[32];
                end
            end
        end
        if(state_write==W_SEND) begin
            if(m_axi_awvalid && m_axi_awready) flag_aw_sent<=1;
            if(m_axi_wvalid && m_axi_wready) begin
                if(cnt_send_word==15) flag_w_sent<=1;
                else cnt_send_word<=cnt_send_word+1'b1;
            end
        end
        if(state_write==W_RESPONSE && m_axi_bvalid) begin
            if(m_axi_bresp!=0) begin flag_write_bad<=1;flag_write_error<=1;end
            cnt_write_word<=cnt_write_word+16;
            reg_write_address<=reg_write_address+64;
            if(flag_last_word || cnt_write_word==38384) begin
                flag_write_active<=0;
                if(flag_good_frame && flag_publish_available) begin
                    flag_offer_bank<=flag_write_bank;flag_offer<=!flag_offer;flag_pending<=1;
                end
            end
        end
    end
end

// Frame toggles are separated by a camera frame period, far longer than the
// three i_clk synchronizer cycles. Count events, never HDMI repeats or CPU polls.
(* ASYNC_REG="TRUE" *) reg [2:0] reg_camera_frame_sync;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_camera_overflow_sync,reg_underflow_sync;
reg flag_camera_seen,flag_display_seen,flag_bank_drop;
reg [31:0] cnt_camera_frames,cnt_written_frames,cnt_display_frames;
reg [15:0] cnt_bank_drops;
assign o_camera_frames=cnt_camera_frames;
assign o_written_frames=cnt_written_frames;
assign o_display_frames=cnt_display_frames;
assign o_video_status={cnt_bank_drops,11'd0,flag_bank_drop,reg_underflow_sync[2],
                       flag_read_error,flag_write_error,reg_camera_overflow_sync[2]};
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_camera_frame_sync<=0;reg_camera_overflow_sync<=0;reg_underflow_sync<=0;
        flag_camera_seen<=0;flag_display_seen<=0;flag_bank_drop<=0;
        cnt_camera_frames<=0;cnt_written_frames<=0;cnt_display_frames<=0;cnt_bank_drops<=0;
    end else begin
        reg_camera_frame_sync<={reg_camera_frame_sync[1:0],flag_camera_frame};
        reg_camera_overflow_sync<={reg_camera_overflow_sync[1:0],flag_camera_overflow};
        reg_underflow_sync<={reg_underflow_sync[1:0],flag_underflow};
        if(reg_camera_frame_sync[2]!=flag_camera_seen) begin
            flag_camera_seen<=reg_camera_frame_sync[2];cnt_camera_frames<=cnt_camera_frames+1'b1;
        end
        if(reg_accept_sync[2]!=flag_display_seen) begin
            flag_display_seen<=reg_accept_sync[2];cnt_display_frames<=cnt_display_frames+1'b1;
        end
        if(flag_good_frame && flag_publish_available)
            cnt_written_frames<=cnt_written_frames+1'b1;
        // A stopped display may retain front+offer indefinitely. Discard a
        // newly completed candidate, rather than overwrite either owner.
        if(flag_good_frame && !flag_publish_available) begin
            flag_bank_drop<=1;cnt_bank_drops<=cnt_bank_drops+1'b1;
        end
    end
end

 
(* ram_style="block" *) reg [31:0] reg_lines[0:511];
reg [31:0] reg_line_read;
reg flag_read_half,flag_read_visible;
reg [1:0] state_read,state_read_next;
reg [1:0] flag_request_bank;
reg flag_request,flag_response,flag_response_bad,flag_read_bad;
reg [7:0] reg_request_row,reg_read_row,cnt_read_word;
reg [31:0] reg_read_base;
(* ASYNC_REG="TRUE" *) reg [2:0] reg_request_sync;
wire [8:0] dec_line_write={reg_read_row[0],cnt_read_word};
assign o_idle=state_write==W_IDLE && state_read==R_IDLE && !i_run;
assign m_axi_araddr=reg_read_base+{22'd0,cnt_read_word[7:4],6'b0};
assign m_axi_arlen=15;assign m_axi_arsize=2;assign m_axi_arburst=1;
assign m_axi_arlock=0;assign m_axi_arcache=3;assign m_axi_arprot=0;assign m_axi_arqos=8;
assign m_axi_arvalid=state_read==R_ADDRESS;
assign m_axi_rready=state_read==R_DATA;
always @(*) begin
    state_read_next=state_read;
    case(state_read)
        R_IDLE:if(i_run && reg_request_sync[2]!=flag_response) state_read_next=R_ADDRESS;
        R_ADDRESS:if(m_axi_arready) state_read_next=R_DATA;
        R_DATA:if(m_axi_rvalid && m_axi_rlast) begin
            if(!i_run || cnt_read_word==159 || cnt_read_word[3:0]!=15) state_read_next=R_IDLE;
            else state_read_next=R_ADDRESS;
        end
        default:state_read_next=R_IDLE;
    endcase
end
always @(posedge i_clk) begin
    if(!i_rstn) state_read<=R_IDLE;
    else state_read<=state_read_next;
    if(state_read==R_DATA && m_axi_rvalid) reg_lines[dec_line_write]<=m_axi_rdata;
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_request_sync<=0;flag_response<=0;flag_response_bad<=0;flag_read_bad<=0;flag_read_error<=0;
        reg_read_row<=0;cnt_read_word<=0;reg_read_base<=0;
    end else begin
        reg_request_sync<={reg_request_sync[1:0],flag_request};
        if(state_read==R_IDLE && state_read_next==R_ADDRESS) begin
            reg_read_row<=reg_request_row;cnt_read_word<=0;flag_read_bad<=0;
            reg_read_base<=i_base_address+{12'd0,flag_request_bank,18'd0}+
                          {15'd0,reg_request_row,9'd0}+{17'd0,reg_request_row,7'd0};
        end
        if(state_read==R_DATA && m_axi_rvalid) begin
            cnt_read_word<=cnt_read_word+1'b1;
            if(m_axi_rresp!=0 || (m_axi_rlast!=(cnt_read_word[3:0]==15))) begin flag_read_bad<=1;flag_read_error<=1;end
            if(state_read_next==R_IDLE) begin
                flag_response<=reg_request_sync[2];
                flag_response_bad<=flag_read_bad || m_axi_rresp!=0 || cnt_read_word[3:0]!=15;
            end
        end
    end
end

(* ASYNC_REG="TRUE" *) reg [2:0] reg_offer_sync,reg_response_sync;
reg [1:0] flag_front_bank;
reg flag_have_frame,flag_display_ready,flag_seen_response;
reg [1:0] reg_line_valid;
reg [7:0] reg_tag_even,reg_tag_odd;
assign display_pixel=flag_read_visible?(flag_read_half?reg_line_read[31:16]:reg_line_read[15:0]):16'd0;
assign frame_complete=flag_display_ready;
assign camera_status={flag_write_error,flag_camera_overflow,flag_display_ready};
assign screen_status={flag_read_error,flag_underflow,flag_have_frame};
always @(posedge display_clk) begin
    reg_line_read<=reg_lines[{display_y[0],display_x[8:1]}];
    flag_read_half<=display_x[0];
    flag_read_visible<=flag_have_frame && reg_line_valid[display_y[0]] &&
                       (display_y[0]?reg_tag_odd:reg_tag_even)==display_y;
end
always @(posedge display_clk) begin
    if(!reg_video_reset[2]) begin
        reg_offer_sync<=0;reg_response_sync<=0;flag_front_bank<=0;flag_have_frame<=0;
        flag_display_ready<=0;flag_underflow<=0;flag_accept<=0;flag_request<=0;flag_request_bank<=0;
        reg_request_row<=0;flag_seen_response<=0;reg_line_valid<=0;reg_tag_even<=0;reg_tag_odd<=0;
    end else begin
        reg_offer_sync<={reg_offer_sync[1:0],flag_offer};
        reg_response_sync<={reg_response_sync[1:0],flag_response};
        if(reg_response_sync[2]!=flag_seen_response) begin
            flag_seen_response<=reg_response_sync[2];
            reg_line_valid[reg_request_row[0]]<=!flag_response_bad;
            if(reg_request_row[0]) reg_tag_odd<=reg_request_row;
            else reg_tag_even<=reg_request_row;
            if(!flag_response_bad && reg_request_row==239) flag_display_ready<=1;
        end
         
        if(display_vblank && reg_response_sync[2]==flag_request) begin
            reg_line_valid<=0;
            if(reg_offer_sync[2]!=flag_accept) begin
                flag_front_bank<=flag_offer_bank;flag_have_frame<=1;flag_accept<=reg_offer_sync[2];
                flag_request_bank<=flag_offer_bank;reg_request_row<=239;flag_request<=!flag_request;
            end else if(flag_have_frame) begin
                flag_request_bank<=flag_front_bank;reg_request_row<=239;flag_request<=!flag_request;
            end
        end else if(display_row_start && flag_have_frame) begin
            if(!reg_line_valid[display_next_row[0]] ||
               (display_next_row[0]?reg_tag_odd:reg_tag_even)!=display_next_row) flag_underflow<=1;
            if(display_next_row!=0 && reg_response_sync[2]==flag_request) begin
                reg_request_row<=display_next_row-1'b1;flag_request_bank<=flag_front_bank;
                reg_line_valid[!display_next_row[0]]<=0;flag_request<=!flag_request;
            end
        end
    end
end
endmodule
