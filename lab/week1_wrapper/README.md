# Week-1 lab builds (not team code)

Written by Claude for the 11 Nov 2026 hardware session. Results: `docs/hardware_results_2026-11-11.md`.
Nothing here is deliverable RTL; the codec fixes themselves are in `rtl/codec_cfg.v`.

**Power-cycle the ZedBoard (SW8 off, 5 s, on) before every reprogram.** Otherwise the codec can stop
answering I2C after a few programs (LD1 on).

## Builds

Run from the repo root, in a terminal where Vivado 2020.2 is sourced
(`source ~/Xilinx/Vivado/2020.2/settings64.sh`). Each takes 5–10 minutes.

| Build | Command | Bitstream |
|---|---|---|
| Plain passthrough (Aarav's `week1_passthrough_top` + fixed `rtl/codec_cfg.v`) | `vivado -mode batch -source lab/week1_wrapper/build_week1.tcl` | `build/week1/week1_lab_wrapper.bit` |
| Diagnostic (tone, gain, level meter) | `vivado -mode batch -source lab/week1_wrapper/build_week1_diag.tcl` | `build/week1_diag/week1_diag_top.bit` |

Program with Hardware Manager → Program Device.

## Plain passthrough: `week1_lab_wrapper`

| Control | Meaning |
|---|---|
| BTND | reset (reruns the codec configuration) |
| LD0 | `codec_ready` |
| LD1 | `codec_error` (an I2C write was not ACKed) |
| LD2 | blinks 1 s on / 1 s off when LRCLK is 48 kHz |

## Diagnostic: `week1_diag_top`

Uses `codec_cfg_diag.v`: the fixed ROM plus blue line-in (AUX) at 0 dB, and a retry-and-continue
sequencer that records the first failing row.

| Control | Meaning |
|---|---|
| SW0 up | FPGA plays a 1 kHz square wave (−24 dBFS) to both ears |
| SW1 up | LD7..LD3 = first ROM row that NACKed twice (binary, LD3 = bit 0); LD2 = a write was retried |
| SW1 down | LD7..LD3 = level bar of the louder ADC channel (raw): −78 / −66 / −54 / −42 / −30 dBFS |
| SW2 up | passthrough mono: (L+R)/2 to both ears |
| SW3 up | passthrough ×32 (+30 dB), saturating |
| LD0 / LD1 / LD2 | `codec_ready` / `codec_error` / 1 Hz blink from `sample_tick` (SW1 down) |
| BTND | reset |

## Files

| File | What |
|---|---|
| `week1_lab_wrapper.v`, `.xdc` | Pins for every port of `rtl/week1_passthrough_top.v` (the week-1 `.xdc` leaves 52 unplaced, so `write_bitstream` fails) |
| `week1_diag_top.v`, `.xdc` | Diagnostic top built from the same `rtl/` blocks |
| `codec_cfg_diag.v` | Diagnostic copy of `rtl/codec_cfg.v` |
| `build_week1.tcl`, `build_week1_diag.tcl` | Batch builds (Vivado 2020.2, in-memory project) |
