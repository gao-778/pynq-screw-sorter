 

module hdmi_serial #(
    parameter BIT_ORDER = 1'b0,   // 0: LSB 先发(规范); 1: MSB 先发(调试备选)
    parameter SIM_NO_SERDES = 0   // 仅仿真: 1=旁路 OSERDESE2/OBUFDS(行为级直出),
                                  //     避开串化器行为模型的天文事件量
)(
    input  wire       clk_5x,    // 5× 像素时钟(来自 MMCM, 与 clk_1x 同源相位对齐)
    input  wire       clk_1x,    // 像素时钟
    input  wire       rst,       // 高有效; MMCM 未锁定期间拉高, 输出静默
    input  wire [9:0] q_blue,    // 通道0(蓝, 含 HSYNC/VSYNC 控制)
    input  wire [9:0] q_green,   // 通道1(绿)
    input  wire [9:0] q_red,     // 通道2(红)
    output wire       hdmi_clk_p,
    output wire       hdmi_clk_n,
    output wire [2:0] hdmi_d_p,
    output wire [2:0] hdmi_d_n
);
    generate
        if (SIM_NO_SERDES) begin : g_sim_out
            // ---- 仿真旁路: 只验证 TMDS 编码字在变化, 不验证 10:1 串化 ----
            assign hdmi_clk_p = clk_1x;
            assign hdmi_clk_n = ~clk_1x;
            assign hdmi_d_p[0] = rst ? 1'b0 : (^q_blue  ^ clk_1x);
            assign hdmi_d_p[1] = rst ? 1'b0 : (^q_green ^ clk_1x);
            assign hdmi_d_p[2] = rst ? 1'b0 : (^q_red   ^ clk_1x);
            assign hdmi_d_n = ~hdmi_d_p;
        end else begin : g_real_serdes
            wire ser0, ser1, ser2;

            serializer_10_1 #(.BIT_ORDER(BIT_ORDER)) u_ch0
                (.clk_5x(clk_5x), .clk_1x(clk_1x), .rst(rst), .data(q_blue),  .ser(ser0));
            serializer_10_1 #(.BIT_ORDER(BIT_ORDER)) u_ch1
                (.clk_5x(clk_5x), .clk_1x(clk_1x), .rst(rst), .data(q_green), .ser(ser1));
            serializer_10_1 #(.BIT_ORDER(BIT_ORDER)) u_ch2
                (.clk_5x(clk_5x), .clk_1x(clk_1x), .rst(rst), .data(q_red),   .ser(ser2));

            OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) ob0
                (.I(ser0), .O(hdmi_d_p[0]), .OB(hdmi_d_n[0]));
            OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) ob1
                (.I(ser1), .O(hdmi_d_p[1]), .OB(hdmi_d_n[1]));
            OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) ob2
                (.I(ser2), .O(hdmi_d_p[2]), .OB(hdmi_d_n[2]));

             
            wire clk_ser;
            ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("ASYNC")) u_oddr (
                .Q(clk_ser), .C(clk_1x), .CE(1'b1),
                .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0));
            OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) obc
                (.I(clk_ser), .O(hdmi_clk_p), .OB(hdmi_clk_n));
        end
    endgenerate
endmodule

module serializer_10_1 #(
    parameter BIT_ORDER = 1'b0
)(
    input  wire       clk_5x,
    input  wire       clk_1x,
    input  wire       rst,
    input  wire [9:0] data,
    output wire       ser
);
    wire [9:0] d = BIT_ORDER ?
        {data[0], data[1], data[2], data[3], data[4],
         data[5], data[6], data[7], data[8], data[9]} : data;

    wire shift1, shift2;

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"),        // DDR: 双沿输出
        .DATA_RATE_TQ("DDR"),
        .DATA_WIDTH(10),             // 10:1 需主从级联
        .SERDES_MODE("MASTER"),
        .TRISTATE_WIDTH(1),
        .TBYTE_CTL("FALSE"),
        .TBYTE_SRC("FALSE")
    ) u_master (
        .CLK(clk_5x),                // 高速时钟(5×)
        .CLKDIV(clk_1x),             // 并行时钟(1×)
        .RST(rst), .OCE(1'b1),
        .D1(d[0]), .D2(d[1]), .D3(d[2]), .D4(d[3]),    
        .D5(d[4]), .D6(d[5]), .D7(d[6]), .D8(d[7]),
        .SHIFTIN1(shift1), .SHIFTIN2(shift2),
        .OQ(ser), .OFB(), .TQ(), .TFB(), .TBYTEOUT(),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0),
        .TCE(1'b0), .TBYTEIN(1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"),
        .DATA_RATE_TQ("DDR"),
        .DATA_WIDTH(10),
        .SERDES_MODE("SLAVE"),
        .TRISTATE_WIDTH(1),
        .TBYTE_CTL("FALSE"),
        .TBYTE_SRC("FALSE")
    ) u_slave (
        .CLK(clk_5x),
        .CLKDIV(clk_1x),
        .RST(rst), .OCE(1'b1),
        .D1(1'b0), .D2(1'b0),
        .D3(d[8]), .D4(d[9]),        // 从片 D3/D4 承载最后两位
        .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
        .SHIFTOUT1(shift1), .SHIFTOUT2(shift2),
        .OQ(), .OFB(), .TQ(), .TFB(), .TBYTEOUT(),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0),
        .TCE(1'b0), .TBYTEIN(1'b0)
    );
endmodule
