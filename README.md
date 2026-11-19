# FPGA Audio Enhancement: treble restoration of low-bitrate MP3 on the ZedBoard

*Written by Claude, Swarneel's agent, 19 Nov 2026.*

EEE F314 FPGA-Based System Design, BITS Pilani Hyderabad. **Group 16**, section P2.

| Member | ID |
|---|---|
| Aarav Barnwal | 2023B3A30512H |
| Aadyant Lahiri | 2023B3AA1191H |
| Samarth Shreepad Dixit | 2023B1AA1324H |
| Swarneel Bhattacharjee | 2023AAPS0695H |

An MP3 is sent from a PC over the USB-UART, decoded on the Zynq ARM (minimp3), streamed over
AXI4-Lite into a FIFO in the PL, passed through `treble_fixed` (fixed-point treble restoration),
and played through I2S to the on-board ADAU1761 codec and the headphones. Top module: `enh_top`.
Tools: Vivado / Vitis **2020.2**, ZedBoard (xc7z020clg484-1).

```
MP3 (PC) --UART--> ARM: minimp3 decode --AXI4-Lite--> music_fifo_axi --> treble_fixed --> i2s_tx --> ADAU1761 --> HPH OUT
```

## Layout

```
rtl/          PL Verilog: enh_top, enh_core, treble_fixed (+ treble_coefs.mem), music_fifo,
              music_fifo_axi, codec_cfg, adau_i2c_write, i2s_rx, i2s_tx, mclk_out
constraints/  zedboard_enh.xdc
scripts/      build_enh.tcl (+ enh_bd.tcl), build_enh_sw.tcl, run_enh_jtag.tcl,
              reports_enh.tcl, postsynth_sim_treble.tcl
sim/          testbenches, vectors (treble_*.hex), run_treble.sh, run_enh.sh, run_stream.sh,
              stream_sim.c
sw/app/       bare-metal ARM application (UART receive, MP3 decode, AXI feed, streaming play)
sw/sender/    PC sender (send_mp3.py)
model/goal2/  Python reference models; ref_fixed.py generates the bit-exact test vectors
screenshots/  Vivado 2020.2 screenshots and simulation results (see screenshots/README.md)
demo.sh       one-command demo
```

## Quick demo (one command)

Board: JTAG boot jumpers, PROG and UART micro-USB cables connected, headphones in HPH OUT.

```bash
./demo.sh song.mp3
```

```bash
./demo.sh next.mp3 --app-only
```

The first command builds the bitstream and ARM app if missing, sets up Python in `.venv`,
converts the file to 48 kHz mono at 32 kbit/s if needed, asks you to power-cycle the board,
starts the sender, programs the FPGA and starts the app over JTAG. The second plays another song
without reprogramming the FPGA. Options:

| Option | Meaning |
|---|---|
| `--port DEV` | USB-UART port (default: auto-detect) |
| `--app-only` | restart only the ARM app (for the 2nd, 3rd ... song) |
| `--rebuild` | rebuild bitstream and app even if outputs exist |
| `--as-is` | send the file unchanged (must already be 48 kHz mono) |
| `--bitrate R` | bitrate when converting (default 32k) |
| `--yes` | do not stop for the power-cycle prompt |

## Simulation (Icarus Verilog, committed vectors)

```bash
mkdir -p sim/build
iverilog -g2012 -o sim/build/tb_treble_fixed rtl/treble_fixed.v sim/tb_treble_fixed.v && vvp -n sim/build/tb_treble_fixed | tail -6
bash sim/run_enh.sh | tail -3
bash sim/run_stream.sh | tail -12
for t in "tb_music_fifo rtl/music_fifo.v" "tb_music_fifo_axi rtl/music_fifo.v rtl/music_fifo_axi.v" \
         "tb_codec_cfg rtl/codec_cfg.v rtl/adau_i2c_write.v" "tb_i2s_rx rtl/i2s_rx.v" \
         "tb_i2s_tx rtl/i2s_tx.v" "tb_i2s_tx_skew rtl/i2s_tx.v"; do
  set -- $t; n=$1; shift
  iverilog -g2012 -o sim/build/$n "$@" sim/$n.v && vvp -n sim/build/$n | grep -E "PASS|FAIL"
done
```

`sim/run_treble.sh` regenerates the vectors and `rtl/treble_coefs.mem` from
`model/goal2/ref_fixed.py` (needs numpy/scipy); the commands above use the committed vectors.

PC build of the ARM decoder (prints the MP3 FNV-1a and the PCM checksum):

```bash
mkdir -p build && gcc -O2 -o build/decode_pc sw/app/main_host.c sw/app/decode.c -lm
build/decode_pc test_32k.mp3 /tmp/out.raw
```

## Build (Vivado / Vitis 2020.2)

In every terminal first:

```bash
source ~/Xilinx/Vivado/2020.2/settings64.sh && source ~/Xilinx/Vitis/2020.2/settings64.sh
```

```bash
vivado -mode batch -source scripts/build_enh.tcl
vivado -mode batch -source scripts/reports_enh.tcl
vivado -mode batch -source scripts/postsynth_sim_treble.tcl
xsct scripts/build_enh_sw.tcl
```

- `build_enh.tcl`: bitstream and XSA in `build/enh/`, ends with `BUILD_DONE`.
- `reports_enh.tcl`: utilization, timing, power and DRC reports in `build/enh/reports/`.
- `postsynth_sim_treble.tcl`: runs the bit-exact `treble_fixed` testbench on the post-synthesis
  and post-route netlists (`build/postsim/`); add `-tclargs timing` for an SDF timing simulation.
- `build_enh_sw.tcl`: ARM app `build/enh/enh_app.elf`, ends with `SW_DONE`.

## Running on the board by hand

1. Power-cycle the board (SW8) before each FPGA programming: reprogramming without it can stop
   the codec answering I2C.
2. Start the sender first (it waits for the board's `**Ready**`):
   ```bash
   python3 sw/sender/send_mp3.py /dev/ttyACM0 test_32k.mp3
   ```
3. In a second terminal, program the FPGA and start the app:
   ```bash
   xsct scripts/run_enh_jtag.tcl
   ```
   Next song without reprogramming: `xsct scripts/run_enh_jtag.tcl app`.

## Switches and LEDs (from `rtl/enh_core.v`)

| Control | Function |
|---|---|
| SW0 | up = enhanced, down = plain MP3 |
| SW1 | up = 1 kHz square test tone at -24 dBFS instead of the music |
| SW2 / SW3 / SW4 | volume: up = -6 / -12 / -24 dB, added together (0 to -42 dB) |
| SW5 | up = added treble -12 dB |
| SW6 | up = retuned enhancer (9 kHz, shelf EQ, -8 dB); down = original 7.2 kHz tuning |
| LD0 | codec ready |
| LD1 | codec error (power-cycle) |
| LD2 | 1 Hz blink: 48 kHz LRCLK present |
| LD3 | music arriving (FIFO not empty) |
| LD4 | SW0 (enhanced) |
| LD5 | AXI side out of reset (PS booted) |
| LD6 | SW1 (tone) |
| LD7 | output reached full scale in the last ~0.25 s (clipping) |

## Input format and test audio

The board accepts only **48 kHz mono MP3**; the enhancer is tuned for **32 kbit/s**. The test
audio is **not included** in this submission. Make a test file with:

```bash
ffmpeg -i <source> -ar 48000 -ac 1 -b:a 32k test_32k.mp3
```

`sim/run_stream.sh` needs the Beethoven test MP3s (`beethoven5_ogg_32k.mp3`,
`beethoven5_ogg_128k.mp3`, `beethoven5_20s_48k_mono_128k.mp3`) in `test_audio/`.
