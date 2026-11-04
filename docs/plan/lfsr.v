`timescale 1ns / 1ps

// 23-bit LFSR matching the supplied Python model.
// Seed: 0x5A5A5A
// Feedback: state[22] XOR state[17]
// Output: +0.25 when the new LSB is 1, otherwise -0.25 (Q1.23).

module lfsr(
    input clk,
    input reset,
    input enable,
    output reg [22:0] state,
    output reg signed [23:0] sample_out,
    output reg sample_valid
);

    wire feedback;
    assign feedback = state[22] ^ state[17];

    always @(posedge clk)
    begin
        if (reset)
        begin
            state <= 23'h5A5A5A;
            sample_out <= 24'sd0;
            sample_valid <= 1'b0;
        end
        else
        begin
            sample_valid <= 1'b0;

            if (enable)
            begin
                state <= {state[21:0], feedback};

                if (feedback == 1'b1)
                    sample_out <= 24'sd2097152;
                else
                    sample_out <= -24'sd2097152;

                sample_valid <= 1'b1;
            end
        end
    end

endmodule
