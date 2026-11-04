`timescale 1ns / 1ps

// Testbench for Member C's LFSR and secondary-path LMS module.
// Synthetic true secondary path: S[2] = 0.70, S[3] = 0.20.
// All signals use the project's fixed-point formats.

module tb_sec_path_id;

    reg clk;
    reg rst;
    reg lfsr_enable;
    reg sample_tick;
    reg cal_en;
    reg signed [23:0] measured_in;
    reg [6:0] shat_addr;

    wire [22:0] lfsr_state;
    wire signed [23:0] probe_out;
    wire lfsr_valid;
    wire signed [23:0] shat_data;
    wire busy;
    wire done;

    reg signed [23:0] plant_history [0:3];
    reg signed [23:0] probe_value;

    reg signed [23:0] coeff2;
    reg signed [23:0] coeff3;
    reg signed [47:0] product2;
    reg signed [47:0] product3;
    reg signed [63:0] path_accum;

    integer sample_number;
    integer i;
    integer difference;
    integer expected_coefficient;
    integer errors;

    lfsr lfsr_unit(
        .clk(clk),
        .reset(rst),
        .enable(lfsr_enable),
        .state(lfsr_state),
        .sample_out(probe_out),
        .sample_valid(lfsr_valid)
    );

    sec_path_id id_unit(
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .cal_en(cal_en),
        .probe_in(probe_value),
        .measured_in(measured_in),
        .shat_addr(shat_addr),
        .shat_data(shat_data),
        .busy(busy),
        .done(done)
    );

    always #5 clk = ~clk;

    // Round a signed number to nearest, ties away from zero.
    function signed [63:0] round_shift64_tb;
        input signed [63:0] value;
        input integer shift;
        reg signed [63:0] magnitude;
        reg signed [63:0] rounded_magnitude;
        begin
            if (shift <= 0)
                round_shift64_tb = value <<< (-shift);
            else if (value >= 0)
                round_shift64_tb = (value + (64'sd1 <<< (shift-1))) >>> shift;
            else
            begin
                magnitude = -value;
                rounded_magnitude = (magnitude + (64'sd1 <<< (shift-1))) >>> shift;
                round_shift64_tb = -rounded_magnitude;
            end
        end
    endfunction

    function signed [23:0] sat24_tb;
        input signed [63:0] value;
        begin
            if (value > 64'sd8388607)
                sat24_tb = 24'sh7fffff;
            else if (value < -64'sd8388608)
                sat24_tb = 24'sh800000;
            else
                sat24_tb = value[23:0];
        end
    endfunction

    // Generate one LFSR sample, pass it through the synthetic S path,
    // then let the path identifier process that probe/measured pair.
    task run_one_sample;
        begin
            // Advance LFSR for one sample.
            @(negedge clk);
            lfsr_enable = 1'b1;
            @(negedge clk);
            lfsr_enable = 1'b0;

            probe_value = probe_out;

            // Update synthetic physical-path history.
            plant_history[3] = plant_history[2];
            plant_history[2] = plant_history[1];
            plant_history[1] = plant_history[0];
            plant_history[0] = probe_value;

            // Q2.22 coefficients: 0.70 = 24'h2CCCCD; 0.20 = 24'h0CCCCD.
            product2 = $signed({{24{coeff2[23]}}, coeff2}) *
                       $signed({{24{plant_history[2][23]}}, plant_history[2]});
            product3 = $signed({{24{coeff3[23]}}, coeff3}) *
                       $signed({{24{plant_history[3][23]}}, plant_history[3]});

            path_accum = {{16{product2[47]}}, product2} +
                         {{16{product3[47]}}, product3};
            measured_in = sat24_tb(round_shift64_tb(path_accum, 22));

            // The identifier accepts the current probe and measured output.
            @(negedge clk);
            sample_tick = 1'b1;
            @(negedge clk);
            sample_tick = 1'b0;

            // Wait until the 128-tap estimate and 128 coefficient updates finish.
            while (busy !== 1'b1)
                @(negedge clk);
            while (busy !== 1'b0)
                @(negedge clk);
        end
    endtask

    initial
    begin
        clk = 1'b0;
        rst = 1'b1;
        lfsr_enable = 1'b0;
        sample_tick = 1'b0;
        cal_en = 1'b1;
        measured_in = 24'sd0;
        shat_addr = 7'd0;
        probe_value = 24'sd0;
        coeff2 = 24'sh2CCCCD;
        coeff3 = 24'sh0CCCCD;
        errors = 0;

        for (i = 0; i < 4; i = i + 1)
            plant_history[i] = 24'sd0;

        repeat (4) @(negedge clk);
        rst = 1'b0;

        // 10,000 samples are enough for the supplied probe and mu_s=2^-6
        // to identify the two nonzero synthetic path coefficients.
        for (sample_number = 0; sample_number < 10000; sample_number = sample_number + 1)
        begin
            run_one_sample;

            if ((sample_number % 2000) == 1999)
                $display("Processed %0d calibration samples", sample_number + 1);
        end

        // Check all estimated coefficients through the synchronous read port.
        for (i = 0; i < 128; i = i + 1)
        begin
            @(negedge clk);
            shat_addr = i;
            @(negedge clk);

            if (i == 2)
                expected_coefficient = 2936013;
            else if (i == 3)
                expected_coefficient = 838861;
            else
                expected_coefficient = 0;

            difference = $signed(shat_data) - expected_coefficient;
            if (difference < 0)
                difference = -difference;

            if (difference > 10000)
            begin
                $display("ERROR tap=%0d got=%0d expected=%0d difference=%0d",
                         i, $signed(shat_data), expected_coefficient, difference);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: secondary-path LMS identified S[2]=0.70 and S[3]=0.20.");
        else
            $display("FAIL: %0d coefficient checks failed", errors);
        $finish;
    end

endmodule
