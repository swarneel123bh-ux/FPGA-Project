# run_jtag.tcl: load and start goal2_app over JTAG without the Vitis IDE.
#
# NOT TEAM CODE. Scaffolding written by Claude; it does what "Launch Hardware" does in the IDE
# (lab_run_windows.md 7.2). Needs build_boot.tcl to have run first, the board on, J17 (PROG)
# plugged in and the boot jumpers on JTAG (all five on GND).
#
# From the repository root:
#   xsct sw/xsct/run_jtag.tcl
# Start send_mp3.py BEFORE running this: the board prints **Ready** only once.

set script_dir [file dirname [file normalize [info script]]]
set repo [file normalize [file join $script_dir .. ..]]
set ws   [file join $repo build vitis_ws]
set elf  [file join $repo build sd goal2_app.elf]

proc find_file {dir name} {
    set hits [glob -nocomplain -types f -directory $dir $name]
    foreach sub [glob -nocomplain -types d -directory $dir *] {
        set hits [concat $hits [find_file $sub $name]]
    }
    return $hits
}

if {![file exists $elf]} {
    puts stderr "\[run_jtag\] ERROR: $elf missing; run build_boot.tcl first"
    exit 1
}
set init [find_file [file join $ws zed_plat] ps7_init.tcl]
if {[llength $init] < 1} {
    puts stderr "\[run_jtag\] ERROR: no ps7_init.tcl under [file join $ws zed_plat]"
    exit 1
}

connect
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 1000
# Clocks, DDR and MIO set-up: what the FSBL does when booting from SD
source [lindex $init 0]
ps7_init
ps7_post_config

targets -set -nocase -filter {name =~ "*Cortex-A9*#0"}
rst -processor
dow $elf
con
puts "\[run_jtag\] goal2_app running; its output appears in send_mp3.py, not here"
disconnect
