`timescale 1ns/1ps
module tb_mode_fsm;
 reg clk=0,rst=1; always #5 clk=~clk;
 reg [1:0] sel=0; reg recal=0,done=0,diverge=0,underrun=0;
 wire [2:0] mode; wire cal,anc,wr,donepulse;
 mode_fsm #(.CLK_HZ(10),.CALIBRATION_SECONDS(2)) dut(clk,rst,sel,recal,done,diverge,underrun,mode,cal,anc,wr,donepulse);
 task tick; begin @(posedge clk); #1; end endtask
 initial begin
  tick; rst=0;
  if(mode!==0||!cal||anc) $fatal(1,"reset state");
  repeat(20) tick;
  if(mode!==1||!anc) $fatal(1,"timer -> CANCEL");
  sel=1; tick; if(mode!==2||anc) $fatal(1,"CANCEL -> BYPASS");
  sel=0; tick; if(mode!==0) $fatal(1,"BYPASS -> CAL");
  done=1; tick; done=0; if(mode!==1) $fatal(1,"external cal_done");
  diverge=1; tick; diverge=0; if(mode!==3||!wr) $fatal(1,"diverge -> MUTE");
  tick; if(mode!==3) $fatal(1,"mute hold");
  tick; if(mode!==0||wr) $fatal(1,"mute -> CAL");
  sel=2; tick; if(mode!==4) $fatal(1,"CAL -> MUSIC select");
  underrun=1; tick; underrun=0; if(mode!==2) $fatal(1,"music underrun -> BYPASS");
  $display("PASS tb_mode_fsm"); $finish;
 end
endmodule
