`timescale 1ns/1ps
module tb_i2s_rx;
    reg clk = 0;
    reg rst = 1;
    reg bclk = 0;
    reg lrclk = 1;
    reg adc_sdata = 0;
    wire signed [23:0] x_ref, e_err;
    wire sample_tick;
    integer frame;
    reg [23:0] expected_l, expected_r;

    always #5 clk = ~clk;       // 100 MHz
    always #50 bclk = ~bclk;    // 10 MHz simulation BCLK (timing ratio only)

    i2s_rx dut (
        .clk(clk), .rst(rst), .bclk_in(bclk), .lrclk_in(lrclk),
        .adc_sdata(adc_sdata), .x_ref(x_ref), .e_err(e_err),
        .sample_tick(sample_tick)
    );

    // Drive a channel using I2S timing: LRCLK changes first; MSB is driven
    // on the next falling BCLK edge and sampled on the following rising edge.
    task send_channel;
        input channel; // 0=left, 1=right
        input [23:0] sample;
        integer k;
        begin
            @(negedge bclk);
            lrclk = channel;
            adc_sdata = 1'b0;
            for (k=0; k<24; k=k+1) begin
                @(negedge bclk);
                adc_sdata = sample[23-k];
            end
        end
    endtask

    task pad_slot;
        integer k;
        begin
            for (k=0; k<8; k=k+1) begin
                @(negedge bclk);
                adc_sdata = 1'b0;
            end
        end
    endtask

    initial begin
        repeat (10) @(negedge clk);
        rst = 0;
        // First left/right pair after a word-select transition.
        expected_l = 24'h812345;
        expected_r = 24'h7ABCDE;
        send_channel(1'b0, expected_l);
        pad_slot;
        send_channel(1'b1, expected_r);
        @(posedge sample_tick);
        pad_slot;
        #1;
        if (x_ref !== expected_l || e_err !== expected_r)
            $fatal(1, "I2S RX mismatch: L=%h expected=%h R=%h expected=%h",
                   x_ref, expected_l, e_err, expected_r);

        expected_l = 24'h000001;
        expected_r = 24'hFFFFFF;
        send_channel(1'b0, expected_l);
        pad_slot;
        send_channel(1'b1, expected_r);
        @(posedge sample_tick);
        pad_slot;
        #1;
        if (x_ref !== expected_l || e_err !== expected_r)
            $fatal(1, "I2S RX second frame mismatch");

        $display("PASS: i2s_rx captured two signed stereo I2S frames.");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "tb_i2s_rx timeout");
    end
endmodule
