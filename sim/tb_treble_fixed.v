`timescale 1ns/1ps
// Testbench for rtl/treble_fixed.v.
//
// WRITTEN BY CLAUDE (Swarneel's agent) on 11 Nov 2026, at Swarneel's request (Swarneel assigned
// the treble RTL port to Claude). Not written by a team member.
//
// Vectors come from model/goal2/ref_fixed.py (run it first):
//   sim/vectors/treble_in.hex   input samples, s24
//   sim/vectors/treble_out.hex  expected music, s24, enh_en = 1
//   rtl/treble_coefs.mem        coefficient ROM the DUT loads
//
// music_raw is driven the way music_fifo drives it: valid 2 clocks after sample_tick. The output
// for sample k is taken at tick k+1, as i2s_tx takes it.
//
// Checks (docs/goal2_rtl_plan.md section 5):
//   1. Bit-exact against treble_out.hex for every vector.
//   2. enh_en = 0 for a window of samples: output equals input; bit-exact again after the window
//      (proves the filters kept running).
//   3. Full-scale input: covered by 1 (the vectors include full-scale tones and impulses; the
//      model checks they saturate and never wrap). Also: any |output| == full scale is counted.
//   4. Reset, then replay the first samples: identical output.
//   5. music holds its value from the end of each run to the next tick; each run finishes in
//      fewer than RUN_MAX clocks.
//   6. The first samples again at the real 48 kHz spacing (2,083 clocks).
//
// Run:  ./sim/run_treble.sh      (or the two commands at its bottom)

module tb_treble_fixed;

localparam MAXV     = 65536;
localparam TICK_FAST = 160;			// clocks between ticks for the long run (DUT needs ~115)
localparam TICK_REAL = 2083;			// 100 MHz / 48 kHz
localparam RUN_MAX   = 140;			// a run must finish within this many clocks of the tick
localparam OFF_LO    = 22000;			// enh_en = 0 for samples [OFF_LO, OFF_HI)
localparam OFF_HI    = 23000;
localparam REPLAY_N  = 3000;
localparam REAL_N    = 300;

reg clk = 0;
reg rst = 1;
reg sample_tick = 0;
reg signed [23:0] music_raw = 0;
reg enh_en = 1;
wire signed [23:0] music;

treble_fixed #(.COEF_FILE("rtl/treble_coefs.mem")) uut (
	.clk(clk), .rst(rst), .sample_tick(sample_tick),
	.music_raw(music_raw), .music(music), .enh_en(enh_en)
);

always #5 clk = ~clk;

reg [23:0] vin  [0:MAXV-1];
reg [23:0] vexp [0:MAXV-1];
integer nvec;

integer errors = 0, checks = 0, hold_errors = 0, late = 0, nsat = 0;
integer shown = 0;
integer max_run = 0;

// ---------------------------------------------------------------- run-length and hold monitor
// Counts clocks from each tick to the change of music (if it changes), and checks that music
// does not change after RUN_MAX clocks.
integer since_tick = 0;
reg signed [23:0] music_prev = 0;
always @(posedge clk) begin
	if (sample_tick) since_tick <= 0;
	else             since_tick <= since_tick + 1;
	if (!rst && music !== music_prev) begin
		if (since_tick > max_run) max_run = since_tick;
		if (since_tick >= RUN_MAX) hold_errors = hold_errors + 1;
	end
	music_prev <= music;
end

// ---------------------------------------------------------------- one sample
task automatic tick(input [23:0] sample, input integer period);
	integer c;
	begin
		@(posedge clk) sample_tick <= 1;
		@(posedge clk) sample_tick <= 0;
		@(posedge clk) music_raw <= sample;		// valid 2 clocks after the tick, like music_fifo
		for (c = 3; c < period; c = c + 1) @(posedge clk);
	end
endtask

task automatic check(input integer k, input [23:0] expv, input [8*16-1:0] what);
	begin
		checks = checks + 1;
		if (music !== expv) begin
			errors = errors + 1;
			if (shown < 10) begin
				$display("FAIL %0s sample %0d: got %h expected %h (input %h)", what, k, music, expv, vin[k]);
				shown = shown + 1;
			end
		end
		if (music == 24'h7FFFFF || music == 24'h800000) nsat = nsat + 1;
	end
endtask

// Play samples [0, n) and compare each output at the following tick.
task automatic play(input integer n, input integer period, input integer use_off_window,
                    input [8*16-1:0] what);
	integer k;
	reg [23:0] e;
	begin
		for (k = 0; k < n; k = k + 1) begin
			enh_en <= (use_off_window && k >= OFF_LO && k < OFF_HI) ? 1'b0 : 1'b1;
			tick(vin[k], period);					// music now holds the result for sample k
			e = (use_off_window && k >= OFF_LO && k < OFF_HI) ? vin[k] : vexp[k];
			check(k, e, what);
		end
	end
endtask

task automatic do_reset;
	begin
		rst <= 1; music_raw <= 0;
		repeat (5) @(posedge clk);
		rst <= 0;
		repeat (5) @(posedge clk);
	end
endtask

integer e1, e2, e4, e6;
integer fd;
initial begin
	$readmemh("sim/vectors/treble_in.hex",  vin);
	$readmemh("sim/vectors/treble_out.hex", vexp);
	// count vectors (file length): stop at the first unwritten entry
	nvec = 0;
	while (nvec < MAXV && vin[nvec] !== 24'bx) nvec = nvec + 1;
	$display("tb_treble_fixed: %0d vectors", nvec);
	if (nvec <= OFF_HI) begin
		$display("FAIL: too few vectors; rerun model/goal2/ref_fixed.py"); $finish;
	end

	do_reset;

	// 1 + 2 + 3 + 5: whole vector set, with the enh_en = 0 window
	play(nvec, TICK_FAST, 1, "full run");
	e1 = errors;
	$display("check 1/2: %0d samples, %0d mismatches (enh_en = 0 for samples %0d..%0d), %0d at full scale",
	         nvec, e1, OFF_LO, OFF_HI - 1, nsat);

	// 4: reset, replay
	do_reset;
	play(REPLAY_N, TICK_FAST, 0, "replay");
	e4 = errors - e1;
	$display("check 4:   reset + replay of %0d samples: %0d mismatches", REPLAY_N, e4);

	// 6: real 48 kHz spacing
	do_reset;
	play(REAL_N, TICK_REAL, 0, "48k spacing");
	e6 = errors - e1 - e4;
	$display("check 6:   %0d samples at 2,083-clock spacing: %0d mismatches", REAL_N, e6);

	$display("check 5:   longest tick-to-result %0d clocks (limit %0d), %0d changes outside the run",
	         max_run, RUN_MAX, hold_errors);

	if (errors == 0 && hold_errors == 0)
		$display("PASS: %0d checks, bit-exact with model/goal2/ref_fixed.py", checks);
	else
		$display("FAIL: %0d mismatches, %0d hold errors", errors, hold_errors);
	$finish;
end

endmodule
