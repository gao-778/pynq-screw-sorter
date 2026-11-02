 

// 移植自 Hirosh Dabui 的开源实现(ISC 许可, 基于同一规范页),
 
 
// 原实现版权声明 (依据 ISC 许可保留):
// tmds_encode implementation (c) 2020 Hirosh Dabui <hirosh@dabui.de>
 
// Permission to use, copy, modify, and/or distribute this software for any

module tmds_encoder(
    input  wire       clk,      
    input  wire       DE,       
    input  wire [7:0] D,        
    input  wire       C1,       
    input  wire       C0,       
    output reg  [9:0] q_out     
);
     
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
