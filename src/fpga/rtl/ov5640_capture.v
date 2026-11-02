 

module ov5640_capture #(
    parameter VSYNC_ACTIVE_HIGH = 1'b1,  // 实测值, 花屏/不同步时再考虑改
    parameter HREF_ACTIVE_HIGH  = 1'b1,
    parameter RGB565_BYTE_ORDER = 1'b0   // 0=先高字节; 1=先低字节(红蓝会颠倒)
)(
    input  wire        pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,
    output reg         de,          // 像素有效(配准 1 拍, 与 rgb 对齐)
    output wire        de_wide,     // DE 展宽 2 拍(覆盖整个像素周期, 供 PCLK/2 域安全采样)
    output reg  [23:0] rgb,         // RGB888(在下一像素凑齐前保持 2 拍不变)
    output wire        frame_start, // VSYNC 有效下降沿脉冲: 新一帧即将开始
    output wire        line_start   // HREF  上升沿脉冲: 新一行开始
);
    // Sample data and both qualifiers together. The decoder is delayed by one
    // PCLK, without changing pixel order, image dimensions or byte polarity.
    // Fabric placement lets the router balance setup and hold on non-CCIO PCLK.
    // 中文：数据和行场同步同拍采样，首级放逻辑区，允许路由调整保持时间。
    (* IOB="FALSE" *) reg [7:0] reg_input_data;
    (* IOB="FALSE" *) reg flag_input_vsync;
    (* IOB="FALSE" *) reg flag_input_href;
    always @(posedge pclk) begin
        reg_input_data <= cam_data;
        flag_input_vsync <= cam_vsync;
        flag_input_href <= cam_href;
    end
    wire vsync_a = VSYNC_ACTIVE_HIGH ? flag_input_vsync : ~flag_input_vsync;
    wire href_a  = HREF_ACTIVE_HIGH  ? flag_input_href  : ~flag_input_href;

    reg  vsync_d, href_d;
    reg  byte_phase;
    reg  [7:0] first_byte;
    reg  de_d;

    assign frame_start = ~vsync_a & vsync_d;   // 下降沿(有效→无效)
    assign line_start  =  href_a & ~href_d;    // 上升沿
    assign de_wide     = de | de_d;            // 高电平覆盖完整像素周期(2 PCLK)

    // 两种字节序都生成, 综合器自动裁剪未用的一路
    wire [4:0] r5 = RGB565_BYTE_ORDER ? reg_input_data[7:3]     : first_byte[7:3];
    wire [5:0] g6 = RGB565_BYTE_ORDER ? {reg_input_data[2:0], first_byte[7:5]}
                                      : {first_byte[2:0], reg_input_data[7:5]};
    wire [4:0] b5 = RGB565_BYTE_ORDER ? first_byte[4:0]   : reg_input_data[4:0];

    // 5/6/5 位扩到 8 位: 高位复制低位
    wire [23:0] rgb888 = { {r5, r5[4:2]}, {g6, g6[5:4]}, {b5, b5[4:2]} };

    always @(posedge pclk) begin
        vsync_d <= vsync_a;
        href_d  <= href_a;
        de_d    <= de;

        if (href_a) begin
            if (!byte_phase) begin
                first_byte <= reg_input_data; // 高字节先到
                byte_phase <= 1'b1;
                de         <= 1'b0;
            end else begin
                byte_phase <= 1'b0;
                de         <= 1'b1;          // 凑齐 2 字节, 输出一个像素
                rgb        <= rgb888;
            end
        end else begin
            de         <= 1'b0;
            byte_phase <= 1'b0;
        end
    end
endmodule
