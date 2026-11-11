// NOT TEAM CODE. Lab diagnostic top written by Claude for the 11 Nov 2026 session (T3e debug).
// Same blocks as rtl/week1_passthrough_top.v (Aarav's, unchanged), plus:
//   SW0 up   -> FPGA plays its own 1 kHz square wave (-24 dBFS) to both ears (tests DAC/headphone path)
//   SW0 down -> normal passthrough (left ADC -> left ear, right ADC -> right ear)
//   LD0 codec_ready, LD1 codec_error, LD2 blinks at 1 Hz when LRCLK = 48 kHz
//   SW2 up   -> passthrough is mono: (L+R)/2 to both ears
//   SW3 up   -> passthrough digital gain x32 (+30 dB), saturating
//   SW1 down -> LD7..LD3 = level bar of the louder ADC channel (raw): -78/-66/-54/-42/-30 dBFS
//   BTND -> reset
//   SW1 up   -> LD7..LD3 = first codec_cfg ROM row that NACKed twice (LD3 = bit 0), LD2 = a write was retried
`timescale 1ns / 1ps
module week1_diag_top (
    input  wire clk100,
    input  wire btnd,
    input  wire sw0,
    input  wire sw1,
    input  wire sw2,
    input  wire sw3,
    inout  wire ac_scl,
    inout  wire ac_sda,
    output wire ac_mclk,
    input  wire ac_bclk,
    input  wire ac_lrclk,
    input  wire ac_adc_sdata,
    output wire ac_dac_sdata,
    output wire ac_addr0,
    output wire ac_addr1,
    output wire [7:0] led
);
    wire clk24, clk_locked;
    wire sys_rst = btnd | ~clk_locked;
    wire codec_ready, codec_error, sample_tick;
    wire [4:0] fail_index;
    wire retried;
    wire signed [23:0] x_ref, e_err;

    assign ac_addr0 = 1'b0;
    assign ac_addr1 = 1'b0;

    clk_wiz_0 u_clk (.clk_in1(clk100), .reset(btnd), .clk_out1(clk24), .locked(clk_locked));
    mclk_out  u_mclk (.clk_24(clk24), .rst(sys_rst), .mclk(ac_mclk));
    codec_cfg u_cfg (.clk(clk100), .rst(sys_rst), .codec_scl(ac_scl), .codec_sda(ac_sda),
                     .busy(), .ready(codec_ready), .error(codec_error),
                     .fail_index(fail_index), .retried(retried));
    i2s_rx    u_rx  (.clk(clk100), .rst(sys_rst), .bclk_in(ac_bclk), .lrclk_in(ac_lrclk),
                     .adc_sdata(ac_adc_sdata), .x_ref(x_ref), .e_err(e_err), .sample_tick(sample_tick));

    // switch synchroniser
    reg sw_m = 1'b0, sw_s = 1'b0, sw1_m = 1'b0, sw1_s = 1'b0, sw2_m = 1'b0, sw2_s = 1'b0, sw3_m = 1'b0, sw3_s = 1'b0;
    always @(posedge clk100) begin sw_m <= sw0; sw_s <= sw_m; sw1_m <= sw1; sw1_s <= sw1_m; sw2_m <= sw2; sw2_s <= sw2_m; sw3_m <= sw3; sw3_s <= sw3_m; end

    // 1 kHz square wave: toggle every 24 samples at 48 kHz, amplitude 2^19 (-24 dBFS)
    reg [4:0] half_cnt = 5'd0;
    reg       sq       = 1'b0;
    always @(posedge clk100) begin
        if (sys_rst) begin half_cnt <= 5'd0; sq <= 1'b0; end
        else if (sample_tick) begin
            if (half_cnt == 5'd23) begin half_cnt <= 5'd0; sq <= ~sq; end
            else half_cnt <= half_cnt + 5'd1;
        end
    end
    wire signed [23:0] tone = sq ? 24'sh080000 : -24'sh080000;

    wire signed [24:0] lr_sum = {x_ref[23], x_ref} + {e_err[23], e_err};
    wire signed [23:0] mono   = lr_sum[24:1];   // (L+R)/2
    wire signed [23:0] pl = sw2_s ? mono : x_ref;
    wire signed [23:0] pr = sw2_s ? mono : e_err;
    // SW3 up: x32 (+30 dB) digital gain with saturation
    function signed [23:0] gain32(input signed [23:0] v);
        reg signed [28:0] w;
        begin
            w = {{5{v[23]}}, v} <<< 5;
            if (w > 29'sd8388607)       gain32 = 24'sh7FFFFF;
            else if (w < -29'sd8388608) gain32 = 24'sh800000;
            else                        gain32 = w[23:0];
        end
    endfunction
    wire signed [23:0] dac_l = sw_s ? tone : (sw3_s ? gain32(pl) : pl);
    wire signed [23:0] dac_r = sw_s ? tone : (sw3_s ? gain32(pr) : pr);

    i2s_tx u_tx (.clk(clk100), .rst(sys_rst), .bclk_in(ac_bclk), .lrclk_in(ac_lrclk),
                 .sample_tick(sample_tick), .dac_left(dac_l), .dac_right(dac_r),
                 .dac_sdata(ac_dac_sdata));

    // 1 Hz blink from sample_tick
    reg [14:0] tick_cnt = 15'd0;
    reg        blink    = 1'b0;
    always @(posedge clk100) begin
        if (sys_rst) begin tick_cnt <= 15'd0; blink <= 1'b0; end
        else if (sample_tick) begin
            if (tick_cnt == 15'd23999) begin tick_cnt <= 15'd0; blink <= ~blink; end
            else tick_cnt <= tick_cnt + 15'd1;
        end
    end

    // ADC level detectors: |x| > 2^15 (~-48 dBFS) holds the LED for 4800 samples (0.1 s)
    wire [23:0] abs_l = x_ref[23] ? -x_ref : x_ref;
    wire [23:0] abs_r = e_err[23] ? -e_err : e_err;
    reg [12:0] hold_l = 13'd0, hold_r = 13'd0;
    always @(posedge clk100) begin
        if (sys_rst) begin hold_l <= 0; hold_r <= 0; end
        else if (sample_tick) begin
            hold_l <= (abs_l > 24'd32768) ? 13'd4800 : (hold_l != 0 ? hold_l - 13'd1 : 13'd0);
            hold_r <= (abs_r > 24'd32768) ? 13'd4800 : (hold_r != 0 ? hold_r - 13'd1 : 13'd0);
        end
    end

    // SW1 up: LD7..LD3 = first failing ROM row (binary, LD3 = bit 0), LD2 = a retry happened
    // Level bar of max(|L|,|R|), raw ADC (before SW3 gain), each step held 0.1 s:
    // LD3 > -78 dBFS (2^10), LD4 > -66 (2^12), LD5 > -54 (2^14), LD6 > -42 (2^16), LD7 > -30 (2^18)
    wire [23:0] abs_max = (abs_l > abs_r) ? abs_l : abs_r;
    reg [12:0] hold_b [0:4];
    integer k;
    always @(posedge clk100) begin
        for (k = 0; k < 5; k = k + 1) begin
            if (sys_rst) hold_b[k] <= 13'd0;
            else if (sample_tick)
                hold_b[k] <= (abs_max > (24'd1 << (10 + 2*k))) ? 13'd4800 :
                             (hold_b[k] != 0 ? hold_b[k] - 13'd1 : 13'd0);
        end
    end
    wire [4:0] bar = {hold_b[4] != 0, hold_b[3] != 0, hold_b[2] != 0, hold_b[1] != 0, hold_b[0] != 0};
    assign led = sw1_s ? {fail_index[4], fail_index[3], fail_index[2], fail_index[1], fail_index[0], retried, codec_error, codec_ready}
                       : {bar, blink, codec_error, codec_ready};
endmodule
