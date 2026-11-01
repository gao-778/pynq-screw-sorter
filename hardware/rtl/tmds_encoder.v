// ============================================================================
// tmds_encoder.v — TMDS(DVI/HDMI) 8b→10b 编码器 (单通道)
//
// 算法依据 Digital Visual Interface Revision 1.0, Page 29:
//   第一级: 转换最小化(XOR/XNOR 链, 减少跳变沿)
//   第二级: 直流平衡(可选反转 + 失衡计数 cnt)
//   消隐期: 编码 4 个控制符号(携带 HSYNC/VSYNC)
// 移植自 Hirosh Dabui 的开源实现(ISC 许可, 基于同一规范页),
// 每个通道例化一个: 通道0(蓝)还承载行/场同步控制位。
// ============================================================================
// 原实现版权声明 (依据 ISC 许可保留):
// tmds_encode implementation (c) 2020 Hirosh Dabui <hirosh@dabui.de>
// based on Digital Visual Interface Revision 1.0, Page 29
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided this notice appears
// in all copies.
// ============================================================================
module tmds_encoder(
    input  wire       clk,     // 像素时钟
    input  wire       DE,      // 数据使能(高=视频有效期, 低=消隐/控制期)
    input  wire [7:0] D,       // 该通道 8 位数据
    input  wire       C1,      // 控制位1(场同步 VSYNC)
    input  wire       C0,      // 控制位0(行同步 HSYNC)
    output reg  [9:0] q_out    // 10 位 TMDS 编码输出(LSB 先串行发送)
);
    // ---- 1 的个数 / 0 的个数 ----
    function [3:0] N0;
        input [7:0] d;
        integer i;
        begin
            N0 = 0;
            for (i = 0; i < 8; i = i + 1)
                N0 = N0 + !d[i];
        end
    endfunction

    function [3:0] N1;
        input [7:0] d;
        integer i;
        begin
            N1 = 0;
            for (i = 0; i < 8; i = i + 1)
                N1 = N1 + d[i];
        end
    endfunction

    reg signed [7:0] cnt_prev = 0;
    reg signed [7:0] cnt      = 0;
    reg        [8:0] q_m;

    // ---- 第一级: 转换最小化(组合) ----
    always @(*) begin
        if ((N1(D) > 4) | ((N1(D) == 4) & (D[0] == 1'b0))) begin
            // 多数位为 1 → 用 XNOR 链, 输出以 1 为主
            q_m[0] = D[0];
            q_m[1] = q_m[0] ~^ D[1];
            q_m[2] = q_m[1] ~^ D[2];
            q_m[3] = q_m[2] ~^ D[3];
            q_m[4] = q_m[3] ~^ D[4];
            q_m[5] = q_m[4] ~^ D[5];
            q_m[6] = q_m[5] ~^ D[6];
            q_m[7] = q_m[6] ~^ D[7];
            q_m[8] = 1'b0;
        end else begin
            // 多数位为 0 → 用 XOR 链, 输出以 0 为主
            q_m[0] = D[0];
            q_m[1] = q_m[0] ^ D[1];
            q_m[2] = q_m[1] ^ D[2];
            q_m[3] = q_m[2] ^ D[3];
            q_m[4] = q_m[3] ^ D[4];
            q_m[5] = q_m[4] ^ D[5];
            q_m[6] = q_m[5] ^ D[6];
            q_m[7] = q_m[6] ^ D[7];
            q_m[8] = 1'b1;
        end
    end

    // ---- 第二级: 直流平衡 + 控制 symbol(时序) ----
    always @(posedge clk) begin
        if (DE) begin
            if ((cnt_prev == 0) | (N1(q_m[7:0]) == N0(q_m[7:0]))) begin
                // 失衡为 0 或 q_m 本身均衡: 按 q_m[8] 决定是否反转
                q_out[9]   <= ~q_m[8];
                q_out[8]   <=  q_m[8];
                q_out[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (q_m[8] == 1'b0)
                    cnt = cnt_prev + (N0(q_m[7:0]) - N1(q_m[7:0]));
                else
                    cnt = cnt_prev + (N1(q_m[7:0]) - N0(q_m[7:0]));
            end else if ((cnt_prev > 0 & (N1(q_m[7:0]) > N0(q_m[7:0]))) |
                         (cnt_prev < 0 & (N0(q_m[7:0]) > N1(q_m[7:0])))) begin
                // 发出去会加剧失衡 → 反转
                q_out[9]   <= 1'b1;
                q_out[8]   <= q_m[8];
                q_out[7:0] <= ~q_m[7:0];
                cnt = cnt_prev + 2 * q_m[8] + (N0(q_m[7:0]) - N1(q_m[7:0]));
            end else begin
                // 发出去会收敛失衡 → 不反转
                q_out[9]   <= 1'b0;
                q_out[8]   <= q_m[8];
                q_out[7:0] <= q_m[7:0];
                cnt = cnt_prev - {~q_m[8], 1'b0} + (N1(q_m[7:0]) - N0(q_m[7:0]));
            end
        end else begin
            // 消隐期: 控制 symbol 编码 {C1,C0}
            cnt = 0;
            case ({C1, C0})
                2'b00: q_out <= 10'b1101010100;
                2'b01: q_out <= 10'b0010101011;
                2'b10: q_out <= 10'b0101010100;
                2'b11: q_out <= 10'b1010101011;
            endcase
        end
        cnt_prev <= cnt;
    end
endmodule
