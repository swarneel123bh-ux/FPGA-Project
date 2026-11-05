`timescale 1ns / 1ps
// Member C simulation: verify Q2.46 mean-square calculations.
module tb_power_meter;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg clear_window = 1'b0;
    reg sample_valid = 1'b0;
    reg signed [23:0] sample_in = 24'sd0;
    wire [63:0] mean_square_q46;
    wire [23:0] peak_abs;
    wire window_done;
    wire [31:0] total_samples;
    wire [31:0] windows_completed;
    integer i;

    power_meter #(.WINDOW_LOG2(4)) dut (
        .clk(clk), .rst(rst), .clear_window(clear_window),
        .sample_valid(sample_valid), .sample_in(sample_in),
        .mean_square_q46(mean_square_q46), .peak_abs(peak_abs),
        .window_done(window_done), .total_samples(total_samples),
        .windows_completed(windows_completed)
    );

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // 16 samples at +0.5 FS => mean-square = 0.25 (Q2.46 = 2^44).
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); sample_valid = 1'b1; sample_in = 24'sd4194304;
        end
        @(negedge clk); sample_valid = 1'b0;
        if (window_done !== 1'b1 || mean_square_q46 !== (64'd1 << 44) || peak_abs !== 24'd4194304)
            $fatal(1, "Power meter first-window test failed: done=%b power=%h peak=%0d", window_done, mean_square_q46, peak_abs);

        @(negedge clk); clear_window = 1'b1;
        @(negedge clk); clear_window = 1'b0;
        // Alternating +/-0.25 FS => mean-square = 0.0625 (Q2.46 = 2^42).
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk);
            sample_valid = 1'b1;
            sample_in = (i % 2) ? -24'sd2097152 : 24'sd2097152;
        end
        @(negedge clk); sample_valid = 1'b0;
        if (window_done !== 1'b1 || mean_square_q46 !== (64'd1 << 42) || peak_abs !== 24'd2097152)
            $fatal(1, "Power meter second-window test failed: done=%b power=%h peak=%0d", window_done, mean_square_q46, peak_abs);

        $display("PASS: power_meter Q2.46 mean-square and peak outputs verified");
        $finish;
    end
endmodule
