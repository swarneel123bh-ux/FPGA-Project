# Block design for the enhancement build: the Zynq PS and one AXI4-Lite port for music_fifo_axi.
# Written by Claude (Swarneel's agent), 11 Nov 2026, at Swarneel's request. Sourced by
# scripts/build_enh.tcl inside an open project (Vivado 2020.2, board digilentinc.com:zedboard).
#
#   aclk (board 100 MHz, from enh_top) --> M_AXI_GP0_ACLK, interconnect, reset block
#   PS M_AXI_GP0 (AXI3) --> axi_interconnect (protocol conversion) --> M_AXI (AXI4-Lite, external)
#   proc_sys_reset: ext_reset_in = FCLK_RESET0_N, dcm_locked = clocking wizard locked
#                   --> axi_aresetn (external, for music_fifo_axi)
#
# Address map: M_AXI at 0x43C0_0000, 64 KB (sw/app/pl_feed.h must match).
# The PL clock is the board oscillator, not FCLK_CLK0, so all PL logic (codec, I2S, FIFO, treble)
# is in one clock domain that also runs before the PS has booted.

set bd_name enh_ps
create_bd_design $bd_name

# ---- Processing system with the ZedBoard preset (DDR, MIO, UART1 on MIO 48/49)
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1}] $ps

# ---- External ports
set aclk [create_bd_port -dir I -type clk -freq_hz 100000000 aclk]
set dcm_locked [create_bd_port -dir I dcm_locked]
set aresetn [create_bd_port -dir O -type rst axi_aresetn]
set m_axi [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI]
set_property -dict [list \
  CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {32} CONFIG.DATA_WIDTH {32} \
  CONFIG.HAS_BURST {0} CONFIG.HAS_CACHE {0} CONFIG.HAS_LOCK {0} CONFIG.HAS_QOS {0} \
  CONFIG.HAS_REGION {0} CONFIG.FREQ_HZ {100000000}] $m_axi
set_property CONFIG.ASSOCIATED_BUSIF {M_AXI} $aclk
set_property CONFIG.ASSOCIATED_RESET {axi_aresetn} $aclk

# ---- Reset and interconnect
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_aclk]
set ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $ic

connect_bd_net $aclk [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
  [get_bd_pins rst_aclk/slowest_sync_clk] \
  [get_bd_pins axi_ic/ACLK] [get_bd_pins axi_ic/S00_ACLK] [get_bd_pins axi_ic/M00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_aclk/ext_reset_in]
connect_bd_net $dcm_locked [get_bd_pins rst_aclk/dcm_locked]
connect_bd_net [get_bd_pins rst_aclk/interconnect_aresetn] [get_bd_pins axi_ic/ARESETN]
connect_bd_net [get_bd_pins rst_aclk/peripheral_aresetn] \
  [get_bd_pins axi_ic/S00_ARESETN] [get_bd_pins axi_ic/M00_ARESETN] $aresetn

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M00_AXI] $m_axi

# ---- Address map
assign_bd_address -offset 0x43C00000 -range 64K \
  -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
  [get_bd_addr_segs M_AXI/Reg] -force

validate_bd_design
save_bd_design
