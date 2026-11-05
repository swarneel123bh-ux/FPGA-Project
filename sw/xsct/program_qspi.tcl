# program_qspi.tcl: write BOOT.BIN into the ZedBoard's QSPI flash with Vivado (no Vitis needed).
#
# NOT TEAM CODE. Scaffolding written by Claude; it does what Vivado's Hardware Manager does under
# "Add Configuration Memory Device" + "Program Configuration Memory Device" (lab_run_windows.md 11).
#
# Needs BOOT.BIN and fsbl.elf from build_boot.tcl (build/sd/), the board on, J17 (PROG) plugged
# in, and the boot jumpers on JTAG (all five on GND) while programming.
#
# From the folder holding the two files, in a Command Prompt where vivado works
# (C:\Xilinx\Vivado\2020.1\bin\vivado.bat):
#   vivado -mode batch -source program_qspi.tcl -tclargs BOOT.BIN fsbl.elf
# With no -tclargs it uses build/sd/BOOT.BIN and build/sd/fsbl.elf of this repository.

set script_dir [file dirname [file normalize [info script]]]
set repo [file normalize [file join $script_dir .. ..]]

proc fail {msg} {
    puts stderr "\[program_qspi\] ERROR: $msg"
    exit 1
}

if {[llength $argv] >= 2} {
    set bootbin [file normalize [lindex $argv 0]]
    set fsbl    [file normalize [lindex $argv 1]]
} else {
    set bootbin [file join $repo build sd BOOT.BIN]
    set fsbl    [file join $repo build sd fsbl.elf]
}
foreach f [list $bootbin $fsbl] {
    if {![file exists $f]} { fail "missing $f" }
}

# Flash chip on the ZedBoard: Spansion S25FL256S, 3.3 V, one chip in x4 (quad) mode
set flash_part s25fl256s-3.3v-qspi-x4-single

# open_hw_manager replaced open_hw around 2020.1; accept either
if {[llength [info commands open_hw_manager]]} { open_hw_manager } else { open_hw }
connect_hw_server
open_hw_target

set dev [lindex [get_hw_devices -filter {PART =~ "xc7z020*"}] 0]
if {$dev eq ""} { fail "no xc7z020 on the JTAG chain: check J17, power and the jumpers" }
current_hw_device $dev
puts "\[program_qspi\] device: $dev"

set part [lindex [get_cfgmem_parts $flash_part] 0]
if {$part eq ""} { fail "Vivado does not know flash part $flash_part" }
create_hw_cfgmem -hw_device $dev $part
set cm [get_property PROGRAM.HW_CFGMEM $dev]

set_property PROGRAM.ADDRESS_RANGE {use_file} $cm
set_property PROGRAM.FILES        [list $bootbin] $cm
# Vivado runs this boot loader on the ARM to reach the flash
set_property PROGRAM.ZYNQ_FSBL    $fsbl $cm
set_property PROGRAM.BLANK_CHECK  0 $cm
set_property PROGRAM.ERASE        1 $cm
set_property PROGRAM.CFG_PROGRAM  1 $cm
set_property PROGRAM.VERIFY       1 $cm
set_property PROGRAM.CHECKSUM     0 $cm

puts "\[program_qspi\] erasing, programming and verifying $bootbin (about a minute)"
program_hw_cfgmem -hw_cfgmem $cm

close_hw_target
disconnect_hw_server
puts "\[program_qspi\] done. Power off, set QSPI boot jumpers (JP10 on 3V3, rest GND), power on."
