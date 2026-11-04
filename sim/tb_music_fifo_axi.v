`timescale 1ns/1ps

// Testbench for rtl/music_fifo_axi.v (AXI4-Lite wrapper around rtl/music_fifo.v).
// The two tasks axi_write/axi_read act like the ARM doing Xil_Out32/Xil_In32. Register map:
//   0x0  write: push one sample (bits [23:0]); read: 0
//   0x4  read:  level (samples stored)
//   0x8  read:  {30'b0, overflow, full}

module tb_music_fifo_axi;

localparam ADDR_W = 12;                // the real size; the overfill test writes 4,097 samples
localparam DEPTH  = 1 << ADDR_W;

reg         clk = 0;
reg         aresetn = 0;
always #5 clk = ~clk;                  // 100 MHz

// AXI4-Lite master signals (driven by the tasks below)
reg  [3:0]  awaddr = 0;   reg awvalid = 0;  wire awready;
reg  [31:0] wdata = 0;    reg [3:0] wstrb = 0;  reg wvalid = 0;  wire wready;
wire [1:0]  bresp;        wire bvalid;      reg bready = 0;
reg  [3:0]  araddr = 0;   reg arvalid = 0;  wire arready;
wire [31:0] rdata;        wire [1:0] rresp; wire rvalid;  reg rready = 0;

reg                sample_tick = 0;
wire signed [23:0] music_raw;
wire               fifo_underrun;

music_fifo_axi #(.ADDR_W(ADDR_W)) dut (
  .sample_tick(sample_tick), .music_raw(music_raw), .fifo_underrun(fifo_underrun),
  .S_AXI_ACLK(clk), .S_AXI_ARESETN(aresetn),
  .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b000), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
  .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
  .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
  .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b000), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
  .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready)
);

integer errors = 0;
integer pass_checks = 0;

task automatic check(input [8*40-1:0] what, input [31:0] got, input [31:0] exp);
  begin
    if (got !== exp) begin
      errors = errors + 1;
      $display("FAIL t=%0t  %0s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end else pass_checks = pass_checks + 1;
  end
endtask

// ---- AXI master tasks (inputs change on the falling edge) -----------------------------------
task automatic axi_write(input [3:0] addr, input [31:0] data);
  integer n;
  begin
    @(negedge clk);
    awaddr = addr; awvalid = 1; wdata = data; wstrb = 4'hF; wvalid = 1; bready = 1;
    n = 0;
    @(posedge clk);
    while (!(awready && wready) && n < 50) begin @(posedge clk); n = n + 1; end
    if (n == 50) begin errors = errors + 1; $display("FAIL t=%0t  write 0x%0h: no AWREADY/WREADY", $time, addr); end
    @(negedge clk); awvalid = 0; wvalid = 0;
    n = 0;
    while (!bvalid && n < 50) begin @(posedge clk); n = n + 1; end
    if (n == 50) begin errors = errors + 1; $display("FAIL t=%0t  write 0x%0h: no BVALID", $time, addr); end
    else check("write response BRESP", bresp, 0);
    @(negedge clk); bready = 0;
  end
endtask

task automatic axi_read(input [3:0] addr, output [31:0] data);
  integer n;
  begin
    @(negedge clk);
    araddr = addr; arvalid = 1; rready = 1;
    n = 0;
    @(posedge clk);
    while (!arready && n < 50) begin @(posedge clk); n = n + 1; end
    if (n == 50) begin errors = errors + 1; $display("FAIL t=%0t  read 0x%0h: no ARREADY", $time, addr); end
    @(negedge clk); arvalid = 0;
    n = 0;
    while (!rvalid && n < 50) begin @(posedge clk); n = n + 1; end
    if (n == 50) begin errors = errors + 1; $display("FAIL t=%0t  read 0x%0h: no RVALID", $time, addr); data = 32'hxxxxxxxx; end
    else data = rdata;
    @(negedge clk); rready = 0;
  end
endtask

task automatic tick;                   // one sample_tick, then wait out the 1-cycle RAM latency
  begin
    @(negedge clk); sample_tick = 1;
    @(negedge clk); sample_tick = 0;
    repeat (3) @(negedge clk);
  end
endtask

task automatic section(input [8*80-1:0] name);
  $display("--- %0s", name);
endtask

reg [31:0] r;
integer i;

initial begin
  $dumpfile("sim/tb_music_fifo_axi.vcd");
  $dumpvars(0, tb_music_fifo_axi);

  repeat (4) @(negedge clk);
  aresetn = 1;
  repeat (2) @(negedge clk);

  section("1. after reset: level 0, status 0, register 0 reads 0");
  axi_read(4'h4, r); check("level after reset", r, 0);
  axi_read(4'h8, r); check("status after reset", r, 0);
  axi_read(4'h0, r); check("reg 0 read", r, 0);

  section("2. three writes to 0x0 raise level to 3");
  axi_write(4'h0, 32'h00111111);
  axi_write(4'h0, 32'h00222222);
  axi_write(4'h0, 32'h00333333);
  axi_read(4'h4, r); check("level after 3 writes", r, 3);

  section("3. three ticks return the samples in order");
  tick; check("1st sample", {8'h0, music_raw}, 32'h00111111); check("underrun 1", fifo_underrun, 0);
  tick; check("2nd sample", {8'h0, music_raw}, 32'h00222222);
  tick; check("3rd sample", {8'h0, music_raw}, 32'h00333333);
  axi_read(4'h4, r); check("level after 3 ticks", r, 0);
  tick; check("underrun when empty", fifo_underrun, 1); check("output 0 on underrun", {8'h0, music_raw}, 0);

  section("4. writes to 0x4, 0x8, 0xC do not push");
  axi_write(4'h4, 32'h00AAAAAA);
  axi_write(4'h8, 32'h00BBBBBB);
  axi_write(4'hC, 32'h00CCCCCC);
  axi_read(4'h4, r); check("level after writes to 1..3", r, 0);

  section("5. top 8 bits of WDATA ignored, sign kept");
  axi_write(4'h0, 32'hFF800000);       // s24 most negative, garbage in [31:24]
  tick; check("negative sample", {8'h0, music_raw}, 32'h00800000);
  check("music_raw is negative", music_raw < 0, 1);

  section("6. overfill: DEPTH + 1 writes -> level DEPTH, status full|overflow");
  for (i = 0; i <= DEPTH; i = i + 1) axi_write(4'h0, i);
  axi_read(4'h4, r); check("level when full", r, DEPTH);
  axi_read(4'h8, r); check("status full+overflow", r, 3);
  tick; check("oldest sample first", {8'h0, music_raw}, 0);
  axi_read(4'h8, r); check("overflow sticky, not full", r, 2);

  section("7. reset clears everything");
  @(negedge clk); aresetn = 0;
  repeat (2) @(negedge clk); aresetn = 1;
  repeat (2) @(negedge clk);
  axi_read(4'h4, r); check("level after 2nd reset", r, 0);
  axi_read(4'h8, r); check("status after 2nd reset", r, 0);

  if (errors == 0) $display("PASS: %0d checks, 0 errors", pass_checks);
  else             $display("FAIL: %0d errors, %0d checks passed", errors, pass_checks);
  $finish;
end

initial begin #5_000_000; $display("FAIL: timeout"); $finish; end

endmodule
