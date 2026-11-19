# Write the report tables for the final report from the implemented enhancement build.
# Written by Claude (Swarneel's agent), 19 Nov 2026, at Swarneel's request. Not team code.
#
# Needs build/enh/proj/enh.xpr from scripts/build_enh.tcl. From the repo root, Vivado 2020.2 sourced:
#   vivado -mode batch -source scripts/reports_enh.tcl
# Output: build/enh/reports/  utilization (flat and per module), timing summary, power,
#         clock summary, DRC, and summary.txt with the numbers for the report table.

set root [file normalize [pwd]]
set out  $root/build/enh/reports
file mkdir $out
open_project $root/build/enh/proj/enh.xpr

open_run synth_1 -name synth_1
report_utilization -file $out/util_synth.rpt
close_design

open_run impl_1
report_utilization                 -file $out/util_impl.rpt
report_utilization -hierarchical   -file $out/util_impl_hier.rpt
report_timing_summary -max_paths 10 -file $out/timing_impl.rpt
report_clocks                      -file $out/clocks.rpt
report_power                       -file $out/power_impl.rpt
report_drc                         -file $out/drc_impl.rpt

set wns  [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs  [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set f [open $out/summary.txt w]
puts $f "WNS (setup) = $wns ns"
puts $f "WHS (hold)  = $whs ns"
foreach t {"Slice LUTs" "Slice Registers" "Block RAM Tile" "DSPs" "Bonded IOB"} {
	set fu [open $out/util_impl.rpt r]
	while {[gets $fu line] >= 0} {
		if {[string match "| $t*" $line]} { puts $f [string trim $line]; break }
	}
	close $fu
}
set fp [open $out/power_impl.rpt r]
while {[gets $fp line] >= 0} {
	if {[regexp {^\| (Total On-Chip Power|Dynamic|Device Static|Junction Temperature)} $line]} {
		puts $f [string trim $line]
	}
}
close $fp
close $f
puts "================ build/enh/reports/summary.txt ================"
set f [open $out/summary.txt r]; puts [read $f]; close $f
