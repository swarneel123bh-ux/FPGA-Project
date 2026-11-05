#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v iverilog >/dev/null 2>&1 || { echo "iverilog not found; use Vivado Simulator or install Icarus Verilog." >&2; exit 1; }
command -v vvp >/dev/null 2>&1 || { echo "vvp not found; install Icarus Verilog runtime." >&2; exit 1; }
mkdir -p sim/build

iverilog -g2012 -o sim/build/tb_lfsr rtl/lfsr.v sim/tb_lfsr.v
vvp sim/build/tb_lfsr

iverilog -g2012 -o sim/build/tb_sec_path_id rtl/lfsr.v rtl/sec_path_id.v sim/tb_sec_path_id.v
vvp sim/build/tb_sec_path_id

iverilog -g2012 -o sim/build/tb_power_meter rtl/power_meter.v sim/tb_power_meter.v
vvp sim/build/tb_power_meter

iverilog -g2012 -o sim/build/tb_db_calc rtl/db_calc.v sim/tb_db_calc.v
vvp sim/build/tb_db_calc

iverilog -g2012 -o sim/build/tb_anc_measurement rtl/power_meter.v rtl/db_calc.v rtl/anc_measurement.v sim/tb_anc_measurement.v
vvp sim/build/tb_anc_measurement
