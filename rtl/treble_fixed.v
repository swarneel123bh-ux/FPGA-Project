`timescale 1ns/1ps


module treble_fixed(
	input wire clk,													// 100 MHz clk
	input wire rst,													// Active high sync reset
	input wire sample_tick,									// one-cycle tick signal
	input wire signed [23:0] music_raw,			// from music_fifo.v, valid on sample_tick
	output reg signed [23:0] music,					// to out_mux, held until next tick
	input wire enh_en												// switch to enable/disable enhancement, currently unused
);


always @(posedge clk) begin
	if (rst) begin
		music <= 0;
	end else begin
		if (sample_tick) begin
			// ...
		end
	end
end

endmodule
