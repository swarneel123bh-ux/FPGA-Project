# Enhancement build (primary goal since 11 Nov 2026)

*Written by Claude (Swarneel's agent) on 11 Nov 2026, at Swarneel's request. The build files listed
below are Claude's, not team-written.*

An MP3 is sent from the laptop over the USB-UART, decoded on the ARM, written into the PL music FIFO
over AXI, passed through `treble_fixed` (treble restoration), and played on the headphones. ANC
blocks are not in this build.

```
laptop --UART 230,400--> ARM: receive, check FNV, decode (minimp3), loop: write PCM to FIFO
                              | AXI GP0, 0x43C0_0000
                              v
PL (100 MHz):  music_fifo_axi --> treble_fixed --> (SW1: test tone) --> i2s_tx --> ADAU1761 --> headphones
               codec_cfg (I2C), i2s_rx (sample_tick, 48 kHz), clk_wiz_0 (24 MHz MCLK)
```

## Files

| File | What |
|---|---|
| `rtl/enh_top.v` | Top: pins, clocking wizard, MCLK, PS block design wrapper, `enh_core` |
| `rtl/enh_core.v` | The PL audio path, switches, LEDs (simulated by `sim/tb_enh_core.v`) |
| `rtl/treble_fixed.v`, `rtl/treble_coefs.mem` | Treble restoration, 32 kbit/s coefficients |
| `constraints/zedboard_enh.xdc` | Pins (copied from the 11 Nov working builds) |
| `scripts/enh_bd.tcl` | Block design: PS7 (ZedBoard preset), AXI interconnect, reset |
| `scripts/build_enh.tcl` | Vivado build: bitstream and XSA |
| `scripts/build_enh_sw.tcl` | Vitis build: platform, app, BOOT.BIN |
| `scripts/run_enh_jtag.tcl` | Program over JTAG and start the app |
| `sw/app/pl_feed.c` | ARM: keeps the PL FIFO full, loops the song |

## Build (Ubuntu laptop, 2020.2)

```bash
source ~/Xilinx/Vivado/2020.2/settings64.sh
vivado -mode batch -source scripts/build_enh.tcl
```
```bash
source ~/Xilinx/Vitis/2020.2/settings64.sh
xsct scripts/build_enh_sw.tcl
```
Outputs in `build/enh/`: `enh_top.bit`, `enh_top.xsa`, `enh_app.elf`, `BOOT.BIN`.
Simulation first if anything RTL changed: `./sim/run_treble.sh` and `./sim/run_enh.sh` (each prints PASS).

## Run on the board

Full step-by-step test for 12 Nov, with pass criteria and a results sheet: [`enh_test_plan_2026-11-12.md`](enh_test_plan_2026-11-12.md).

1. Headphones in the HPH OUT jack. JTAG boot jumpers. PROG and UART USB cables in.
2. **Power-cycle the board (SW8 off, 5 s, on).** Reprogramming without a power cycle can make the
   codec stop answering I2C (LD1 on).
3. Start the sender first (it waits for `**Ready**`):
   ```bash
   .venv/bin/python sw/sender/send_mp3.py /dev/ttyACM0 test_audio/beethoven5_ogg_32k.mp3
   ```
4. In a second terminal: `xsct scripts/run_enh_jtag.tcl` (Vitis 2020.2 sourced).
5. The sender prints the receive and decode results. The song then plays in a loop.
   To watch the playback messages, open a serial terminal at 230,400 baud after the sender has exited.

The file must be 48 kHz mono; the 32 kbit/s files in `test_audio/` and `test_audio/ABXtesting/` are.
The coefficients are set for 32 kbit/s (cutoff 7.2 kHz).

## Switches and LEDs

| Control | Meaning |
|---|---|
| SW0 | up = enhanced, down = plain MP3 (the live A/B switch) |
| SW1 | up = 1 kHz test tone, −24 dBFS, both ears (checks codec and headphones without the ARM) |
| SW2 / SW3 / SW4 | volume (12 Nov): up = −6 / −12 / −24 dB, added together, so 0 to −42 dB in 6 dB steps; all down = 0 dB (as before). Applies to the music and the tone |
| SW5 | added treble: down = gain 1, up = −12 dB (12 Nov) |
| SW6 | enhancer tuning: down = original (7.2 kHz, as blind-tested on 11 Nov; brighter voice, hiss on strummed guitar), up = retune (9 kHz, −6 dB shelf above 11 kHz, −8 dB; less hiss, duller voice) (12 Nov). Changing it mid-song gives a short transient while the filters settle |
| BTND | reset the PL audio path (reruns the codec configuration) |
| LD0 | codec configured (`codec_ready`) |
| LD1 | codec did not answer I2C (`codec_error`): power-cycle |
| LD2 | blinks 1 s on, 1 s off when the codec clocks run at 48 kHz |
| LD3 | music is arriving from the ARM (FIFO not empty) |
| LD4 | SW0 (enhanced) |
| LD5 | AXI side out of reset (the PS has been initialised) |
| LD6 | SW1 (tone) |
| LD7 | output hit full scale in the last 0.25 s (clipping, measured before the volume switches) |

## Fault finding, in order

| Symptom | Check |
|---|---|
| LD1 on, LD0 off | Power-cycle, reprogram once |
| LD2 not blinking | Codec clocks missing: as on 11 Nov before the `codec_cfg` fixes |
| SW1 up, no tone | Codec/headphone path: compare with `build/week1_diag/week1_diag_top.bit` (SW0 tone) |
| Tone OK, LD5 off | PS not initialised: `ps7_init` / `ps7_post_config` did not run |
| LD5 on, LD3 off | ARM not writing: check the sender output and the serial messages |
| LD3 on, no music | Check SW1 is down |
| Music, no difference with SW0 | Expected on dull passages; use a bright passage, and listen above about 7 kHz |
| LD7 often on | The added treble clips: lower the input level, or add a gain below 1 in the model and RTL |

## Build results (11 Nov)

Built on the Ubuntu laptop with Vivado/Vitis 2020.2. **Not yet run on the board.**

| Item | Result |
|---|---|
| `./sim/run_treble.sh` | PASS: 34,056 checks, `treble_fixed` bit-exact with `model/goal2/ref_fixed.py` |
| `./sim/run_enh.sh` | PASS: 30,756 samples written over AXI come out of the I2S serial line bit-exact with the model (both ears); no FIFO underrun; SW1 tone correct |
| 12 Nov, `./sim/run_treble.sh` | PASS: 34,056 checks bit-exact, with SW6 (both tunings) and SW5 (−12 dB) switched mid-signal from `sim/vectors/treble_ctl.hex`. Negative control (switches ignored in the testbench): 18,238 mismatches, so the vectors do exercise them. Tuning 0 ROM words are identical to the 11 Nov ROM |
| 12 Nov, `./sim/run_enh.sh` | PASS: as above (switches down), plus volume −18 / −42 dB exact on both ears, SW5/SW6 reach `treble_fixed` |
| 12 Nov bitstream | `build/enh/enh_top.bit` (15:36): WNS +2.92 ns at 100 MHz, 0 critical warnings; 1,679 LUTs, 2,588 flip-flops, 3 BRAM tiles; SW5 on H18, SW6 on H17 (placed I/O report). **Run on the board 12 Nov (Stairway to Heaven, full song): works; these settings kept for the 14 Nov submission** |
| 12 Nov app | `build/enh/enh_app.elf` (15:38), with streaming playback (`stream_play.c`; `./sim/run_stream.sh` ALL PASS). On the board 12 Nov: first audio 733 ms after the header (sim predicted 0.73 s; was 93 s), 1,931,757 bytes, 0 UART errors, fnv match, 20,121 frames, decode x53 real time |
| Bitstream | `build/enh/enh_top.bit`, WNS +2.97 ns at 100 MHz; 1,603 LUTs, 2,569 flip-flops, 2 DSP48E1, 3 BRAM tiles (FIFO) |
| Address map | M_AXI at 0x43C0_0000, 64 KB |
| ARM app | `build/enh/enh_app.elf`: `-DBOARD -O2`, 64 KB stack |
| SD image | `build/enh/BOOT.BIN` (FSBL, bitstream, app) |
| Known warning | `Clock 'sys_clk' completely overrides clock 'clk100'`: the clocking wizard and the `.xdc` both define the same 100 MHz clock; harmless, same as the week-1 build |

The sender must be running before the app prints `**Ready**`, as before. `BOOT.BIN` is built
but not used: the team has no SD card, so the board is always run over JTAG.
