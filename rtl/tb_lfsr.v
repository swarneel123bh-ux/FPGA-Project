`timescale 1ns / 1ps

module tb_lfsr;

    reg clk;
    reg reset;
    reg enable;

    wire [22:0] state;
    wire signed [23:0] sample_out;
    wire sample_valid;

    integer expected [0:9];
    integer i;
    integer errors;

    lfsr dut(
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .state(state),
        .sample_out(sample_out),
        .sample_valid(sample_valid)
    );

    always #5 clk = ~clk;

    initial
    begin
        clk = 1'b0;
        reset = 1'b1;
        enable = 1'b0;
        errors = 0;

        expected[0] = -2097152;
        expected[1] = -2097152;
        expected[2] =  2097152;
        expected[3] = -2097152;
        expected[4] = -2097152;
        expected[5] = -2097152;
        expected[6] =  2097152;
        expected[7] = -2097152;
        expected[8] = -2097152;
        expected[9] = -2097152;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        if (state !== 23'h5A5A5A)
        begin
            $display("ERROR: seed is incorrect. Got %h", state);
            errors = errors + 1;
        end

        for (i = 0; i < 10; i = i + 1)
        begin
            @(negedge clk);
            enable = 1'b1;
            @(negedge clk);
            enable = 1'b0;

            if (sample_valid !== 1'b1)
            begin
                $display("ERROR: sample_valid was not asserted at sample %0d", i);
                errors = errors + 1;
            end

            if ($signed(sample_out) !== expected[i])
            begin
                $display("ERROR: sample %0d got %0d expected %0d",
                         i, $signed(sample_out), expected[i]);
                errors = errors + 1;
            end
            else
                $display("Sample %0d: %0d PASS", i, $signed(sample_out));
        end

        if (errors == 0)
            $display("PASS: LFSR seed and first 10 samples match the Python model.");
        else
            $display("FAIL: %0d LFSR errors", errors);
        $finish;
    end

endmodule
