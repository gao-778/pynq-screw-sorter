 
module st7789_camera_control (
    input wire control_clk,
    input wire [31:0] gpio_control,
    output wire [2:0] sensor_status,
    inout wire cam_scl,
    inout wire cam_sda,
    output wire cam_rst_n,
    output wire cam_pwdn,
    output wire init_done,
    output wire [7:0] nack_count
);
    reg [21:0] power_count = 22'd0;
    always @(posedge control_clk) begin
        if (power_count < 22'd625000)
            power_count <= power_count + 22'd1;
    end
    assign cam_rst_n = (power_count == 22'd625000);
    assign cam_pwdn = 1'b0;
    i2c_baseline_init #(.CLK_FREQ(31250000), .SCL_HZ(100000), .START_DELAY_MS(100)) init_sequence (
        .clk(control_clk), .rst_n(cam_rst_n), .restart(1'b0),
        .gpio_control(gpio_control), .sensor_status(sensor_status),
        .scl(cam_scl), .sda(cam_sda), .init_done(init_done), .nack_cnt(nack_count)
    );
endmodule
