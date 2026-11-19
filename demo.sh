#!/usr/bin/env bash
# demo.sh: play an MP3 through the ZedBoard enhancement system with one command.
# Written by Claude (Swarneel's agent), 19 Nov 2026, at Swarneel's request. Not team code.
#
# Usage (from anywhere; Ubuntu with Vivado/Vitis 2020.2):
#   ./demo.sh song.mp3                 build if needed, program the FPGA, start the ARM app, send, play
#   ./demo.sh song.mp3 --app-only      next song: restart only the ARM app (FPGA and codec untouched)
#   ./demo.sh song.mp3 --rebuild       rebuild bitstream and app first (about 10 minutes)
#   ./demo.sh song.mp3 --port /dev/ttyACM1 --yes
# Options:
#   --port DEV     USB-UART port (default: auto-detect the ZedBoard's Cypress bridge)
#   --app-only     do not reprogram the FPGA (use for the 2nd, 3rd ... song after a full run)
#   --rebuild      run scripts/build_enh.tcl and scripts/build_enh_sw.tcl even if outputs exist
#   --as-is        send the file unchanged (it must already be 48 kHz mono)
#   --bitrate R    bitrate when converting (default 32k: the enhancer is tuned for 32 kbit/s)
#   --yes          do not stop to ask for the board power-cycle
#
# What it does:
#   1. Finds Vivado/Vitis 2020.2 and sources their settings.
#   2. Builds build/enh/{enh_top.bit,enh_top.xsa,enh_app.elf} if missing (or with --rebuild).
#   3. Sets up Python (pyserial, imageio-ffmpeg) in .venv if needed.
#   4. Checks the MP3: 48 kHz mono is sent unchanged; anything else is converted to 48 kHz mono
#      at 32 kbit/s (a second lossy step: fine for a demo, not for measurements).
#   5. Asks you to power-cycle the board (SW8): reprogramming without it can stop the codec.
#   6. Starts the sender (it waits for the board's **Ready**), then programs the FPGA and starts
#      the ARM app over JTAG (scripts/run_enh_jtag.tcl). The board receives, decodes and plays.
# Board setup: JTAG boot jumpers, PROG and UART micro-USB cables in, headphones in HPH OUT.
# Controls while playing: SW0 enhanced/plain, SW1 test tone, SW2-4 volume, SW5 treble -12 dB,
# SW6 second tuning. The song loops until the next run or a power-off.

set -eo pipefail
START_DIR="$(pwd)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

die()  { echo "demo.sh: ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# ---------------------------------------------------------------- arguments
MP3=""; PORT=""; APP_ONLY=0; REBUILD=0; AS_IS=0; BITRATE=32k; YES=0
while [ $# -gt 0 ]; do
	case "$1" in
		--port)     PORT="$2"; shift 2 ;;
		--app-only) APP_ONLY=1; shift ;;
		--rebuild)  REBUILD=1; shift ;;
		--as-is)    AS_IS=1; shift ;;
		--bitrate)  BITRATE="$2"; shift 2 ;;
		--yes|-y)   YES=1; shift ;;
		-h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
		-*)         die "unknown option $1 (see ./demo.sh --help)" ;;
		*)          [ -z "$MP3" ] || die "give one MP3 file"; MP3="$1"; shift ;;
	esac
done
[ -n "$MP3" ] || { sed -n '2,30p' "$0"; exit 1; }
case "$MP3" in /*) ;; *) MP3="$START_DIR/$MP3" ;; esac   # relative to where the user ran it
[ -f "$MP3" ] || die "file not found: $MP3"

# ---------------------------------------------------------------- Xilinx 2020.2 tools
find_settings() {   # $1 = Vivado or Vitis
	local c
	for c in "${XILINX_ROOT:-}/$1/2020.2/settings64.sh" "$HOME/Xilinx/$1/2020.2/settings64.sh" \
	         "/tools/Xilinx/$1/2020.2/settings64.sh" "/opt/Xilinx/$1/2020.2/settings64.sh"; do
		[ -f "$c" ] && { echo "$c"; return 0; }
	done
	return 1
}
VITIS_SET="$(find_settings Vitis)" || die "Vitis 2020.2 settings64.sh not found (set XILINX_ROOT, e.g. XILINX_ROOT=\$HOME/Xilinx)"
VIVADO_SET="$(find_settings Vivado)" || die "Vivado 2020.2 settings64.sh not found (set XILINX_ROOT)"
# shellcheck disable=SC1090
set +e; source "$VIVADO_SET"; source "$VITIS_SET"; set -e
vivado -version 2>/dev/null | head -1 | grep -q "v2020.2" || die "vivado on PATH is not 2020.2"
command -v xsct >/dev/null || die "xsct not found after sourcing $VITIS_SET"
info "Xilinx tools: $(vivado -version | head -1)"

# ---------------------------------------------------------------- build if needed
OUT="$ROOT/build/enh"
PS7_INIT="$ROOT/build/enh_ws/enh_plat/hw/ps7_init.tcl"
if [ $REBUILD = 1 ] || [ ! -f "$OUT/enh_top.bit" ] || [ ! -f "$OUT/enh_top.xsa" ]; then
	info "Building the bitstream (Vivado, several minutes): log build/build_enh.log"
	mkdir -p "$ROOT/build"
	vivado -mode batch -nojournal -source scripts/build_enh.tcl > build/build_enh.log 2>&1 \
		|| die "Vivado build failed, see build/build_enh.log"
	grep -q BUILD_DONE build/build_enh.log || die "Vivado build did not finish, see build/build_enh.log"
	REBUILD=1   # the app must be rebuilt on the new XSA
fi
if [ $REBUILD = 1 ] || [ ! -f "$OUT/enh_app.elf" ] || [ ! -f "$PS7_INIT" ]; then
	info "Building the ARM app (Vitis/xsct): log build/build_enh_sw.log"
	xsct scripts/build_enh_sw.tcl > build/build_enh_sw.log 2>&1 \
		|| die "ARM app build failed, see build/build_enh_sw.log"
	grep -q SW_DONE build/build_enh_sw.log || die "ARM app build did not finish, see build/build_enh_sw.log"
fi
[ -f "$PS7_INIT" ] || die "missing $PS7_INIT (run with --rebuild)"

# ---------------------------------------------------------------- Python
PY=""
for c in "$ROOT/.venv/bin/python" python3; do
	if command -v "$c" >/dev/null && "$c" -c "import serial, imageio_ffmpeg" 2>/dev/null; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
	info "Setting up Python packages in .venv (needs internet once)"
	python3 -m venv "$ROOT/.venv" || die "python3 -m venv failed (sudo apt install python3-venv)"
	"$ROOT/.venv/bin/pip" install -q -r sw/sender/requirements.txt || die "pip install failed"
	PY="$ROOT/.venv/bin/python"
fi

# ---------------------------------------------------------------- MP3 format check
# Reads the first MPEG audio frame header (after any ID3v2 tag).
FMT="$("$PY" - "$MP3" <<'PYEOF'
import sys
d = open(sys.argv[1], "rb").read(1 << 20)
i = 0
if d[:3] == b"ID3" and len(d) >= 10:
    i = 10 + ((d[6] & 0x7F) << 21 | (d[7] & 0x7F) << 14 | (d[8] & 0x7F) << 7 | (d[9] & 0x7F))
rates = {3: (44100, 48000, 32000), 2: (22050, 24000, 16000), 0: (11025, 12000, 8000)}
while i + 4 <= len(d):
    if d[i] == 0xFF and (d[i + 1] & 0xE0) == 0xE0:
        ver = (d[i + 1] >> 3) & 3; layer = (d[i + 1] >> 1) & 3
        sr_i = (d[i + 2] >> 2) & 3; mode = (d[i + 3] >> 6) & 3
        if ver != 1 and layer == 1 and sr_i != 3:          # valid Layer III header
            print(rates[ver][sr_i], "mono" if mode == 3 else "stereo"); sys.exit(0)
    i += 1
print("unknown unknown")
PYEOF
)"
mkdir -p "$ROOT/build"
SEND_FILE="$MP3"
if [ "$FMT" = "48000 mono" ] || [ $AS_IS = 1 ]; then
	info "File is $FMT: sent unchanged"
else
	# Converted here, before the sender starts, so the sender is already listening when the
	# board prints **Ready** (a long song takes several seconds to convert).
	SEND_FILE="$ROOT/build/demo_input_48k_mono_${BITRATE}.mp3"
	info "File is $FMT: converting to 48 kHz mono at $BITRATE for the board (demo only)"
	FFMPEG="$("$PY" -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")"
	"$FFMPEG" -v error -y -i "$MP3" -ar 48000 -ac 1 -b:a "$BITRATE" -f mp3 "$SEND_FILE" \
		|| die "ffmpeg could not convert $MP3"
fi
SIZE=$(wc -c < "$SEND_FILE")
[ "$SIZE" -le 2097152 ] || die "file is $SIZE bytes; the board takes at most 2 MiB (about 8.7 min at 32k). Use a shorter song (32 kbit/s is the lowest MP3 rate at 48 kHz)"

# ---------------------------------------------------------------- serial port
if [ -z "$PORT" ]; then
	PORT="$(ls /dev/serial/by-id/*Cypress* 2>/dev/null | head -1 || true)"
	[ -n "$PORT" ] || PORT="$(ls /dev/ttyACM* 2>/dev/null | head -1 || true)"
	[ -n "$PORT" ] || PORT="$(ls /dev/ttyUSB* 2>/dev/null | head -1 || true)"
fi
[ -n "$PORT" ] || die "no USB-UART port found: is the UART cable in and the board on? (or give --port)"
[ -r "$PORT" ] && [ -w "$PORT" ] || die "no permission on $PORT: sudo usermod -aG dialout \$USER, then log out and in"
info "UART port: $PORT"

# ---------------------------------------------------------------- go
if [ $APP_ONLY = 0 ] && [ $YES = 0 ]; then
	echo
	echo "Power-cycle the ZedBoard now (SW8 off, wait 5 s, on). JTAG boot jumpers, headphones in HPH OUT."
	read -r -p "Press Enter when the board is back on... " _
	sleep 2   # let the USB-UART re-enumerate
	if [ ! -e "$PORT" ]; then
		NEWPORT="$(ls /dev/serial/by-id/*Cypress* /dev/ttyACM* 2>/dev/null | head -1 || true)"
		[ -n "$NEWPORT" ] || die "UART port disappeared after the power-cycle"
		PORT="$NEWPORT"; info "UART port is now $PORT"
	fi
fi

mkdir -p "$ROOT/build"
LOG="$ROOT/build/demo_$(date +%Y%m%d_%H%M%S).log"
info "Starting the sender (log: ${LOG#$ROOT/})"
"$PY" -u sw/sender/send_mp3.py "$PORT" "$SEND_FILE" > "$LOG" 2>&1 &
SENDER=$!
tail -n +1 -f "$LOG" &
TAILER=$!
trap 'kill $SENDER $TAILER 2>/dev/null || true' INT TERM EXIT
sleep 2   # the sender opens the port before the board prints **Ready**

if [ $APP_ONLY = 1 ]; then
	info "Restarting the ARM app only (FPGA left as it is)"
	xsct scripts/run_enh_jtag.tcl app > build/demo_jtag.log 2>&1 || { kill $SENDER 2>/dev/null; die "JTAG failed, see build/demo_jtag.log"; }
else
	info "Programming the FPGA and starting the ARM app over JTAG"
	xsct scripts/run_enh_jtag.tcl > build/demo_jtag.log 2>&1 || { kill $SENDER 2>/dev/null; die "JTAG failed, see build/demo_jtag.log (cable in? board on? JTAG jumpers?)"; }
fi
grep -q RUNNING build/demo_jtag.log || { kill $SENDER 2>/dev/null; die "app did not start, see build/demo_jtag.log"; }

info "ARM app started; waiting for the board's report (audio starts within about a second of the transfer)"
SENDER_OK=0; wait $SENDER && SENDER_OK=1
sleep 1; kill $TAILER 2>/dev/null || true
if [ $SENDER_OK = 1 ] && ! grep -qE "\[FAIL\]|Hang|hang:|Something went wrong" "$LOG"; then
	echo
	info "PLAYING. The song loops until the next run or power-off."
	echo "    SW0 up = enhanced, down = plain MP3 | SW1 test tone | SW2-4 volume | SW5 treble -12 dB | SW6 second tuning"
	echo "    Next song without reprogramming: ./demo.sh other.mp3 --app-only"
	echo "    LEDs: LD0 codec ready, LD1 codec error (power-cycle), LD2 blinks = 48 kHz clocks, LD3 music arriving"
else
	die "the board did not play the file (see ${LOG#$ROOT/}). If LD1 is on: power-cycle and run again"
fi
