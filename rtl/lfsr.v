`timescale 1ns / 1ps
// Member C: 23-bit maximal-length LFSR probe generator.
// Output format: signed 24-bit Q1.23, +/-0.25 full scale.
// State update matches sw/member_c/lfsr.py.
module lfsr #(
    parameter [22:0] SEED = 23'h5A5A5A
)(
    input  wire               clk,
    input  wire               rst,          // active-high synchronous reset
    input  wire               enable,       // one pulse per probe sample
    output reg  [22:0]        state,
    output reg  signed [23:0]  sample_out,
    output reg                sample_valid
);
    wire feedback = state[22] ^ state[17];

    always @(posedge clk) begin
        if (rst) begin
            state        <= SEED;
            sample_out   <= 24'sd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            if (enable) begin
                state        <= {state[21:0], feedback};
                // New state's LSB is feedback. This is the exact Python convention.
                sample_out   <= feedback ? 24'sd2097152 : -24'sd2097152;
                sample_valid <= 1'b1;
            end
        end
    end
endmodule
