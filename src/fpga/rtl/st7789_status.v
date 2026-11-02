 
 
module st7789_status (
    input wire control_clk,
    input wire sys_clk,
    input wire frame_sent,
    input wire camera_ready,
    input wire init_done,
    input wire [7:0] nack_count,
    output wire [3:0] led
);
    reg [23:0] heartbeat = 24'd0;
    reg [7:0] displayed_frames = 8'd0;
    always @(posedge control_clk) heartbeat <= heartbeat + 24'd1;
    always @(posedge sys_clk)
        if (frame_sent) displayed_frames <= displayed_frames + 8'd1;
    assign led = {init_done && (nack_count == 8'd0),
                  camera_ready, displayed_frames[3], heartbeat[23]};
endmodule
