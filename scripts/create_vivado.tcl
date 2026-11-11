# Rebuild project with Vivado 2020.2 from repo root:
#   vivado -mode batch -source scripts/create_vivado.tcl
set proj_name fpga_audio
set proj_dir ./vivado_build
create_project $proj_name $proj_dir -part xc7z020clg484-1 -force
set_property board_part digilentinc.com:zedboard:part0:1.4 [current_project]

set rtl_files [list \
  rtl/adau_i2c_write.v rtl/codec_cfg.v rtl/i2s_rx.v rtl/i2s_tx.v rtl/mclk_out.v \
  rtl/lfsr.v rtl/sec_path_id.v rtl/fxlms.v rtl/mode_fsm.v rtl/out_mux.v rtl/top.v]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse constraints/zedboard.xdc
set_property top top [current_fileset]

# 100 MHz -> 24 MHz codec master clock. Wizard is used only to generate MCLK;
# the audio serial clocks remain codec-driven and are sampled in clk100 domain.
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {100.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {24.000} \
  CONFIG.USE_LOCKED {true} \
  CONFIG.USE_RESET {true} \
  CONFIG.RESET_TYPE {ACTIVE_HIGH}] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created $proj_dir/$proj_name.xpr. Open it and run synthesis/implementation."
