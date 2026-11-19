# Post-synthesis and post-route simulation of rtl/treble_fixed.v with Vivado 2020.2 (xsim).
# Written by Claude (Swarneel's agent), 19 Nov 2026, at Swarneel's request. Not team code.
#
# Runs the unchanged bit-exact testbench sim/tb_treble_fixed.v (vectors from
# model/goal2/ref_fixed.py) against the gate-level netlists Vivado writes after synthesis and
# after routing, instead of against the RTL.
#
# From the repo root, in a terminal with Vivado 2020.2 sourced:
#   vivado -mode batch -source scripts/postsynth_sim_treble.tcl
#   vivado -mode batch -source scripts/postsynth_sim_treble.tcl -tclargs timing    (adds a
#       post-route TIMING simulation with SDF delays; slower, optional)
# Output: build/postsim/  (*.log, netlists, util/timing/power reports of the block alone)
# Each simulation prints "PASS: 34056 checks ..." at the end of its log, as the RTL run does.
#
# Changes made to a COPY of the testbench (the original is not touched):
#   - the COEF_FILE parameter override is removed (a netlist has no parameters; the ROM
#     contents are already inside it);
#   - the inputs reach the netlist through 2 ns delays, so they never change exactly on the
#     clock edge (needed for the timing simulation, harmless for the others);
#   - 200 ns wait before each reset, after the global set/reset (GSR) of the netlist ends.

set root [file normalize [pwd]]
set out  $root/build/postsim
set part xc7z020clg484-1
set do_timing [expr {[lsearch $argv timing] >= 0}]

if {![file exists $root/sim/vectors/treble_in.hex]} {
	puts "Run from the repository root (sim/vectors/treble_in.hex not found)"; exit 1
}
file delete -force $out
file mkdir $out $out/sim/vectors $out/rtl
foreach v {treble_in.hex treble_out.hex treble_ctl.hex} {
	file copy $root/sim/vectors/$v $out/sim/vectors/$v
}
file copy $root/rtl/treble_coefs.mem $out/rtl/treble_coefs.mem

# ---------------------------------------------------------------- testbench copy
set f [open $root/sim/tb_treble_fixed.v r]; set tb [read $f]; close $f
set inst_old {treble_fixed #(.COEF_FILE("rtl/treble_coefs.mem")) uut (
	.clk(clk), .rst(rst), .sample_tick(sample_tick),
	.music_raw(music_raw), .music(music), .enh_en(enh_en),
	.tune_sel(tune_sel), .att12(att12)
);}
set inst_new {wire #2 rst_d = rst;
wire #2 tick_d = sample_tick;
wire signed [23:0] #2 raw_d = music_raw;
wire #2 enh_d = enh_en;
wire #2 tune_d = tune_sel;
wire #2 att_d = att12;
treble_fixed uut (
	.clk(clk), .rst(rst_d), .sample_tick(tick_d),
	.music_raw(raw_d), .music(music), .enh_en(enh_d),
	.tune_sel(tune_d), .att12(att_d)
);}
set i [string first $inst_old $tb]
if {$i < 0} { puts "TB_PATCH_FAILED: instance text not found in sim/tb_treble_fixed.v"; exit 1 }
set tb [string replace $tb $i [expr {$i + [string length $inst_old] - 1}] $inst_new]
set n [regsub -all {\n\tdo_reset;} $tb "\n\t#200 do_reset;" tb]
if {$n != 3} { puts "TB_PATCH_FAILED: expected 3 do_reset calls, found $n"; exit 1 }
set f [open $out/tb_treble_fixed_post.v w]; puts -nonewline $f $tb; close $f

# ---------------------------------------------------------------- synthesis and routing (block alone)
set f [open $out/clk.xdc w]
puts $f {create_clock -period 10.000 -name clk [get_ports clk]}
close $f

# Synthesis reads COPIES in build/postsim/rtl: Vivado 2020.2 removed the .mem file it read in
# non-project mode (seen on 19 Nov), so the repository files are never handed to it.
file copy $root/rtl/treble_fixed.v $out/rtl/treble_fixed.v
read_verilog $out/rtl/treble_fixed.v
read_mem $out/rtl/treble_coefs.mem
read_xdc $out/clk.xdc
cd $out/rtl
synth_design -top treble_fixed -part $part -mode out_of_context
cd $out
write_verilog -force -mode funcsim $out/treble_fixed_postsynth.v
report_utilization -file $out/util_postsynth.rpt

opt_design
place_design
route_design
report_timing_summary -file $out/timing_postroute.rpt
report_utilization -file $out/util_postroute.rpt
report_power -file $out/power_postroute.rpt
write_verilog -force -mode funcsim $out/treble_fixed_postroute.v
if {$do_timing} {
	write_sdf -force -mode timesim $out/treble_fixed_postroute.sdf
	write_verilog -force -mode timesim -sdf_anno true -sdf_file $out/treble_fixed_postroute.sdf \
		$out/treble_fixed_postroute_timesim.v
}

# ---------------------------------------------------------------- simulations
set glbl $::env(XILINX_VIVADO)/data/verilog/src/glbl.v
set results {}

proc run_sim {name netlist libs xelab_extra} {
	global out glbl results
	cd $out
	set ok 1
	if {[catch {exec xvlog -work $name $netlist $out/tb_treble_fixed_post.v $glbl >& $out/${name}_xvlog.log}]} {
		set ok 0
	} elseif {[catch {exec xelab -L $name {*}$libs {*}$xelab_extra -s ${name}_snap \
			$name.tb_treble_fixed $name.glbl >& $out/${name}_xelab.log}]} {
		set ok 0
	} elseif {[catch {exec xsim ${name}_snap -R >& $out/${name}.log}]} {
		set ok 0
	}
	set verdict "FAIL (see build/postsim/${name}*.log)"
	if {$ok} {
		set f [open $out/${name}.log r]; set txt [read $f]; close $f
		if {[regexp {PASS: (\d+) checks} $txt -> nchk]} { set verdict "PASS, $nchk checks bit-exact" }
	}
	lappend results "$name: $verdict"
}

run_sim post_synth_func  $out/treble_fixed_postsynth.v {-L unisims_ver} {}
run_sim post_route_func  $out/treble_fixed_postroute.v {-L unisims_ver} {}
if {$do_timing} {
	run_sim post_route_timing $out/treble_fixed_postroute_timesim.v {-L simprims_ver} \
		{-maxdelay -transport_int_delays -pulse_r 0 -pulse_int_r 0}
}

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "================ RESULTS (build/postsim) ================"
puts "treble_fixed alone, post-route WNS at 100 MHz: $wns ns"
foreach r $results { puts $r }
