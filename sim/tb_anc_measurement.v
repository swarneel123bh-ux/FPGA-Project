`timescale 1ns / 1ps
// Member C simulation: capture ANC-off baseline then ANC-on residual.
module tb_anc_measurement;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg clear_measurements = 1'b0;
    reg sample_valid = 1'b0;
    reg signed [23:0] error_sample = 24'sd0;
    reg capture_baseline = 1'b0;
    reg capture_residual = 1'b0;

    wire [63:0] baseline_power_q46;
    wire [63:0] residual_power_q46;
    wire signed [15:0] baseline_db_centi;
    wire signed [15:0] residual_db_centi;
    wire signed [15:0] attenuation_db_centi;
    wire baseline_ready;
    wire residual_ready;
    wire attenuation_valid;
    wire [31:0] baseline_samples;
    wire [31:0] residual_samples;
    integer i;

    anc_measurement #(.WINDOW_LOG2(4)) dut (
        .clk(clk), .rst(rst), .clear_measurements(clear_measurements),
        .sample_valid(sample_valid), .error_sample(error_sample),
        .capture_baseline(capture_baseline), .capture_residual(capture_residual),
        .baseline_power_q46(baseline_power_q46), .residual_power_q46(residual_power_q46),
        .baseline_db_centi(baseline_db_centi), .residual_db_centi(residual_db_centi),
        .attenuation_db_centi(attenuation_db_centi),
        .baseline_ready(baseline_ready), .residual_ready(residual_ready),
        .attenuation_valid(attenuation_valid),
        .baseline_samples(baseline_samples), .residual_samples(residual_samples)
    );

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk); clear_measurements = 1'b1;
        @(negedge clk); clear_measurements = 1'b0;

        // Baseline (ANC off): error microphone receives 0.5 FS.
        capture_baseline = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); sample_valid = 1'b1; error_sample = 24'sd4194304;
        end
        @(negedge clk); sample_valid = 1'b0; capture_baseline = 1'b0;
        repeat (2) @(negedge clk);
        if (!baseline_ready || baseline_power_q46 !== (64'd1 << 44) || baseline_db_centi !== -16'sd602)
            $fatal(1, "Baseline capture failed power=%h dB=%0d", baseline_power_q46, baseline_db_centi);

        // Residual (ANC on): error microphone receives 0.125 FS.
        capture_residual = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); sample_valid = 1'b1; error_sample = 24'sd1048576;
        end
        @(negedge clk); sample_valid = 1'b0; capture_residual = 1'b0;
        repeat (3) @(negedge clk);

        if (!attenuation_valid || !residual_ready)
            $fatal(1, "Measurement validity flags not asserted");
        if (residual_power_q46 !== (64'd1 << 40))
            $fatal(1, "Residual power mismatch: %h", residual_power_q46);
        if (attenuation_db_centi !== 16'sd1204)
            $fatal(1, "Attenuation mismatch: got %0d centi-dB expected 1204", attenuation_db_centi);

        $display("PASS: baseline/residual power and ANC attenuation measurement verified (%0.2f dB)", attenuation_db_centi / 100.0);
        $finish;
    end
endmodule
