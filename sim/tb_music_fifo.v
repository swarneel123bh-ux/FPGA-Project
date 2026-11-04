`timescale 1ns/1ps
// Testbench for rtl/music_fifo.v.
// Port list and tick generator idea: Swarneel. Checker, model and test sequence: written by
// Claude at Swarneel's request (marked [Claude] below) - review and own it before submission.
//
// Self-checking: a reference model (an ordinary queue) runs alongside the DUT and every cycle
// the DUT's level/full/overflow, and after every tick its music_raw/fifo_underrun, are compared
// with the model. Prints PASS or FAIL with an error count at the end.
//
// Run:  iverilog -g2012 -o sim/tb_music_fifo.vvp rtl/music_fifo.v sim/tb_music_fifo.v
//       vvp sim/tb_music_fifo.vvp

module tb_music_fifo;

localparam ADDR_W = 3;                 // 8 slots, so "full" is quick to reach
localparam DEPTH  = 1 << ADDR_W;

reg               clk = 0;
reg               rst = 0;

// write side (from the AXI wrapper)
reg               wr_en = 0;           // one-cycle pulse per sample
reg        [23:0] wr_data = 0;
wire              full;
wire   [ADDR_W:0] level;               // samples stored, for the ARM to poll
wire              overflow;            // sticky: a write arrived while full

// read side
reg               sample_tick = 0;
wire signed[23:0] music_raw;
wire              fifo_underrun;

music_fifo #(.ADDR_W(ADDR_W)) uut (
  .clk(clk), .rst(rst),
  .wr_en(wr_en), .wr_data(wr_data), .full(full), .level(level), .overflow(overflow),
  .sample_tick(sample_tick), .music_raw(music_raw), .fifo_underrun(fifo_underrun)
);

always #5 clk = ~clk;                  // 100 MHz

// ---------------------------------------------------------------------------------------------
// [Claude] Reference model: what the FIFO should hold, updated on the same clock edges.
// ---------------------------------------------------------------------------------------------
reg [23:0] q [0:4095];                 // expected contents, oldest at q_head
integer q_head = 0, q_tail = 0, cnt = 0;
reg     model_ovf = 0;

// Pending output check after a tick: outputs must be final by the negedge after the next
// posedge (one cycle of block-RAM read latency allowed).
integer    chk_delay = 0;
reg [23:0] chk_val;
reg        chk_ur;
reg [23:0] last_val = 0;               // what music_raw must hold between ticks
reg        last_ur  = 0;
integer    errors = 0, checks = 0;

always @(posedge clk) begin : model
  reg can_wr, can_rd;
  if (rst) begin
    q_head = 0; q_tail = 0; cnt = 0; model_ovf = 0;
    chk_delay = 0; last_val = 0; last_ur = 0;
  end else begin
    can_wr = wr_en && (cnt < DEPTH);
    can_rd = sample_tick && (cnt > 0);   // uses the count from BEFORE this edge
    if (wr_en && cnt == DEPTH) model_ovf = 1;
    if (sample_tick) begin
      chk_ur    = !can_rd;
      chk_val   = can_rd ? q[q_head % 4096] : 24'd0;
      chk_delay = 2;
    end
    if (can_rd) q_head = q_head + 1;
    if (can_wr) begin q[q_tail % 4096] = wr_data; q_tail = q_tail + 1; end
    cnt = cnt + can_wr - can_rd;
  end
end

reg [8*48-1:0] last_what = 0;
integer        shown = 0;
task automatic fail(input [8*48-1:0] what, input integer got, input integer exp);
  begin
    errors = errors + 1;
    // show the first failure of each kind (repeats of the same kind are only counted)
    if (what != last_what && shown < 30) begin
      last_what = what;
      shown = shown + 1;
      $display("FAIL t=%0t  %0s: got %0d (0x%06h), expected %0d (0x%06h)",
               $time, what, got, got[23:0], exp, exp[23:0]);
    end
  end
endtask

// [Claude] Checker, on the falling edge so all DUT outputs have settled.
always @(negedge clk) begin
  if (!rst) begin
    checks = checks + 1;
    if (level !== cnt[ADDR_W:0])         fail("level",    level,    cnt);
    if (full !== (cnt == DEPTH))         fail("full",     full,     cnt == DEPTH);
    if (overflow !== model_ovf)          fail("overflow", overflow, model_ovf);

    if (chk_delay > 0) begin
      chk_delay = chk_delay - 1;
      if (chk_delay == 0) begin
        if (fifo_underrun !== chk_ur)    fail("fifo_underrun after tick", fifo_underrun, chk_ur);
        if (music_raw !== chk_val)       fail("music_raw after tick",     music_raw,     chk_val);
        last_val = chk_val;
        last_ur  = chk_ur;
      end
    end else if (!sample_tick) begin
      // between ticks: outputs must hold
      if (music_raw !== last_val)        fail("music_raw not held",       music_raw,     last_val);
      if (fifo_underrun !== last_ur)     fail("fifo_underrun not held",   fifo_underrun, last_ur);
    end
  end
end

// ---------------------------------------------------------------------------------------------
// [Claude] Stimulus helpers. Inputs change on the falling edge, so the DUT sees them cleanly
// on the next rising edge.
// ---------------------------------------------------------------------------------------------
task automatic idle(input integer n);
  repeat (n) @(negedge clk);
endtask

task automatic push(input [23:0] v);
  begin
    @(negedge clk); wr_en = 1; wr_data = v;
    @(negedge clk); wr_en = 0;
  end
endtask

task automatic tick;                   // one tick, then 3 quiet cycles for the read latency
  begin
    @(negedge clk); sample_tick = 1;
    @(negedge clk); sample_tick = 0;
    idle(3);
  end
endtask

task automatic push_and_tick(input [23:0] v);   // write and tick on the same edge
  begin
    @(negedge clk); wr_en = 1; wr_data = v; sample_tick = 1;
    @(negedge clk); wr_en = 0; sample_tick = 0;
    idle(3);
  end
endtask

task automatic section(input [8*40-1:0] name);
  $display("--- %0s (errors so far: %0d)", name, errors);
endtask

integer i, gap;

initial begin
  $dumpfile("sim/tb_music_fifo.vcd");
  $dumpvars(0, tb_music_fifo);

  // Reset (synchronous: hold for two edges)
  @(negedge clk); rst = 1;
  idle(2);
  rst = 0;

  section("1. after reset: empty, tick underruns");
  idle(2);
  tick;

  section("2. five samples in, five out in order");
  for (i = 1; i <= 5; i = i + 1) push(24'h100000 + i);
  for (i = 1; i <= 5; i = i + 1) tick;

  section("3. run dry: underrun, output 0, held");
  tick;
  idle(10);

  section("4. overfill: full, overflow, 9th dropped");
  for (i = 0; i < DEPTH + 1; i = i + 1) push(24'h200000 + i);
  for (i = 0; i < DEPTH; i = i + 1) tick;
  tick;                                // now empty again

  section("5. write on the same edge as a tick");
  push(24'h300001);
  push(24'h300002);
  push_and_tick(24'h300003);           // level stays 2
  tick; tick;
  push_and_tick(24'h300004);           // empty FIFO + write + tick: underrun, sample kept
  tick;

  section("6. negative samples keep their sign");
  push(24'h800000);                    // most negative s24
  push(24'hFFFFFF);                    // -1
  tick; tick;

  section("7. random writes and ticks, 2000 cycles");
  gap = 0;
  for (i = 0; i < 2000; i = i + 1) begin
    @(negedge clk);
    wr_en   = ($random % 3 == 0);
    wr_data = $random;
    if (gap == 0) begin sample_tick = 1; gap = 4 + ($unsigned($random) % 4); end
    else begin sample_tick = 0; gap = gap - 1; end
  end
  @(negedge clk); wr_en = 0; sample_tick = 0;
  idle(5);

  if (errors == 0) $display("PASS: %0d cycles checked, 0 errors", checks);
  else             $display("FAIL: %0d errors in %0d cycles checked", errors, checks);
  $finish;
end

// Safety net: never hang
initial begin #1_000_000; $display("FAIL: timeout"); $finish; end

endmodule
