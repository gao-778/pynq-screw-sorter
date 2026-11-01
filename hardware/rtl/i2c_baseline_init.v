// ============================================================================
// i2c_init_master.v — SCCB(I2C) 主控 + ROM 表自动初始化
//
// 上电延时后自动把 ov5640_init_rom 里的整张寄存器表写入摄像头
// (每条: START, 0x78, regH, regL, val, STOP), 全程无需软件参与——
// 因此 HDMI 直出在 Linux/Jupyter 完全不参与的情况下也能独立工作。
//
// 电气: SCL/SDA 用 IOBUF 做"开漏"(只会拉低/释放), 依赖 XDC 里
//       PULLUP true 内部弱上拉; 手头没有外部 4.7kΩ 时的标准兜底。
//       若 NACK 很多, 把 SCL_HZ 参数降到 50_000。
// ============================================================================
module i2c_baseline_init #(
    parameter integer CLK_FREQ       = 100_000_000, // 驱动时钟频率
    parameter integer SCL_HZ         = 100_000,     // SCCB 时钟(弱上拉下建议 ≤100k)
    parameter integer START_DELAY_MS = 100,         // 上电到开始配置的延时
    parameter         SIM_FAST       = 0            // 仿真提速(延时按微秒算)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        restart,    // 单拍脉冲: 重新跑一遍初始化表
    input  wire [31:0]  gpio_control, // Runtime open-drain controls after ROM initialization.
    output wire [2:0]   sensor_status,
    inout  wire        scl,
    inout  wire        sda,
    output reg         init_done,  // 整表写完(含最后 30ms 等待)
    output reg  [7:0]  nack_cnt    // 无应答累计(诊断用)
);
    localparam integer QUARTER_TICKS = CLK_FREQ / (4 * SCL_HZ); // 1/4 位周期
    localparam integer START_TICKS   = START_DELAY_MS * (CLK_FREQ / 1000);

    // ---------------- ROM ----------------
    wire [15:0] rom_reg;
    wire [7:0]  rom_val;
    wire        rom_delay, rom_end;
    reg  [8:0]  rom_idx;
    ov5640_baseline_rom #(.SIM_FAST(SIM_FAST)) u_rom (.addr(rom_idx), .o_reg(rom_reg), .o_val(rom_val),
                           .o_delay(rom_delay), .o_end(rom_end));

    // ---------------- 节拍 ----------------
    reg [31:0] tick_cnt;
    reg [1:0]  qph;                  // 0..3 四分之一位相位
    wire       qtick = (tick_cnt == QUARTER_TICKS - 1);
    // 所有状态迁移只发生在 (qtick && qph==3), 保证相位对齐:
    // 每个状态从 qph==0 开始, 各 qph 的动作与 SCL 电平严格对应

    // ---------------- 状态机 ----------------
    localparam [3:0] S_WAIT = 4'd0,   // 上电延时
                     S_CHECK= 4'd1,   // 查表项类型
                     S_START= 4'd2,   // 起始条件
                     S_BIT  = 4'd3,   // 发 8 位
                     S_ACK  = 4'd4,   // 第 9 位应答
                     S_STOP = 4'd5,   // 停止条件
                     S_GAP  = 4'd6,   // 条目间隙
                     S_DLY  = 4'd7,   // 延时表项
                     S_DONE = 4'd8;   // 完成
    reg [3:0]  state;
    reg [31:0] dly_cnt;              // 通用毫秒计数
    reg [2:0]  bit_idx;              // 当前位(7..0, MSB 先发)
    reg [1:0]  byte_idx;             // 事务内字节序号 0..3
    reg [7:0]  shifter;
    reg        scl_low, sda_low;     // 1=拉低, 0=释放

    wire scl_in, sda_in;
    // CPU changes lines at least10us apart; two control-clock flops settle first.
    (* ASYNC_REG="TRUE" *) reg [2:0] reg_host_meta;
    (* ASYNC_REG="TRUE" *) reg [2:0] reg_host_sync;
    wire flag_host_owner = init_done && reg_host_sync[0];
    wire flag_scl_low = flag_host_owner ? reg_host_sync[1] : scl_low;
    wire flag_sda_low = flag_host_owner ? reg_host_sync[2] : sda_low;
    assign sensor_status = {init_done,sda_in,scl_in};
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_host_meta <= 0;
            reg_host_sync <= 0;
        end else begin
            reg_host_meta <= gpio_control[18:16];
            reg_host_sync <= reg_host_meta;
        end
    end
    IOBUF u_scl_iob (.IO(scl), .I(1'b0), .T(~flag_scl_low), .O(scl_in));
    IOBUF u_sda_iob (.IO(sda), .I(1'b0), .T(~flag_sda_low), .O(sda_in));

    always @(posedge clk) begin
        if (!rst_n) begin
            tick_cnt <= 0; qph <= 0; state <= S_WAIT; dly_cnt <= 0;
            rom_idx <= 0; bit_idx <= 0; byte_idx <= 0; shifter <= 0;
            init_done <= 1'b0; nack_cnt <= 0;
            scl_low <= 1'b1; sda_low <= 1'b1;
        end else begin
            // 四分位节拍
            if (tick_cnt == QUARTER_TICKS - 1) begin
                tick_cnt <= 0;
                qph <= (qph == 2'd3) ? 2'd0 : qph + 2'd1;
            end else begin
                tick_cnt <= tick_cnt + 32'd1;
            end

            // 软件重触发
            if (restart) begin
                state <= S_WAIT; dly_cnt <= 0; rom_idx <= 0;
                init_done <= 1'b0; nack_cnt <= 0;
                scl_low <= 1'b1; sda_low <= 1'b1;
            end else begin
                case (state)
                // ---------------- 上电延时 ----------------
                S_WAIT: begin
                    scl_low <= 1'b0; sda_low <= 1'b0;      // 总线释放
                    if (dly_cnt >= START_TICKS) begin
                        dly_cnt <= 0; rom_idx <= 0;
                        state <= S_CHECK;
                    end else dly_cnt <= dly_cnt + 32'd1;
                end
                // ---------------- 查表 ----------------
                S_CHECK: begin
                    if (qtick && qph == 2'd3) begin
                        if (rom_end) begin
                            state <= S_DONE;
                        end else if (rom_delay) begin
                            dly_cnt <= 0;
                            state <= S_DLY;
                        end else begin
                            shifter  <= 8'h78;             // 8 位写地址(0x3C<<1)
                            bit_idx  <= 3'd7;
                            byte_idx <= 2'd0;
                            scl_low  <= 1'b1;              // 都拉低, 从空闲进入
                            sda_low  <= 1'b1;
                            state    <= S_START;
                        end
                    end
                end
                // ---------------- 起始条件 ----------------
                // ph0: SCL 低, 释放 SDA      ph1: SCL 升
                // ph2: SDA 降(SCL 高)=START  ph3: SCL 降 + 摆好 bit7
                S_START: if (qtick) begin
                    case (qph)
                    2'd0: sda_low <= 1'b0;
                    2'd1: scl_low <= 1'b0;
                    2'd2: sda_low <= 1'b1;
                    2'd3: begin
                        scl_low <= 1'b1;
                        sda_low <= ~shifter[3'd7];
                        state   <= S_BIT;
                    end
                    endcase
                end
                // ---------------- 8 个数据位(MSB 先) ----------------
                // ph0: SCL 升(采样)  ph2: SCL 降  ph3: 换下一位数据
                S_BIT: if (qtick) begin
                    case (qph)
                    2'd0: scl_low <= 1'b0;
                    2'd2: scl_low <= 1'b1;
                    2'd3: begin
                        if (bit_idx == 3'd0) begin
                            sda_low <= 1'b0;               // 释放 SDA 给从机应答
                            state   <= S_ACK;
                        end else begin
                            bit_idx <= bit_idx - 3'd1;
                            sda_low <= ~shifter[bit_idx - 3'd1];
                        end
                    end
                    endcase
                end
                // ---------------- 应答位 ----------------
                // ph0: SCL 升   ph1: 采样(高=NACK)
                // ph2: SCL 降   ph3: 装下一字节或转 STOP
                S_ACK: if (qtick) begin
                    case (qph)
                    2'd0: scl_low <= 1'b0;
                    2'd1: if (sda_in) nack_cnt <= nack_cnt + 8'd1;
                    2'd2: scl_low <= 1'b1;
                    2'd3: begin
                        if (byte_idx == 2'd3) begin
                            sda_low <= 1'b1;               // STOP 预置: SCL 低时拉低 SDA
                            state   <= S_STOP;
                        end else begin
                            case (byte_idx)
                            2'd0: begin shifter <= rom_reg[15:8]; sda_low <= ~rom_reg[15]; end
                            2'd1: begin shifter <= rom_reg[7:0];  sda_low <= ~rom_reg[7];  end
                            default: begin shifter <= rom_val;    sda_low <= ~rom_val[7];  end
                            endcase
                            byte_idx <= byte_idx + 2'd1;
                            bit_idx  <= 3'd7;
                            state    <= S_BIT;
                        end
                    end
                    endcase
                end
                // ---------------- 停止条件 ----------------
                // ph0: SCL 升(SDA 低)  ph2: SDA 升(SCL 高)=STOP
                S_STOP: if (qtick) begin
                    case (qph)
                    2'd0: scl_low <= 1'b0;
                    2'd2: sda_low <= 1'b0;
                    2'd3: state <= S_GAP;
                    endcase
                end
                // ---------------- 条目间隙 ----------------
                S_GAP: begin
                    if (qtick && qph == 2'd3) begin
                        rom_idx <= rom_idx + 9'd1;
                        state   <= S_CHECK;
                    end
                end
                // ---------------- 毫秒延时表项 ----------------
                S_DLY: begin
                    if (dly_cnt >= (rom_val * (CLK_FREQ / 1000)) - 1 || rom_val == 8'd0) begin
                        dly_cnt <= 0;
                        rom_idx <= rom_idx + 9'd1;
                        state   <= S_CHECK;
                    end else dly_cnt <= dly_cnt + 32'd1;
                end
                // ---------------- 完成 ----------------
                S_DONE: begin
                    scl_low   <= 1'b0;
                    sda_low   <= 1'b0;
                    init_done <= 1'b1;
                end
                endcase
            end
        end
    end
endmodule

