# ZedBoard Rev C/D pin map (Digilent Master XDC). Bank 13/33 = 3.3 V;
# Banks 34/35 use board default 1.8 V. Confirm JP1/mic analog wiring separately.
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

# User switches SW0/SW1 select ANC/BYPASS/MUSIC (00/01/10).
set_property PACKAGE_PIN F22 [get_ports {sw[0]}]
set_property PACKAGE_PIN G22 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {sw[1]}]

# BTN0 (center) = recalibrate; BTND (down) = active-high reset input.
set_property PACKAGE_PIN R16 [get_ports {rst}]
set_property IOSTANDARD LVCMOS18 [get_ports {rst}]
set_property PACKAGE_PIN P16 [get_ports {recal_btn}]
set_property IOSTANDARD LVCMOS18 [get_ports {recal_btn}]

# User LEDs LD0..LD7
set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
