// Per-frame integer gray histogram; contract CENTER8_P90_SPREAD3_CLAMP40_220_V1.
// One outstanding frame read. The owning core must keep this DDR frame frozen.
module frame_adaptive_threshold #(
    parameter integer C_WIDTH = 1280,
    parameter integer C_HEIGHT = 960,
    parameter integer C_STEP = 8,
    parameter integer C_OFFSET = 4
) (
    input wire i_clk,
    input wire i_rstn,
    input wire i_start,
    input wire i_abort,
    input wire [7:0] i_fallback_threshold,
    output wire [20:0] o_frame_address,
    output wire o_frame_enable,
    input wire [7:0] i_frame_data,
    input wire i_frame_valid,
    input wire i_frame_error,
    output reg [7:0] o_threshold,
    output reg [7:0] o_p50,
    output reg [7:0] o_p90,
    output reg [15:0] o_samples,
    output wire o_busy,
    output reg o_done,
    output reg o_error
);

    localparam integer C_COLUMNS = (C_WIDTH - 1 - C_OFFSET) / C_STEP + 1;
    localparam integer C_ROWS = (C_HEIGHT - 1 - C_OFFSET) / C_STEP + 1;
    localparam integer C_SAMPLES = C_COLUMNS * C_ROWS;
    localparam [16:0] C_TARGET50 = (C_SAMPLES + 1) / 2;
    localparam [16:0] C_TARGET90 = (9 * C_SAMPLES + 9) / 10;
    localparam [20:0] C_FIRST_ADDRESS = C_OFFSET * C_WIDTH + C_OFFSET;
    localparam [20:0] C_ROW_STRIDE = C_STEP * C_WIDTH;
    localparam [20:0] C_COLUMN_STRIDE = C_STEP;
    localparam [15:0] C_LAST_COLUMN = C_COLUMNS - 1;
    localparam [15:0] C_LAST_ROW = C_ROWS - 1;

    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_CLEAR = 4'd1;
    localparam [3:0] ST_FRAME_READ = 4'd2;
    localparam [3:0] ST_HIST_READ = 4'd3;
    localparam [3:0] ST_HIST_WRITE = 4'd4;
    localparam [3:0] ST_SCAN_READ = 4'd5;
    localparam [3:0] ST_SCAN_SUM = 4'd6;
    localparam [3:0] ST_MARGIN = 4'd7;
    localparam [3:0] ST_ADD = 4'd8;
    localparam [3:0] ST_CLAMP = 4'd9;
    localparam [3:0] ST_DONE = 4'd10;

    reg [3:0] reg_state;
    // The small 4-Kbit histogram has one synchronous read and one write.
    (* ram_style = "distributed" *) reg [15:0] mem_histogram [0:255];
    reg [7:0] reg_hist_index;
    reg [15:0] reg_hist_count;
    reg [15:0] reg_column;
    reg [15:0] reg_row;
    reg [20:0] reg_row_address;
    reg [20:0] reg_address;
    reg [16:0] reg_cumulative;
    reg reg_found50;
    reg [9:0] reg_margin;
    reg [10:0] reg_raw_threshold;
    wire [16:0] wire_next_sum = reg_cumulative + {1'b0, reg_hist_count};
    wire [8:0] wire_spread = {1'b0, o_p90} - {1'b0, o_p50};
    wire [9:0] wire_triple_spread = {wire_spread, 1'b0} + {1'b0, wire_spread};

    assign o_frame_address = reg_address;
    assign o_frame_enable = (reg_state == ST_FRAME_READ) && !i_abort;
    assign o_busy = reg_state != ST_IDLE;

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            reg_state <= ST_IDLE;
            reg_hist_index <= 8'd0;
            reg_hist_count <= 16'd0;
            reg_column <= 16'd0;
            reg_row <= 16'd0;
            reg_row_address <= C_FIRST_ADDRESS;
            reg_address <= C_FIRST_ADDRESS;
            reg_cumulative <= 17'd0;
            reg_found50 <= 1'b0;
            reg_margin <= 10'd0;
            reg_raw_threshold <= 11'd0;
            o_threshold <= 8'd40;
            o_p50 <= 8'd0;
            o_p90 <= 8'd0;
            o_samples <= 16'd0;
            o_done <= 1'b0;
            o_error <= 1'b0;
        end else begin
            o_done <= 1'b0;
            if (i_abort) begin
                reg_state <= ST_IDLE;
            end else begin
                case (reg_state)
                    ST_IDLE: begin
                        if (i_start) begin
                            reg_hist_index <= 8'd0;
                            reg_column <= 16'd0;
                            reg_row <= 16'd0;
                            reg_row_address <= C_FIRST_ADDRESS;
                            reg_address <= C_FIRST_ADDRESS;
                            reg_cumulative <= 17'd0;
                            reg_found50 <= 1'b0;
                            o_threshold <= i_fallback_threshold;
                            o_p50 <= 8'd0;
                            o_p90 <= 8'd0;
                            o_samples <= 16'd0;
                            o_error <= 1'b0;
                            reg_state <= ST_CLEAR;
                        end
                    end
                    ST_CLEAR: begin
                        mem_histogram[reg_hist_index] <= 16'd0;
                        if (reg_hist_index == 8'd255) begin
                            reg_state <= ST_FRAME_READ;
                        end else begin
                            reg_hist_index <= reg_hist_index + 8'd1;
                        end
                    end
                    ST_FRAME_READ: begin
                        if (i_frame_error) begin
                            o_error <= 1'b1;
                            reg_state <= ST_DONE;
                        end else if (i_frame_valid) begin
                            reg_hist_index <= i_frame_data;
                            o_samples <= o_samples + 16'd1;
                            reg_state <= ST_HIST_READ;
                        end
                    end
                    ST_HIST_READ: begin
                        reg_hist_count <= mem_histogram[reg_hist_index];
                        reg_state <= ST_HIST_WRITE;
                    end
                    ST_HIST_WRITE: begin
                        mem_histogram[reg_hist_index] <= reg_hist_count + 16'd1;
                        if (reg_column == C_LAST_COLUMN) begin
                            if (reg_row == C_LAST_ROW) begin
                                reg_hist_index <= 8'd0;
                                reg_state <= ST_SCAN_READ;
                            end else begin
                                reg_row <= reg_row + 16'd1;
                                reg_column <= 16'd0;
                                reg_row_address <= reg_row_address + C_ROW_STRIDE;
                                reg_address <= reg_row_address + C_ROW_STRIDE;
                                reg_state <= ST_FRAME_READ;
                            end
                        end else begin
                            reg_column <= reg_column + 16'd1;
                            reg_address <= reg_address + C_COLUMN_STRIDE;
                            reg_state <= ST_FRAME_READ;
                        end
                    end
                    ST_SCAN_READ: begin
                        reg_hist_count <= mem_histogram[reg_hist_index];
                        reg_state <= ST_SCAN_SUM;
                    end
                    ST_SCAN_SUM: begin
                        reg_cumulative <= wire_next_sum;
                        if (!reg_found50 && wire_next_sum >= C_TARGET50) begin
                            o_p50 <= reg_hist_index;
                            reg_found50 <= 1'b1;
                        end
                        if (wire_next_sum >= C_TARGET90) begin
                            o_p90 <= reg_hist_index;
                            reg_state <= ST_MARGIN;
                        end else begin
                            reg_hist_index <= reg_hist_index + 8'd1;
                            reg_state <= ST_SCAN_READ;
                        end
                    end
                    ST_MARGIN: begin
                        reg_margin <= wire_triple_spread < 10'd8 ? 10'd8 : wire_triple_spread;
                        reg_state <= ST_ADD;
                    end
                    ST_ADD: begin
                        reg_raw_threshold <= {3'd0, o_p90} + {1'b0, reg_margin};
                        reg_state <= ST_CLAMP;
                    end
                    ST_CLAMP: begin
                        if (reg_raw_threshold < 11'd40) begin
                            o_threshold <= 8'd40;
                        end else if (reg_raw_threshold > 11'd220) begin
                            o_threshold <= 8'd220;
                        end else begin
                            o_threshold <= reg_raw_threshold[7:0];
                        end
                        reg_state <= ST_DONE;
                    end
                    ST_DONE: begin
                        o_done <= 1'b1;
                        reg_state <= ST_IDLE;
                    end
                    default: begin
                        o_error <= 1'b1;
                        reg_state <= ST_DONE;
                    end
                endcase
            end
        end
    end
endmodule
