`timescale 1ns/1ps


module music_fifo #(parameter ADDR_W = 12) (
  input  wire               clk,
  input  wire               rst,

  // write side (from the AXI wrapper)
  input  wire               wr_en,      // one-cycle pulse per sample
  input  wire        [23:0] wr_data,
  output wire               full,
  output wire    [ADDR_W:0] level,      // samples stored, for the ARM to poll
  output wire               overflow,   // sticky: a write arrived while full

  // read side
  input  wire               sample_tick,
  output reg signed  [23:0] music_raw,
  output reg                fifo_underrun
);

reg [23:0] music_mem [0: (1<<ADDR_W)-1];
reg [ADDR_W:0] wptr, rptr;
reg overflow_;
reg rdvalid;
reg [23:0] rd_data;

assign level = wptr - rptr;              // wraps correctly because both are ADDR_W+1 bits
wire   empty = (level == 0);
assign full  = (level == (1 << ADDR_W));
assign overflow = overflow_;

always @(posedge clk) begin
  if (rst) begin
    wptr <= 0;
    rptr <= 0;
    music_raw <= 0;
    fifo_underrun <= 0;
    rdvalid <= 0;
    overflow_ <= 0;
  end else begin
    rdvalid <= 0;

    // Writing
    if (wr_en) begin
      if (full) begin overflow_ <= 1; end
      else begin
        music_mem[wptr[ADDR_W-1:0]] <= wr_data;
        wptr <= wptr + 1;
      end
    end

    // Reading
    if (sample_tick) begin
      if (!empty) begin
        rd_data <= music_mem[rptr[ADDR_W-1:0]];
        rptr <= rptr + 1;
        fifo_underrun <= 0;
        rdvalid <= 1;
      end else begin
        music_raw <= 0;
        fifo_underrun <= 1;
      end
    end


    if (rdvalid) music_raw <= rd_data;
  end
end



endmodule
