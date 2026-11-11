# NOT TEAM CODE. Batch build of the week-1 DIAGNOSTIC (tone on SW0, ADC level LEDs) for the 11 Nov lab session.
# Run from the repo root: vivado -mode batch -source lab/week1_wrapper/build_week1_diag.tcl
set out ./build/week1_diag
file mkdir $out
create_project -in_memory -part xc7z020clg484-1
read_verilog {rtl/mclk_out.v lab/week1_wrapper/codec_cfg_diag.v rtl/adau_i2c_write.v
              rtl/i2s_rx.v rtl/i2s_tx.v lab/week1_wrapper/week1_diag_top.v}
read_xdc constraints/zedboard_week1.xdc
read_xdc lab/week1_wrapper/week1_diag_top.xdc
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0 -dir $out
set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {24.000} \
  CONFIG.USE_LOCKED {true} CONFIG.USE_RESET {true} CONFIG.RESET_TYPE {ACTIVE_HIGH}] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
synth_ip [get_ips clk_wiz_0]
synth_design -top week1_diag_top -part xc7z020clg484-1
opt_design
place_design
route_design
report_timing_summary -file $out/timing.rpt
report_utilization -file $out/util.rpt
report_drc -file $out/drc.rpt
write_bitstream -force $out/week1_diag_top.bit
puts "BITSTREAM_DONE $out/week1_diag_top.bit"
