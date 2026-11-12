# Program the ZedBoard over JTAG and start the enhancement app (no Vitis GUI needed).
# Written by Claude (Swarneel's agent), 11 Nov 2026. Not team code.
#
# Board: JTAG boot jumpers, PROG and UART USB cables in, powered on. Power-cycle the board
# (SW8) before each run: reprogramming without one can make the codec stop answering I2C.
# Start the sender first (it waits for "**Ready**"), then, from the repo root:
#   source ~/Xilinx/Vitis/2020.2/settings64.sh
#   xsct scripts/run_enh_jtag.tcl
# Same steps as Vitis "Run As -> Launch on Hardware".

#
# To play another file without reprogramming the FPGA (so the codec keeps working):
#   xsct scripts/run_enh_jtag.tcl app
# This only restarts the ARM app; the PL and the codec configuration are left alone.

set root [file normalize [pwd]]
set out  $root/build/enh

if {[lindex $argv 0] eq "app"} {
  connect
  targets -set -nocase -filter {name =~ "*A9*#0"}
  catch {stop}   ;# [12 Nov] "Already stopped" (e.g. after the E8 ARM-stop test) must not abort
  dow $out/enh_app.elf
  con
  puts "RUNNING (app only): the app waits for the sender"
  exit
}

connect
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 3000
targets -set -nocase -filter {name =~ "xc7z020*"}
fpga -file $out/enh_top.bit
targets -set -nocase -filter {name =~ "APU*"}
loadhw -hw $out/enh_top.xsa -mem-ranges [list {0x40000000 0xbfffffff}] -regs
configparams force-mem-access 1
source $root/build/enh_ws/enh_plat/hw/ps7_init.tcl
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "*A9*#0"}
rst -processor
dow $out/enh_app.elf
configparams force-mem-access 0
con
puts "RUNNING: the app waits for the sender (230,400 baud on the UART port)"
