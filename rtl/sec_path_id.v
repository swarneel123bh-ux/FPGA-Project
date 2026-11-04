`timescale 1ns / 1ps
// Member C: serial, fixed-point LMS secondary-path identifier.
//
// It owns shat_mem[0:M-1] and exposes a synchronous read port compatible with
// Member B's fxlms.v:
//   fxlms.shat_addr  -> sec_path_id.shat_addr
//   sec_path_id.shat_data -> fxlms.shat_data
// shat_data has exactly one clock of read latency.
//
// Formats match Member B's fixed.py:
//   probe/measured/id_error : signed 24-bit Q1.23
//   shat coefficients      : signed 24-bit Q2.22
//   accumulator            : signed 64-bit
//   mu_s                   : 2**(-MU_S_SHIFT), default 2**-6
//
// For each accepted sample, the engine makes one 128-tap estimate pass and
// one 128-tap coefficient-update pass. At 100 MHz this is comfortably faster
// than a 48 kHz sample stream (256 clocks versus about 2083 clocks/sample).
module sec_path_id #(
    parameter integer M = 128,
    parameter integer MU_S_SHIFT = 6,
    parameter integer ADDR_W = (M <= 2) ? 1 : $clog2(M)
)(
    input  wire                   clk,
    input  wire                   rst,              // active-high synchronous reset
    input  wire                   coeff_clear,      // clear shat and probe history
    input  wire                   calibrate_enable,
    input  wire                   sample_tick,
    input  wire signed [23:0]     probe_in,         // Q1.23
    input  wire signed [23:0]     measured_in,      // Q1.23, aligned to probe sample

    output wire                   ready,
    output reg                    busy,
    output reg                    done,             // one-clock pulse after coefficient update
    output reg                    id_error_valid,   // one-clock pulse for epsilon sample
    output reg signed [23:0]      id_error,         // epsilon = measured - estimated
    output reg [31:0]             sample_count,
    output reg [15:0]             last_id_cycles,
    output reg                    coeff_overflow,
    output reg                    sample_overrun,

    // Shared coefficient-memory read port for Member B's fxlms.v.
    input  wire [ADDR_W-1:0]      shat_addr,
    output reg signed [23:0]      shat_data
);
    localparam [1:0] ST_IDLE   = 2'd0;
    localparam [1:0] ST_EST    = 2'd1;
    localparam [1:0] ST_UPDATE = 2'd2;

    reg [1:0] state;
    reg [ADDR_W-1:0] tap_index;
    reg signed [23:0] shat_mem [0:M-1];
    reg signed [23:0] probe_hist [0:M-1];
    reg signed [23:0] measured_sample;
    reg signed [23:0] epsilon_reg;
    reg signed [63:0] estimate_accum;
    reg [15:0] elapsed_counter;

    integer i;

    // The synchronous read port is intentionally independent of the LMS
    // engine's internal coefficient update address.
    always @(posedge clk) begin
        if (rst)
            shat_data <= 24'sd0;
        else
            shat_data <= shat_mem[shat_addr];
    end

    assign ready = (state == ST_IDLE);

    function signed [63:0] round_shift64;
        input signed [63:0] value;
        input integer shift;
        reg signed [63:0] magnitude;
        reg signed [63:0] rounded_magnitude;
        begin
            if (shift <= 0) begin
                round_shift64 = value <<< (-shift);
            end else if (value >= 0) begin
                round_shift64 = (value + (64'sd1 <<< (shift - 1))) >>> shift;
            end else begin
                magnitude = -value;
                rounded_magnitude = (magnitude + (64'sd1 <<< (shift - 1))) >>> shift;
                round_shift64 = -rounded_magnitude;
            end
        end
    endfunction

    function signed [23:0] sat24;
        input signed [63:0] value;
        begin
            if (value > 64'sd8388607)
                sat24 = 24'sh7fffff;
            else if (value < -64'sd8388608)
                sat24 = 24'sh800000;
            else
                sat24 = value[23:0];
        end
    endfunction

    wire signed [47:0] estimate_a_ext =
        {{24{shat_mem[tap_index][23]}}, shat_mem[tap_index]};
    wire signed [47:0] estimate_b_ext =
        {{24{probe_hist[tap_index][23]}}, probe_hist[tap_index]};
    wire signed [47:0] estimate_product = estimate_a_ext * estimate_b_ext;
    wire signed [63:0] estimate_product_ext =
        {{16{estimate_product[47]}}, estimate_product};
    wire signed [63:0] estimate_sum_next = estimate_accum + estimate_product_ext;
    wire signed [23:0] estimate_next = sat24(round_shift64(estimate_sum_next, 22));
    wire signed [63:0] epsilon_wide =
        $signed({{40{measured_sample[23]}}, measured_sample}) -
        $signed({{40{estimate_next[23]}}, estimate_next});
    wire signed [23:0] epsilon_next = sat24(epsilon_wide);

    wire signed [47:0] update_a_ext = {{24{epsilon_reg[23]}}, epsilon_reg};
    wire signed [47:0] update_b_ext =
        {{24{probe_hist[tap_index][23]}}, probe_hist[tap_index]};
    wire signed [47:0] update_product = update_a_ext * update_b_ext;
    wire signed [63:0] update_product_ext = {{16{update_product[47]}}, update_product};
    // Q1.23 * Q1.23 -> Q2.46; convert to Q2.22 and apply mu_s=2^-6:
    // total right shift = 46 - 22 + 6 = 30.
    wire signed [63:0] delta_shat = round_shift64(update_product_ext, 24 + MU_S_SHIFT);
    wire signed [63:0] shat_old_ext =
        {{40{shat_mem[tap_index][23]}}, shat_mem[tap_index]};
    wire signed [63:0] shat_next_wide = shat_old_ext + delta_shat;

    always @(posedge clk) begin
        if (rst) begin
            state            <= ST_IDLE;
            tap_index        <= {ADDR_W{1'b0}};
            measured_sample  <= 24'sd0;
            epsilon_reg      <= 24'sd0;
            estimate_accum   <= 64'sd0;
            busy             <= 1'b0;
            done             <= 1'b0;
            id_error_valid   <= 1'b0;
            id_error         <= 24'sd0;
            sample_count     <= 32'd0;
            last_id_cycles   <= 16'd0;
            elapsed_counter  <= 16'd0;
            coeff_overflow   <= 1'b0;
            sample_overrun   <= 1'b0;
            for (i = 0; i < M; i = i + 1) begin
                shat_mem[i]  <= 24'sd0;
                probe_hist[i] <= 24'sd0;
            end
        end else if (coeff_clear) begin
            state            <= ST_IDLE;
            tap_index        <= {ADDR_W{1'b0}};
            measured_sample  <= 24'sd0;
            epsilon_reg      <= 24'sd0;
            estimate_accum   <= 64'sd0;
            busy             <= 1'b0;
            done             <= 1'b0;
            id_error_valid   <= 1'b0;
            id_error         <= 24'sd0;
            sample_count     <= 32'd0;
            last_id_cycles   <= 16'd0;
            elapsed_counter  <= 16'd0;
            coeff_overflow   <= 1'b0;
            sample_overrun   <= 1'b0;
            for (i = 0; i < M; i = i + 1) begin
                shat_mem[i]  <= 24'sd0;
                probe_hist[i] <= 24'sd0;
            end
        end else begin
            done           <= 1'b0;
            id_error_valid <= 1'b0;

            if (busy)
                elapsed_counter <= elapsed_counter + 1'b1;

            if (sample_tick && calibrate_enable && (state != ST_IDLE))
                sample_overrun <= 1'b1;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (sample_tick && calibrate_enable) begin
                        for (i = M-1; i > 0; i = i - 1)
                            probe_hist[i] <= probe_hist[i-1];
                        probe_hist[0] <= probe_in;
                        measured_sample <= measured_in;
                        tap_index <= {ADDR_W{1'b0}};
                        estimate_accum <= 64'sd0;
                        elapsed_counter <= 16'd0;
                        busy <= 1'b1;
                        state <= ST_EST;
                    end
                end

                ST_EST: begin
                    if (tap_index == M-1) begin
                        epsilon_reg    <= epsilon_next;
                        id_error       <= epsilon_next;
                        id_error_valid <= 1'b1;
                        tap_index      <= {ADDR_W{1'b0}};
                        state          <= ST_UPDATE;
                    end else begin
                        estimate_accum <= estimate_sum_next;
                        tap_index <= tap_index + 1'b1;
                    end
                end

                ST_UPDATE: begin
                    shat_mem[tap_index] <= sat24(shat_next_wide);
                    if ((shat_next_wide > 64'sd8388607) ||
                        (shat_next_wide < -64'sd8388608))
                        coeff_overflow <= 1'b1;

                    if (tap_index == M-1) begin
                        state <= ST_IDLE;
                        busy <= 1'b0;
                        done <= 1'b1;
                        sample_count <= sample_count + 1'b1;
                        last_id_cycles <= elapsed_counter + 1'b1;
                    end else begin
                        tap_index <= tap_index + 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy <= 1'b0;
                    tap_index <= {ADDR_W{1'b0}};
                end
            endcase
        end
    end
endmodule
