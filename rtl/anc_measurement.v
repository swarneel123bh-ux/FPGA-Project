`timescale 1ns / 1ps
// Member C: two-phase physical ANC measurement helper.
// Capture the error-microphone signal with ANC disabled (baseline), then with
// ANC enabled (residual). Each phase needs 2**WINDOW_LOG2 valid samples.
// attenuation_db_centi = baseline dBFS - residual dBFS; positive is improvement.
module anc_measurement #(
    parameter integer WINDOW_LOG2 = 10
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              clear_measurements,
    input  wire              sample_valid,
    input  wire signed [23:0] error_sample,
    input  wire              capture_baseline,
    input  wire              capture_residual,
    output wire [63:0]       baseline_power_q46,
    output wire [63:0]       residual_power_q46,
    output wire signed [15:0] baseline_db_centi,
    output wire signed [15:0] residual_db_centi,
    output reg signed [15:0] attenuation_db_centi,
    output reg               baseline_ready,
    output reg               residual_ready,
    output wire              attenuation_valid,
    output wire [31:0]       baseline_samples,
    output wire [31:0]       residual_samples
);
    wire baseline_window_done;
    wire residual_window_done;
    wire [23:0] baseline_peak_unused;
    wire [23:0] residual_peak_unused;
    wire [31:0] baseline_windows_unused;
    wire [31:0] residual_windows_unused;

    power_meter #(.WINDOW_LOG2(WINDOW_LOG2)) baseline_meter (
        .clk(clk), .rst(rst), .clear_window(clear_measurements),
        .sample_valid(sample_valid && capture_baseline), .sample_in(error_sample),
        .mean_square_q46(baseline_power_q46), .peak_abs(baseline_peak_unused),
        .window_done(baseline_window_done), .total_samples(baseline_samples),
        .windows_completed(baseline_windows_unused)
    );

    power_meter #(.WINDOW_LOG2(WINDOW_LOG2)) residual_meter (
        .clk(clk), .rst(rst), .clear_window(clear_measurements),
        .sample_valid(sample_valid && capture_residual), .sample_in(error_sample),
        .mean_square_q46(residual_power_q46), .peak_abs(residual_peak_unused),
        .window_done(residual_window_done), .total_samples(residual_samples),
        .windows_completed(residual_windows_unused)
    );

    db_calc baseline_db (
        .power_q46(baseline_power_q46), .db_centi(baseline_db_centi)
    );
    db_calc residual_db (
        .power_q46(residual_power_q46), .db_centi(residual_db_centi)
    );

    wire signed [16:0] attenuation_wide =
        $signed({baseline_db_centi[15], baseline_db_centi}) -
        $signed({residual_db_centi[15], residual_db_centi});

    assign attenuation_valid = baseline_ready && residual_ready;

    always @(posedge clk) begin
        if (rst || clear_measurements) begin
            baseline_ready <= 1'b0;
            residual_ready <= 1'b0;
            attenuation_db_centi <= 16'sd0;
        end else begin
            if (baseline_window_done) baseline_ready <= 1'b1;
            if (residual_window_done) residual_ready <= 1'b1;
            if (baseline_ready && residual_ready) begin
                if (attenuation_wide > 17'sd32767)
                    attenuation_db_centi <= 16'sh7fff;
                else if (attenuation_wide < -17'sd32768)
                    attenuation_db_centi <= 16'sh8000;
                else
                    attenuation_db_centi <= attenuation_wide[15:0];
            end else if (baseline_window_done && residual_ready) begin
                attenuation_db_centi <= attenuation_wide[15:0];
            end else if (residual_window_done && baseline_ready) begin
                attenuation_db_centi <= attenuation_wide[15:0];
            end
        end
    end
endmodule
