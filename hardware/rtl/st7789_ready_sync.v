// A completed camera frame is a sticky level; synchronize it before selecting
// camera pixels in the system-clock display domain.
module st7789_ready_sync (
    input wire sys_clk,
    input wire frame_complete,
    output reg camera_ready = 1'b0
);
    reg camera_ready_meta = 1'b0;
    always @(posedge sys_clk) begin
        camera_ready_meta <= frame_complete;
        camera_ready <= camera_ready_meta;
    end
endmodule
