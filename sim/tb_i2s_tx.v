`timescale 1ns/1ps
module tb_i2s_tx;
    reg clk = 0;
    reg rst = 1;
    reg bclk = 0;
    reg lrclk = 1;
    reg sample_tick = 0;
    reg signed [23:0] dac_left = 24'sd0;
    reg signed [23:0] dac_right = 24'sd0;
    wire dac_sdata;
    integer k;
    reg [23:0] captured_l, captured_r;

    always #5 clk = ~clk;
    always #50 bclk = ~bclk;

    i2s_tx dut (
        .clk(clk), .rst(rst), .bclk_in(bclk), .lrclk_in(lrclk),
        .sample_tick(sample_tick), .dac_left(dac_left),
        .dac_right(dac_right), .dac_sdata(dac_sdata)
    );

    // Send one frame of LRCLK/BCLK to establish timing, then capture the
    // next frame. The TX data is sampled on rising BCLK after the I2S delay.
    task send_slot;
        input channel;
        output [23:0] captured;
        integer n;
        reg [23:0] tmp;
        begin
            tmp = 0;
            @(negedge bclk); lrclk = channel;
            // I2S one-bit delay slot: ignore first rising edge.
            @(posedge bclk);
            for (n=0; n<24; n=n+1) begin
                @(posedge bclk);
                tmp = {tmp[22:0], dac_sdata};
            end
            for (n=0; n<8; n=n+1) @(posedge bclk);
            captured = tmp;
        end
    endtask

    initial begin
        repeat (10) @(negedge clk);
        rst = 0;
        // Let the TX capture a new stereo pair on sample_tick.
        @(negedge clk);
        dac_left = 24'h812345;
        dac_right = 24'h7ABCDE;
        sample_tick = 1;
        @(negedge clk);
        sample_tick = 0;

        // The first observed slot may be partial; wait for the next left edge.
        send_slot(1'b0, captured_l);
        send_slot(1'b1, captured_r);
        #1;
        if (captured_l !== 24'h812345 || captured_r !== 24'h7ABCDE)
            $fatal(1, "I2S TX mismatch: L=%h R=%h", captured_l, captured_r);
        $display("PASS: i2s_tx serialized the stereo sample pair.");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "tb_i2s_tx timeout");
    end
endmodule
