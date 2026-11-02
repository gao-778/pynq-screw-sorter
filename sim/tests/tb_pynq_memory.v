`timescale 1ns/1ps
 
module tb_pynq_memory;
reg clk=0,cam=0,vid=0,rstn=0;
always #5 clk=~clk;always #7 cam=~cam;always #9 vid=~vid;
reg genable=0,ginvalidate=0,garready=0,grvalid=0,grlast=0;
wire garvalid,grready,gidle;wire [31:0] garaddr;
reg [31:0] grdata=0;
ddr_gray_reader g(.i_clk(clk),.i_rstn(rstn),.i_base_address(32'h04000000),.o_idle(gidle),
 .i_invalidate(ginvalidate),.i_enable(genable),.i_bank(1'b1),.i_address(21'h123),
 .m_axi_araddr(garaddr),.m_axi_arvalid(garvalid),.m_axi_arready(garready),
 .m_axi_rdata(grdata),.m_axi_rresp(2'b0),.m_axi_rlast(grlast),.m_axi_rvalid(grvalid),.m_axi_rready(grready),
 .m_axi_awready(1'b0),.m_axi_wready(1'b0),.m_axi_bresp(2'b0),.m_axi_bvalid(1'b0));
reg run=0,frame=0,line=0,pixelvalid=0;
reg parready=0,prvalid=0,prlast=0,pawready=0,pwready=0,pbvalid=0;
wire pidle,parvalid,prready,pawvalid,pwvalid,pwlast,pbready;
wire [31:0] paraddr,pawaddr;
ddr_preview p(.i_clk(clk),.i_rstn(rstn),.i_base_address(32'h02000000),.i_run(run),.o_idle(pidle),
 .camera_clk(cam),.frame_start(frame),.line_start(line),.pixel_valid(pixelvalid),.pixel_rgb(24'hff0000),
 .display_clk(vid),.display_vblank(1'b0),.display_row_start(1'b0),.display_next_row(8'd0),.display_x(9'd0),.display_y(8'd0),
 .m_axi_araddr(paraddr),.m_axi_arvalid(parvalid),.m_axi_arready(parready),
 .m_axi_rdata(32'h12345678),.m_axi_rresp(2'b0),.m_axi_rlast(prlast),.m_axi_rvalid(prvalid),.m_axi_rready(prready),
 .m_axi_awaddr(pawaddr),.m_axi_awvalid(pawvalid),.m_axi_awready(pawready),
 .m_axi_wvalid(pwvalid),.m_axi_wlast(pwlast),.m_axi_wready(pwready),
 .m_axi_bresp(2'b0),.m_axi_bvalid(pbvalid),.m_axi_bready(pbready));
integer beats=0;reg aw_seen=0;reg gray_done=0,preview_done=0;
always @(posedge clk) begin
 if(pawvalid && pawready) aw_seen<=1;
 if(pwvalid && pwready) begin
   if(pwlast !== (beats==15))$fatal(1,"preview WLAST");
   beats<=beats+1;
 end
end
initial begin repeat(20)@(negedge clk);rstn=1;end
integer gi;
initial begin
 wait(rstn);@(negedge clk);genable=1;
 wait(garvalid);#1;if(garaddr!==32'h04200100)$fatal(1,"relocated gray bank/line address %h",garaddr);
 @(negedge clk);genable=0;ginvalidate=1;
 repeat(10)begin @(negedge clk);if(!garvalid || gidle)$fatal(1,"gray cancelled stalled AR");end
 garready=1;@(negedge clk);garready=0;
 wait(grready);repeat(3)@(negedge clk);
 if(gidle)$fatal(1,"gray idle before R drain");
 for(gi=0;gi<16;gi=gi+1)begin
  grvalid=1;grlast=gi==15;grdata=gi;@(negedge clk);
  grvalid=0;grlast=0;@(negedge clk);
 end
 repeat(5)@(negedge clk);if(!gidle || garvalid)$fatal(1,"gray failed drain");gray_done=1;
end
integer px,pi,row;
initial begin
 wait(rstn);@(negedge clk);run=1;repeat(100)@(negedge cam);
 frame=1;@(negedge cam);frame=0;
 // The Mint preview emits pixels only after a complete 4x4 area reduction.
 for(row=0;row<4;row=row+1)begin
  line=1;@(negedge cam);line=0;
  pixelvalid=1;for(px=0;px<1280;px=px+1)@(negedge cam);pixelvalid=0;
  repeat(8)@(negedge cam);
 end
end
initial begin
 wait(pawvalid);#1;if(pawaddr!==32'h02040000)$fatal(1,"relocated preview write bank %h",pawaddr);
  
 force p.flag_request=1'b1;force p.flag_request_bank=2'd2;force p.reg_request_row=8'd7;
 wait(parvalid);#1;if(paraddr!==32'h02081180)$fatal(1,"relocated preview read bank/row %h",paraddr);
 @(negedge clk);run=0;
 repeat(15)begin @(negedge clk);if(!pawvalid || !parvalid || pidle)$fatal(1,"preview cancelled outstanding address");end
 parready=1;pawready=1;pwready=1;@(negedge clk);parready=0;pawready=0;
 wait(prready);
 for(pi=0;pi<16;pi=pi+1)begin
  prvalid=1;prlast=pi==15;@(negedge clk);prvalid=0;prlast=0;@(negedge clk);
 end
 wait(pbready);if(pidle || !aw_seen || beats!=16)$fatal(1,"preview idle before B / write incomplete");
 repeat(10)@(negedge clk);pbvalid=1;@(negedge clk);pbvalid=0;
 repeat(100)begin @(negedge clk);if(pawvalid || parvalid || pwvalid)$fatal(1,"preview restarted after stop");end
 if(!pidle)$fatal(1,"preview failed drain");preview_done=1;
end
initial begin
 wait(gray_done && preview_done);
 $display("PASS PYNQ_MEMORY: relocated gray/preview bank addresses; stalled AR/AW and read/write/B shutdown drain; no restart after run=0");$finish;
end
initial begin #1000000;$fatal(1,"timeout gray=%b preview=%b",gray_done,preview_done);end
endmodule
