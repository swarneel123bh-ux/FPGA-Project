`timescale 1ns/1ps
// Integration testbench for rtl/enh_core.v: AXI4-Lite writes -> music_fifo -> treble_fixed ->
// i2s_tx, checked bit-exact against model/goal2/ref_fixed.py at the I2S serial output.
//
// WRITTEN BY CLAUDE (Swarneel's agent), 11 Nov 2026, at Swarneel's request. Not team code.
//
// The testbench plays the codec: it drives BCLK/LRCLK (I2S, 32-bit slots, LRCLK changes on the
// falling BCLK edge) and decodes AC-DAC-SDATA (one-bit delay, 24 bits MSB first). To keep the run
// short, BCLK is 6.25 MHz (16 clocks per bit, 1,024 clocks per sample) instead of 3.072 MHz; the
// treble run takes about 115 clocks, so this still leaves plenty of time per sample.
//
// The "ARM" writes sim/vectors/treble_in.hex through the AXI port (register 0x0), polling the
// FIFO level (register 0x4) to keep the FIFO from running dry. Checks:
//   1. The left-channel I2S words, from the first non-zero one, equal treble_out_default.hex for every
//      vector, and the right channel equals the left.
//   2. No FIFO underrun once playback has started (LED3 stays on).
//   3. SW1 (test tone): the output becomes +/-0x080000 square at 1 kHz.
//   4. Volume (SW2-4): tone at -18 dB (SW2+SW3) is +/-0x010000, at -42 dB (all three) +/-0x001000.
//   5. SW5/SW6 reach treble_fixed. Check 1 uses treble_out_default.hex (all switches down).
//
// Run: ./sim/run_enh.sh

module tb_enh_core;

localparam MAXV     = 65536;
localparam BCLK_HALF = 80;							// ns -> 6.25 MHz BCLK

reg clk = 0;
always #5 clk = ~clk;
reg rst = 1;
reg axi_aresetn = 0;

reg  [3:0]  awaddr = 0;  reg awvalid = 0;  wire awready;
reg  [31:0] wdata = 0;   reg wvalid = 0;   wire wready;
wire [1:0]  bresp;       wire bvalid;      reg bready = 0;
reg  [3:0]  araddr = 0;  reg arvalid = 0;  wire arready;
wire [31:0] rdata;       wire [1:0] rresp; wire rvalid; reg rready = 0;

wire scl, sda;
pullup (scl);
pullup (sda);
reg  bclk = 0, lrclk = 0;
wire dac_sdata;
reg  [6:0] sw = 7'b0000001;						// enhanced, no tone, 0 dB, tuning 0, gain 1
wire [7:0] led;

enh_core dut (
	.clk(clk), .rst(rst), .axi_aresetn(axi_aresetn),
	.s_axi_awaddr(awaddr), .s_axi_awprot(3'b000), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
	.s_axi_wdata(wdata), .s_axi_wstrb(4'hF), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
	.s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
	.s_axi_araddr(araddr), .s_axi_arprot(3'b000), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
	.s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
	.ac_scl(scl), .ac_sda(sda), .ac_bclk(bclk), .ac_lrclk(lrclk),
	.ac_adc_sdata(1'b0), .ac_dac_sdata(dac_sdata),
	.sw(sw), .led(led)
);
// The simulator runs from the repo root; Vivado finds the .mem file as a project source.
defparam dut.u_treble.COEF_FILE = "rtl/treble_coefs.mem";

// ---------------------------------------------------------------- codec clocks
integer bit_in_slot = 0;
initial begin
	#1000;
	forever begin
		#BCLK_HALF bclk = 1;
		#BCLK_HALF bclk = 0;								// falling edge: LRCLK may change
		bit_in_slot = bit_in_slot + 1;
		if (bit_in_slot == 32) begin
			bit_in_slot = 0;
			lrclk = ~lrclk;
		end
	end
end

// ---------------------------------------------------------------- I2S decoder (codec side)
reg  [23:0] rx_left [0:MAXV-1];
reg  [23:0] rx_right[0:MAXV-1];
integer n_left = 0, n_right = 0;
reg  lr_prev = 0;
integer rbit = 0;
reg [23:0] shreg = 0;
always @(posedge bclk) begin							// the codec samples on rising BCLK
	if (lrclk != lr_prev) rbit = 0;
	else                  rbit = rbit + 1;
	lr_prev = lrclk;
	if (rbit >= 1 && rbit <= 24) shreg = {shreg[22:0], dac_sdata};	// one-bit I2S delay
	if (rbit == 24) begin
		if (!lrclk) begin rx_left[n_left % MAXV] = shreg;   n_left = n_left + 1;   end
		else        begin rx_right[n_right % MAXV] = shreg; n_right = n_right + 1; end
	end
end

// ---------------------------------------------------------------- AXI master tasks
task automatic axi_write(input [3:0] a, input [31:0] d);
	begin
		@(posedge clk);
		awaddr <= a; awvalid <= 1; wdata <= d; wvalid <= 1; bready <= 1;
		@(posedge clk);
		while (!(awready && wready)) @(posedge clk);
		awvalid <= 0; wvalid <= 0;
		while (!bvalid) @(posedge clk);
		@(posedge clk);
		bready <= 0;
	end
endtask

task automatic axi_read(input [3:0] a, output [31:0] d);
	begin
		@(posedge clk);
		araddr <= a; arvalid <= 1; rready <= 1;
		@(posedge clk);
		while (!arready) @(posedge clk);
		arvalid <= 0;
		while (!rvalid) @(posedge clk);
		d = rdata;
		@(posedge clk);
		rready <= 0;
	end
endtask

// ---------------------------------------------------------------- stimulus and checks
reg [23:0] vin  [0:MAXV-1];
reg [23:0] vexp [0:MAXV-1];
integer nvec, k, start, errors = 0, shown = 0, underruns = 0, started = 0;
reg [31:0] lvl;

always @(posedge clk) if (dut.sample_tick && started && dut.fifo_underrun) underruns = underruns + 1;

initial begin
	$readmemh("sim/vectors/treble_in.hex",  vin);
	$readmemh("sim/vectors/treble_out_default.hex", vexp);	// switches down
	nvec = 0;
	while (nvec < MAXV && vin[nvec] !== 24'bx) nvec = nvec + 1;
	$display("tb_enh_core: %0d vectors", nvec);

	repeat (10) @(posedge clk);
	rst <= 0; axi_aresetn <= 1;

	// "ARM": prefill, then keep the FIFO above 1,000 samples
	k = 0;
	while (k < nvec) begin
		axi_read(4'h4, lvl);
		if (lvl[12:0] < 13'd3000) begin
			repeat (1000) begin
				if (k < nvec) begin axi_write(4'h0, {8'h00, vin[k]}); k = k + 1; end
			end
		end else begin
			repeat (200) @(posedge clk);
		end
		if (k > 0 && !started) begin
			// playback starts at the next tick once data is in the FIFO
			@(posedge dut.sample_tick); @(posedge clk); started = 1;
		end
	end
	// let the FIFO drain, then stop counting underruns
	axi_read(4'h4, lvl);
	while (lvl[12:0] != 0) begin repeat (500) @(posedge clk); axi_read(4'h4, lvl); end
	started = 0;
	repeat (4) @(posedge dut.sample_tick);

	// Check 1: align on the first non-zero expected value
	start = -1;
	for (k = 0; k < n_left && start < 0; k = k + 1) if (rx_left[k] != 0) start = k;
	begin : align
		integer first_nz;
		first_nz = -1;
		for (k = 0; k < nvec && first_nz < 0; k = k + 1) if (vexp[k] != 0) first_nz = k;
		start = start - first_nz;							// rx index of vector 0
	end
	if (start < 0) begin
		$display("FAIL: no output, or output before the input"); $finish;
	end
	for (k = 0; k < nvec; k = k + 1) begin
		if (rx_left[start + k] !== vexp[k] || rx_right[start + k] !== vexp[k]) begin
			errors = errors + 1;
			if (shown < 10) begin
				$display("FAIL sample %0d: left %h right %h expected %h", k,
				         rx_left[start + k], rx_right[start + k], vexp[k]);
				shown = shown + 1;
			end
		end
	end
	$display("check 1: %0d samples through AXI -> FIFO -> treble -> I2S, %0d mismatches", nvec, errors);
	$display("check 2: %0d FIFO underruns during playback", underruns);

	// Check 3: test tone
	sw <= 7'b0000011;
	repeat (60) @(posedge dut.sample_tick);
	begin : tone_chk
		integer i, hi, lo, bad;
		hi = 0; lo = 0; bad = 0;
		for (i = n_left - 48; i < n_left; i = i + 1) begin
			if (rx_left[i] == 24'h080000) hi = hi + 1;
			else if (rx_left[i] == 24'hF80000) lo = lo + 1;
			else bad = bad + 1;
		end
		$display("check 3: tone, last 48 samples: %0d high, %0d low, %0d other (expect 24/24/0)", hi, lo, bad);
		if (hi != 24 || lo != 24) errors = errors + 1;
	end

	// Check 4: volume switches, on the tone (exact values after the arithmetic shift)
	begin : vol_chk
		integer v, i, hi, lo, bad;
		reg [23:0] eh, el;
		for (v = 0; v < 2; v = v + 1) begin
			sw <= v ? 7'b0011111 : 7'b0001111;
			eh = v ? 24'h001000 : 24'h010000;
			el = v ? 24'hFFF000 : 24'hFF0000;
			repeat (60) @(posedge dut.sample_tick);
			hi = 0; lo = 0; bad = 0;
			for (i = n_left - 48; i < n_left; i = i + 1) begin
				if (rx_left[i] == eh && rx_right[i] == eh) hi = hi + 1;
				else if (rx_left[i] == el && rx_right[i] == el) lo = lo + 1;
				else bad = bad + 1;
			end
			$display("check 4: volume %0s dB, last 48 samples: %0d at %h, %0d at %h, %0d other (expect 24/24/0)",
			         v ? "-42" : "-18", hi, eh, lo, el, bad);
			if (hi != 24 || lo != 24) errors = errors + 1;
		end
	end

	// Check 5: SW5/SW6 reach treble_fixed (its own testbench checks what they do)
	sw <= 7'b1100001;
	repeat (4) @(posedge clk);
	$display("check 5: SW6 -> tune_sel %0d, SW5 -> att12 %0d (expect 1 1)", dut.u_treble.tune_s2, dut.u_treble.att_s2);
	if (dut.u_treble.tune_s2 !== 1'b1 || dut.u_treble.att_s2 !== 1'b1) errors = errors + 1;

	if (errors == 0 && underruns == 0) $display("PASS");
	else                               $display("FAIL");
	$finish;
end

endmodule
