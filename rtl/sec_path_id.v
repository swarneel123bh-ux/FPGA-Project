`timescale 1ns / 1ps

// Member C: 128-tap secondary-path identification using LMS.
//
// Formats:
//   probe_in, measured_in, estimate, epsilon : signed 24-bit Q1.23
//   shat_mem coefficients                    : signed 24-bit Q2.22
//   LMS step size                            : mu_s = 2^-6
//   coefficient update right shift           : 30 bits
//   estimate output right shift              : 22 bits
//
// LMS equations:
//   epsilon = measured_in - estimated_output
//   shat[k] = shat[k] + round(epsilon * probe_history[k] / 2^30)
//
// The module uses one serial estimate MAC and one serial coefficient update.
// It needs about 256 clocks per input sample. Do not assert sample_tick while
// busy. The shat read port has one clock of latency for Member B's fxlms.v.

module sec_path_id(
    input clk,
    input rst,
    input sample_tick,
    input cal_en,
    input signed [23:0] probe_in,
    input signed [23:0] measured_in,
    input [6:0] shat_addr,
    output reg signed [23:0] shat_data,
    output reg busy,
    output reg done
);

    localparam IDLE   = 2'd0;
    localparam EST    = 2'd1;
    localparam UPDATE = 2'd2;

    reg [1:0] state;
    reg [6:0] tap_index;

    reg signed [23:0] probe_history [0:127];
    reg signed [23:0] shat_mem [0:127];
    reg signed [23:0] measured_sample;
    reg signed [23:0] epsilon;
    reg signed [63:0] accum;

    integer i;

    // Intermediate signals for the estimate calculation.
    wire signed [47:0] shat_ext;
    wire signed [47:0] probe_ext;
    wire signed [47:0] est_product;
    wire signed [63:0] est_product_ext;
    wire signed [63:0] est_sum_next;
    wire signed [63:0] estimate_q23_full;
    wire signed [23:0] estimate_q23;
    wire signed [63:0] epsilon_full;
    wire signed [23:0] epsilon_next;

    // Intermediate signals for the coefficient update.
    wire signed [47:0] epsilon_ext;
    wire signed [47:0] history_ext;
    wire signed [47:0] update_product;
    wire signed [63:0] update_product_ext;
    wire signed [63:0] delta_s;
    wire signed [63:0] old_shat_ext;
    wire signed [63:0] shat_next_full;
    wire signed [23:0] shat_next;

    // Round to nearest, ties away from zero.
    function signed [63:0] round_shift64;
        input signed [63:0] value;
        input integer shift;
        reg signed [63:0] magnitude;
        reg signed [63:0] rounded_magnitude;
        begin
            if (shift <= 0)
                round_shift64 = value <<< (-shift);
            else if (value >= 0)
                round_shift64 = (value + (64'sd1 <<< (shift - 1))) >>> shift;
            else
            begin
                magnitude = -value;
                rounded_magnitude = (magnitude + (64'sd1 <<< (shift - 1))) >>> shift;
                round_shift64 = -rounded_magnitude;
            end
        end
    endfunction

    // Saturate to signed 24-bit two's-complement range.
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

    // Estimate: S_hat(z) multiplied by the stored probe history.
    assign shat_ext = {{24{shat_mem[tap_index][23]}}, shat_mem[tap_index]};
    assign probe_ext = {{24{probe_history[tap_index][23]}}, probe_history[tap_index]};
    assign est_product = shat_ext * probe_ext;
    assign est_product_ext = {{16{est_product[47]}}, est_product};
    assign est_sum_next = accum + est_product_ext;
    assign estimate_q23_full = round_shift64(est_sum_next, 22);
    assign estimate_q23 = sat24(estimate_q23_full);
    assign epsilon_full = $signed(measured_sample) - $signed(estimate_q23);
    assign epsilon_next = sat24(epsilon_full);

    // Update: shat[k] += mu_s * epsilon * probe_history[k].
    assign epsilon_ext = {{24{epsilon[23]}}, epsilon};
    assign history_ext = {{24{probe_history[tap_index][23]}}, probe_history[tap_index]};
    assign update_product = epsilon_ext * history_ext;
    assign update_product_ext = {{16{update_product[47]}}, update_product};
    assign delta_s = round_shift64(update_product_ext, 30);
    assign old_shat_ext = {{40{shat_mem[tap_index][23]}}, shat_mem[tap_index]};
    assign shat_next_full = old_shat_ext + delta_s;
    assign shat_next = sat24(shat_next_full);

    // Synchronous coefficient read: one clock from address to data.
    always @(posedge clk)
    begin
        if (rst)
            shat_data <= 24'sd0;
        else
            shat_data <= shat_mem[shat_addr];
    end

    always @(posedge clk)
    begin
        if (rst)
        begin
            state <= IDLE;
            tap_index <= 7'd0;
            measured_sample <= 24'sd0;
            epsilon <= 24'sd0;
            accum <= 64'sd0;
            busy <= 1'b0;
            done <= 1'b0;

            for (i = 0; i < 128; i = i + 1)
            begin
                probe_history[i] <= 24'sd0;
                shat_mem[i] <= 24'sd0;
            end
        end
        else
        begin
            done <= 1'b0;

            case (state)
                IDLE:
                begin
                    if (sample_tick && cal_en)
                    begin
                        // Add newest calibration sample to history.
                        for (i = 127; i > 0; i = i - 1)
                            probe_history[i] <= probe_history[i-1];
                        probe_history[0] <= probe_in;

                        measured_sample <= measured_in;
                        accum <= 64'sd0;
                        tap_index <= 7'd0;
                        busy <= 1'b1;
                        state <= EST;
                    end
                end

                EST:
                begin
                    if (tap_index == 7'd127)
                    begin
                        // Include the final tap product before calculating epsilon.
                        epsilon <= epsilon_next;
                        tap_index <= 7'd0;
                        state <= UPDATE;
                    end
                    else
                    begin
                        accum <= est_sum_next;
                        tap_index <= tap_index + 1'b1;
                    end
                end

                UPDATE:
                begin
                    shat_mem[tap_index] <= shat_next;

                    if (tap_index == 7'd127)
                    begin
                        tap_index <= 7'd0;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= IDLE;
                    end
                    else
                        tap_index <= tap_index + 1'b1;
                end

                default:
                begin
                    state <= IDLE;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
