// -----------------------------------------------------------------------------
// WEEK-1 SCAFFOLDING — review and understand before adopting as team RTL.
// ADAU1761 I2S transmitter. All logic remains in the 100 MHz clk domain.
//
// Stereo inputs are intentional: Week-1 passthrough must preserve left and
// right microphones independently. At later integration, mono ANC/music can
// be duplicated onto dac_left and dac_right. This makes explicit the mismatch
// between the plan's current scalar dac_out contract and stereo passthrough.
//
// Samples are latched on sample_tick and serialized MSB-first. Data changes on
// falling BCLK; codec samples on rising BCLK. 24 bits are followed by 8 zero
// pad bits in each 32-bit slot. LRCLK low=left, high=right; one-bit I2S delay.
//
// [Claude fix 11 Nov] The codec changes LRCLK on the same falling BCLK edge this block used to
// look at it. If LRCLK reached its synchroniser even ~1 ns after BCLK, the word start was
// seen one bit late, so that word went out shifted by one bit (a loud spike for negative
// samples). BCLK drifts against clk, so this hit random frames: the crackle heard on the board.
// LRCLK is now sampled on the rising BCLK edge (half a bit after it changed, so it is stable)
// and the MSB is driven on the next falling edge, as i2s_rx already does on the receive side.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module i2s_tx (
    input  wire clk,
    input  wire rst,             // synchronous, active high
    input  wire bclk_in,
    input  wire lrclk_in,
    input  wire sample_tick,
    input  wire signed [23:0] dac_left,
    input  wire signed [23:0] dac_right,
    output reg  dac_sdata
);
    (* ASYNC_REG = "TRUE" *) reg bclk_meta, bclk_sync;
    (* ASYNC_REG = "TRUE" *) reg lrclk_meta, lrclk_sync;
    reg bclk_prev;
    reg lrclk_prev;          // LRCLK of the word being sent
    reg lrclk_at_rise;       // LRCLK sampled on the last rising BCLK  [Claude fix 11 Nov]
    reg frame_seen;
    reg [4:0] bit_count;
    reg [23:0] left_pending, right_pending;
    reg [23:0] shift_reg;
    wire bclk_fall = ~bclk_sync & bclk_prev;
    wire bclk_rise =  bclk_sync & ~bclk_prev;   // [Claude fix 11 Nov]
    wire [23:0] next_word = (lrclk_at_rise == 1'b0) ? left_pending : right_pending;  // [Claude fix 11 Nov]

    always @(posedge clk) begin
        if (rst) begin
            bclk_meta    <= 1'b0;
            bclk_sync    <= 1'b0;
            bclk_prev    <= 1'b0;
            lrclk_meta   <= 1'b0;
            lrclk_sync   <= 1'b0;
            lrclk_prev   <= 1'b0;
            lrclk_at_rise<= 1'b0;   // [Claude fix 11 Nov]
            frame_seen   <= 1'b0;
            bit_count    <= 0;
            left_pending <= 24'sd0;
            right_pending<= 24'sd0;
            shift_reg    <= 24'h0;
            dac_sdata    <= 1'b0;
        end else begin
            bclk_meta  <= bclk_in;
            bclk_sync  <= bclk_meta;
            bclk_prev  <= bclk_sync;
            lrclk_meta <= lrclk_in;
            lrclk_sync <= lrclk_meta;

            if (sample_tick) begin
                left_pending  <= dac_left;
                right_pending <= dac_right;
            end

            if (bclk_rise) lrclk_at_rise <= lrclk_sync;   // [Claude fix 11 Nov]
            if (bclk_fall) begin
                if (!frame_seen || (lrclk_at_rise != lrclk_prev)) begin   // [Claude fix 11 Nov] was lrclk_sync
                    // [Claude fix 11 Nov] The rising edge just seen was the I2S delay slot after
                    // the LRCLK change, so drive the new word's MSB now.
                    frame_seen <= 1'b1;
                    lrclk_prev <= lrclk_at_rise;
                    dac_sdata  <= next_word[23];
                    shift_reg  <= {next_word[22:0], 1'b0};
                    bit_count  <= 5'd1;
                end else if (bit_count < 5'd24) begin
                    dac_sdata <= shift_reg[23];
                    shift_reg <= {shift_reg[22:0], 1'b0};
                    bit_count <= bit_count + 1'b1;
                end else begin
                    dac_sdata <= 1'b0;
                end
            end
        end
    end
endmodule
