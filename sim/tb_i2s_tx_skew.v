// NOT TEAM CODE. Regression written by Claude on 11 Nov 2026 for the crackle found on the board.
// The codec (I2S master) changes LRCLK on the same falling BCLK edge; on the board LRCLK can reach
// the FPGA a little before or after BCLK. BCLK (3.072 MHz) drifts against the 100 MHz clk, so the
// test runs 200 frames per skew. A model codec decodes dac_sdata on rising BCLK (I2S, one-bit delay)
// and every frame must match. The pre-fix i2s_tx failed 18-100 % of frames for skews of +1 to +8 ns.
`timescale 1ns/1ps
module tb_i2s_tx_skew;
    reg clk = 0; always #5 clk = ~clk;          // 100 MHz
    reg rst = 1;
    reg bclk = 0, lrclk = 0;
    reg sample_tick = 0;
    reg tick_req = 0;
    always @(posedge clk) begin sample_tick <= tick_req; if (tick_req) tick_req <= 0; end
    reg signed [23:0] dl, dr;
    wire sdata;
    i2s_tx dut(.clk(clk), .rst(rst), .bclk_in(bclk), .lrclk_in(lrclk),
               .sample_tick(sample_tick), .dac_left(dl), .dac_right(dr), .dac_sdata(sdata));

    real skew;          // LRCLK edge delay after the BCLK falling edge (ns), may be negative
    integer frames_bad = 0, frames = 0, total_bad = 0;
    // model codec receiver
    reg [31:0] sh; integer bitn; reg lr_prev; reg signed [23:0] got_l, got_r;
    always @(posedge bclk) begin
        if (lrclk != lr_prev) begin bitn = 0; lr_prev = lrclk; end   // transition edge = delay slot
        else begin
            if (bitn < 24) sh = {sh[30:0], sdata};
            bitn = bitn + 1;
            if (bitn == 24) begin
                if (lrclk == 0) got_l = sh[23:0]; else got_r = sh[23:0];
            end
        end
    end

    task run(input real sk, input real bclk_phase);
        integer f, b;
        begin
            skew = sk; frames_bad = 0; frames = 0;
            rst = 1; bclk = 0; lrclk = 0; lr_prev = 0; bitn = 99;
            #(100 + bclk_phase); rst = 0;
            for (f = 0; f < 200; f = f + 1) begin
                dl = 24'sh123456 + f; dr = -24'sh0ABCDE - f;
                // one stereo frame: 64 BCLK, LRCLK low for 32, high for 32; BCLK period 325.5 ns
                for (b = 0; b < 64; b = b + 1) begin
                    // falling BCLK edge; LRCLK changes on b==0 (to L) and b==32 (to R), skewed
                    if (b == 0)  begin if (sk >= 0) begin bclk = 0; #(sk) lrclk = 0; end else begin lrclk = 0; #(-sk) bclk = 0; end end
                    else if (b == 32) begin if (sk >= 0) begin bclk = 0; #(sk) lrclk = 1; end else begin lrclk = 1; #(-sk) bclk = 0; end end
                    else bclk = 0;
                    #(162.76 - ((b == 0 || b == 32) ? (sk >= 0 ? sk : -sk) : 0));
                    bclk = 1;
                    #162.76;
                    // pulse sample_tick once per frame mid-right word, like i2s_rx does
                    if (b == 60) tick_req = 1;   // no re-alignment: BCLK drifts against clk
                end
                if (f > 3) begin
                    frames = frames + 1;
                    // data latched on tick of frame f is sent in frame f+1
                    if (got_l !== 24'sh123456 + f - 1 || got_r !== -24'sh0ABCDE - (f - 1)) frames_bad = frames_bad + 1;
                end
            end
            if (frames_bad != 0)
                $display("FAIL skew %6.2f ns: %0d/%0d frames wrong (last L=%h R=%h)",
                         sk, frames_bad, frames, got_l, got_r);
            total_bad = total_bad + frames_bad;
        end
    endtask

    initial begin
        run(-60.0, 0.0);
        run(-15.0, 0.0);
        run(-8.0, 0.0);
        run(-3.0, 0.0);
        run(-1.0, 0.0);
        run(0.0, 0.0);
        run(1.0, 0.0);
        run(2.0, 0.0);
        run(3.0, 0.0);
        run(4.0, 0.0);
        run(6.0, 0.0);
        run(8.0, 0.0);
        run(15.0, 0.0);
        run(60.0, 0.0);
        if (total_bad != 0) $fatal(1, "i2s_tx sent wrong frames under LRCLK/BCLK skew");
        $display("PASS: i2s_tx correct for LRCLK skew -60..+60 ns, 200 drifting frames each");
        $finish;
    end
endmodule
