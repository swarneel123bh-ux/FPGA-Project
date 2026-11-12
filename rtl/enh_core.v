`timescale 1ns/1ps
// enh_core: the PL audio path of the enhancement build (goal 2, now the primary goal).
//
// WRITTEN BY CLAUDE (Swarneel's agent), 11 Nov 2026, at Swarneel's request. Not team-written.
// Everything in the PL except the clocking wizard, the MCLK output buffer and the PS block
// design, so a testbench can drive it directly (sim/tb_enh_core.v).
//
//   ARM --AXI4-Lite--> music_fifo_axi --music_raw--> treble_fixed --music--+
//                                                                         +--> i2s_tx --> headphones
//                                  test tone (SW1) -----------------------+     (same sample, both ears)
//   codec_cfg (I2C) configures the ADAU1761; i2s_rx provides sample_tick (48 kHz) from its clocks.
//
// Switches and LEDs (see docs/enh_build.md):
//   SW0  up = enhanced, down = plain MP3 (treble_fixed enh_en)
//   SW1  up = 1 kHz square test tone at -24 dBFS instead of the music (checks codec + headphones
//        without the ARM)
//   SW2/SW3/SW4  volume: up = -6 / -12 / -24 dB, added together (0 to -42 dB in 6 dB steps,
//        all down = 0 dB). Arithmetic shift of the headphone signal (music or tone). [12 Nov]
//   SW5  up = added treble -12 dB (treble_fixed att12) [12 Nov]
//   SW6  up = retuned enhancer (9 kHz, shelf EQ, -8 dB), down = original 7.2 kHz tuning
//        (treble_fixed tune_sel) [12 Nov]
//   LD0 codec_ready   LD1 codec_error   LD2 1 Hz blink from sample_tick (48 kHz LRCLK present)
//   LD3 music arriving (FIFO not empty at the last tick)   LD4 SW0 (enhanced)
//   LD5 AXI side out of reset (PS has booted)   LD6 SW1 (tone)   LD7 output reached full scale
//   in the last ~0.25 s (clipping, measured before the volume control)
//
// Clock: one domain, clk (board 100 MHz). The AXI port of the PS runs on the same clock.
// Resets: rst (BTND or clock not locked) for the codec path; axi_aresetn (from the PS) for the
// AXI slave and FIFO. treble_fixed uses rst.

module enh_core (
	input  wire        clk,
	input  wire        rst,
	input  wire        axi_aresetn,

	// AXI4-Lite slave (from the PS through the block design), 4-bit address
	input  wire [3:0]  s_axi_awaddr,
	input  wire [2:0]  s_axi_awprot,
	input  wire        s_axi_awvalid,
	output wire        s_axi_awready,
	input  wire [31:0] s_axi_wdata,
	input  wire [3:0]  s_axi_wstrb,
	input  wire        s_axi_wvalid,
	output wire        s_axi_wready,
	output wire [1:0]  s_axi_bresp,
	output wire        s_axi_bvalid,
	input  wire        s_axi_bready,
	input  wire [3:0]  s_axi_araddr,
	input  wire [2:0]  s_axi_arprot,
	input  wire        s_axi_arvalid,
	output wire        s_axi_arready,
	output wire [31:0] s_axi_rdata,
	output wire [1:0]  s_axi_rresp,
	output wire        s_axi_rvalid,
	input  wire        s_axi_rready,

	// ADAU1761 (MCLK is driven by enh_top)
	inout  wire        ac_scl,
	inout  wire        ac_sda,
	input  wire        ac_bclk,
	input  wire        ac_lrclk,
	input  wire        ac_adc_sdata,
	output wire        ac_dac_sdata,

	input  wire [6:0]  sw,
	output wire [7:0]  led
);

wire codec_ready, codec_error, sample_tick;
wire signed [23:0] x_ref_unused, e_err_unused;
wire signed [23:0] music_raw, music;
wire fifo_underrun;

// ---------------------------------------------------------------- switches (2-flop sync)
reg [6:0] sw_m, sw_s;
always @(posedge clk) begin
	sw_m <= sw;
	sw_s <= sw_m;
end
wire tone_on = sw_s[1];
wire [2:0] vol_att = sw_s[4:2];							// 6 dB steps of attenuation

// ---------------------------------------------------------------- codec and I2S
codec_cfg u_codec (
	.clk(clk), .rst(rst),
	.codec_scl(ac_scl), .codec_sda(ac_sda),
	.busy(), .ready(codec_ready), .error(codec_error)
);

i2s_rx u_rx (
	.clk(clk), .rst(rst),
	.bclk_in(ac_bclk), .lrclk_in(ac_lrclk), .adc_sdata(ac_adc_sdata),
	.x_ref(x_ref_unused), .e_err(e_err_unused), .sample_tick(sample_tick)
);

// ---------------------------------------------------------------- music path
music_fifo_axi #(.ADDR_W(12), .C_S_AXI_DATA_WIDTH(32), .C_S_AXI_ADDR_WIDTH(4)) u_fifo (
	.sample_tick(sample_tick), .music_raw(music_raw), .fifo_underrun(fifo_underrun),
	.S_AXI_ACLK(clk), .S_AXI_ARESETN(axi_aresetn),
	.S_AXI_AWADDR(s_axi_awaddr), .S_AXI_AWPROT(s_axi_awprot),
	.S_AXI_AWVALID(s_axi_awvalid), .S_AXI_AWREADY(s_axi_awready),
	.S_AXI_WDATA(s_axi_wdata), .S_AXI_WSTRB(s_axi_wstrb),
	.S_AXI_WVALID(s_axi_wvalid), .S_AXI_WREADY(s_axi_wready),
	.S_AXI_BRESP(s_axi_bresp), .S_AXI_BVALID(s_axi_bvalid), .S_AXI_BREADY(s_axi_bready),
	.S_AXI_ARADDR(s_axi_araddr), .S_AXI_ARPROT(s_axi_arprot),
	.S_AXI_ARVALID(s_axi_arvalid), .S_AXI_ARREADY(s_axi_arready),
	.S_AXI_RDATA(s_axi_rdata), .S_AXI_RRESP(s_axi_rresp),
	.S_AXI_RVALID(s_axi_rvalid), .S_AXI_RREADY(s_axi_rready)
);

treble_fixed u_treble (
	.clk(clk), .rst(rst), .sample_tick(sample_tick),
	.music_raw(music_raw), .music(music), .enh_en(sw[0]),		// synchronised inside
	.tune_sel(sw[6]), .att12(sw[5])
);

// ---------------------------------------------------------------- 1 kHz test tone
localparam signed [23:0] TONE_AMP = 24'sh080000;			// 2^19 = -24 dBFS
reg [4:0] tone_cnt;
reg       tone_hi;
always @(posedge clk) begin
	if (rst) begin
		tone_cnt <= 0;
		tone_hi  <= 0;
	end else if (sample_tick) begin
		if (tone_cnt == 5'd23) begin							// 24 samples high, 24 low = 1 kHz
			tone_cnt <= 0;
			tone_hi  <= ~tone_hi;
		end else begin
			tone_cnt <= tone_cnt + 1'b1;
		end
	end
end
wire signed [23:0] tone = tone_hi ? TONE_AMP : -TONE_AMP;

wire signed [23:0] dac_pre = tone_on ? tone : music;
// Volume: >>> rounds towards -inf; at most 7 shifts, so a full-scale sample never reaches 0 dB+
wire signed [23:0] dac = dac_pre >>> vol_att;

i2s_tx u_tx (
	.clk(clk), .rst(rst),
	.bclk_in(ac_bclk), .lrclk_in(ac_lrclk), .sample_tick(sample_tick),
	.dac_left(dac), .dac_right(dac), .dac_sdata(ac_dac_sdata)
);

// ---------------------------------------------------------------- LEDs
reg [14:0] blink_cnt;
reg        blink;
reg        playing;
reg [13:0] clip_hold;										// ticks left to show clipping
always @(posedge clk) begin
	if (rst) begin
		blink_cnt <= 0;
		blink     <= 0;
		playing   <= 0;
		clip_hold <= 0;
	end else if (sample_tick) begin
		if (blink_cnt == 15'd23999) begin
			blink_cnt <= 0;
			blink     <= ~blink;
		end else begin
			blink_cnt <= blink_cnt + 1'b1;
		end
		playing <= ~fifo_underrun;
		if (dac_pre == 24'sh7FFFFF || dac_pre == 24'sh800000) clip_hold <= 14'd12000;
		else if (clip_hold != 0)                       clip_hold <= clip_hold - 1'b1;
	end
end

assign led = {clip_hold != 0, tone_on, axi_aresetn, sw_s[0], playing, blink, codec_error, codec_ready};

endmodule
