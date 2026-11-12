#!/usr/bin/env bash
# Timing simulation of streaming playback (sw/app/stream_play.c) on the PC.
# Written by Claude (Swarneel's agent), 12 Nov 2026. Not team code.
# Each line must end in PASS: PCM identical to the batch decode, no FIFO underrun or overflow.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
gcc -O2 -Wall -Wextra -o build/stream_sim sim/stream_sim.c sw/app/stream_play.c sw/app/decode.c -Isw/app -lm
fail=0
run() { build/stream_sim "$@" || fail=1; }
for f in test_audio/stairway_full_32k.mp3 test_audio/beethoven5_ogg_32k.mp3 test_audio/synthetic_32k.mp3 \
         test_audio/ABXtesting/excerpt_01_32k.mp3 test_audio/beethoven5_ogg_128k.mp3; do
	[ -f "$f" ] || continue
	run "$f" 230400
	run "$f" 115200
done
# Slow link: playback must wait until the rest of the file can keep up
run test_audio/beethoven5_20s_48k_mono_128k.mp3 57600
# Negative control: told 230,400 baud but the link is 57,600, so it starts too early and must underrun
if build/stream_sim test_audio/beethoven5_ogg_128k.mp3 57600 230400 >/dev/null; then
	echo "negative control did not detect underruns: FAIL"; fail=1
else
	echo "negative control (wrong baud) detected underruns: PASS"
fi
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
