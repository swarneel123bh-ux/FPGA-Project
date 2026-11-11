#!/usr/bin/env bash
# Member A focused regressions. Run from anywhere; requires Icarus Verilog 11+.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build
iverilog -g2012 -Wall -o sim/build/tb_mode_fsm rtl/mode_fsm.v sim/tb_mode_fsm.v
vvp sim/build/tb_mode_fsm
iverilog -g2012 -Wall -o sim/build/tb_out_mux rtl/out_mux.v sim/tb_out_mux.v
vvp sim/build/tb_out_mux
# [Claude fix 11 Nov] codec_cfg regression (26 I2C transactions after the T3 hardware fixes)
iverilog -g2012 -Wall -o sim/build/tb_codec_cfg rtl/codec_cfg.v rtl/adau_i2c_write.v sim/tb_codec_cfg.v
vvp sim/build/tb_codec_cfg
