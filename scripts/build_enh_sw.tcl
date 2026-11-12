# Build the ARM app for the enhancement build with Vitis 2020.2 (xsct), and an SD-card BOOT.BIN.
# Written by Claude (Swarneel's agent), 11 Nov 2026. Not team code.
#
# Needs build/enh/enh_top.xsa (scripts/build_enh.tcl). From the repo root:
#   source ~/Xilinx/Vitis/2020.2/settings64.sh
#   xsct scripts/build_enh_sw.tcl
# Output (git-ignored):
#   build/enh_ws/                Vitis workspace (open it in the Vitis GUI if needed)
#   build/enh/enh_app.elf        the app (sw/app/*.c with BOARD defined, -O2, 64 KB stack)
#   build/enh/BOOT.BIN           FSBL + bitstream + app, for SD boot

set root [file normalize [pwd]]
set out  $root/build/enh
set ws   $root/build/enh_ws
set xsa  $out/enh_top.xsa
if {![file exists $xsa]} { puts "missing $xsa: run scripts/build_enh.tcl first"; exit 1 }

file delete -force $ws
setws $ws

platform create -name enh_plat -hw $xsa -proc ps7_cortexa9_0 -os standalone
platform generate

app create -name enh_app -platform enh_plat -lang C -template {Empty Application}
importsources -name enh_app -path $root/sw/app
app config -name enh_app build-config release
app config -name enh_app define-compiler-symbols BOARD

# The MP3 decoder needs about 17 KB of stack; the template gives 8 KB (instructions.md section 5).
set ld $ws/enh_app/src/lscript.ld
set f [open $ld r]; set txt [read $f]; close $f
regsub {_STACK_SIZE : 0x[0-9A-Fa-f]+;} $txt {_STACK_SIZE : 0x10000;} txt
set f [open $ld w]; puts -nonewline $f $txt; close $f

app build -name enh_app

set elf [glob $ws/enh_app/Release/enh_app.elf]
file copy -force $elf $out/enh_app.elf

# BOOT.BIN: FSBL from the platform, the bitstream, the app
set fsbl [lindex [glob -nocomplain $ws/enh_plat/export/enh_plat/sw/enh_plat/boot/fsbl.elf \
                                  $ws/enh_plat/zynq_fsbl/fsbl.elf] 0]
set bif $out/boot.bif
set f [open $bif w]
puts $f "the_ROM_image:\n\{\n  \[bootloader\] $fsbl\n  $out/enh_top.bit\n  $out/enh_app.elf\n\}"
close $f
exec bootgen -image $bif -arch zynq -o $out/BOOT.BIN -w on
puts "SW_DONE $out/enh_app.elf $out/BOOT.BIN"
