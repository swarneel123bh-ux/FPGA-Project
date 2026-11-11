`timescale 1ns / 1ps
// Group 16 — Member B: fixed-point FxLMS controller.
//
// Formats:
//   x_ref/e_err/y_anti/shat_data : signed 24-bit Q1.23/Q2.22 as appropriate
//   w_mem                       : signed 32-bit Q4.28
//   y accumulator               : signed 64-bit, product frac = 28+23 = 51
//   filtered-x accumulator      : signed 64-bit, product frac = 22+23 = 45
//   weight update               : e*xf is Q2.46; mu=2^-MU_SHIFT;
//                                convert to Q4.28 by rounded shift 18+MU_SHIFT
//
// Error convention is e = d + S*y, so weight update subtracts mu*e*x'.
// The shat RAM is synchronous, with exactly one clock of read latency.
//
// [Claude pipelining 11 Nov] The one-tap-per-clock MAC (64-way read, 32x24 multiply, 64-bit
// round/add, saturate, write in one cycle) needed ~25 ns and failed timing at 100 MHz by
// 15 ns. Each tap now takes a few clocks with a register between steps: 4 per output tap,
// 5 per filtered-x tap, 6 per weight update, ~1290 clocks per sample (budget 2083 at
// 48 kHz). The arithmetic and its order are unchanged, so results stay bit-exact with the
// Python model; y_anti still changes once per sample, before the next sample_tick.
// round_shift64 uses an equivalent single-adder form. Lines changed or added carry the tag.

module fxlms #(
    parameter integer L = 64,
    parameter integer M = 128,
    parameter integer MU_SHIFT = 7,
    parameter integer SHAT_ADDR_W = (M <= 2) ? 1 : $clog2(M),
    parameter signed [63:0] W_LIMIT = 64'sd402653184
)(
    input  wire               clk,
    input  wire               rst,          // active-high synchronous reset
    input  wire               sample_tick,
    input  wire               anc_en,
    input  wire               w_reset,
    input  wire signed [23:0] x_ref,
    input  wire signed [23:0] e_err,
    output reg  signed [23:0] y_anti,
    output wire [SHAT_ADDR_W-1:0] shat_addr,
    input  wire signed [23:0] shat_data,
    output reg                w_over
);
    localparam integer L_AW = (L <= 2) ? 1 : $clog2(L);
    localparam integer M_AW = SHAT_ADDR_W;

    localparam [2:0] ST_IDLE      = 3'd0;
    localparam [2:0] ST_Y_MAC     = 3'd1;
    localparam [2:0] ST_SHAT      = 3'd2;   // [Claude pipelining 11 Nov] was ST_SHAT_REQ/ST_SHAT_ACC
    localparam [2:0] ST_Y_FIN     = 3'd3;   // [Claude pipelining 11 Nov]
    localparam [2:0] ST_W_UPDATE  = 3'd4;
    localparam [2:0] ST_FINISH    = 3'd5;
    localparam [2:0] ST_X_FIN     = 3'd6;   // [Claude pipelining 11 Nov]

    reg [2:0] state;
    reg [L_AW-1:0] tap_index;
    reg [M_AW-1:0] shat_index;
    reg signed [23:0] x_hist [0:((L > M) ? L : M)-1];
    reg signed [23:0] xf_hist [0:L-1];
    reg signed [31:0] w_mem [0:L-1];
    reg signed [23:0] e_sample;
    reg signed [23:0] y_pending;
    reg signed [63:0] y_accum;
    reg signed [63:0] xf_accum;
    reg anc_en_sample;
    // [Claude pipelining 11 Nov] BEGIN pipeline registers
    reg [2:0] phase;                     // step within the current tap
    reg signed [31:0] op_a_r;            // registered multiplier operands
    reg signed [23:0] op_b_r;
    reg signed [55:0] prod_r, prod_r2;   // two product registers (map into DSP M/P regs)
    reg signed [31:0] w_old_r;           // weight read for the update tap
    reg signed [63:0] round_r;           // rounded sum / update delta
    reg signed [63:0] weight_next_r;     // updated weight before saturation
    // [Claude pipelining 11 Nov] END
    integer i;

    assign shat_addr = shat_index;

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

    function signed [31:0] sat32;
        input signed [63:0] value;
        begin
            if (value > 64'sd2147483647)
                sat32 = 32'sh7fffffff;
            else if (value < -64'sd2147483648)
                sat32 = 32'sh80000000;
            else
                sat32 = value[31:0];
        end
    endfunction

    // One shared signed multiplier, selected by the FSM. This implements the
    // project's time-shared MAC schedule: L output products, M filtered-x
    // products, and L weight-update products per sample.
    // [Claude pipelining 11 Nov] The operands are now registers (op_a_r/op_b_r, loaded by the FSM) and
    // the product goes through prod_r and prod_r2 before it is used.
    wire signed [63:0] mac_product_ext = {{8{prod_r2[55]}}, prod_r2};

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            phase <= 3'd0;   // [Claude pipelining 11 Nov]
            tap_index <= {L_AW{1'b0}};
            shat_index <= {M_AW{1'b0}};
            y_anti <= 24'sd0;
            e_sample <= 24'sd0;
            y_pending <= 24'sd0;
            y_accum <= 64'sd0;
            xf_accum <= 64'sd0;
            anc_en_sample <= 1'b0;
            w_over <= 1'b0;
            for (i = 0; i < L; i = i + 1) begin
                w_mem[i] <= 32'sd0;
                xf_hist[i] <= 24'sd0;
            end
            for (i = 0; i < ((L > M) ? L : M); i = i + 1)
                x_hist[i] <= 24'sd0;
        end else if (w_reset) begin
            // Clear adaptive state and delay lines before a fresh calibration.
            state <= ST_IDLE;
            phase <= 3'd0;   // [Claude pipelining 11 Nov]
            tap_index <= {L_AW{1'b0}};
            shat_index <= {M_AW{1'b0}};
            y_anti <= 24'sd0;
            e_sample <= 24'sd0;
            y_pending <= 24'sd0;
            y_accum <= 64'sd0;
            xf_accum <= 64'sd0;
            anc_en_sample <= 1'b0;
            w_over <= 1'b0;
            for (i = 0; i < L; i = i + 1) begin
                w_mem[i] <= 32'sd0;
                xf_hist[i] <= 24'sd0;
            end
            for (i = 0; i < ((L > M) ? L : M); i = i + 1)
                x_hist[i] <= 24'sd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (sample_tick) begin
                        // Current sample enters the reference history. This happens
                        // before ST_Y_MAC/ST_SHAT_REQ read the history next cycles.
                        for (i = ((L > M) ? L : M)-1; i > 0; i = i - 1)
                            x_hist[i] <= x_hist[i-1];
                        x_hist[0] <= x_ref;
                        e_sample <= e_err;
                        anc_en_sample <= anc_en;
                        tap_index <= {L_AW{1'b0}};
                        shat_index <= {M_AW{1'b0}};
                        y_accum <= 64'sd0;
                        xf_accum <= 64'sd0;
                        phase <= 3'd0;   // [Claude pipelining 11 Nov]
                        state <= ST_Y_MAC;
                    end
                end

                // [Claude pipelining 11 Nov] BEGIN multi-clock MAC passes
                ST_Y_MAC: begin
                    case (phase)
                        3'd0: begin   // read operands
                            op_a_r <= w_mem[tap_index];
                            op_b_r <= x_hist[tap_index];
                            phase  <= 3'd1;
                        end
                        3'd1: begin prod_r  <= op_a_r * op_b_r; phase <= 3'd2; end
                        3'd2: begin prod_r2 <= prod_r;          phase <= 3'd3; end
                        default: begin   // accumulate
                            y_accum <= y_accum + mac_product_ext;
                            phase <= 3'd0;
                            if (tap_index == L-1)
                                state <= ST_Y_FIN;
                            else
                                tap_index <= tap_index + 1'b1;
                        end
                    endcase
                end

                ST_Y_FIN: begin
                    if (phase == 3'd0) begin
                        round_r <= round_shift64(y_accum, 28);
                        phase <= 3'd1;
                    end else begin
                        y_pending <= sat24(round_r);
                        shat_index <= {M_AW{1'b0}};
                        xf_accum <= 64'sd0;
                        phase <= 3'd0;
                        state <= ST_SHAT;
                    end
                end

                // Phase 0 presents shat_addr to the external synchronous RAM;
                // phase 1 consumes shat_data one clock later.
                ST_SHAT: begin
                    case (phase)
                        3'd0: phase <= 3'd1;
                        3'd1: begin
                            op_a_r <= {{8{shat_data[23]}}, shat_data};
                            op_b_r <= x_hist[shat_index];
                            phase  <= 3'd2;
                        end
                        3'd2: begin prod_r  <= op_a_r * op_b_r; phase <= 3'd3; end
                        3'd3: begin prod_r2 <= prod_r;          phase <= 3'd4; end
                        default: begin   // accumulate
                            xf_accum <= xf_accum + mac_product_ext;
                            phase <= 3'd0;
                            if (shat_index == M-1)
                                state <= ST_X_FIN;
                            else
                                shat_index <= shat_index + 1'b1;
                        end
                    endcase
                end

                ST_X_FIN: begin
                    if (phase == 3'd0) begin
                        round_r <= round_shift64(xf_accum, 22);
                        phase <= 3'd1;
                    end else begin
                        // x_filtered is narrowed/saturated to signed Q1.23.
                        xf_hist[0] <= sat24(round_r);
                        for (i = L-1; i > 0; i = i - 1)
                            xf_hist[i] <= xf_hist[i-1];
                        tap_index <= {L_AW{1'b0}};
                        phase <= 3'd0;
                        state <= ST_W_UPDATE;
                    end
                end

                ST_W_UPDATE: begin
                    case (phase)
                        3'd0: begin   // read operands
                            op_a_r  <= {{8{e_sample[23]}}, e_sample};
                            op_b_r  <= xf_hist[tap_index];
                            w_old_r <= w_mem[tap_index];
                            phase   <= 3'd1;
                        end
                        3'd1: begin prod_r  <= op_a_r * op_b_r; phase <= 3'd2; end
                        3'd2: begin prod_r2 <= prod_r;          phase <= 3'd3; end
                        3'd3: begin round_r <= round_shift64(mac_product_ext, 18 + MU_SHIFT); phase <= 3'd4; end
                        3'd4: begin
                            weight_next_r <= {{32{w_old_r[31]}}, w_old_r} - round_r;
                            phase <= 3'd5;
                        end
                        default: begin   // saturate and write back
                            if (anc_en_sample) begin
                                w_mem[tap_index] <= sat32(weight_next_r);
                                if ((weight_next_r > W_LIMIT) || (weight_next_r < -W_LIMIT))
                                    w_over <= 1'b1;
                            end
                            phase <= 3'd0;
                            if (tap_index == L-1)
                                state <= ST_FINISH;
                            else
                                tap_index <= tap_index + 1'b1;
                        end
                    endcase
                end
                // [Claude pipelining 11 Nov] END

                ST_FINISH: begin
                    y_anti <= anc_en_sample ? y_pending : 24'sd0;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                    y_anti <= 24'sd0;
                end
            endcase
        end
    end
endmodule
