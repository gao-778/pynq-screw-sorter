`timescale 1ns/1ps
 
 
module ddr_gray_reader (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 i_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXI, ASSOCIATED_RESET i_rstn" *) input i_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 i_rstn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *) input i_rstn,
    input [31:0] i_base_address, output o_idle,
    input i_invalidate,
    input i_enable,
    input i_bank,
    input [20:0] i_address,
    output [7:0] o_data,
    output o_valid,
    output o_error,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *) output [31:0] m_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *) output [7:0] m_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *) output [2:0] m_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *) output [1:0] m_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *) output [3:0] m_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *) output m_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *) output [3:0] m_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *) input m_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *) output [2:0] m_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *) output m_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *) input m_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *) input [31:0] m_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *) input [1:0] m_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *) input m_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *) output m_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *) output [31:0] m_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *) output [7:0] m_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *) output [2:0] m_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *) output [1:0] m_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *) output [3:0] m_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *) output m_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *) output [3:0] m_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *) output m_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *) output [2:0] m_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *) output m_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *) input m_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *) output [31:0] m_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *) output [3:0] m_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *) output m_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *) input m_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *) input [1:0] m_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *) input m_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *) output m_axi_bready
);
localparam ST_IDLE=0, ST_ADDRESS=1, ST_DATA=2;
reg [1:0] state_current, state_next;
reg [18:0] reg_line_base;
reg [3:0] reg_fill_index;
reg [31:0] reg_cache_data [0:15];
reg [15:0] reg_cache_valid;
reg flag_line_valid, flag_error, flag_discard, reg_bank;
wire [18:0] wire_word_address=i_address[20:2];
wire wire_same_line=flag_line_valid && reg_bank==i_bank && wire_word_address[18:4]==reg_line_base[18:4];
wire [3:0] wire_cache_index=wire_word_address[3:0];
wire wire_hit=wire_same_line && reg_cache_valid[wire_cache_index];
assign m_axi_araddr=i_base_address+{10'd0,reg_bank,reg_line_base,2'b00};
assign o_idle=state_current==ST_IDLE && !i_enable;
assign m_axi_arlen=15;
assign m_axi_arsize=2;
assign m_axi_arburst=1;
assign m_axi_arcache=3;
assign m_axi_arlock=0;
assign m_axi_arqos=0;
assign m_axi_awlen=0;
assign m_axi_awsize=2;
assign m_axi_awburst=1;
assign m_axi_awcache=0;
assign m_axi_awlock=0;
assign m_axi_awqos=0;
assign m_axi_wlast=1;
assign m_axi_arprot=0;
assign m_axi_arvalid=state_current==ST_ADDRESS;
assign m_axi_rready=state_current==ST_DATA;
assign m_axi_awaddr=0;
assign m_axi_awprot=0;
assign m_axi_awvalid=0;
assign m_axi_wdata=0;
assign m_axi_wstrb=0;
assign m_axi_wvalid=0;
assign m_axi_bready=1;
assign o_valid=wire_hit && i_enable && !i_invalidate;
assign o_data=reg_cache_data[wire_cache_index] >> {i_address[1:0],3'b000};
assign o_error=flag_error;
always @(posedge i_clk) begin
    if(!i_rstn) state_current<=ST_IDLE;
    else state_current<=state_next;
end
always @(*) begin
    state_next=state_current;
    case(state_current)
        ST_IDLE: if(i_enable && !wire_hit && !i_invalidate && !flag_error) state_next=ST_ADDRESS;
        ST_ADDRESS: if(m_axi_arready) state_next=ST_DATA;
        ST_DATA: if(m_axi_rvalid) begin
            if(m_axi_rlast) state_next=ST_IDLE;
        end
        default: state_next=ST_IDLE;
    endcase
end
always @(posedge i_clk) begin
    if(!i_rstn) begin
        reg_line_base<=0;reg_fill_index<=0;reg_cache_valid<=0;reg_bank<=0;
        flag_line_valid<=0;flag_error<=0;flag_discard<=0;
    end else begin
        if(state_current==ST_IDLE && state_next==ST_ADDRESS) begin
            reg_line_base<={wire_word_address[18:4],4'b0};reg_bank<=i_bank;
            reg_fill_index<=0;reg_cache_valid<=0;flag_line_valid<=0;flag_discard<=0;
        end
        if(state_current==ST_DATA && m_axi_rvalid) begin
            if(!flag_discard && m_axi_rresp==0) begin
                reg_cache_data[reg_fill_index]<=m_axi_rdata;
                reg_cache_valid[reg_fill_index]<=1;
                if(reg_fill_index==4'd15 && m_axi_rlast && !flag_error) flag_line_valid<=1;
            end
            if((m_axi_rresp!=0 || (m_axi_rlast!=(reg_fill_index==15))) && !flag_discard && !i_invalidate) flag_error<=1;
            if(reg_fill_index!=4'd15) reg_fill_index<=reg_fill_index+1'b1;
        end
         
        if(i_invalidate) begin
            reg_cache_valid<=0;flag_line_valid<=0;flag_discard<=1;flag_error<=0;
        end
    end
end
endmodule
