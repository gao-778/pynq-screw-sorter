// Divide the 125 MHz oscillator by four using a global clock buffer.
module st7789_clock_divider(input wire sys_clk, output wire control_clk);
    reg [1:0] clock_divider = 2'd0;
    always @(posedge sys_clk) begin
        clock_divider <= clock_divider + 2'd1;
    end
    BUFG control_buffer (.I(clock_divider[1]), .O(control_clk));
endmodule
