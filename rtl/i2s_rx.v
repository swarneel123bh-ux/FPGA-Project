// -----------------------------------------------------------------------------
// WEEK-1 SCAFFOLDING — review and understand before adopting as team RTL.
// ADAU1761 I2S receiver. All logic remains in the 100 MHz clk domain; BCLK,
// LRCLK and ADC_SDATA are synchronized before edge detection/sampling.
//
// Assumes codec is I2S MAIN, 64 BCLK per stereo frame, 24 MSB-first bits in a
// 32-bit slot, LRCLK low=left and high=right, one-bit I2S delay. The LRCLK
// transition edge itself is discarded; the next BCLK rising edge is bit 23.
// x_ref=left sample, e_err=right sample. sample_tick pulses after right sample.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module i2s_rx (
    input  wire clk,
    input  wire rst,             // synchronous, active high
    input  wire bclk_in,
    input  wire lrclk_in,
    input  wire adc_sdata,
    output reg signed [23:0] x_ref,
    output reg signed [23:0] e_err,
    output reg sample_tick
);
    (* ASYNC_REG = "TRUE" *) reg bclk_meta, bclk_sync;
    (* ASYNC_REG = "TRUE" *) reg lrclk_meta, lrclk_sync;
    (* ASYNC_REG = "TRUE" *) reg sdata_meta, sdata_sync;
    reg bclk_prev;
    reg lrclk_prev;
    reg frame_seen;
    reg [4:0] bit_count;
    reg [23:0] shift_reg;
    wire bclk_rise = bclk_sync & ~bclk_prev;

    always @(posedge clk) begin
        if (rst) begin
            bclk_meta   <= 1'b0;
            bclk_sync   <= 1'b0;
            bclk_prev   <= 1'b0;
            lrclk_meta  <= 1'b0;
            lrclk_sync  <= 1'b0;
            lrclk_prev  <= 1'b0;
            sdata_meta  <= 1'b0;
            sdata_sync  <= 1'b0;
            frame_seen  <= 1'b0;
            bit_count   <= 0;
            shift_reg   <= 24'h0;
            x_ref       <= 24'sd0;
            e_err       <= 24'sd0;
            sample_tick <= 1'b0;
        end else begin
            bclk_meta  <= bclk_in;
            bclk_sync  <= bclk_meta;
            bclk_prev  <= bclk_sync;
            lrclk_meta <= lrclk_in;
            lrclk_sync <= lrclk_meta;
            sdata_meta <= adc_sdata;
            sdata_sync <= sdata_meta;
            sample_tick <= 1'b0;

            if (bclk_rise) begin
                if (!frame_seen || (lrclk_sync != lrclk_prev)) begin
                    // I2S word-select changes one BCLK before the MSB.
                    // Do not sample data on the LRCLK-transition edge.
                    frame_seen <= 1'b1;
                    lrclk_prev <= lrclk_sync;
                    bit_count <= 0;
                    shift_reg <= 24'h0;
                end else if (bit_count < 5'd24) begin
                    shift_reg <= {shift_reg[22:0], sdata_sync};
                    if (bit_count == 5'd23) begin
                        if (lrclk_prev == 1'b0)
                            x_ref <= {shift_reg[22:0], sdata_sync};
                        else begin
                            e_err <= {shift_reg[22:0], sdata_sync};
                            sample_tick <= 1'b1;
                        end
                        bit_count <= 5'd24;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end
            end
        end
    end
endmodule
