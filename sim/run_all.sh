#!/usr/bin/env bash
# Run every testbench of the submission with the committed vectors (Icarus Verilog).
# Written by Claude (Swarneel's agent), 19 Nov 2026. Not team code.
# From any shell:  bash sim/run_all.sh
# Does not regenerate vectors (sim/run_treble.sh does; it needs numpy/scipy).
# sim/run_stream.sh is separate: it needs the test MP3s in test_audio/ (not submitted).
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build
fail=0
run() {   # name, then the RTL files
	local n=$1; shift
	if ! iverilog -g2012 -o "sim/build/$n" "$@" "sim/$n.v" 2>"sim/build/$n.err"; then
		echo "$n: COMPILE FAILED (sim/build/$n.err)"; fail=1; return
	fi
	local r
	r=$(vvp -n "sim/build/$n" | grep -E "PASS|FAIL" | tail -1)
	echo "$n: ${r:-no PASS line}"
	case "$r" in PASS*) ;; *) fail=1 ;; esac
}
run tb_treble_fixed    rtl/treble_fixed.v
run tb_enh_core        rtl/enh_core.v rtl/treble_fixed.v rtl/music_fifo_axi.v rtl/music_fifo.v \
                       rtl/codec_cfg.v rtl/adau_i2c_write.v rtl/i2s_rx.v rtl/i2s_tx.v
run tb_music_fifo      rtl/music_fifo.v
run tb_music_fifo_axi  rtl/music_fifo.v rtl/music_fifo_axi.v
run tb_codec_cfg       rtl/codec_cfg.v rtl/adau_i2c_write.v
run tb_i2s_rx          rtl/i2s_rx.v
run tb_i2s_tx          rtl/i2s_tx.v
run tb_i2s_tx_skew     rtl/i2s_tx.v
[ $fail = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
