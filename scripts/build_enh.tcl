# Build the enhancement bitstream and hardware platform (XSA) with Vivado 2020.2.
# Written by Claude (Swarneel's agent), 11 Nov 2026. Not team code.
#
# From the repo root, in a terminal with 2020.2 sourced:
#   source ~/Xilinx/Vivado/2020.2/settings64.sh
#   vivado -mode batch -source scripts/build_enh.tcl
# Output (git-ignored):
#   build/enh/enh_top.bit   bitstream
#   build/enh/enh_top.xsa   hardware platform for Vitis (bitstream included)
#   build/enh/timing.rpt, util.rpt
# Project for inspection in the GUI: build/enh/proj/enh.xpr

set root [file normalize [pwd]]
set out  $root/build/enh
file mkdir $out

create_project enh $out/proj -part xc7z020clg484-1 -force
set_property board_part em.avnet.com:zed:part0:1.4 [current_project]
set_property target_language Verilog [current_project]

add_files -norecurse [list \
  $root/rtl/enh_top.v $root/rtl/enh_core.v $root/rtl/treble_fixed.v $root/rtl/treble_coefs.mem \
  $root/rtl/music_fifo_axi.v $root/rtl/music_fifo.v \
  $root/rtl/codec_cfg.v $root/rtl/adau_i2c_write.v $root/rtl/i2s_rx.v $root/rtl/i2s_tx.v \
  $root/rtl/mclk_out.v]
add_files -fileset constrs_1 -norecurse $root/constraints/zedboard_enh.xdc

# 100 MHz -> 24 MHz codec MCLK (same settings as the 11 Nov week-1 build)
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {24.000} \
  CONFIG.USE_LOCKED {true} CONFIG.USE_RESET {true} CONFIG.RESET_TYPE {ACTIVE_HIGH}] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

# Block design: PS7 + AXI4-Lite port at 0x43C0_0000
source $root/scripts/enh_bd.tcl
set bd_file [get_files enh_ps.bd]
generate_target all $bd_file
add_files -norecurse [make_wrapper -files $bd_file -top]
puts "ADDRESS MAP:"
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
  puts "  $seg offset [get_property OFFSET $seg] range [get_property RANGE $seg]"
}

set_property top enh_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  puts "BUILD_FAILED: impl_1 [get_property STATUS [get_runs impl_1]]"
  exit 1
}

open_run impl_1
report_timing_summary -file $out/timing.rpt
report_utilization -file $out/util.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS = $wns ns"

file copy -force [glob $out/proj/enh.runs/impl_1/enh_top.bit] $out/enh_top.bit
write_hw_platform -fixed -include_bit -force -file $out/enh_top.xsa
puts "BUILD_DONE $out/enh_top.bit $out/enh_top.xsa"
