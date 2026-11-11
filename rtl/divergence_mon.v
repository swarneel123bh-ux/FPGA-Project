`timescale 1ns / 1ps
// Member C reference implementation: sticky ANC divergence/over-limit monitor.
// error_power_q46 is the power_meter mean_square_q46 output (unsigned Q2.46).
// power_valid should be connected to power_meter.window_done.
// w_over should be connected to Member B's fxlms.w_over output.
// The threshold is a STARTING CONFIGURATION, not a measured hardware value.

module divergence_mon #(
    // 0.25 full-scale squared = 0.25 * 2^46 = 2^44 (about -6.02 dBFS).
    // Ask Member B to confirm/tune this threshold using the fixed-point model.
    parameter [63:0] ERROR_POWER_LIMIT_Q46 = (64'd1 << 44)
)(
    input  wire        clk,
    input  wire        rst,          // active-high synchronous reset
    input  wire        clear_trip,   // pulse to clear the sticky divergence flag
    input  wire        power_valid,  // one pulse when a fresh power window is ready
    input  wire [63:0] error_power_q46,
    input  wire        w_over,
    output reg         diverge
);

    always @(posedge clk) begin
        if (rst || clear_trip) begin
            diverge <= 1'b0;
        end else if (w_over || (power_valid && (error_power_q46 > ERROR_POWER_LIMIT_Q46))) begin
            // Latch the fault so a one-cycle over-limit event is not missed by the FSM.
            diverge <= 1'b1;
        end
    end

endmodule
