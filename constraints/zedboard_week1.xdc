## ZedBoard / XC7Z020-1CLG484C — Week-1 codec interface pins.
## Confirm board revision and Bank 13 VCCO before implementation.

## 100 MHz PL oscillator (ZedBoard UG, Clock Sources; pin Y9)
set_property PACKAGE_PIN Y9 [get_ports {clk100}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk100}]
create_clock -name clk100 -period 10.000 [get_ports {clk100}]

## ADAU1761 audio interface (ZedBoard UG, Table 9 / master XDC)
set_property PACKAGE_PIN AB2 [get_ports {ac_mclk}]
set_property PACKAGE_PIN AA6 [get_ports {ac_bclk}]
set_property PACKAGE_PIN Y6  [get_ports {ac_lrclk}]
set_property PACKAGE_PIN Y8  [get_ports {ac_dac_sdata}]
set_property PACKAGE_PIN AA7 [get_ports {ac_adc_sdata}]
set_property PACKAGE_PIN AB4 [get_ports {ac_scl}]
set_property PACKAGE_PIN AB5 [get_ports {ac_sda}]
set_property PACKAGE_PIN AB1 [get_ports {ac_addr0}]
set_property PACKAGE_PIN Y5  [get_ports {ac_addr1}]

set_property IOSTANDARD LVCMOS33 [get_ports {ac_mclk}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_bclk}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_lrclk}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_dac_sdata}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_adc_sdata}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_scl}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_sda}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_addr0}]
set_property IOSTANDARD LVCMOS33 [get_ports {ac_addr1}]

## Drive ADDR1=ADDR0=0 to select the 7-bit ADAU1761 address 0x38.
## If your schematic/board revision straps these pins differently, update both
## this logic and codec_cfg's I2C_ADDR parameter instead of fighting the straps.

## Add I/O timing constraints for the audio pins once board timing is measured.
## Do not apply an unconstrained generated-clock assumption to BCLK/LRCLK:
## in this design the ADAU1761 is serial-port MAIN and drives those clocks.
