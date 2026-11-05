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
    localparam [2:0] ST_SHAT_REQ  = 3'd2;
    localparam [2:0] ST_SHAT_ACC  = 3'd3;
    localparam [2:0] ST_W_UPDATE  = 3'd4;
    localparam [2:0] ST_FINISH    = 3'd5;

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
    integer i;

    assign shat_addr = shat_index;

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
    reg signed [31:0] mac_a;
    reg signed [23:0] mac_b;
    wire signed [55:0] mac_a_ext = {{24{mac_a[31]}}, mac_a};
    wire signed [55:0] mac_b_ext = {{32{mac_b[23]}}, mac_b};
    wire signed [55:0] mac_product = mac_a_ext * mac_b_ext;
    wire signed [63:0] mac_product_ext = {{8{mac_product[55]}}, mac_product};
    wire signed [63:0] y_sum_next = y_accum + mac_product_ext;
    wire signed [63:0] xf_sum_next = xf_accum + mac_product_ext;
    wire signed [63:0] delta_w = round_shift64(mac_product_ext, 18 + MU_SHIFT);
    wire signed [63:0] weight_ext = {{32{w_mem[tap_index][31]}}, w_mem[tap_index]};
    wire signed [63:0] weight_next = weight_ext - delta_w;

    always @* begin
        mac_a = 32'sd0;
        mac_b = 24'sd0;
        case (state)
            ST_Y_MAC: begin
                mac_a = w_mem[tap_index];
                mac_b = x_hist[tap_index];
            end
            ST_SHAT_ACC: begin
                mac_a = {{8{shat_data[23]}}, shat_data};
                mac_b = x_hist[shat_index];
            end
            ST_W_UPDATE: begin
                mac_a = {{8{e_sample[23]}}, e_sample};
                mac_b = xf_hist[tap_index];
            end
            default: begin
                mac_a = 32'sd0;
                mac_b = 24'sd0;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
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
                        state <= ST_Y_MAC;
                    end
                end

                ST_Y_MAC: begin
                    if (tap_index == L-1) begin
                        y_pending <= sat24(round_shift64(y_sum_next, 28));
                        shat_index <= {M_AW{1'b0}};
                        xf_accum <= 64'sd0;
                        state <= ST_SHAT_REQ;
                    end else begin
                        y_accum <= y_sum_next;
                        tap_index <= tap_index + 1'b1;
                    end
                end

                // In ST_SHAT_REQ the external synchronous RAM samples shat_addr.
                // ST_SHAT_ACC consumes shat_data one clock later.
                ST_SHAT_REQ: begin
                    state <= ST_SHAT_ACC;
                end

                ST_SHAT_ACC: begin
                    if (shat_index == M-1) begin
                        // x_filtered is narrowed/saturated to signed Q1.23.
                        xf_hist[0] <= sat24(round_shift64(xf_sum_next, 22));
                        for (i = L-1; i > 0; i = i - 1)
                            xf_hist[i] <= xf_hist[i-1];
                        tap_index <= {L_AW{1'b0}};
                        state <= ST_W_UPDATE;
                    end else begin
                        xf_accum <= xf_sum_next;
                        shat_index <= shat_index + 1'b1;
                        state <= ST_SHAT_REQ;
                    end
                end

                ST_W_UPDATE: begin
                    if (anc_en_sample) begin
                        w_mem[tap_index] <= sat32(weight_next);
                        if ((weight_next > W_LIMIT) || (weight_next < -W_LIMIT))
                            w_over <= 1'b1;
                    end
                    if (tap_index == L-1) begin
                        state <= ST_FINISH;
                    end else begin
                        tap_index <= tap_index + 1'b1;
                    end
                end

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
