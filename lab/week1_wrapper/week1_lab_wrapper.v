// NOT TEAM CODE. Lab scaffolding written by Claude for the 11 Nov 2026 hardware session (T3).
// Wraps Aarav's week1_passthrough_top unchanged so every top-level port has a pin:
//   BTND (R16)  -> rst (active high, same pin as constraints/zedboard.xdc)
//   LD0         <- codec_ready   (on = I2C configuration finished)
//   LD1         <- codec_error   (on = codec did not ACK an I2C write)
//   LD2         <- sample_tick / 24000, toggled: blinks at 1 Hz (on 1 s, off 1 s) when LRCLK = 48 kHz
// The 24-bit debug buses stay internal. Not for rtl/; delete after the session.
`timescale 1ns / 1ps
module week1_lab_wrapper (
    input  wire clk100,
    input  wire btnd,
    inout  wire ac_scl,
    inout  wire ac_sda,
    output wire ac_mclk,
    input  wire ac_bclk,
    input  wire ac_lrclk,
    input  wire ac_adc_sdata,
    output wire ac_dac_sdata,
    output wire ac_addr0,
    output wire ac_addr1,
    output wire [2:0] led
);
    wire codec_ready, codec_error, sample_tick;

    week1_passthrough_top u_dut (
        .clk100(clk100), .rst(btnd),
        .ac_scl(ac_scl), .ac_sda(ac_sda),
        .ac_mclk(ac_mclk), .ac_bclk(ac_bclk), .ac_lrclk(ac_lrclk),
        .ac_adc_sdata(ac_adc_sdata), .ac_dac_sdata(ac_dac_sdata),
        .ac_addr0(ac_addr0), .ac_addr1(ac_addr1),
        .codec_ready(codec_ready), .codec_error(codec_error),
        .sample_tick(sample_tick),
        .x_ref_debug(), .e_err_debug()
    );

    reg [14:0] tick_cnt = 15'd0;
    reg        blink    = 1'b0;
    always @(posedge clk100) begin
        if (btnd) begin
            tick_cnt <= 15'd0;
            blink    <= 1'b0;
        end else if (sample_tick) begin
            if (tick_cnt == 15'd23999) begin
                tick_cnt <= 15'd0;
                blink    <= ~blink;
            end else begin
                tick_cnt <= tick_cnt + 15'd1;
            end
        end
    end

    assign led = {blink, codec_error, codec_ready};
endmodule
