`timescale 1ns/1ps
// PS FCLK=100MHz. VCO=742.5MHz; pixel=74.25MHz; DDR serializer=371.25MHz.
// Camera control keeps its independent, board-tested 125MHz/4 clock.
module hdmi_clocks (
    input wire sys_clk,
    output wire pixel_clk,
    output wire serial_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 video_reset RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire reset
);
    wire feedback;
    wire pixel_raw;
    wire serial_raw;
    wire locked;
    (* ASYNC_REG = "TRUE" *) reg [2:0] released = 0;
    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0), .CLKFBOUT_MULT_F(37.125), .DIVCLK_DIVIDE(5),
        .CLKOUT0_DIVIDE_F(10.0), .CLKOUT1_DIVIDE(2)
    ) video_mmcm (
        .CLKIN1(sys_clk), .CLKFBIN(feedback), .CLKFBOUT(feedback),
        .CLKOUT0(pixel_raw), .CLKOUT1(serial_raw), .LOCKED(locked),
        .PWRDWN(1'b0), .RST(1'b0),
        .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );
    BUFG pixel_buffer (.I(pixel_raw), .O(pixel_clk));
    BUFG serial_buffer (.I(serial_raw), .O(serial_clk));
    always @(posedge pixel_clk or negedge locked) begin
        if (!locked) released <= 0;
        else released <= {released[1:0],1'b1};
    end
    assign reset = !released[2];
endmodule
