# Hardware results: Wednesday 11 Nov 2026 (T0–T3)

*Written by Claude from the lab session run by Swarneel (not team code). Plan:
[`hardware_testing_plan.md`](hardware_testing_plan.md). Laptop: Ubuntu 24.04.5, Vivado/Vitis 2020.2.*

## Summary

- **T0–T2 pass.** Tools, board, JTAG, UART and the goal-2 MP3 receive/decode all work from the laptop.
- **T3 passes only after four fixes to `rtl/codec_cfg.v`.** With the original file the codec
  configured over I2C but produced no I2S clocks, no playback and no capture. The fixes are now in
  `rtl/codec_cfg.v`, each line tagged `[Claude fix 11 Nov]`, and `sim/tb_codec_cfg.v` was updated
  to match (26 transactions, passes).
- **One known issue remains:** reprogramming the FPGA several times without a power cycle makes the
  codec stop answering I2C. **Power-cycle the ZedBoard (SW8) before each reprogram.**
- **To redo:** left/right check and a second mic, with headphones known to work on both sides
  (the pair used had a dead right earpiece).

## Results sheet

| Test | Result | Value or evidence | Notes |
|---|---|---|---|
| T0 Ubuntu version | PASS | 24.04.5 LTS | Not an official 2020.2 host; tools ran anyway |
| T0 Vivado and Vitis open | PASS | `vivado` v2020.2, `xsct` 2020.2 | 2026.1 is also installed and first on `PATH`: source the 2020.2 `settings64.sh` in every terminal |
| T0 Python | PASS | repo `.venv` has pyserial 3.5, imageio-ffmpeg 0.6.0 | System `pip install` is blocked on 24.04 (PEP 668); use the venv |
| T1 LD13 on; serial device | PASS | `/dev/ttyACM0` | USB devices only appear with the board powered |
| T1 Hardware Manager target | PASS | `xc7z020` | |
| T2 MP3 receive and decode | PASS | file `test_audio/beethoven5_ogg_48k.mp3`; fnv matched by hand | Different file from the plan. Laptop reference for it: fnv `0xc5cf4f22`, 836 frames, 963072 samples, checksum `0x2638ea7c` (x86 gcc) |
| T2 PC checksum, 56k file | note | laptop `0xd986ca98`, plan says `0xb5f37fd1` | Checksum depends on build/CPU (SIMD off gives `0xa2bd42f8`); fnv, frames and samples match |
| T3a bitstream; WNS | PASS | +4.633 ns (original), +4.549 ns (with fix 1) | Needed the lab wrapper: see "Week-1 top cannot make a bitstream" |
| T3b LD12 (DONE) lit | PASS | | |
| T3c `codec_ready` high / `codec_error` low | PASS | read on LD0/LD1 via the lab wrapper | After a power cycle; see known issue |
| T3d LRCLK 48 kHz | PASS after fix 1 | LD2 blinks 1 s on / 1 s off (`sample_tick` ÷ 24000) | Original RTL: no `sample_tick` at all. MCLK/BCLK not measured (no scope) |
| T3e FPGA tone → headphone | PASS after fix 2 | 1 kHz square, −24 dBFS, heard in the left ear | Right earpiece of the headset was broken |
| T3e mic → headphone | PASS after fix 4 | pink jack; tone and music heard | Mic lands on the **left** ADC (heard in left ear with stereo passthrough) |
| T3e mic level (0 dB analog gain) | measured | tone/music peaks above −30 dBFS; silence about −78 to −66 dBFS | Level bar on LD3–LD7 of the diagnostic build |
| T3e L/R swap | BLOCKED | | Redo with working headphones |
| T3e second mic | NOT TESTED | | One mic only |
| JP1 position | not recorded | | Record next time |
| T4, T5, T6 | not tested | | Out of scope |

## The four `codec_cfg` problems

All found on the board. Register meanings checked against the Linux ADAU17x1 driver
(`sound/soc/codecs/adau1761.c`, `adau17x1.c`) and the ADAU1761 datasheet register map.

| # | Symptom on the board | Cause | Fix in `rtl/codec_cfg.v` | Confirmed |
|---|---|---|---|---|
| 1 | `codec_ready` high, but no `sample_tick` (no BCLK/LRCLK) | R65 Clock Enable 0 (0x40F9) and R66 Clock Enable 1 (0x40FA) never written; both reset to 0x00, so the serial port and clock generators are off | rows 21–22: R65 = 0x7F, R66 = 0x03 | yes |
| 2 | FPGA-generated tone not heard; ADC data all zero | R58 (0x40F2) / R59 (0x40F3) reset to 0, which routes the serial port through the SigmaDSP, which is not running | rows 24–25: R58 = R59 = 0x01 (direct serial-in → DAC, ADC → serial-out) | yes |
| 3 | Mic not heard; ADC level below −48 dBFS | ZedBoard MIC jack is wired to LINN/RINN; R4/R6 = 0x51 opened only LINP/RINP | rows 8–9: R4 = R6 = 0x5B (LINN/RINN also 0 dB) | yes |
| 4 | — | MICBIAS (R10) off; headphones at −30 dB | row 23: R10 = 0x01; rows 17–20: headphones −10 dB | ran in the passing build; not tested separately |

Source for the MIC-jack wiring: a third-party ZedBoard write-up
(<https://henryomd.blogspot.com/2015/06/listening-to-sound-on-zedboard.html>), matched by the
board behaviour. Check the Avnet ZedBoard schematic before the report quotes it.

## Known issue: codec stops answering I2C after reprogramming

Seen: after the third FPGA program since power-on, every I2C write NACKed (`codec_error` on, failing
row 0, even after BTND reset). A power cycle cleared it; one program after a power cycle always worked.

Likely cause (not yet checked in the datasheet): ADAU1761 pin ADDR1 is also CLATCH (SPI latch). The
codec starts in I2C mode and switches to SPI after CLATCH goes low a few times. The design ties ADDR1
low, and each FPGA configuration floats then drives the pin low. A possible fix is ADDR0/ADDR1 high
(I2C address 0x3B), but whether that avoids the pulses depends on the pin state during configuration.
**Until someone checks this: power-cycle before every reprogram.**

## Week-1 top cannot make a bitstream on its own

`rtl/week1_passthrough_top.v` has 52 ports with no pin in `constraints/zedboard_week1.xdc`
(`rst`, `codec_ready`, `codec_error`, `sample_tick`, two 24-bit debug buses). Vivado 2020.2 stops at
`write_bitstream` with DRC NSTD-1/UCIO-1; the test plan's "warnings only" was wrong. The lab wrapper
in `lab/week1_wrapper/` gives every port a pin. The integration top `rtl/top.v` with
`constraints/zedboard.xdc` does not have this problem (every port is constrained).

## Other warnings (harmless)

- RPBF-3 on `ac_scl`: SCL has no input buffer because `adau_i2c_write` never reads SCL (no clock
  stretching). The ADAU1761 does not stretch the clock.
- ZPS7-1 "PS7 block required": the week-1 design is PL-only.
- Synth 8-589: `!==` in `adau_i2c_write.v` line 131 is synthesised as `!=`.

## For the retest with working headphones

Use `lab/week1_wrapper/` (see its README). Power-cycle, program once, then:
1. Build `week1_lab_wrapper.bit` (plain passthrough, fixed `rtl/codec_cfg.v`): mic in the pink jack,
   tone near it. Which ear? Expected: left (the mic lands on the left ADC).
2. Second mic: record which channel it lands on and whether it needs JP1 or MICBIAS.
3. Record JP1's position.
