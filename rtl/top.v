`timescale 1ns/1ps
// Member A integration top. Clocking Wizard clk_wiz_0: 100 MHz -> 24 MHz.
// mode_sel SW[1:0]: 00 ANC, 01 bypass, 10 music. BTN0 recalibrate.
// music/music_underrun are the interface boundary for Member D's PL path;
// connect treble_fixed and music_fifo_axi in the block design when available.
module top(
 input wire clk100, input wire rst,
 input wire [1:0] sw, input wire recal_btn,
 inout wire ac_scl, inout wire ac_sda,
 output wire ac_mclk, input wire ac_bclk, input wire ac_lrclk,
 input wire ac_adc_sdata, output wire ac_dac_sdata,
 output wire ac_addr0, output wire ac_addr1,
 output wire [7:0] led
);
 wire clk24, clk_locked;
 wire sys_rst = rst | ~clk_locked;
 wire signed [23:0] x_ref, e_err, v_lfsr, y_anti, dac_out;
 // Goal-2 path is parked at zero until Member D's RTL is merged.
 wire signed [23:0] music = 24'sd0;
 wire music_underrun = 1'b0;
 wire codec_ready, codec_error, sample_tick;
 wire [2:0] mode;
 wire cal_en, anc_en, w_reset, cal_done_pulse;
 wire [6:0] shat_addr;
 wire signed [23:0] shat_data;
 wire w_over;
 wire lfsr_valid;
 wire diverge = w_over; // TODO: replace with Member C divergence_mon output when merged.

 assign ac_addr0=1'b0; assign ac_addr1=1'b0;
 assign led[2:0]=mode; assign led[3]=w_over; assign led[4]=music_underrun;
 assign led[7:5]={sample_tick,codec_error,codec_ready};

 clk_wiz_0 u_clocking_wizard(.clk_in1(clk100),.reset(rst),.clk_out1(clk24),.locked(clk_locked));
 mclk_out u_mclk(.clk_24(clk24),.rst(sys_rst),.mclk(ac_mclk));
 codec_cfg u_codec(.clk(clk100),.rst(sys_rst),.codec_scl(ac_scl),.codec_sda(ac_sda),
                   .busy(),.ready(codec_ready),.error(codec_error));
 i2s_rx u_rx(.clk(clk100),.rst(sys_rst),.bclk_in(ac_bclk),.lrclk_in(ac_lrclk),
             .adc_sdata(ac_adc_sdata),.x_ref(x_ref),.e_err(e_err),.sample_tick(sample_tick));
 lfsr u_probe(.clk(clk100),.rst(sys_rst),.enable(cal_en && sample_tick),
              .state(),.sample_out(v_lfsr),.sample_valid(lfsr_valid));
 sec_path_id #(.M(128),.MU_S_SHIFT(6)) u_pathid(
   .clk(clk100),.rst(sys_rst),.coeff_clear(w_reset),.calibrate_enable(cal_en),
   .sample_tick(sample_tick),.probe_in(v_lfsr),.measured_in(e_err),
   .ready(),.busy(),.done(),.id_error_valid(),.id_error(),.sample_count(),
   .last_id_cycles(),.coeff_overflow(),.sample_overrun(),
   .shat_addr(shat_addr),.shat_data(shat_data));
 fxlms #(.L(64),.M(128),.MU_SHIFT(7),.SHAT_ADDR_W(7)) u_fxlms(
   .clk(clk100),.rst(sys_rst),.sample_tick(sample_tick),.anc_en(anc_en),.w_reset(w_reset),
   .x_ref(x_ref),.e_err(e_err),.y_anti(y_anti),.shat_addr(shat_addr),
   .shat_data(shat_data),.w_over(w_over));
 mode_fsm #(.CLK_HZ(100_000_000),.CALIBRATION_SECONDS(5)) u_mode(
   .clk(clk100),.rst(sys_rst),.mode_sel(sw[1:0]),.recalibrate(recal_btn),
   .cal_done(1'b0),.diverge(diverge),.fifo_underrun(music_underrun),
   .mode(mode),.cal_en(cal_en),.anc_en(anc_en),.w_reset(w_reset),.cal_done_pulse(cal_done_pulse));
 out_mux u_mux(.mode(mode),.v_lfsr(v_lfsr),.y_anti(y_anti),.music(music),
               .fifo_underrun(music_underrun),.dac_out(dac_out));
 i2s_tx u_tx(.clk(clk100),.rst(sys_rst),.bclk_in(ac_bclk),.lrclk_in(ac_lrclk),
   .sample_tick(sample_tick),.dac_left(dac_out),.dac_right(dac_out),.dac_sdata(ac_dac_sdata));
endmodule
