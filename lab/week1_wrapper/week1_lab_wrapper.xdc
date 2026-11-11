## NOT TEAM CODE. Lab scaffolding (Claude, 11 Nov 2026). Used together with
## constraints/zedboard_week1.xdc. Pins copied from constraints/zedboard.xdc (rst, led[0..2]).
set_property PACKAGE_PIN R16 [get_ports {btnd}]
set_property IOSTANDARD LVCMOS18 [get_ports {btnd}]
set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
