`timescale 1ns/1ps
module tb_codec_cfg;
    reg clk = 0;
    reg rst = 1;
    wire scl;
    wire sda;
    reg slave_sda_low = 0;
    wire busy, ready, error;
    reg active = 0;
    reg [7:0] rx_byte = 0;
    integer bit_count = 0;
    integer byte_count = 0;
    integer transaction_count = 0;
    integer expected_len;

    assign sda = slave_sda_low ? 1'b0 : 1'bz;
    pullup(scl);
    pullup(sda);
    always #5 clk = ~clk;

    codec_cfg #(
        .CLK_HZ(100_000_000), .I2C_HZ(10_000_000),
        .POWERUP_CYCLES(4), .PLL_WAIT_CYCLES(4), .HP_WAIT_CYCLES(4)
    ) dut (
        .clk(clk), .rst(rst), .codec_scl(scl), .codec_sda(sda),
        .busy(busy), .ready(ready), .error(error)
    );

    function integer expected_transaction_length;
        input integer t;
        begin
            if ((t == 1) || (t == 2)) expected_transaction_length = 9;
            else expected_transaction_length = 4;
        end
    endfunction

    function [7:0] expected_byte;
        input integer t;
        input integer b;
        begin
            expected_byte = 8'hxx;
            if (b == 0) expected_byte = 8'h70; // 7-bit 0x38 + write bit
            else begin
                case (t)
                    0: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h00; 3:expected_byte=8'h00; endcase
                    1: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h02; 3,4,5,6,7,8:expected_byte=8'h00; endcase
                    2: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h02; 3:expected_byte=8'h00; 4:expected_byte=8'h7D; 5:expected_byte=8'h00; 6:expected_byte=8'h0C; 7:expected_byte=8'h23; 8:expected_byte=8'h01; endcase
                    3: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h00; 3:expected_byte=8'h0F; endcase
                    4: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h15; 3:expected_byte=8'h01; endcase
                    5: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h16; 3:expected_byte=8'h00; endcase
                    6: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h17; 3:expected_byte=8'h00; endcase
                    7: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h09; 3:expected_byte=8'h00; endcase
                    8: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h0A; 3:expected_byte=8'h51; endcase
                    9: case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h0C; 3:expected_byte=8'h51; endcase
                    10:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h19; 3:expected_byte=8'h23; endcase
                    11:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h1A; 3:expected_byte=8'h00; endcase
                    12:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h1B; 3:expected_byte=8'h00; endcase
                    13:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h29; 3:expected_byte=8'h03; endcase
                    14:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h2A; 3:expected_byte=8'h03; endcase
                    15:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h1C; 3:expected_byte=8'h21; endcase
                    16:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h1E; 3:expected_byte=8'h41; endcase
                    17:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h23; 3:expected_byte=8'h6C; endcase
                    18:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h24; 3:expected_byte=8'h6D; endcase
                    19:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h23; 3:expected_byte=8'h6F; endcase
                    20:case (b) 1:expected_byte=8'h40; 2:expected_byte=8'h24; 3:expected_byte=8'h6F; endcase
                endcase
            end
        end
    endfunction

    // Start/stop detection. In the ACK slot the simulated codec pulls SDA low.
    always @(negedge sda) begin
        if (scl === 1'b1) begin
            active = 1;
            bit_count = 0;
            byte_count = 0;
            rx_byte = 0;
            slave_sda_low = 0;
        end
    end

    always @(posedge scl) begin
        if (active) begin
            if (bit_count < 8) begin
                rx_byte = {rx_byte[6:0], sda};
                bit_count = bit_count + 1;
            end else begin
                if (sda !== 1'b0)
                    $fatal(1, "NACK in transaction %0d byte %0d", transaction_count, byte_count);
                if (rx_byte !== expected_byte(transaction_count, byte_count))
                    $fatal(1, "I2C data mismatch txn=%0d byte=%0d got=%02h expected=%02h",
                           transaction_count, byte_count, rx_byte,
                           expected_byte(transaction_count, byte_count));
                byte_count = byte_count + 1;
                bit_count = 0;
                rx_byte = 0;
            end
        end
    end

    always @(negedge scl) begin
        if (active) begin
            if (bit_count == 8) slave_sda_low = 1;
            else if (bit_count == 0) slave_sda_low = 0;
        end
    end

    always @(posedge sda) begin
        if ((scl === 1'b1) && active) begin
            expected_len = expected_transaction_length(transaction_count);
            if (byte_count != expected_len)
                $fatal(1, "Transaction %0d length=%0d expected=%0d",
                       transaction_count, byte_count, expected_len);
            transaction_count = transaction_count + 1;
            active = 0;
            slave_sda_low = 0;
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        rst = 0;
        wait (ready || error);
        if (error) $fatal(1, "codec_cfg reported I2C NACK/error");
        if (transaction_count != 21)
            $fatal(1, "Observed %0d transactions, expected 21", transaction_count);
        $display("PASS: codec_cfg emitted all 21 expected I2C transactions.");
        $finish;
    end

    initial begin
        #5_000_000;
        $fatal(1, "tb_codec_cfg timeout");
    end
endmodule
