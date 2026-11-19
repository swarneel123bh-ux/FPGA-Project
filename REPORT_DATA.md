# Report data: 19 Nov 2026 runs on Ubuntu, Vivado/Vitis 2020.2

Written by Claude (Swarneel's agent), 19 Nov 2026. Every number below is copied from the file named
next to it (all files are in this folder). Source tree: branch `submission`, commit `2fc805c`
(RTL identical to `39d2a76` on `d/goal2`).

## Tools

- Vivado: `Vivado v.2020.2 (lin64) Build 3064766 Wed Nov 18 09:12:47 MST 2020` (util_impl.rpt header)
- Vitis: `xsct 2020.2`
- Device: xc7z020clg484-1 (ZedBoard)

## Timing, full design `enh_top` (timing_impl.rpt, Design Timing Summary)

| WNS | TNS | TNS failing endpoints | TNS total endpoints | WHS | THS | THS failing | WPWS | TPWS failing |
|---|---|---|---|---|---|---|---|---|
| 2.921 ns | 0.000 ns | 0 | 5582 | 0.043 ns | 0.000 ns | 0 | 3.000 ns | 0 |

Clock: 100 MHz (10 ns). build_enh.log: `WNS = 2.921 ns`, `BUILD_DONE`. Same as the 12 Nov build (+2.921 ns).

## Utilization, full design after implementation (util_impl.rpt)

| Resource | Used | Available | Util % |
|---|---|---|---|
| Slice LUTs | 1679 | 53200 | 3.16 |
| LUT as Logic | 1619 | 53200 | 3.04 |
| LUT as Memory (all shift registers) | 60 | 17400 | 0.34 |
| Slice Registers (all flip-flops) | 2588 | 106400 | 2.43 |
| Slice | 928 | 13300 | 6.98 |
| F7 Muxes | 25 | 26600 | 0.09 |
| Block RAM Tile | 3 | 140 | 2.14 |
| DSPs | 2 | 220 | 0.91 |
| Bonded IOB | 25 | 200 | 12.50 |
| BUFGCTRL (BUFG) | 3 | 32 | 9.38 |
| MMCME2_ADV | 1 | 4 | 25.00 |
| PS7 | 1 | | |

### Per module (util_impl_hier.rpt)

| Instance | Module | LUTs | Logic LUTs | SRLs | FFs | RAMB36 | DSP |
|---|---|---|---|---|---|---|---|
| enh_top (top) | | 1679 | 1619 | 60 | 2588 | 3 | 2 |
| u_core | enh_core | 1321 | 1321 | 0 | 2157 | 3 | 2 |
| u_core/u_treble | treble_fixed | 1038 | 1038 | 0 | 1789 | 0 | 2 |
| u_core/u_codec | codec_cfg | 151 | 151 | 0 | 132 | 0 | 0 |
| u_core/u_fifo | music_fifo_axi | 58 | 58 | 0 | 115 | 3 | 0 |
| u_core/u_tx | i2s_tx | 33 | 33 | 0 | 61 | 0 | 0 |
| u_core/u_rx | i2s_rx | 12 | 12 | 0 | 13 | 0 | 0 |
| u_ps | enh_ps_wrapper | 359 | 299 | 60 | 431 | 0 | 0 |
| u_clk | clk_wiz_0 | 0 | 0 | 0 | 0 | 0 | 0 |
| u_mclk | mclk_out | 0 | 0 | 0 | 0 | 0 | 0 |

## Power (power_impl.rpt, vectorless, confidence Low)

| Item | Value |
|---|---|
| Total on-chip power | 1.821 W |
| Dynamic | 1.673 W |
| Device static | 0.148 W |
| Junction temperature | 46.0 °C |
| Effective TJA / max ambient | 11.5 °C/W / 64.0 °C |
| PS7 (on-chip components) | 1.529 W |
| MMCM | 0.122 W |
| Clocks / Signals / Slice logic / I/O / DSP / BRAM | 0.008 / 0.004 / 0.003 / 0.005 / 0.002 / <0.001 W |

By hierarchy: enh_top 1.673 W; u_ps 1.533 W (processing_system7_0 1.529 W, axi_ic 0.003 W);
u_clk 0.122 W; u_core 0.014 W (u_treble 0.011 W).

## Critical warnings

`grep -c "CRITICAL WARNING" build/enh/proj/enh.runs/*/runme.log`: **1** in total (synth_1: 1; impl_1 and
the IP runs: 0). It is:
`[Constraints 18-1056] Clock 'sys_clk' completely overrides clock 'clk100'.`

## treble_fixed alone (out of context, scripts/postsynth_sim_treble.tcl, 100 MHz)

- Post-route WNS 2.385 ns, TNS 0.000, WHS 0.144 ns, 0 failing endpoints (timing_postroute.rpt)
- Post-synthesis: 976 LUTs, 1791 FFs, 0 BRAM, 2 DSP (util_postsynth.rpt)
- Post-route: 971 LUTs, 1791 FFs, 0 BRAM, 2 DSP (util_postroute.rpt)

## Gate-level simulation (Vivado xsim, testbench sim/tb_treble_fixed.v unchanged except the 2 ns input delays)

- `post_synth_func: PASS, 34056 checks bit-exact` (post_synth_func.log)
- `post_route_func: PASS, 34056 checks bit-exact` (post_route_func.log)
- Both logs: 0 mismatches in checks 1/2, 4 and 6; `longest tick-to-result 112 clocks (limit 140)`.
- The optional post-route timing (SDF) simulation was **not run**: each functional run took 25 to 31 minutes.

## RTL simulation, Icarus Verilog, committed vectors (icarus_clean.log, run on the cleaned tree)

```
tb_treble_fixed     PASS: 34056 checks, bit-exact with model/goal2/ref_fixed.py
                    check 5: longest tick-to-result 112 clocks (limit 140)
tb_enh_core         PASS
run_stream.sh       11 runs PASS (stairway_full_32k, beethoven5_ogg_32k, synthetic_32k, excerpt_01_32k
                    at 230400 and 115200 baud; beethoven5_ogg_128k at both; beethoven5_20s 128k at 57600),
                    underruns 0 overflows 0, pcm same res same; negative control PASS; ALL PASS
tb_music_fifo       PASS: 2169 cycles checked, 0 errors
tb_music_fifo_axi   PASS: 4124 checks, 0 errors
tb_codec_cfg        PASS: codec_cfg emitted all 26 expected I2C transactions.
tb_i2s_rx           PASS: i2s_rx captured two signed stereo I2S frames.
tb_i2s_tx           PASS: i2s_tx serialized the stereo sample pair.
tb_i2s_tx_skew      PASS: i2s_tx correct for LRCLK skew -60..+60 ns, 200 drifting frames each
```

## PC decoder vs board (x86 gcc build of sw/app/decode.c, beethoven5_ogg_32k.mp3)

```
fnv1a(mp3) = 0xc50fe207
res.frame_count = 836, sample_rate = 48000, channel_count = 1, samples_per_channel = 963072
res.checksum = 0x27133182
```
- fnv1a **matches** the 12 Nov expected value `0xc50fe207` (docs/enh_test_plan_2026-11-12.md).
- res.checksum **does not match** the brief's board value `0x710F8695`. That board value could not be
  found in any file in the repository, so it is not verified here. Recorded, not counted as a failure.

## Vitis

`xsct scripts/build_enh_sw.tcl`: `SW_DONE .../build/enh/enh_app.elf .../build/enh/BOOT.BIN`
(enh_app.elf 270,332 bytes).

## Not done

- Screenshots: no screen-capture tool was available in this session. Take them by hand from
  `vivado build/enh/proj/enh.xpr`.
- Board test of demo.sh: no ZedBoard was connected when this was written (no USB-UART device).
  `bash -n demo.sh` passes.
