`timescale 1ns / 1ps
// Member C simulation: known power levels for the approximate dBFS converter.
module tb_db_calc;
    reg [63:0] power_q46;
    wire signed [15:0] db_centi;

    db_calc dut (.power_q46(power_q46), .db_centi(db_centi));

    task check_level;
        input [63:0] power_value;
        input signed [15:0] expected_value;
        input integer tolerance;
        integer difference;
        begin
            power_q46 = power_value;
            #2;
            difference = db_centi - expected_value;
            if (difference < 0) difference = -difference;
            if (difference > tolerance)
                $fatal(1, "dB calc mismatch power=%h got=%0d expected=%0d", power_q46, db_centi, expected_value);
        end
    endtask

    initial begin
        check_level(64'd1 << 46, 16'sd0, 1);       // 1.0 FS^2 = 0 dBFS
        check_level(64'd1 << 44, -16'sd602, 1);    // 0.25 = -6.02 dBFS
        check_level(64'd1 << 43, -16'sd903, 1);    // 0.125 = -9.03 dBFS
        check_level(64'd1 << 40, -16'sd1806, 1);   // 1/64 = -18.06 dBFS
        check_level(64'd0, -16'sd12000, 0);        // floor for silence
        $display("PASS: db_calc known Q2.46 levels verified");
        $finish;
    end
endmodule
