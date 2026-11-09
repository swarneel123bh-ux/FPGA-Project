# Hardware test plan: Wednesday 11 Nov 2026

*Written by Claude as a test guide (not team code). Covers what can be tested on the ZedBoard
this week. Run it on the Ubuntu laptop with Vivado and Vitis 2020.2, using the board in the lab.*

---

## Part 1: Requirements

### 1.1 What this session tests, and what it does not

| Test | Owner | In scope Wed? | Why |
|---|---|---|---|
| T0 Laptop pre-flight | Swarneel | Yes | Tools must launch before anything else |
| T1 Board power and JTAG | Swarneel | Yes | Proves the cables and jumpers |
| T2 Goal-2 MP3 receive and decode (regression) | Swarneel (D) | Yes | Passed in the lab on 5 Nov; re-run on the laptop |
| T3 Week-1 codec bring-up and passthrough | Aarav (A) | Yes | First time this bitstream runs on hardware |
| T4 MP3 played through headphones | D + A | **No** | The MP3 path is not wired to the codec output yet |
| T5 ANC noise reduction | A, B, C | **No** | `mode_fsm`, `out_mux`, `top.v` and the ANC blocks are not on hardware |
| T6 Treble restoration | D | **No** | Not started (`treble_fixed` does not exist) |

Only T0–T3 are pass/fail on Wednesday. T4–T6 are listed so nobody expects them.

### 1.2 Hardware

| Item | Detail | Check |
|---|---|---|
| ZedBoard (Zynq-7020) | Rev noted on the board silkscreen | Green LD13 lights when powered |
| 12 V power adapter | Into J20 | |
| Micro-USB cable ×2 | Cable 1 → J17 "PROG" (JTAG, Vivado and Vitis). Cable 2 → J14 "UART" (MP3 sender) | Both plug into the laptop |
| Boot-mode jumpers | JP7–JP11 all on **GND** (JTAG boot) | See `lab_run_windows.md` §4.2 |
| JP1 (electret bias) | Documented as "Right channel only" | Note its position on the day |
| Two electret microphones | One on the right-channel mic input (pink jack, bias from JP1). Second mic: bias is still an **open issue** (HANDOFF §9 item 2) | Record which channel gets bias |
| Headphones | Over-ear, 3.5 mm into the black headphone jack | |
| Phone with a tone app | Plays a 1 kHz test tone | |
| Optional: oscilloscope or logic analyser | Measures BCLK, LRCLK, MCLK | Without it, use the ILA in T3 |
| Optional: USB-UART in the Vivado ILA | For codec status | |

### 1.3 Laptop software (Ubuntu)

| Item | Version | Check |
|---|---|---|
| Ubuntu | 20.04 is the documented host for 2020.2; this laptop runs 24.04 | See T0 |
| Vivado | 2020.2, Zynq-7000 device support installed | `vivado -version` |
| Vitis IDE | 2020.2 | `vitis` opens |
| Cable driver for JTAG | Installed from the Vivado/Vitis install tree | T1 |
| gcc | any recent version | `gcc --version` |
| Python 3 | 3.8 or newer | `python3 --version` |
| pyserial and imageio-ffmpeg | from `sw/sender/requirements.txt` | `python3 -c "import serial"` |
| Repository | `main` at commit `2f5a9d3` or later | `git log -1` |

### 1.4 Files needed

| File | Where | Used in |
|---|---|---|
| `test_audio/beethoven5_20s_48k_mono_56k.mp3` | repository | T2 |
| `test_audio/beethoven5_20s_48k_mono_128k.mp3` | repository | T2 (optional) |
| `sw/app/*` (six files) | repository | T2 |
| `sw/sender/send_mp3.py` | repository | T2 |
| `rtl/week1_passthrough_top.v`, `rtl/codec_cfg.v`, `rtl/adau_i2c_write.v`, `rtl/i2s_rx.v`, `rtl/i2s_tx.v`, `rtl/mclk_out.v` | repository | T3 |
| `constraints/zedboard_week1.xdc` | repository | T3 |
| `zed.xsa` | `$XILINX_VITIS/data/embeddedsw/lib/fixed_hwplatforms/zed.xsa` (Vitis install) | T2 |

### 1.5 Reference numbers for T2

Taken from `test_audio/README.md` and `lab_run_windows.md` §2. The board must print these for
the 56 kbit/s file:

| Line | Expected |
|---|---|
| `fnv1a` (sender) and `rx:` fnv | `0x6bbdb72d` (both) |
| `res.channel_count` | `1` |
| `res.frame_count` | `836` |
| `res.sample_rate` | `48000` |
| `res.samples_per_channel` | `963072` |
| `res.checksum` | `0xb5f37fd1` |
| `uart errors` | `0` |

### 1.6 Known risks, read before the session

1. **Ubuntu 24.04 is not an officially supported host for Vivado/Vitis 2020.2.** The documented
   Ubuntu host for 2020.2 is 20.04. Running on 24.04 needs workarounds: the libtinfo5 and ncurses5
   compatibility libraries (`sudo apt install libtinfo5 libncurses5` may not find them on 24.04; the
   packages may have to be installed from an older archive), and possibly a Java GUI library
   (`libswt-gtk-4-java`) for Vitis to start. Sources: [AMD UG1393 2020.2 install guide](https://docs.amd.com/r/2020.2-English/ug1393-vitis-application-acceleration/Installing-the-Vitis-Software-Platform),
   [NetFPGA 2020.x on Ubuntu wiki](https://github.com/NetFPGA/NetFPGA-SUME-public/wiki/Installation-of-Vivado-Vitis-2020.1-and-2020.2-on-Ubuntu-2020.4-LTS).
   These workarounds are unofficial and unverified on this laptop. If T0 fails and cannot be fixed in
   about 30 minutes, use the fallback in §1.7.
2. **Vitis "Launch Hardware" may reprogram the FPGA.** Run T2 (ARM-only) before T3 (bitstream), and
   re-check T3 after any Vitis launch.
3. **The mic bias on the second microphone is unresolved.** JP1 biases the right channel only. A
   silent left channel is a known result, not a code failure. Record it as "blocked by bias".
4. **The week-1 top has no pin constraints for `codec_ready`, `codec_error` or `sample_tick`.** You
   will read them with the ILA (T3c), not with LEDs, unless A adds LED constraints first.
5. **No timing constraints are set on the audio pins** (the `.xdc` says so). The build may report
   unconstrained-I/O warnings. These are expected; record them.
6. **Codec clocks:** `codec_cfg` sets the codec PLL to 24 MHz in → 49.152 MHz, 1024×fs, 48 kHz base
   rate, codec as I2S master. Expect BCLK = 3.072 MHz and LRCLK = 48 kHz. If LRCLK is off, the
   passthrough test will fail (see T3d).

### 1.7 Fallback if the laptop cannot run Vitis

Run T0 and T1 with Vivado only, and T3 entirely in Vivado (bitstream and Hardware Manager). T2 is
not possible without Vitis; for T2 use the lab PC route described in `lab_run_windows.md` §10
(SD card, built on the laptop) or §11 (QSPI flash). Record the route used.

---

## Part 2: Execution steps

Work in order. Fill in the results sheet (§2.5) as you go. Stop at the first failure in a test and
go to its "If it fails" line.

### T0: Laptop pre-flight (about 20 min)

1. Open a terminal:
   ```bash
   cat /etc/os-release | head -2
   ```
   Note the Ubuntu version.
2. Check the tools open:
   ```bash
   source /tools/Xilinx/Vivado/2020.2/settings64.sh
   vivado -version
   ```
   Then:
   ```bash
   source /tools/Xilinx/Vitis/2020.2/settings64.sh
   xsct -version
   ```
   (If your install path is different, use the path where `settings64.sh` is.)
3. Start the Vitis IDE (`vitis &`) and close it again. The window must open and show a workspace
   chooser. The message "libtinfo.so.5: cannot open shared object file" means §1.6 item 1 applies.
4. Install the JTAG cable driver once (needs sudo):
   ```bash
   cd /tools/Xilinx/Vivado/2020.2/data/xicom/cable_drivers/lin64/install_script/install_drivers
   sudo ./install_drivers
   ```
   Unplug and replug cable 1 (J17) after this.
5. Give yourself serial access (once, then log out and back in):
   ```bash
   sudo usermod -aG dialout "$USER"
   ```
6. Clone or update the repository:
   ```bash
   cd ~ && git clone https://github.com/swarneel123bh-ux/FPGA-Project.git || (cd FPGA-Project && git pull)
   cd ~/FPGA-Project && git checkout main && git pull && git log --oneline -1
   ```
7. Install the Python packages:
   ```bash
   python3 -m venv .venv && . .venv/bin/activate
   pip install -r sw/sender/requirements.txt
   ```

**Pass:** Vivado and Vitis both open; `xsct` runs; the driver installed without error; the repo is at
`main` with `2f5a9d3` or later; `import serial` works in the venv.

**Fail / if it fails:**
- Tools do not launch: check §1.6 item 1. Use the fallback (§1.7) or stop and tell the team.
- Driver install fails: check you ran it from `install_drivers` with sudo.

---

### T1: Board power and JTAG (about 10 min)

1. Power off. Set JP7, JP8, JP9, JP10 and JP11 all to **GND** (`lab_run_windows.md` §4.2).
2. Plug the 12 V adapter into J20. Plug cable 1 into J17 and cable 2 into J14. Plug both into the
   laptop.
3. Switch SW8 on. LD13 (green) must light.
4. Check the serial port appears:
   ```bash
   ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
   ```
   Note the device name (usually `/dev/ttyACM0`).
5. Open Vivado's Hardware Manager (`vivado &` → **Open Hardware Manager** → **Open Target** →
   **Auto Connect**).

**Pass:** LD13 is on; one serial device appears (for example `/dev/ttyACM0`); Vivado's Hardware
Manager lists the target with an `xc7z020` device.

**Fail / if it fails:**
- LD13 off: check the adapter and SW8.
- No serial device: reseat cable 2 in J14 and check `dmesg | tail` for the device name.
- Hardware Manager finds no target: reseat cable 1 in J17, check the jumpers, power-cycle the board,
  re-run the driver install (T0 step 4).

---

### T2: Goal-2 MP3 receive and decode (regression, about 20 min)

This is the goal-2 test from `lab_run_windows.md` §7–8, run on the laptop. It passed in the lab on
5 Nov. Run it first, before any bitstream is loaded.

1. Build the reference decoder on the laptop (for a fresh check):
   ```bash
   cd ~/FPGA-Project && mkdir -p build
   gcc -O2 -o build/decode_pc sw/app/main_host.c sw/app/decode.c -lm
   build/decode_pc test_audio/beethoven5_20s_48k_mono_56k.mp3 build/test_56k.raw
   ```
   Confirm the output matches the table in §1.5.
2. Build the ARM program in Vitis (`lab_run_windows.md` §6, Linux version):
   - `vitis &`, new workspace, e.g. `~/zed_ws`.
   - **File → New → Application Project**, platform from **zed.xsa**, name `goal2_app`,
     **standalone** on **ps7_cortexa9_0**, template **Empty Application (C)**.
   - Import the six files of `sw/app` into `src` (copies).
   - Symbols: add `BOARD`.
   - Libraries: add `m` (linker → Libraries).
   - `src/lscript.ld`: stack size `0x10000`.
   - **Build Project.** The console must end with `Finished building: goal2_app.elf`.
3. Start the sender first (replace the device if different):
   ```bash
   cd ~/FPGA-Project && . .venv/bin/activate
   python3 sw/sender/send_mp3.py /dev/ttyACM0 test_audio/beethoven5_20s_48k_mono_56k.mp3
   ```
   It waits up to 60 s for `**Ready**`. Do not open any other program on the serial port.
4. Within 60 s, in Vitis: right-click **goal2_app → Run As → Launch Hardware (Single Application
   Debug)**.
5. Read the sender terminal. Expect `sending 140516 bytes, fnv 0x6bbdb72d`, then the `rx:` line
   and the `res.*` lines, then `decode ... real time`.
6. Record the values in §2.5.

**Pass (all must hold):**
- `rx:` shows `0 uart errors`.
- Both fnv values on the `rx:` line are `0x6bbdb72d`.
- `res.channel_count = 1`, `res.frame_count = 836`, `res.sample_rate = 48000`,
  `res.samples_per_channel = 963072`, `res.checksum = 0xb5f37fd1`.
- The last line contains `real time` and there is no `[FAIL]`.

**Partial:** every value matches except `res.checksum`. The transfer is correct; record both
checksums and report it. Do not re-run as a fix.

**Fail / if it fails:**
- `Hang: Never got **Ready**`: start the sender first, check the device name, re-launch.
- `could not open port`: another program has the port open (close it). Or run
  `sudo chmod a+rw /dev/ttyACM0` for this session only if `dialout` did not work.
- `[FAIL] checksum mismatch`, `uart errors` above 0, `payload timeout`: run once more. If it
  repeats, record the output and stop this test.
- Output stops after the `rx:` line: stack too small. Check the `lscript.ld` value and rebuild.
- Build error about `sqrt`/`pow`: the `m` library is not linked (step 2).

---

### T3: Week-1 codec bring-up and passthrough (about 90 min)

This tests Aarav's codec interface: I2C configuration, I2S clocks, and mic-to-headphone passthrough.
It is the first time this bitstream runs on the board. Run T2 before this test (see §1.6 item 2).

#### T3a: Build the bitstream in Vivado

1. `vivado &` → **Create Project** → RTL project, part **xc7z020clg484-1**, no sources yet.
2. **IP Catalog → Clocking Wizard**. Component name **`clk_wiz_0`**. Input **100 MHz**
   (`clk_in1`). Output **clk_out1 = 24 MHz**. Reset **active high**. Locked output enabled.
   Generate the IP.
3. Add sources: `rtl/week1_passthrough_top.v`, `rtl/mclk_out.v`, `rtl/codec_cfg.v`,
   `rtl/adau_i2c_write.v`, `rtl/i2s_rx.v`, `rtl/i2s_tx.v`. Set **`week1_passthrough_top`** as the top.
4. Add constraints: `constraints/zedboard_week1.xdc`.
5. **Run Synthesis**, then **Run Implementation**, then **Generate Bitstream**.
6. Open the implemented design and check **Timing Summary**.

**Pass:** no errors; a bitstream file is written (`week1_passthrough_top.bit`); WNS is reported
(record the value). Unconstrained-I/O warnings on the audio pins are expected (§1.6 item 5).

**Fail / if it fails:**
- `module not found` for `clk_wiz_0`: step 2 was not done or the IP was not generated.
- Port mismatch errors: note the message; this is a code issue for Aarav, not a test issue. Stop and
  tell the team.

#### T3b: Program the FPGA and check DONE

1. In the Hardware Manager (connected as in T1), **Program Device**. Select the `.bit` file.
2. Watch LD12 (blue DONE).

**Pass:** programming completes; LD12 (DONE) lights. This is different from the lab guide, which says
DONE stays off: that was true only with no PL design.

**Fail / if it fails:** programming error: power-cycle the board and retry. DONE stays off after a
successful program: stop and record the message.

#### T3c: I2C configuration (codec_ready and codec_error)

The top module has no LED pins for `codec_ready` and `codec_error`. Use the ILA:

1. In Vivado, mark `codec_ready`, `codec_error` and `sample_tick` for debug (Netlist → mark debug) on
   the synthesized design, or insert an ILA with these three probes. Re-run implementation and generate
   the bitstream. Program the device again.
2. In the ILA: set the trigger to capture from reset release. Look at `codec_ready` and `codec_error`
   for about 200 ms after reset.

**Pass:** `codec_ready` goes high within about 100 ms of reset release; `codec_error` stays low.

**Fail / if it fails:**
- `codec_error` high: the codec did not ACK an I2C write. Check the address (`0x38`, pins ADDR0 and
  ADDR1 both low), the SCL/SDA pins and the power to the codec. Record the step (ILA shows the
  register index). Stop and tell A.
- `codec_ready` never goes high: check `sys_rst` and `clk_locked` (the clock wizard lock).

#### T3d: Clocks (BCLK, LRCLK, MCLK)

Measure on the ZedBoard's audio pins (scope or logic analyser). If there is no scope, read
`sample_tick` on the ILA and count its period.

**Pass:**
- MCLK: 24 MHz (from `mclk_out`).
- LRCLK: 48 kHz, ±0.5 %.
- BCLK: 3.072 MHz (64 BCLK per frame).
- `sample_tick`: one pulse per LRCLK frame (48 kHz).

**Fail / if it fails:** LRCLK absent or not 48 kHz: the codec PLL or base-rate register is wrong. Record
the measured frequency and tell A (`codec_cfg` ROM rows 2 and 17).

#### T3e: Passthrough, both microphones

1. Connect headphones to the black jack.
2. Plug the **right** mic into the pink mic jack. Plug a second mic into the **blue** line-in jack,
   or leave it out and record that. JP1 biases the right channel only.
3. Play a 1 kHz tone from the phone, close to the **right** mic. Listen in the right ear.
4. Repeat with the tone near the **left** mic, if one is connected. Listen in the left ear.
5. Turn the tone up until it is loud but not distorted. Note the level at which distortion starts.
6. Check that left and right are not swapped (tone at the right mic must be heard in the right ear).

**Pass (all must hold):**
- The tone is heard in the correct ear at every level tested, with no clicks, dropouts or distortion.
- Left and right are not swapped.
- With both mics biased (if the bias is solved), both channels are heard at the same time.

**Known result (not a failure of the code):** with only the right channel biased, the left channel is
silent. Record it as **"blocked by bias"**.

**Fail / if it fails:**
- No sound at all on the right channel: check the headphone jack, the DAC power and that I2S is
  running (T3d). Record the ILA state.
- Sound in the wrong ear: the L/R wiring in `week1_passthrough_top` or `i2s_tx`. Stop and tell A.
- Constant hiss or clipping at low levels: note the level. This is a measurement for A and B, not a
  pass or fail on Wednesday.

---

### T4–T6: not tested on Wednesday

Do not run or expect these. Record "not tested: out of scope" in §2.5.

---

## Part 2.5: Results sheet

Fill in on the day. Copy this table into `lab_checklist_2026-11-05.md` afterwards if the team wants it
there.

| Test | Result (PASS / FAIL / BLOCKED) | Value or evidence | Notes |
|---|---|---|---|
| T0 Ubuntu version | | | |
| T0 Vivado and Vitis open | | | |
| T1 LD13 on; serial device | | device name: | |
| T1 Hardware Manager target | | | |
| T2 `uart errors` | | | |
| T2 fnv `rx:` (both) | | | |
| T2 `res.frame_count` / `samples_per_channel` | | | |
| T2 `res.sample_rate` / `channel_count` | | | |
| T2 `res.checksum` | | expected `0xb5f37fd1`, got: | |
| T2 `real time` factor | | | |
| T3a bitstream written; WNS | | WNS: | |
| T3b LD12 (DONE) lit | | | |
| T3c `codec_ready` high | | time to ready: | |
| T3c `codec_error` low | | | |
| T3d MCLK 24 MHz | | measured: | |
| T3d LRCLK 48 kHz | | measured: | |
| T3d BCLK 3.072 MHz | | measured: | |
| T3e right mic → right ear | | | |
| T3e left mic → left ear | | | (BLOCKED if no bias) |
| T3e no swap; no clipping | | clipping level: | |
| JP1 position on the day | | | |
| T4, T5, T6 | not tested | | out of scope |

---

## Part 3: After the session

1. Put the results sheet in the repository (for example `docs/hardware_results_2026-11-11.md`, on a
   branch, not on `main`) and update HANDOFF §1 with the outcome of T2 and T3 (via `handoff_mgr.py`).
2. Tell Aarav the T3 results (codec_ready, LRCLK, passthrough) before the 12 Nov freeze.
3. Tell Aadyant and Samarth whether MCLK/clock and the ADC path work, since their week-2 blocks depend
   on them.
4. If T2 passed again, note it in the report: this is the second independent run.
