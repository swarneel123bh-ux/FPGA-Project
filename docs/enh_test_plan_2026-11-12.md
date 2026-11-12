# Hardware test plan: Thursday 12 Nov 2026 — enhancement build

*Written by Claude (Swarneel's agent) on 11 Nov 2026, at Swarneel's request. Not team code. Same
layout as [`hardware_testing_plan.md`](hardware_testing_plan.md) (11 Nov). Build details and the
switch/LED table: [`enh_build.md`](enh_build.md).*

**Goal of the session:** show that an MP3 sent from the laptop plays through the headphones, and
that SW0 switches between plain and enhanced live. Enhancement is the primary goal since 11 Nov.
If E2–E5 pass, the team goes back to ANC (decision gate in §2.12).

---

## Part 1: Requirements

### 1.1 Scope

| Test | What it proves | Pass/fail today? | Time |
|---|---|---|---|
| E0 Pre-flight | Laptop, repo, tools, builds and simulations are ready | Yes | 15 min |
| E1 Board power and JTAG | Cables, jumpers, serial port | Yes | 5 min |
| E2 PL bring-up | Bitstream loads, codec configures, clocks at 48 kHz, PS initialised, test tone heard | Yes | 15 min |
| E3 MP3 receive and decode | The new app (with the FIFO feeder) still receives and decodes correctly | Yes | 10 min |
| E4 Plain playback | ARM → AXI → FIFO → I2S → headphones works, at the right speed, without dropouts | Yes | 15 min |
| E5 Live A/B (SW0) | The treble restoration runs on the board and is audible | Yes | 10 min |
| E6 Board vs model | The board sounds like the Python model's output for the same file | Yes (by ear) | 10 min |
| E7 Blind test on the board | The A/B difference is real on the board, not expectation | Yes, if time | 20 min |
| E8 Robustness | Second file without reprogramming, reset, ARM stopped, 10 min soak | Yes | 20 min |
| E10 Recording | The board output recorded for the report's spectra | Optional (needs a line-in) | 20 min |

Not tested: ANC (hardware unavailable), the second microphone, the combined music + ANC mode, SD boot (no SD card; JTAG only).

### 1.2 Hardware

| Item | Detail | Check |
|---|---|---|
| ZedBoard | 12 V adapter in J20 | LD13 lights |
| Micro-USB ×2 | J17 "PROG" (JTAG), J14 "UART" (sender) | Both to the laptop |
| Boot jumpers | JP7–JP11 all on **GND** (JTAG boot) | Leave them there all session |
| Headphones | **The pair that worked on both sides on 11 Nov afternoon.** Black HPH OUT jack | Start at low volume |
| Laptop headphones or second pair, same model if possible | For E6 (laptop playback of the model output) | |
| Phone stopwatch | E4 speed check | |
| Optional: 3.5 mm cable + USB audio interface with line-in | E10 recording | |
| Microphones | Not needed | |

### 1.3 Laptop software

| Item | Check |
|---|---|
| Vivado and Vitis 2020.2 under `~/Xilinx/` | `source ~/Xilinx/Vitis/2020.2/settings64.sh && xsct -version` |
| Repo at `~/Documents/Programming/FPGAProject1/FPGA-Project`, branch `d/goal2`, with the enhancement build | `git log --oneline -3` |
| `.venv` with pyserial, imageio-ffmpeg, numpy, scipy | `.venv/bin/python -c "import serial, numpy, scipy"` |
| Serial access (`dialout` group) | `groups | grep dialout` |
| Icarus Verilog | `iverilog -V` |

Every terminal: `source ~/Xilinx/Vitis/2020.2/settings64.sh` (it also sets up Vivado's
`hw_server`). 2026.1 is first on `PATH` otherwise.

### 1.4 Files

| File | Made by | Used in |
|---|---|---|
| `build/enh/enh_top.bit`, `enh_top.xsa` | `scripts/build_enh.tcl` | E2 |
| `build/enh/enh_app.elf`, `build/enh_ws/` | `scripts/build_enh_sw.tcl` | E2–E8 |
| `scripts/run_enh_jtag.tcl` | repo | E2 (full), E3–E8 (`app` mode) |
| `test_audio/beethoven5_ogg_32k.mp3` | repo | E3–E5, E8 |
| `test_audio/ABXtesting/excerpt_NN_32k.mp3` | repo | E6, E7, E8 |
| `test_audio/ABXtesting/excerpt_NN_{plain,enhanced}.wav` | `make_abx_wavs.py` (E0) | E6 |
| `test_audio/synthetic_32k.mp3` | repo | E5 (bright material) |
| `build/week1_diag/week1_diag_top.bit` | 11 Nov | Fault finding only |

### 1.5 Reference numbers (PC build of the same decoder, 11 Nov)

All three files are 80,396 bytes, 48 kHz mono, 836 frames, 963,072 samples (20.06 s).

| File | `fnv1a` (sender and board `rx:` line) |
|---|---|
| `beethoven5_ogg_32k.mp3` | `0xc50fe207` |
| `ABXtesting/excerpt_01_32k.mp3` | `0x8ee31ad3` |
| `synthetic_32k.mp3` | `0x2a443153` |

The board prints `res.bitrate = 32`. `res.checksum` from the ARM may differ from the PC value (it
did for the 56k file on 11 Nov: build and CPU dependent); fnv, frames and samples must match exactly.
Receive time at 230,400 baud: about 3.5 s.

### 1.6 Known risks

1. **Codec stops answering I2C after reprogramming without a power cycle** (11 Nov). Power-cycle
   (SW8 off, 5 s, on) before every *full* `run_enh_jtag.tcl`. The `app` mode does not reprogram the
   FPGA and is meant to avoid this.
2. **First time this bitstream and app run on hardware.** The PS block design, the AXI path and the
   feeder are simulated (AXI → I2S bit-exact) but the PS side (`ps7_init`, the interconnect, the
   address map 0x43C0_0000) is only proven by the build.
3. **The `app` restart mode is untested.** If the app does not print `**Ready**` after an `app`
   restart, power-cycle and use the full script.
4. **The sender must be waiting before the app prints `**Ready**`**; it clears its input buffer when
   it starts, so a `**Ready**` printed earlier is lost. If you miss it, restart the app (`app` mode).
5. **The app returns after 30 s if nothing is sent** (`[FAIL] header timeout`). Harmless; restart it.
6. **Loudness.** The music is written at full codec scale (int16 << 8) and the headphone amp is set
   to −10 dB. Start with the headphones off your ears, then raise them gradually.
7. **Clock warning** in the build (`sys_clk` overrides `clk100`) is expected and harmless.

---

## Part 2: Execution steps

Fill in the results sheet (§2.11) as you go. Keep a log of each terminal:
`... 2>&1 | tee -a build/lab_2026-11-12.log`.

### E0: Pre-flight (at home or before going to the lab)

1. Repo and tools:
   ```bash
   cd ~/Documents/Programming/FPGAProject1/FPGA-Project && git status && git log --oneline -3
   ```
2. Simulations must both print PASS:
   ```bash
   ./sim/run_treble.sh 2>&1 | tail -3
   ```
   ```bash
   ./sim/run_enh.sh 2>&1 | tail -5
   ```
   (`run_enh.sh` takes about 6 minutes.)
3. Builds present (rebuild with the commands in `enh_build.md` if anything in `rtl/` or `sw/app/`
   changed since 11 Nov):
   ```bash
   ls -la build/enh/enh_top.bit build/enh/enh_top.xsa build/enh/enh_app.elf
   ```
4. Comparison WAVs for E6:
   ```bash
   .venv/bin/python test_audio/ABXtesting/make_abx_wavs.py
   ```
5. A random A/B sheet for E7 (print it for the helper; the listener must not see it):
   ```bash
   .venv/bin/python -c "import random; print(' '.join(random.choice('AB') for _ in range(16)))" > build/e7_key.txt
   ```

**Pass:** both simulations PASS, the three build files exist, the WAVs are written.

### E1: Board power and JTAG

1. Board off. JP7–JP11 on GND. Cables in J20, J17, J14. Headphones in HPH OUT, **not on your ears**.
2. SW8 on: LD13 lights.
3. `ls /dev/ttyACM*` shows the UART (usually `/dev/ttyACM0`).
4. Set all user switches SW0–SW7 **down**.

**Pass:** LD13 on, serial device present.
**If it fails:** as T1 in `hardware_testing_plan.md`.

### E2: PL bring-up (no MP3 yet)

1. Power-cycle the board (SW8 off, 5 s, on).
2. Program and initialise (no sender running; the app will wait 30 s and then give up, which is fine
   here):
   ```bash
   source ~/Xilinx/Vitis/2020.2/settings64.sh && xsct scripts/run_enh_jtag.tcl 2>&1 | tee -a build/lab_2026-11-12.log
   ```
3. Read the LEDs within a few seconds:

   | LED | Expected |
   |---|---|
   | LD12 (DONE) | on |
   | LD0 `codec_ready` | on |
   | LD1 `codec_error` | **off** |
   | LD2 | blinks 1 s on, 1 s off (48 kHz LRCLK) — time 10 blinks: 20 s ± 1 s |
   | LD5 AXI out of reset | on (PS initialised by the script) |
   | LD3, LD4, LD6, LD7 | off |

4. Tone: SW1 up. LD6 on. Put the headphones on gradually: a 1 kHz square tone in **both** ears,
   equal level. SW1 down: silence (no hiss beyond the codec floor, no clicks).
5. BTND (reset): LD0 goes off briefly and comes back, LD2 keeps blinking. Tone (SW1 up) still works
   after the reset. SW1 down.

**Pass:** the LED table matches, tone in both ears, reset recovers.
**If it fails:**
- LD1 on / LD0 off: power-cycle, run step 2 again once. Still failing: program
  `build/week1_diag/week1_diag_top.bit` (Hardware Manager) and record its LD7..LD3 failing row.
- LD2 not blinking: no codec clocks; compare with the diagnostic build (11 Nov fix 1).
- LD5 off: `ps7_init` did not run. Read the xsct output for errors; check that
  `build/enh_ws/enh_plat/hw/ps7_init.tcl` exists.
- No tone but LEDs right: try `week1_diag_top.bit` SW0 tone. If that works and ours does not, the
  fault is in `enh_core` output path: record and stop.
- Tone in one ear only: swap the headphones; record which ear.

### E3: MP3 receive and decode

1. Terminal 1, start the sender first:
   ```bash
   .venv/bin/python sw/sender/send_mp3.py /dev/ttyACM0 test_audio/beethoven5_ogg_32k.mp3 2>&1 | tee -a build/lab_2026-11-12.log
   ```
2. Terminal 2, within 60 s, restart only the app (does not reprogram the FPGA):
   ```bash
   source ~/Xilinx/Vitis/2020.2/settings64.sh && xsct scripts/run_enh_jtag.tcl app
   ```
3. The sender prints the board's lines. Compare with §1.5.

**Pass:** `rx: 80396 bytes, 0 uart errors`, both fnv values `0xc50fe207`, `frame_count = 836`,
`sample_rate = 48000`, `samples_per_channel = 963072`, `bitrate = 32`, a `real time` line, no `[FAIL]`.
**If it fails:**
- No `**Ready**` (sender says "Hang"): the `app` mode failed (risk 3). Power-cycle, start the sender,
  then run the full script (E2 step 2).
- uart errors or fnv mismatch: re-run once; then try `--baud 115200` on the sender **only if** the
  app is rebuilt for 115,200 (it is fixed at 230,400 in `uart_rx.c`); record and stop.

### E4: Plain playback (SW0 down)

Music starts right after the `real time` line (the sender exits there).

1. SW0 **down** (plain). LD3 on (music arriving). LD4 off.
2. Headphones on gradually. The Beethoven passage plays and repeats every 20 s.
3. Speed check: from the start of one repeat to the start of the next with the phone stopwatch:
   20.1 s ± 0.5 s. (Wrong speed means the sample rate or the FIFO drain is wrong.)
4. Listen to three full repeats for clicks, dropouts, crackle, or one ear only.
5. Serial messages: open a terminal on the UART (the sender has exited):
   ```bash
   .venv/bin/python -m serial.tools.miniterm /dev/ttyACM0 230400
   ```
   Every 20 s: `play: pass N done, overflow flag 0`. Quit miniterm with Ctrl+].
6. Compare with the laptop playing the same file:
   ```bash
   ffplay -nodisp -autoexit test_audio/beethoven5_ogg_32k.mp3
   ```
   Board plain should sound like it: same pitch, no added noise.

**Pass:** plays in both ears, right speed, no dropouts or crackle over 3 repeats, LD3 steady,
overflow flag 0.
**If it fails:**
- LD3 off: ARM is not writing. Check the sender output ended with `real time`, and the serial
  messages (step 5). No `play:` line means the app did not reach `pl_play_loop`.
- LD3 flickers, audio drops out: FIFO underruns. Record how often. (The ARM refills 4,096 samples at
  a time; each refill is about 85 ms of audio.)
- Wrong speed or pitch: record the measured repeat time.
- Crackle: note which ear and whether the 11 Nov `i2s_tx` fix is in the build (it is in `rtl/`).
- Loud noise or full-scale buzz: SW1 down? If yes, stop and record (possible byte/sign error in the
  feeder: samples are written as `int16 × 256` in bits 23:0).

### E5: Live A/B with SW0

1. While it plays, flip SW0 up (enhanced): LD4 on. Then down, then up, a few times.
2. Listen for: more "air"/brightness on cymbal-like and string attacks when SW0 is up; the bass and
   mid must not change. Bright passages make it easiest.
3. Listen for a click at the moment of switching (the filters keep running, so there should be at
   most a small step).
4. LD7 (clipping) should stay off for this file (the model predicted no clipped samples).
5. Repeat with `test_audio/synthetic_32k.mp3` (E3 steps with that file, `app` mode, fnv
   `0x2a443153`): synthetic material with more treble makes the difference easier to hear.

**Pass:** audible, repeatable difference that matches SW0; no artefacts besides added treble; LD7
off.
**If it fails:**
- No audible difference: check LD4 follows SW0, then try the synthetic file. The added treble is
  quiet (about −67 dBFS RMS on the Beethoven passage, from the model), but it sits above the
  7.2 kHz cutoff where the plain MP3 has nothing. Raise the volume a little and listen for
  brightness, not loudness. If still nothing, record "not audible on this headset".
- Harsh/distorted when enhanced: record the passage time; check LD7.
- Loud click when switching: record; the output selection is in `treble_fixed` (S_OUT).

### E6: Board vs model

1. Send `test_audio/ABXtesting/excerpt_01_32k.mp3` (E3 steps, `app` mode, fnv `0x8ee31ad3`).
2. Listen to the board with SW0 down, then up.
3. On the laptop (same headphones if possible), play `excerpt_01_plain.wav` and
   `excerpt_01_enhanced.wav` from `test_audio/ABXtesting/`.

**Pass:** board plain ≈ laptop plain, board enhanced ≈ laptop enhanced (same character of the
added treble). The WAVs are from the float model; the board runs the fixed-point version, which is
81 dB from the float one, so any difference heard is from the playback chain, not the algorithm.
Record a 1–5 similarity score and comments.

### E7: Blind test on the board (if time)

Helper and listener. The listener wears the headphones and does not see the board.

1. Send `excerpt_01_32k.mp3` (or another bright passage) and let it loop.
2. For each of the 16 letters in `build/e7_key.txt`: the helper sets SW0 (A = down/plain,
   B = up/enhanced), flipping SW0 down and up once even when the letter repeats, so the click does
   not give it away. The listener hears at least one full repeat and says "plain" or "enhanced".
3. The helper writes down each answer; score at the end.

**Pass:** 12/16 or more correct (p < 0.05, as in `ABXtesting/README.md`). Record the score, the
headphones and the passage. This is the on-board version of the 11 Nov laptop tests.

### E8: Robustness

1. **Second file without reprogramming:** send `excerpt_01_32k.mp3` again with `app` mode. Pass:
   `**Ready**`, correct fnv, plays.
2. **Reset during playback:** press BTND. The codec reconfigures (LD0 off then on) and music
   resumes within about 1 s (the ARM keeps writing). Record any noise.
3. **ARM stopped:** in a third terminal:
   ```bash
   source ~/Xilinx/Vitis/2020.2/settings64.sh && xsct -eval "connect; targets -set -filter {name =~ \"*A9*#0\"}; stop"
   ```
   Pass: within 0.1 s the music stops, LD3 goes off, silence (no buzz or loop). Then restart with
   `app` mode.
4. **Soak:** let the 20 s file loop for 10 minutes with SW0 up. Pass: no dropouts, overflow flag 0 in
   all `play:` lines, nothing warm on the board beyond normal.

### E10: Recording for the report (optional)

Only with a line-in (USB audio interface). HPH OUT → line in, headphone volume low to avoid
clipping the recorder.

1. Send the Beethoven 32k file. Record 20 s with SW0 down, then 20 s with SW0 up (48 kHz, 16- or
   24-bit WAV), e.g. with `arecord -f S24_3LE -r 48000 -c 2 -d 20 build/board_plain.wav`.
2. Save as `build/board_plain.wav` and `build/board_enhanced.wav`. Afterwards (not in the lab):
   compare their spectra above 7.2 kHz with the model output; the report claim needs measured
   numbers, not "sounds better".

### 2.11 Results sheet

| Test | Result | Value / evidence | Notes |
|---|---|---|---|
| E0 simulations | | `run_treble` / `run_enh` PASS | |
| E1 LD13, serial device | | `/dev/ttyACM_` | |
| E2 LD0 / LD1 / LD5 | | | |
| E2 LD2 10 blinks | | ___ s | |
| E2 tone L / R | | | |
| E2 BTND recovery | | | |
| E3 rx bytes / uart errors | | | |
| E3 fnv board / sender | | `0x________` / `0x________` | expect `0xc50fe207` |
| E3 frames / samples / rate / bitrate | | | expect 836 / 963072 / 48000 / 32 |
| E3 res.checksum (board) | | `0x________` | record only |
| E3 decode time | | ___ ms, x__ real time | |
| E4 plays L / R | | | |
| E4 repeat time | | ___ s | expect 20.1 s |
| E4 dropouts / crackle (3 repeats) | | | |
| E4 overflow flag | | | expect 0 |
| E5 audible difference | | | file, passage |
| E5 switching click | | | |
| E5 LD7 | | | expect off |
| E5 synthetic file | | | |
| E6 similarity plain / enhanced (1–5) | | | |
| E7 score | | __/16 | listener, headphones |
| E8 second file (app mode) | | | |
| E8 BTND during playback | | | |
| E8 ARM stopped → silence | | | |
| E8 10 min soak | | | |
| E10 recordings | | | optional |
| Jumper JP1 position | | | for the record |

### 2.12 Decision gate

| Outcome | Next |
|---|---|
| E2–E5 pass | **Enhancement works on the board.** Freeze `d/goal2` for the demo (PR to `main`), write up E-results in `docs/hardware_results_2026-11-12.md`, and the team continues on ANC. |
| E2–E4 pass, E5 not audible | Playback works; the enhancement needs a gain above 1 or a lower cutoff for this headset. Change `GAIN` in `model/goal2/ref_fixed.py` and the RTL together, regenerate, re-simulate, rebuild. |
| E2 passes, E3–E4 fail | PS/AXI/feeder problem. Debug with the serial messages; an ILA on `enh_core` AXI signals is the next step. |
| E2 fails | Codec path problem: same procedure as 11 Nov with the diagnostic build. |

After the session: commit the log (`build/` is ignored, so copy the relevant lines into the results
file) and fill in `docs/hardware_results_2026-11-12.md`.
