#!/usr/bin/env bash
# Run the enhancement integration testbench (AXI -> FIFO -> treble -> I2S).
# Written by Claude (Swarneel's agent), 11 Nov 2026. Not team code.
# Needs sim/vectors/treble_*.hex and rtl/treble_coefs.mem (from ./sim/run_treble.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build
iverilog -g2012 -o sim/build/tb_enh_core \
  rtl/enh_core.v rtl/treble_fixed.v rtl/music_fifo_axi.v rtl/music_fifo.v \
  rtl/codec_cfg.v rtl/adau_i2c_write.v rtl/i2s_rx.v rtl/i2s_tx.v sim/tb_enh_core.v
vvp -n sim/build/tb_enh_core
