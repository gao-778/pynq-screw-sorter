`timescale 1ns/1ps
 
 
module snapshot_control (
    input wire clk,
    input wire reset_n,
    input wire [3:0] button,
    input wire [2:0] sensor_status,
    input wire [31:0] gpio_control,
    input wire [2:0] camera_status,
    input wire [2:0] screen_status,
    input wire [2:0] screenshot_status,
    output wire [31:0] gpio_status,
    output wire camera_arm,
    output wire screen_arm,
    output wire capture_reset_n,
    output wire [2:0] rgb_led
);
    (* ASYNC_REG = "TRUE" *) reg [12:0] status_meta = 0;
    (* ASYNC_REG = "TRUE" *) reg [12:0] status_sync = 0;
    (* ASYNC_REG = "TRUE" *) reg [2:0] screenshot_meta=0,screenshot_sync=0;
    always @(posedge clk) begin
        if (!reset_n) begin
            status_meta <= 0;
            status_sync <= 0;
            screenshot_meta<=0;screenshot_sync<=0;
        end else begin
            status_meta <= {sensor_status,screen_status,camera_status,button};
            status_sync <= status_meta;
            screenshot_meta<=screenshot_status;screenshot_sync<=screenshot_meta;
        end
    end
    assign gpio_status = {13'd0,screenshot_sync,3'd0,status_sync};
    assign camera_arm = gpio_control[0];
    assign screen_arm = gpio_control[1];
    assign capture_reset_n = reset_n && gpio_control[2];
    assign rgb_led = gpio_control[10:8];
endmodule
