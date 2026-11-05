# build_boot.tcl: build goal2_app and an SD-card BOOT.BIN without the Vitis IDE.
#
# NOT TEAM CODE. Build scaffolding written by Claude; it does what sections 6.2-6.6 of
# lab_run_windows.md do in the IDE, plus the boot loader (FSBL) and BOOT.BIN for SD boot.
#
# Run on a machine with Vitis 2020.x (Windows or Linux), from the repository root:
#   xsct sw/xsct/build_boot.tcl                 (finds zed.xsa in the Vitis install)
#   xsct sw/xsct/build_boot.tcl path/to/my.xsa  (any other hardware, e.g. from Vivado)
# On Windows, xsct is C:\Xilinx\Vitis\2020.x\bin\xsct.bat (or the "Vitis 2020.x XSCT" shortcut).
#
# Output:
#   build/sd/BOOT.BIN             copy to the root of a FAT32 SD card
#   build/vitis_ws/...            workspace (deleted and rebuilt on every run)
# Run it on the board over JTAG instead with run_jtag.tcl.

set script_dir [file dirname [file normalize [info script]]]
set repo [file normalize [file join $script_dir .. ..]]
set ws   [file join $repo build vitis_ws]
set out  [file join $repo build sd]

# Recursive search: XSCT output paths differ a little between 2020.1 and 2020.2.
proc find_file {dir name} {
    set hits [glob -nocomplain -types f -directory $dir $name]
    foreach sub [glob -nocomplain -types d -directory $dir *] {
        set hits [concat $hits [find_file $sub $name]]
    }
    return $hits
}

proc fail {msg} {
    puts stderr "\[build_boot\] ERROR: $msg"
    exit 1
}

# ---- hardware description ----------------------------------------------------------------
if {[llength $argv] >= 1} {
    set xsa [file normalize [lindex $argv 0]]
} else {
    if {![info exists ::env(XILINX_VITIS)]} {
        fail "XILINX_VITIS is not set: run this with Vitis's xsct, or pass the .xsa path"
    }
    set xsa [file join $::env(XILINX_VITIS) data embeddedsw lib fixed_hwplatforms zed.xsa]
}
if {![file exists $xsa]} { fail "no hardware file at $xsa" }
puts "\[build_boot\] hardware: $xsa"

# ---- fresh workspace ---------------------------------------------------------------------
file delete -force $ws
file mkdir $ws $out
setws $ws

# Platform: the FSBL (boot loader) is generated with it.
platform create -name zed_plat -hw $xsa
domain create -name app_domain -os standalone -proc ps7_cortexa9_0
platform generate

# ---- application -------------------------------------------------------------------------
# The template is called "Empty Application" in 2020.x and "Empty Application(C)" later.
if {[catch {app create -name goal2_app -platform zed_plat -domain app_domain \
                -template {Empty Application} -lang c} err]} {
    puts "\[build_boot\] 'Empty Application' failed ($err), trying 'Empty Application(C)'"
    app create -name goal2_app -platform zed_plat -domain app_domain \
        -template {Empty Application(C)} -lang c
}

# Copies of sw/app (6 files), like Import Sources in the IDE
importsources -name goal2_app -path [file join $repo sw app]

# Release (-O2); the settings below go into the active configuration, so set it first.
app config -name goal2_app build-config release
app config -name goal2_app define-compiler-symbols BOARD
app config -name goal2_app libraries m

# Stack 8 KB -> 64 KB: the MP3 decoder needs about 17 KB (lab guide 6.5)
set ld [file join $ws goal2_app src lscript.ld]
set fh [open $ld r]; set txt [read $fh]; close $fh
set n [regsub {(_STACK_SIZE\s*:\s*)0x2000} $txt {\10x10000} txt]
if {$n != 1} { fail "could not find the 0x2000 stack size in $ld; edit it by hand" }
set fh [open $ld w]; puts -nonewline $fh $txt; close $fh
puts "\[build_boot\] stack size set to 0x10000"

app build -name goal2_app

# ---- BOOT.BIN ----------------------------------------------------------------------------
set app_elf [find_file [file join $ws goal2_app] goal2_app.elf]
set fsbl    [find_file [file join $ws zed_plat] fsbl.elf]
if {[llength $app_elf] != 1} { fail "expected one goal2_app.elf, found: $app_elf" }
if {[llength $fsbl] < 1}     { fail "no fsbl.elf under [file join $ws zed_plat]" }
set app_elf [lindex $app_elf 0]
set fsbl    [lindex $fsbl 0]

file copy -force $app_elf [file join $out goal2_app.elf]
file copy -force $fsbl    [file join $out fsbl.elf]

# FSBL first, then our program. A bitstream line goes between them once the PL has a design.
set bif [file join $out boot.bif]
set fh [open $bif w]
puts $fh "the_ROM_image:"
puts $fh "\{"
puts $fh "  \[bootloader\] fsbl.elf"
puts $fh "  goal2_app.elf"
puts $fh "\}"
close $fh

set here [pwd]
cd $out
if {[catch {exec bootgen -arch zynq -image boot.bif -o BOOT.BIN -w on 2>@1} msg]} {
    cd $here
    fail "bootgen failed:\n$msg"
}
puts $msg
cd $here

puts "\[build_boot\] done:"
puts "  [file join $out BOOT.BIN]   (copy to the SD card, or program_qspi.tcl)"
puts "  [file join $out fsbl.elf]   (program_qspi.tcl needs it too)"
puts "  [file join $out goal2_app.elf]   (for run_jtag.tcl)"
