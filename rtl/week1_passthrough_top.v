// -----------------------------------------------------------------------------
// WEEK-1 SCAFFOLDING — temporary hardware integration top, not the final top.v.
// Requires a Vivado Clocking Wizard IP named clk_wiz_0 configured for:
//   input clk_in1 = 100 MHz; output clk_out1 = 24 MHz; reset active high.
//
// The codec is configured as I2S MAIN and supplies AC-BCLK/AC-LRCLK. The FPGA
// captures left/right ADC samples and plays them back unchanged to left/right
// DAC channels. Week-2 mode_fsm/out_mux/top integration replaces this wrapper.
// -----------------------------------------------------------------------------
module week1_passthrough_top (
    input  wire clk100,
    input  wire rst,
    inout  wire ac_scl,
    inout  wire ac_sda,
    output wire ac_mclk,
    input  wire ac_bclk,
    input  wire ac_lrclk,
    input  wire ac_adc_sdata,
    output wire ac_dac_sdata,
    output wire ac_addr0,
    output wire ac_addr1,
    output wire codec_ready,
    output wire codec_error,
    output wire sample_tick,
    output wire signed [23:0] x_ref_debug,
    output wire signed [23:0] e_err_debug
);
    wire clk24;
    wire clk_locked;
    wire sys_rst = rst | ~clk_locked;
    wire signed [23:0] x_ref;
    wire signed [23:0] e_err;

    assign ac_addr0 = 1'b0;
    assign ac_addr1 = 1'b0;
    assign x_ref_debug = x_ref;
    assign e_err_debug = e_err;

    // Create this IP in Vivado using the configuration in docs/WEEK1_README.md.
    clk_wiz_0 u_clocking_wizard (
        .clk_in1(clk100),
        .reset(rst),
        .clk_out1(clk24),
        .locked(clk_locked)
    );

    mclk_out u_mclk_out (
        .clk_24(clk24), .rst(sys_rst), .mclk(ac_mclk)
    );

    codec_cfg u_codec_cfg (
        .clk(clk100), .rst(sys_rst),
        .codec_scl(ac_scl), .codec_sda(ac_sda),
        .busy(), .ready(codec_ready), .error(codec_error)
    );

    i2s_rx u_i2s_rx (
        .clk(clk100), .rst(sys_rst),
        .bclk_in(ac_bclk), .lrclk_in(ac_lrclk),
        .adc_sdata(ac_adc_sdata),
        .x_ref(x_ref), .e_err(e_err), .sample_tick(sample_tick)
    );

    // Week-1 stereo passthrough. Week-2 mono ANC/music sources can be
    // duplicated onto both inputs when the output mux is integrated.
    i2s_tx u_i2s_tx (
        .clk(clk100), .rst(sys_rst),
        .bclk_in(ac_bclk), .lrclk_in(ac_lrclk),
        .sample_tick(sample_tick),
        .dac_left(x_ref), .dac_right(e_err),
        .dac_sdata(ac_dac_sdata)
    );
endmodule
