// -----------------------------------------------------------------------------
// WEEK-1 SCAFFOLDING — review and understand before adopting as team RTL.
// Forward a Clocking Wizard's 24 MHz output to the ADAU1761 AC-MCLK pin using
// a Xilinx 7-series ODDR output register. Create a Clocking Wizard named
// clk_wiz_0 (100 MHz input, 24 MHz output) in Vivado and connect clk_24 here.
// -----------------------------------------------------------------------------
module mclk_out (
    input  wire clk_24,
    input  wire rst,       // active-high reset
    output wire mclk
);
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) mclk_oddr (
        .Q(mclk),
        .C(clk_24),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(rst),
        .S(1'b0)
    );
endmodule
