`timescale 1ns/1ps
module tb_out_mux;
 // [Claude fix 11 Nov] inputs were initialised in their declarations at time 0, before
 // out_mux's always @* was waiting, so dac_out stayed X and the first check failed (race).
 // They are now set at #1, when the always block is already waiting for a change.
 reg [2:0] mode; reg signed [23:0] v,y,m; reg under;
 wire signed [23:0] out;
 out_mux dut(mode,v,y,m,under,out);
 initial begin
  #1; mode=0; v=24'sd123; y=-24'sd456; m=24'sd789; under=0; // [Claude fix 11 Nov]
  #1; if(out!==v) $fatal(1,"CAL");
  mode=1; #1; if(out!==y) $fatal(1,"CANCEL");
  mode=2; #1; if(out!==0) $fatal(1,"BYPASS");
  mode=3; #1; if(out!==0) $fatal(1,"MUTE");
  mode=4; #1; if(out!==m) $fatal(1,"MUSIC");
  under=1; #1; if(out!==0) $fatal(1,"underrun mute");
  mode=7; #1; if(out!==0) $fatal(1,"invalid mode");
  $display("PASS tb_out_mux"); $finish;
 end
endmodule
