`timescale 1ns/1ps
module tb_out_mux;
 reg [2:0] mode=0; reg signed [23:0] v=24'sd123,y=-24'sd456,m=24'sd789; reg under=0;
 wire signed [23:0] out;
 out_mux dut(mode,v,y,m,under,out);
 initial begin
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
