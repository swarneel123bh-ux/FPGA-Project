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
//
// [Claude pipelining 11 Nov] The one-tap-per-clock datapath (128-way read, 24x24 multiply, 64-bit
// round/add, saturate, write in one cycle) needed ~25 ns and failed timing at 100 MHz by
// 15 ns. Each tap now takes a few clocks with a register between steps: 4 clocks per
// estimate tap, 6 per update tap, ~1290 clocks per sample (budget 2083). The arithmetic
// and its order are unchanged, so results stay bit-exact with the Python model.
// round_shift64 uses an equivalent single-adder form. Lines changed or added carry the tag.
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
    localparam [1:0] ST_EST_FIN = 2'd3;   // [Claude pipelining 11 Nov]

    reg [1:0] state;
    reg [ADDR_W-1:0] tap_index;
    reg signed [23:0] shat_mem [0:M-1];
    reg signed [23:0] probe_hist [0:M-1];
    reg signed [23:0] measured_sample;
    reg signed [23:0] epsilon_reg;
    reg signed [63:0] estimate_accum;
    reg [15:0] elapsed_counter;
    // [Claude pipelining 11 Nov] BEGIN pipeline registers
    reg [2:0] phase;                     // step within the current tap
    reg signed [23:0] op_a_r, op_b_r;    // registered multiplier operands
    reg signed [47:0] prod_r, prod_r2;   // two product registers (map into DSP M/P regs)
    reg signed [23:0] shat_old_r;        // coefficient read for the update tap
    reg signed [63:0] round_r;           // rounded estimate / update delta
    reg signed [63:0] shat_next_r;       // updated coefficient before saturation
    reg signed [23:0] estimate_r;
    // [Claude pipelining 11 Nov] END

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
            // [Claude pipelining 11 Nov] Same result as the original (round half away from zero):
            // negative values add half-1 instead of negate/add/negate, so one adder.
            // Checked equal on 2.4M random cases for |value| < 2^62.
            magnitude = 64'sd0; rounded_magnitude = 64'sd0;
            if (shift <= 0)
                round_shift64 = value <<< (-shift);
            else
                round_shift64 = (value + ((64'sd1 <<< (shift - 1)) - (value[63] ? 64'sd1 : 64'sd0))) >>> shift;
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

    // [Claude pipelining 11 Nov] BEGIN datapath: one shared multiplier on registered operands.
    wire signed [63:0] prod_ext = {{16{prod_r2[47]}}, prod_r2};
    wire signed [63:0] epsilon_wide =
        $signed({{40{measured_sample[23]}}, measured_sample}) -
        $signed({{40{estimate_r[23]}}, estimate_r});
    wire signed [23:0] epsilon_next = sat24(epsilon_wide);
    // Q1.23 * Q1.23 -> Q2.46; convert to Q2.22 and apply mu_s=2^-6:
    // total right shift = 46 - 22 + 6 = 30.
    // [Claude pipelining 11 Nov] END

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
            phase            <= 3'd0;   // [Claude pipelining 11 Nov]
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
            phase            <= 3'd0;   // [Claude pipelining 11 Nov]
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
                        phase <= 3'd0;   // [Claude pipelining 11 Nov]
                        busy <= 1'b1;
                        state <= ST_EST;
                    end
                end

                // [Claude pipelining 11 Nov] BEGIN multi-clock estimate and update passes
                ST_EST: begin
                    case (phase)
                        3'd0: begin   // read operands
                            op_a_r <= shat_mem[tap_index];
                            op_b_r <= probe_hist[tap_index];
                            phase  <= 3'd1;
                        end
                        3'd1: begin prod_r  <= op_a_r * op_b_r; phase <= 3'd2; end
                        3'd2: begin prod_r2 <= prod_r;          phase <= 3'd3; end
                        default: begin   // accumulate
                            estimate_accum <= estimate_accum + prod_ext;
                            phase <= 3'd0;
                            if (tap_index == M-1) begin
                                tap_index <= {ADDR_W{1'b0}};
                                state     <= ST_EST_FIN;
                            end else begin
                                tap_index <= tap_index + 1'b1;
                            end
                        end
                    endcase
                end

                ST_EST_FIN: begin
                    case (phase)
                        3'd0: begin round_r <= round_shift64(estimate_accum, 22); phase <= 3'd1; end
                        3'd1: begin estimate_r <= sat24(round_r);                  phase <= 3'd2; end
                        default: begin
                            epsilon_reg    <= epsilon_next;
                            id_error       <= epsilon_next;
                            id_error_valid <= 1'b1;
                            tap_index      <= {ADDR_W{1'b0}};
                            phase          <= 3'd0;
                            state          <= ST_UPDATE;
                        end
                    endcase
                end

                ST_UPDATE: begin
                    case (phase)
                        3'd0: begin   // read operands
                            op_a_r     <= epsilon_reg;
                            op_b_r     <= probe_hist[tap_index];
                            shat_old_r <= shat_mem[tap_index];
                            phase      <= 3'd1;
                        end
                        3'd1: begin prod_r  <= op_a_r * op_b_r; phase <= 3'd2; end
                        3'd2: begin prod_r2 <= prod_r;          phase <= 3'd3; end
                        3'd3: begin round_r <= round_shift64(prod_ext, 24 + MU_S_SHIFT); phase <= 3'd4; end
                        3'd4: begin
                            shat_next_r <= {{40{shat_old_r[23]}}, shat_old_r} + round_r;
                            phase <= 3'd5;
                        end
                        default: begin   // saturate and write back
                            shat_mem[tap_index] <= sat24(shat_next_r);
                            if ((shat_next_r > 64'sd8388607) ||
                                (shat_next_r < -64'sd8388608))
                                coeff_overflow <= 1'b1;
                            phase <= 3'd0;
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
                    endcase
                end
                // [Claude pipelining 11 Nov] END

                default: begin
                    state <= ST_IDLE;
                    busy <= 1'b0;
                    tap_index <= {ADDR_W{1'b0}};
                end
            endcase
        end
    end
endmodule
