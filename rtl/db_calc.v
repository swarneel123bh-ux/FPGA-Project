`timescale 1ns / 1ps
// Member C: approximate dBFS calculator for unsigned mean-square Q2.46.
// Output is signed centi-dBFS (e.g. -602 means -6.02 dBFS).
// A 4-bit mantissa lookup gives sub-0.1 dB-class resolution for ordinary levels.
// Zero power is reported as -120.00 dBFS.
module db_calc(
    input  wire [63:0]      power_q46,
    output reg signed [15:0] db_centi
);
    reg [6:0] msb_index;
    reg [3:0] mantissa_index;
    reg signed [31:0] log2_q8;
    reg signed [63:0] numerator;
    integer i;
    integer db_value;

    function integer log2_fraction_q8;
        input [3:0] index;
        begin
            case (index)
                4'd0:  log2_fraction_q8 = 0;
                4'd1:  log2_fraction_q8 = 22;
                4'd2:  log2_fraction_q8 = 44;
                4'd3:  log2_fraction_q8 = 63;
                4'd4:  log2_fraction_q8 = 82;
                4'd5:  log2_fraction_q8 = 100;
                4'd6:  log2_fraction_q8 = 118;
                4'd7:  log2_fraction_q8 = 134;
                4'd8:  log2_fraction_q8 = 150;
                4'd9:  log2_fraction_q8 = 165;
                4'd10: log2_fraction_q8 = 179;
                4'd11: log2_fraction_q8 = 193;
                4'd12: log2_fraction_q8 = 207;
                4'd13: log2_fraction_q8 = 220;
                4'd14: log2_fraction_q8 = 232;
                default: log2_fraction_q8 = 244;
            endcase
        end
    endfunction

    always @* begin
        msb_index = 7'd0;
        mantissa_index = 4'd0;
        log2_q8 = 32'sd0;
        numerator = 64'sd0;
        db_value = -12000;
        db_centi = -16'sd12000;

        if (power_q46 != 64'd0) begin
            for (i = 0; i < 64; i = i + 1)
                if (power_q46[i]) msb_index = i;

            if (msb_index >= 4)
                mantissa_index = (power_q46 >> (msb_index - 4)) & 64'hF;
            else
                mantissa_index = (power_q46 << (4 - msb_index)) & 64'hF;

            // Divide by 2^46 to normalize Q2.46 power to full-scale squared.
            log2_q8 = ($signed({1'b0, msb_index}) - 32'sd46) * 32'sd256
                      + log2_fraction_q8(mantissa_index);
            // dB*100 = 301.03 * log2(power / 2^46).
            numerator = $signed(log2_q8) * 64'sd30103;
            if (numerator >= 0)
                db_value = (numerator + 64'sd12800) / 64'sd25600;
            else
                db_value = -(((-numerator) + 64'sd12800) / 64'sd25600);

            if (db_value > 32767)
                db_centi = 16'sh7fff;
            else if (db_value < -32768)
                db_centi = 16'sh8000;
            else
                db_centi = db_value;
        end
    end
endmodule
