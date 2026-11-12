## Pins for rtl/enh_top.v (enhancement build). Written by Claude, 11 Nov 2026.
## Copied from constraints/zedboard.xdc (Aarav's) and lab/week1_wrapper/week1_lab_wrapper.xdc,
## which worked on the board on 11 Nov. PS pins (DDR, MIO) come from the block design.

set_property PACKAGE_PIN Y9 [get_ports {clk100}]
create_clock -name sys_clk -period 10.000 [get_ports {clk100}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk100}]

# ADAU1761 codec
set_property PACKAGE_PIN AB1 [get_ports {ac_addr0}]
set_property PACKAGE_PIN Y5  [get_ports {ac_addr1}]
set_property PACKAGE_PIN AB2 [get_ports {ac_mclk}]
set_property PACKAGE_PIN AB4 [get_ports {ac_scl}]
set_property PACKAGE_PIN AB5 [get_ports {ac_sda}]
set_property PACKAGE_PIN AA6 [get_ports {ac_bclk}]
set_property PACKAGE_PIN Y6  [get_ports {ac_lrclk}]
set_property PACKAGE_PIN AA7 [get_ports {ac_adc_sdata}]
set_property PACKAGE_PIN Y8  [get_ports {ac_dac_sdata}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_addr0 ac_addr1 ac_mclk ac_scl ac_sda ac_bclk ac_lrclk ac_adc_sdata ac_dac_sdata}]

# SW0 = enhanced/plain, SW1 = test tone
set_property PACKAGE_PIN F22 [get_ports {sw[0]}]
set_property PACKAGE_PIN G22 [get_ports {sw[1]}]
# SW2-SW4: volume (pins from Digilent Zedboard-Master.xdc, checked 12 Nov)
set_property PACKAGE_PIN H22 [get_ports {sw[2]}]
set_property PACKAGE_PIN F21 [get_ports {sw[3]}]
set_property PACKAGE_PIN H19 [get_ports {sw[4]}]
# SW5: added treble -12 dB, SW6: enhancer tuning (same pin list)
set_property PACKAGE_PIN H18 [get_ports {sw[5]}]
set_property PACKAGE_PIN H17 [get_ports {sw[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {sw[*]}]

# BTND = reset
set_property PACKAGE_PIN R16 [get_ports {btnd}]
set_property IOSTANDARD LVCMOS18 [get_ports {btnd}]

# LD0..LD7
set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
