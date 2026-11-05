`timescale 1ns / 1ps
// Member C simulation: LFSR probe -> synthetic secondary path -> LMS identifier.
// The Python vector sec_expected_shat.hex is the bit-exact expected final RAM.
module tb_sec_path_id;
    localparam integer M = 128;
    localparam integer NUM_SAMPLES = 8000;
    localparam signed [23:0] S2_Q22 = 24'sh2CCCCD; // 0.70
    localparam signed [23:0] S3_Q22 = 24'sh0CCCCD; // 0.20

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg coeff_clear = 1'b0;
    reg calibrate_enable = 1'b1;
    reg lfsr_enable = 1'b0;
    wire [22:0] lfsr_state;
    wire signed [23:0] probe_out;
    wire probe_valid;
    wire feedback = lfsr_state[22] ^ lfsr_state[17];

    reg signed [23:0] measured_in = 24'sd0;
    wire ready;
    wire busy;
    wire done;
    wire id_error_valid;
    wire signed [23:0] id_error;
    wire [31:0] sample_count;
    wire [15:0] last_id_cycles;
    wire coeff_overflow;
    wire sample_overrun;
    reg [6:0] shat_addr = 7'd0;
    wire signed [23:0] shat_data;

    reg signed [23:0] plant_history [0:3];
    reg [23:0] expected_shat [0:M-1];
    reg signed [23:0] predicted_probe;
    reg signed [47:0] plant_product2;
    reg signed [47:0] plant_product3;
    reg signed [63:0] plant_accum;
    integer i;
    integer j;
    integer errors;

    lfsr probe_generator (
        .clk(clk), .rst(rst), .enable(lfsr_enable),
        .state(lfsr_state), .sample_out(probe_out), .sample_valid(probe_valid)
    );

    sec_path_id #(.M(M), .MU_S_SHIFT(6)) dut (
        .clk(clk), .rst(rst), .coeff_clear(coeff_clear),
        .calibrate_enable(calibrate_enable), .sample_tick(probe_valid),
        .probe_in(probe_out), .measured_in(measured_in),
        .ready(ready), .busy(busy), .done(done),
        .id_error_valid(id_error_valid), .id_error(id_error),
        .sample_count(sample_count), .last_id_cycles(last_id_cycles),
        .coeff_overflow(coeff_overflow), .sample_overrun(sample_overrun),
        .shat_addr(shat_addr), .shat_data(shat_data)
    );

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
            else begin
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

    // Create the same causal FIR measurement as Member B's synthetic S path.
    // A predicted LFSR sample is used before the LFSR clock edge; measured_in
    // is held until sec_path_id accepts probe_valid one clock later.
    task send_probe_sample;
        begin
            @(negedge clk);
            predicted_probe = feedback ? 24'sd2097152 : -24'sd2097152;
            for (j = 3; j > 0; j = j - 1)
                plant_history[j] = plant_history[j-1];
            plant_history[0] = predicted_probe;

            plant_product2 =
                $signed({{24{S2_Q22[23]}}, S2_Q22}) *
                $signed({{24{plant_history[2][23]}}, plant_history[2]});
            plant_product3 =
                $signed({{24{S3_Q22[23]}}, S3_Q22}) *
                $signed({{24{plant_history[3][23]}}, plant_history[3]});
            plant_accum = {{16{plant_product2[47]}}, plant_product2}
                        + {{16{plant_product3[47]}}, plant_product3};
            measured_in = sat24_tb(round_shift64_tb(plant_accum, 22));

            lfsr_enable = 1'b1;
            @(negedge clk);
            lfsr_enable = 1'b0;
            // First rising edge advanced LFSR; next rising edge is when the
            // identifier sees sample_valid=1 and consumes this probe/measurement.
            @(negedge clk);
            wait (done === 1'b1);
            @(negedge clk);
        end
    endtask

    initial begin
        errors = 0;
        predicted_probe = 24'sd0;
        $readmemh("sim/vectors/sec_expected_shat.hex", expected_shat);
        for (i = 0; i < 4; i = i + 1)
            plant_history[i] = 24'sd0;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        for (i = 0; i < NUM_SAMPLES; i = i + 1)
            send_probe_sample;

        if (sample_count !== NUM_SAMPLES) begin
            $display("sample_count mismatch got=%0d expected=%0d", sample_count, NUM_SAMPLES);
            errors = errors + 1;
        end
        if (last_id_cycles !== 16'd256) begin
            $display("last_id_cycles mismatch got=%0d expected=256", last_id_cycles);
            errors = errors + 1;
        end
        if (coeff_overflow !== 1'b0) begin
            $display("Unexpected coefficient saturation/overflow");
            errors = errors + 1;
        end
        if (sample_overrun !== 1'b0) begin
            $display("Unexpected calibration sample overrun");
            errors = errors + 1;
        end

        // Verify the entire coefficient bank through the same synchronous read
        // port that Member B's fxlms.v uses.
        for (i = 0; i < M; i = i + 1) begin
            @(negedge clk);
            shat_addr = i[6:0];
            @(posedge clk);
            #1;
            if (shat_data !== expected_shat[i]) begin
                $display("shat mismatch tap=%0d got=%h expected=%h", i, shat_data, expected_shat[i]);
                errors = errors + 1;
                if (errors >= 10) $fatal(1, "Too many coefficient mismatches");
            end
        end

        if (errors == 0)
            $display("PASS: sec_path_id converged bit-for-bit with Python; %0d samples, %0d cycles/sample", sample_count, last_id_cycles);
        else
            $fatal(1, "FAIL: %0d secondary-path ID mismatches", errors);
        $finish;
    end
endmodule
