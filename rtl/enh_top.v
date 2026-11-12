`timescale 1ns/1ps
// enh_top: top level of the enhancement build (goal 2: MP3 over UART -> ARM decode -> PL treble
// restoration -> headphones). ANC blocks are not in this build.
//
// WRITTEN BY CLAUDE (Swarneel's agent), 11 Nov 2026, at Swarneel's request. Not team-written.
// Built by scripts/build_enh.tcl; pins in constraints/zedboard_enh.xdc; how to run it in
// docs/enh_build.md.
//
//   clk100 (Y9) --> clk_wiz_0 --> 24 MHz --> mclk_out (ODDR) --> AC-MCLK
//        |
//        +--> enh_core (codec, I2S, FIFO, treble, LEDs)        one 100 MHz clock domain
//        +--> enh_ps_wrapper (block design: PS7, AXI interconnect, reset) aclk
//
// Same clocking as the week-1 build that worked on 11 Nov (clk_wiz_0: 100 -> 24 MHz only; logic
// on clk100).

module enh_top (
	input  wire        clk100,
	input  wire        btnd,					// reset (active high)
	input  wire [6:0]  sw,				// SW0 enhanced, SW1 tone, SW2-4 volume, SW5 -12 dB treble, SW6 tuning
	output wire [7:0]  led,

	inout  wire        ac_scl,
	inout  wire        ac_sda,
	output wire        ac_mclk,
	input  wire        ac_bclk,
	input  wire        ac_lrclk,
	input  wire        ac_adc_sdata,
	output wire        ac_dac_sdata,
	output wire        ac_addr0,
	output wire        ac_addr1,

	// Zynq PS (fixed pins, no constraints needed)
	inout  wire [14:0] DDR_addr,
	inout  wire [2:0]  DDR_ba,
	inout  wire        DDR_cas_n,
	inout  wire        DDR_ck_n,
	inout  wire        DDR_ck_p,
	inout  wire        DDR_cke,
	inout  wire        DDR_cs_n,
	inout  wire [3:0]  DDR_dm,
	inout  wire [31:0] DDR_dq,
	inout  wire [3:0]  DDR_dqs_n,
	inout  wire [3:0]  DDR_dqs_p,
	inout  wire        DDR_odt,
	inout  wire        DDR_ras_n,
	inout  wire        DDR_reset_n,
	inout  wire        DDR_we_n,
	inout  wire        FIXED_IO_ddr_vrn,
	inout  wire        FIXED_IO_ddr_vrp,
	inout  wire [53:0] FIXED_IO_mio,
	inout  wire        FIXED_IO_ps_clk,
	inout  wire        FIXED_IO_ps_porb,
	inout  wire        FIXED_IO_ps_srstb
);

assign ac_addr0 = 1'b0;
assign ac_addr1 = 1'b0;

wire clk24, clk_locked;
wire rst = btnd | ~clk_locked;
wire [0:0] axi_aresetn;

clk_wiz_0 u_clk (.clk_in1(clk100), .reset(btnd), .clk_out1(clk24), .locked(clk_locked));
mclk_out  u_mclk (.clk_24(clk24), .rst(rst), .mclk(ac_mclk));

wire [31:0] araddr, awaddr, wdata, rdata;
wire [2:0]  arprot, awprot;
wire [3:0]  wstrb;
wire [1:0]  bresp, rresp;
wire        arvalid, arready, awvalid, awready, wvalid, wready;
wire        bvalid, bready, rvalid, rready;

enh_ps_wrapper u_ps (
	.DDR_addr(DDR_addr), .DDR_ba(DDR_ba), .DDR_cas_n(DDR_cas_n), .DDR_ck_n(DDR_ck_n),
	.DDR_ck_p(DDR_ck_p), .DDR_cke(DDR_cke), .DDR_cs_n(DDR_cs_n), .DDR_dm(DDR_dm),
	.DDR_dq(DDR_dq), .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p), .DDR_odt(DDR_odt),
	.DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n), .DDR_we_n(DDR_we_n),
	.FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
	.FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
	.FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
	.M_AXI_araddr(araddr), .M_AXI_arprot(arprot), .M_AXI_arready(arready),
	.M_AXI_arvalid(arvalid), .M_AXI_awaddr(awaddr), .M_AXI_awprot(awprot),
	.M_AXI_awready(awready), .M_AXI_awvalid(awvalid), .M_AXI_bready(bready),
	.M_AXI_bresp(bresp), .M_AXI_bvalid(bvalid), .M_AXI_rdata(rdata), .M_AXI_rready(rready),
	.M_AXI_rresp(rresp), .M_AXI_rvalid(rvalid), .M_AXI_wdata(wdata), .M_AXI_wready(wready),
	.M_AXI_wstrb(wstrb), .M_AXI_wvalid(wvalid),
	.aclk(clk100), .axi_aresetn(axi_aresetn), .dcm_locked(clk_locked)
);

enh_core u_core (
	.clk(clk100), .rst(rst), .axi_aresetn(axi_aresetn[0]),
	.s_axi_awaddr(awaddr[3:0]), .s_axi_awprot(awprot), .s_axi_awvalid(awvalid),
	.s_axi_awready(awready), .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
	.s_axi_wvalid(wvalid), .s_axi_wready(wready), .s_axi_bresp(bresp),
	.s_axi_bvalid(bvalid), .s_axi_bready(bready), .s_axi_araddr(araddr[3:0]),
	.s_axi_arprot(arprot), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
	.s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
	.ac_scl(ac_scl), .ac_sda(ac_sda), .ac_bclk(ac_bclk), .ac_lrclk(ac_lrclk),
	.ac_adc_sdata(ac_adc_sdata), .ac_dac_sdata(ac_dac_sdata),
	.sw(sw), .led(led)
);

endmodule
