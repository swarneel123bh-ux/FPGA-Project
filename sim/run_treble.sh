#!/usr/bin/env bash
# Regenerate the treble vectors and run tb_treble_fixed.
# Written by Claude (Swarneel's agent), 11 Nov 2026. Not team code.
set -euo pipefail
cd "$(dirname "$0")/.."
PY=${PY:-.venv/bin/python}
"$PY" model/goal2/ref_fixed.py
mkdir -p sim/build
iverilog -g2012 -Wall -o sim/build/tb_treble_fixed rtl/treble_fixed.v sim/tb_treble_fixed.v
vvp -n sim/build/tb_treble_fixed
