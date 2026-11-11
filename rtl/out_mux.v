`timescale 1ns/1ps
// Member A: selects one signed 24-bit source for both headphone channels.
module out_mux(
 input wire [2:0] mode,
 input wire signed [23:0] v_lfsr,
 input wire signed [23:0] y_anti,
 input wire signed [23:0] music,
 input wire fifo_underrun,
 output reg signed [23:0] dac_out
);
 localparam [2:0] CALIBRATE=3'd0, CANCEL=3'd1, BYPASS=3'd2, MUTE=3'd3, MUSIC=3'd4;
 always @* begin
   dac_out=24'sd0;
   case(mode)
     CALIBRATE: dac_out=v_lfsr;
     CANCEL:    dac_out=y_anti;
     MUSIC:     dac_out=fifo_underrun ? 24'sd0 : music;
     default:   dac_out=24'sd0;
   endcase
 end
endmodule
