# HANDOFF — EEE F314 FPGA-Based Audio Enhancement System (ZedBoard)
<!-- id: doc -->

*Rev 10 — patched 09 Nov 2026, 21:03 IST*

Paste this at the start of a new chat to resume the project; it is self-contained.

---

## 1. Status
<!-- id: s1 -->
STATUS: IN_PROGRESS
UPDATED: 2026-11-09
NOTE: Goal 2 target is 32 kbit/s at 48 kHz (cutoff 7.2 kHz); decoder reports the bitrate; float reference model in model/goal2/ref.py; ABX listening set ready but not yet run; hardware session 11 Nov pending. Goal 1 (Vivado build and audio-path hardware validation) still pending.

### Where we are
<!-- id: s1.where -->
| Area | Status | Note |
|---|---|---|
| Scope and architecture | COMPLETED | ANC is goal 1, MP3 enhancement is goal 2; see §8 and §14 |
| Instructor confirmation that "active" ANC is meant | OPEN | §9 item 1 |
| Work plan document (4 marks) | COMPLETED | Group-no-16-Work-Plan.pdf built 19 Oct (3 A4 pages); submission assumed, confirm |
| Repository | COMPLETED | github.com/swarneel123bh-ux/FPGA-Project; main has Aarav's week-1 codec/I2S code (6 Nov); goal-2 work is on branch d/goal2 (commit 580316a, 9 Nov); HANDOFF.md is untracked |
| ANC golden model (FxLMS with modelled acoustic paths) | COMPLETED | B; existing model and simulation artifacts were validated before the 6 Nov integration |
| Codec bring-up: two mic inputs and headphone output | IN_PROGRESS | A's I2C/I2S scaffold and three supplied simulations pass; Vivado build and hardware validation are pending |
| ANC RTL: path identification, FxLMS, FSM, measurement | IN_PROGRESS | Existing B/C blocks are validated; shared FSM, output mux, top-level integration and hardware ANC remain |
| Goal 2: UART receive, ARM MP3 decoding, PL FIFO | COMPLETED | D; end-to-end lab validation passed 5 Nov |
| Goal 2: bitrate and cutoff | COMPLETED | Decoder reports the bitrate; 32 kbit/s cutoff 7.2 kHz (40 dB rule); table in test_audio/beethoven5_ogg_knee_table.md; §8 decisions 21–23 |
| Goal 2: enhancement reference model | IN_PROGRESS | model/goal2/ref.py runs on the 32k decode (float); fixed point and testbench not started; GAIN = 1 not yet chosen (§9 item 27) |
| Goal 2: ABX listening test | NOT_STARTED | 16 passages in test_audio/ABXtesting; needs a good headset (§9 item 25) |
| Goal 2: FIFO path to the board | NOT_STARTED | Vivado block design with the PS and music_fifo_axi, then the ARM feeder (§9 item 26) |
| Goal 2: treble RTL (treble_fixed) | NOT_STARTED | Only after the model and the ABX result show a gain |
| Smart-guess float prototype | COMPLETED | Claude's scaffolding, not team code; §5.4 |
| Report, demo, code ZIP | NOT_STARTED | §2.2 |
| Extra goals | NOT_STARTED | §13 |
### Immediate next steps
<!-- id: s1.next -->
1. Hardware session on Wednesday 11 Nov: docs/hardware_testing_plan.md, starting with T0 (laptop pre-flight). Work on the Ubuntu laptop from branch d/goal2 (§9 item 28).
2. Run the ABX listening test (test_audio/ABXtesting/abx.py) with a good headset and record the score (§9 item 25).
3. Confirm the 32 kbit/s cutoff on a second clip before relying on 7.2 kHz (§9 item 24).
4. Choose the enhancement gain from measurement and listening, not from the ANC gains (§9 item 27).
5. Build the FIFO path: Vivado block design with the PS and music_fifo_axi, then the ARM feeder (§9 item 26).
6. Make the enhancement model fixed point and write its testbench, only if the ABX result or the measurements show a gain.
7. Goal 1 continues in parallel: Aarav's codec passthrough, mode FSM and top level, then the ANC blocks.
8. Ask the instructor to confirm the active-ANC interpretation and book the demo slot (§9 items 1 and 16).
## 2. Course constraints
<!-- id: s2 -->

### Requirements
<!-- id: s2.requirements -->

1. Course: EEE F314 FPGA-Based System Design, BITS Pilani Hyderabad. Project #20 from the instructor list, pre-assigned: "FPGA-Based Audio Enhancement System: Design a system to improve audio quality using techniques such as noise cancellation, digital filtering, and enhancement of decoded compressed audio."
2. Group 16, lab section P2, 4 members. Two-hour scheduled lab sessions plus practice sessions in I-124 and J-105.
3. Mandatory framework: Input / PMOD peripherals → FPGA interface → Processing → FSM-based decision/control → Display, communication or actuator output.
4. Must be implemented on a ZedBoard, verified in simulation, and demonstrated on hardware.
5. Onboard interfaces (Ethernet, USB, HDMI, VGA, Audio, SD) are allowed alongside lab PMODs (list includes ALS, OLED, BT2, ESP32, AD1, DA2, among others).
6. A project may not consist only of another list title (for example #18 Digital Filter, #19 FFT Spectrum Analyzer); such work may be reused as sub-blocks.
7. Instructor direction (relayed by a teammate, 16 Oct): noise cancellation is the main expectation, "even if far from perfect"; upscaling is welcome as a second feature; "the kit should be able to support two mics".

### Deadlines
<!-- id: s2.deadlines -->

| Item | Deadline |
|---|---|
| Title selection and work plan | 19 Oct 2026 (done, see §10.1) |
| Final report | On or before 14 Nov 2026 (Sat), before the demo |
| Presentation and hardware demo | 17–26 Nov 2026 |
| Source code ZIP | 27 Nov 2026 (Fri) |

### Marks
<!-- id: s2.marks -->

| Component | Marks |
|---|---|
| Work plan | 4 |
| Functional verification through simulation | 3 |
| Source code submission | 3 |
| Hardware implementation and demo | 4 |
| Final report | 3 |
| Presentation and viva (every member must know every block) | 3 |
| Total | 20 |

---

## 3. Goal and scope
<!-- id: s3 -->

### Goal
<!-- id: s3.goal -->

Two goals, in priority order.

1. Goal 1, active noise cancellation: cancel controlled low-frequency periodic noise (about 100–500 Hz, such as a hum or a fan tone) at one point inside an over-ear headphone cup by playing anti-noise through the headphone driver. Feedforward FxLMS in the PL with a reference microphone and an error microphone; design in §14.
2. Goal 2, enhancement of decoded compressed audio (best-effort): a low-bitrate MP3 is sent over the PS USB-UART, decoded on the ARM and streamed to the PL, which regenerates the treble removed by the encoder (fixed-rule extension first, smart guess as the full target; §5). Use case: tiny files played back sounding closer to uncompressed.

### In scope
<!-- id: s3.in -->

1. Goal 1: two-microphone feedforward FxLMS ANC in PL RTL; secondary-path identification with an internal LFSR white-noise generator; ANC states in the mode FSM with divergence protection; noise reduction in dB on the Pmod OLED.
2. Goal 2: MP3 bytes over the PS USB-UART at 230,400 baud; bare-metal ARM decoding into a PL FIFO; cutoff detection and treble restoration in the PL.
3. Shared: ADAU1761 interface (I2C configuration, I2S input and output), mode FSM, output multiplexer, switches, buttons, LEDs and OLED.
4. Mono processing; stereo and other extensions are extra goals (§13).

### Out of scope
<!-- id: s3.out -->

1. Cancelling broadband, room-wide or uncontrolled room noise (quiet-zone size and converter delay, §14).
2. Adaptive noise cancellation of a recorded signal (the two-input Widrow canceller, which produces no anti-noise), unless the instructor's answer to §9 item 1 says that is what she meant.
3. Neural or generative models.
4. MP3 decoding in PL RTL (the ARM decodes instead).
5. Repairing MP3 codec artifacts below the cutoff (spectral holes, "swirly" sounds, pre-echo).
6. Generating content above 20 kHz.
7. The EQ stage (moved to extra goals, decision 18).

### What we may and may not claim
<!-- id: s3.claims -->

1. Lost detail cannot be recovered by any algorithm: two masters that differ only above the cutoff compress to identical files. The board generates plausible treble, not the original.
2. Goal 2: claim measurable improvement over the plain decoded MP3 (log-spectral distance to the master, plus a blind listening test).
3. Never claim matching or beating the master. Sounding "better than the master" means overshoot (an exciter effect), not restoration.
4. ANC: claim the measured reduction in dB at the error microphone for the tested periodic noise, ANC off versus on. Never claim room-wide or broadband cancellation, or "silence"; cancellation is local (§14).

---

## 4. Goal 2 architecture
<!-- id: s4 -->

This section describes the goal 2 data path (compressed-audio enhancement). Goal 1 (ANC) is in §14. Both goals share the ADAU1761 interface, the mode FSM and the output multiplexer; the codec runs at 48 kHz in every mode (decision 19).

### Data flow
<!-- id: s4.flow -->

```
Laptop: MP3 file (compressed bytes, unchanged)
   │  PS USB-UART, 230,400 baud (CY7C64225 → UART1)
   ▼
ZedBoard PS (ARM, bare-metal, Vitis 2020.x):
   UART RX interrupt → DDR ring buffer → MP3 decoder → 44.1 → 48 kHz (open, §9) → PL FIFO
   │  AXI
   ▼
ZedBoard PL: FIFO (drained at 48 kHz) → cutoff detector → treble restoration
             → output mux (shared with ANC, §14) → I2S → ADAU1761 → headphones
             Mode FSM ← switches/buttons;  status → LEDs / OLED
```

### PS role
<!-- id: s4.ps -->

1. Receive: UART RX must be interrupt-driven (or DMA) into a DDR ring buffer. The UART's hardware receive FIFO is small (size to verify), and at 23,040 bytes/s it fills within milliseconds.
2. Decode: a bare-metal MP3 decoder library (choice OPEN; web-verify first, §9). The ARM decodes MP3 in real time with ample margin.
3. Sample rate: the codec runs at 48 kHz for ANC (decision 19), so 44.1 kHz MP3 output is either resampled to 48 kHz on the ARM or the codec is reconfigured in music mode (OPEN, §9 item 10). No enhancement DSP on the ARM.
4. Feed: push decoded PCM into the PL FIFO over AXI; the PL drains it at the codec rate. The DDR buffer always runs ahead, because the link delivers 23,040 bytes/s and a 56 kbps file needs only 7,000 (§4.5), so no flow control is needed.
5. A whole file also fits in DDR: a 3-minute 56 kbps MP3 is 7,000 × 180 = 1,260,000 bytes ≈ 1.26 MB, out of 512 MB.

### PL blocks
<!-- id: s4.pl -->

| Block | Function | Notes |
|---|---|---|
| AXI FIFO / ring buffer | Decouple ARM writes from the 48 kHz codec clock | Underrun → mute state in the FSM |
| Codec I2C config FSM | Configure the ADAU1761 at start-up: both ADC channels (ANC microphones) and the headphone DAC | Shared with goal 1; register sequence open (§9) |
| I2S RX/TX | Two input channels (reference and error microphone); output to the headphones | 48 kHz; shared with goal 1 |
| Cutoff detector | Find where content stops (candidate set, slow update) | §5.2 step 1 |
| Band energy + log2 | Per-5 ms band levels in dB | Leading-zero count + small LUT; also reusable for the ANC dB meter |
| Slope predictor | Level and slope from 4 bands below cutoff; predict 8 bands above | 4-tap dot product + 8 multiply-adds; 8 offsets in ROM |
| Copy-up | Cosine (NCO) modulation of the top octave into the treble range | 2–3 patches depending on cutoff |
| 8-band gain stage | Shape generated treble to predicted levels | Gains interpolated across each frame, capped +40 dB |
| Fixed-rule extension | Stage-1 treble generator: rectifier harmonics plus envelope-shaped noise at a fixed gain | Fallback if the smart guess is not finished (§5) |
| Output mux | Selects anti-noise (goal 1), enhanced music (goal 2) or silence | Driven by the mode FSM |
| Mode FSM | ANC states and music mode (§14); underrun handling | Satisfies the FSM requirement |

### Control and user I/O
<!-- id: s4.fsm -->

1. Goal 2 proof of on-board processing, two ways: the link carries at most 23,040 bytes/s while the board outputs 192,000 bytes/s, about 8.3× more than could come down the wire (§4.5); and an A/B switch changes the sound live.
2. Goal 1: ANC on/off switch; measured noise reduction in dB on the OLED.
3. Switches and buttons: mode selection (ANC, music, bypass) and recalibration.
4. LEDs or OLED: mode, measured noise reduction, detected cutoff frequency, FIFO level / underrun flag.

### Link budget
<!-- id: s4.budget -->

| Quantity | Arithmetic | Result |
|---|---|---|
| MP3 at 56 kbps | 56,000 ÷ 8 | 7,000 bytes/s |
| MP3 at 128 kbps | 128,000 ÷ 8 | 16,000 bytes/s |
| MP3 at 320 kbps (does not fit; Ethernet extra goal, §13) | 320,000 ÷ 8 | 40,000 bytes/s |
| PS USB-UART at 230,400 baud (10 wire bits per byte) | 230,400 ÷ 10 | 23,040 bytes/s |
| Headroom, 56 kbps | 23,040 ÷ 7,000 | ≈ 3.3× |
| Headroom, 128 kbps | 23,040 ÷ 16,000 | 1.44× |
| Fallback at 115,200 baud, 56 kbps | 11,520 ÷ 7,000 | ≈ 1.65× |
| Decoded output, 48 kHz 16-bit stereo | 48,000 × 2 × 2 | 192,000 bytes/s |
| Decoded output, 44.1 kHz 16-bit stereo | 44,100 × 2 × 2 | 176,400 bytes/s |
| Output vs link capacity (proof), 48 kHz | 192,000 ÷ 23,040 | ≈ 8.3× |
| Output vs link capacity (proof), 44.1 kHz | 176,400 ÷ 23,040 | ≈ 7.7× |

### Compute budget
<!-- id: s4.compute -->

1. At a 100 MHz PL clock and 48 kHz output: 100,000,000 ÷ 48,000 ≈ 2,083 clock cycles per output sample.
2. The goal 2 chain is a few hundred multiply-accumulates per sample per channel, so it fits easily, even on time-shared multipliers. The Zynq-7020 has 220 DSP slices.
3. ANC adds about 256 multiply-accumulates per sample with a 64-tap control filter and a 128-tap path model (§14); the combined load stays far below 2,083 cycles per sample.

---

## 5. Goal 2 enhancement algorithm: the smart guess
<!-- id: s5 -->

Goal 2 enhancement is staged. Stage 1 is the fixed-rule extension (rectifier harmonics plus envelope-shaped noise at a fixed gain; the "fixed-rule guess" in §5.4) as a guaranteed fallback. Stage 2 is the smart guess below, the full target. Stage 1 alone makes soft, tonal music worse than the plain MP3 in the prototype (§5.4), so it is a fallback, not the goal.

### Principle
<!-- id: s5.principle -->

Every 5 ms, measure how fast the sound gets quieter just below the MP3 cutoff, continue that slope above the cutoff, and add a per-band extra roll-off learned offline from other songs. Treble texture is copied up from the octave below the cutoff and scaled to the predicted levels. No master is needed at playback.

### Steps
<!-- id: s5.steps -->

1. Cutoff detection: the highest frequency whose long-term level is within 50 dB of the median 1–4 kHz level; fc = floor(0.97 × f ÷ 250) × 250 Hz.
2. Low bands: 10 geometrically spaced bands from 200 Hz to fc. The slope uses bands 5, 6, 7 and 8 (0-indexed), skipping the topmost band, which MP3 leaves full of holes.
3. Per 5 ms frame (240 samples at 48 kHz): band level in dB. Fit a straight line (level and slope in dB per octave) against the log2 centre frequencies of the 4 bands. Clamp the slope to −30…+10 dB per octave.
4. High bands: 8 geometrically spaced bands from fc to 20 kHz. Predicted level of band b = level + (log2 centre of b − mean log2 centre of the 4) × slope + offset of b.
5. Offsets: the median of (true level − slope-only prediction) over the training songs. 8 numbers in ROM.
6. Smoothing: one-pole across frames per band, coefficient 0.6.
7. Copy-up: source = bandpass [fc/2, 0.98 fc]. For patch k = 1, 2, …: multiply the source by 2·cos(2π · k · fc/2 · t) and bandpass to [fc/2 + k·fc/2, fc + k·fc/2] limited to [fc, 20 kHz]. Sum the patches and add a small noise floor.
8. Gain: split the generated treble into the 8 high bands. Per frame, gain = predicted − measured level (dB), capped at +40 dB, interpolated linearly across samples. Sum and add to the input.

### Hardware mapping
<!-- id: s5.hw -->

1. Band levels in dB: energy accumulators per band, then log2 via leading-zero count plus a small lookup table.
2. Slope: the band centres are equally spaced in log2, so the slope is a fixed-weight 4-tap dot product scaled by one constant per detected cutoff.
3. Prediction: 8 multiply-adds per frame. Offsets in ROM (8 values).
4. Copy-up: an NCO (cosine table) and one multiplier per patch, plus bandpass filters.
5. Filter orders and fixed-point word lengths are still open (§9). The prototype used order-6 Butterworth designs in floating point.

### Prototype results
<!-- id: s5.results -->

Setup: a 56 kbps MP3 (LAME via libsndfile) of each test clip, mono, 48 kHz, loudness-matched. The offsets were learned from 7 *other* clips (leave-one-out). Metric: log-spectral distance to the master above the cutoff, in dB, lower is better.

| Version | Vibe Ace (bright) | Sugar Plum Fairy (soft, tonal) | Average |
|---|---|---|---|
| Plain decoded MP3 | 20.6 | 16.6 | 18.6 |
| Fixed-rule guess | 9.7 | 19.7 | 14.7 |
| Smart guess (chosen) | 11.4 | 12.3 | 11.85 |
| True envelope (needs the master, impossible in use) | 8.6 | 10.4 | 9.5 |

1. The smart guess recovers (18.6 − 11.85) ÷ (18.6 − 9.5) = 6.75 ÷ 9.1 ≈ 74% of the achievable gap.
2. The fixed rule makes soft music worse than the MP3 itself (19.7 vs 16.6). The smart guess is never badly wrong.
3. The first attempt (an 88-coefficient linear regression from 10 low bands to 8 high bands) did not generalise from 6 songs, so it was replaced.
4. These numbers come from Claude's scaffolding, not team code; they were deliberately left out of the work plan.

### Known weaknesses
<!-- id: s5.weak -->

1. MP3 spectral holes below the cutoff stay, and copy-up even copies them upward, causing slight warbling.
2. Tonal treble (a sustained high note) gets the right loudness but the wrong texture.
3. The offsets were learned from only 8 clips. Re-learn them from the team's own high-quality library, in the demo genres.

---

## 6. Verified hardware and tool facts
<!-- id: s6 -->

| Fact | Value | Source |
|---|---|---|
| Audio codec | ADAU1761; configured over I2C, audio over I2S; line-in gives stereo 24-bit samples | [TU Kaiserslautern ZedBoard audio interface](https://kluedo.ub.rptu.de/files/4034/zedboard_audio_doc.pdf) |
| Audio jacks | Blue line in, pink mic in, green line out, black headphone out | [Elektronika Praktyczna](https://ep.com.pl/files/12231.pdf) |
| Microphone input | Electret bias jumper JP1 is listed for the "Right Channel only", so a second electret microphone needs bias from elsewhere | [ZedBoard HW User Guide v2.2](https://eclass.uoa.gr/modules/document/file.php/DI375/Manual_ZedBoard_HW_UG_v2_2.pdf) |
| USB-UART | Cypress CY7C64225 on PS UART1, MIO 48/49; TX/RX only, no RTS/CTS | ZedBoard HW User Guide v2.2 |
| CY7C64225 baud limit | 300 to 230,400; no flow control at 230,400 | [Infineon datasheet](https://www.infineon.com/assets/row/public/documents/24/49/infineon-cy7c64225-usb-to-uart-bridge-controller-datasheet-datasheet-en.pdf) |
| PMOD headers | JA–JD on PL (bank 13, 3.3 V); JE on PS MIO | ZedBoard HW User Guide v2.2 |
| SD card, USB-UART | PS hard peripherals via MIO (SD0, UART1) | [UT Austin ZedBoard tutorial](https://users.ece.utexas.edu/~mcdermot/arch/web/Digilent/Embedded_Linux_Hands_on_Tutorial_ZedBoard.pdf) |
| Ethernet | Gigabit, wired to the PS; needs the ARM | ZedBoard HW User Guide (not re-checked) |
| PL resources | Zynq-7020: 140 × 36 Kb block RAM (≈ 630 KB), 220 DSP slices | Not re-checked |
| Lab PMODs usable as fallback analog I/O | AD1 (two-channel ADC) and DA2 (two-channel DAC) | Course guidelines PDF |
| ADAU1761 ADC-to-DAC latency | Unknown | Check the datasheet |
| Lab tools | Vivado 2020 / Vitis 2020.x | Team |
| UDP template | "lwIP UDP Perf Server" built and run in Vitis 2020.1 on a Zybo Z7-20 (Zynq-7000) | [Digilent forum](https://forum.digilent.com/topic/23632-zybo-z7-20-lwip-udp-perf-server-vitis-20201/) |
| Networking without a router | PC on a static IP 192.168.1.x (avoid .10); serial console 115,200 8N1, no handshaking | [Digilent Zynq servers guide](https://digilent.com/reference/programmable-logic/guides/zynq-servers) |
| PHY driver patch | Digilent's patch targets Realtek RTL8211F boards; do not apply it to the ZedBoard blindly | Same guide |

---

## 7. Verification strategy
<!-- id: s7 -->

1. Golden models (team-written, fixed-point Python): ANC as FxLMS plus secondary-path LMS, with the primary path and secondary path modelled as FIR filters (synthetic first, then the path measured on hardware); goal 2 as the treble-restoration chain of §5. The float prototype in §11 is a reference only.
2. Unit testbenches: each RTL block is fed vectors from its golden model, with a bit-exact comparison.
3. ANC loop simulation: the RTL controller runs against the modelled acoustic paths inside the testbench, showing the convergence curve and the steady-state attenuation. These are the main simulation marks.
4. Goal 2 full-chain simulation: WAV in → RTL → WAV out, scored by log-spectral distance against the plain MP3 and the master.
5. Hardware: ANC off versus on, noise reduction in dB at the error microphone shown on the OLED, plus listening inside the cup; goal 2 A/B switch and a blind listening test.
6. Claims follow §3.4.

---

## 8. Decision log
<!-- id: s8 -->

| # | Decision | Rationale | Status |
|---|---|---|---|
| 1 | Core DSP is custom RTL in the PL; the ARM only decodes MP3 and moves data (goal 2) | Simulation marks, mandatory framework, "FPGA-based"; decoding is not the graded part | CLOSED |
| 2 | Neural supersampler and neural accelerator dropped | No team model-training experience; large models can't run on Zynq; can't HDL-simulate meaningfully; can't recover lost information anyway | CLOSED |
| 3 | Superseded by 14. Was: noise cancellation and live microphone path dropped | Earlier chain: two-mic LMS → single-mic spectral subtraction + LMS hum canceller → dropped on 13 Oct | CLOSED |
| 4 | Superseded by 12. Was: Ethernet UDP → ARM (lwIP) → AXI FIFO → PL | Also rejected along the way: laptop line-in and block RAM preload (team ruled out); SD card as the only source (not live); USB-UART PMOD (no budget); BT2 (marginal throughput); PmodESP32 Wi-Fi (jitter, firmware risk) | CLOSED |
| 5 | Superseded by 12. Was: laptop decodes MP3 and resamples to 48 kHz | Sending decoded PCM costs about 27× the bandwidth (192,000 ÷ 7,000) and needs Ethernet | CLOSED |
| 6 | Goal 2 enhancement: smart guess (§5) as the full target, fixed-rule extension as the stage-1 fallback | The fixed rule is simple but makes soft music worse (§5.4). Rejected outright: side-information band replication (needs the master); 88-coefficient regression (did not generalise); ADPCM and μ-law link formats (moot) | CLOSED |
| 7 | Output content up to 20 kHz only | Human hearing limit; content above risks intermodulation | CLOSED |
| 8 | Goal 2 proof of on-board processing = link capacity limit plus live A/B switch | Link carries at most 23,040 bytes/s; output is 176,400–192,000 bytes/s | CLOSED |
| 9 | Mono first; stereo is an extra goal (§13) | Same design instantiated twice | CLOSED |
| 10 | Superseded by 14. Was: lead with treble restoration | ANC now leads; filters and FFT remain sub-blocks only (list titles #18, #19) | CLOSED |
| 11 | Group 16, section P2; members and IDs in §10.2 | Shared 19 Oct; role mapping is a placeholder until confirmed (§9 item 17) | CLOSED |
| 12 | Goal 2 transport = compressed MP3 bytes over the PS USB-UART at 230,400 baud; the ARM decodes bare-metal and feeds the PL FIFO | 56 kbps needs 7,000 bytes/s vs 23,040 available (3.3× headroom); no network stack; matches the tiny-files use case. MP3 decoding in RTL rejected as too large | CLOSED |
| 13 | Extra goals (§13) are implemented only after the core works on hardware | Protects the 14 Nov report and the demo | CLOSED |
| 14 | Goal 1 = active noise cancellation; goal 2 = compressed-audio enhancement, best-effort | Instructor (relayed 16 Oct): noise cancellation is the main expectation, "even if far from perfect"; upscaling welcome. "Active" is the team's reading; confirmation open (§9 item 1) | CLOSED |
| 15 | ANC target = controlled periodic noise, about 100–500 Hz, at one point inside an over-ear headphone cup | Quiet zone is about a tenth of a wavelength; converter delay rules out broadband random noise (§14) | CLOSED |
| 16 | Feedforward FxLMS with a reference and an error microphone; secondary path identified at start-up with LFSR white noise | Instructor: the kit supports two microphones; standard ANC structure. One-microphone feedback ANC kept as fallback | CLOSED |
| 17 | All ANC hardware (two microphones with bias and preamp, over-ear headphones, noise source) assumed available | Team's decision, 18 Oct; any change goes through the instructor with special permission | CLOSED |
| 18 | EQ stage dropped from the core; moved to extra goals | Time, with ANC on the critical path; ANC FIR filters already cover "digital filtering" | CLOSED |
| 19 | Codec runs at 48 kHz in every mode | Set by ANC; MP3 44.1 kHz handling open (§9 item 10) | CLOSED |
| 20 | Work plan submitted as Group-no-16-Work-Plan.pdf (3 pages, drawn block diagrams, Carlito font) | Built 19 Oct from Group-no-16-Work-Plan.md | CLOSED |

---

| 21 | Goal 2 target: 32 kbit/s MP3 at 48 kHz mono is the primary target; lower rates are secondary | 32 kbit/s is the lowest MPEG-1 Layer III rate at 48 kHz, and the board accepts only 48 kHz. A 24 kHz file keeps only about 5–8 kHz (measured) | CLOSED |
| 22 | Sample-rate conversion is done on the laptop with ffmpeg before sending; no resampler on the ARM | ffmpeg is already in the sender's requirements; the board only accepts 48 kHz mono | CLOSED |
| 23 | Cutoff measured with the 40 dB rule (Welch spectrum; passband 2–4 kHz). The bitrate is read from the MP3 frame info and looked up in a table | The midpoint rule is not valid at 64 kbit/s; the 20 dB rule returns 5.4 kHz for every rate. Table in test_audio/beethoven5_ogg_knee_table.md. Supersedes the cutoff-detector candidate in §9 item 14 | CLOSED |
| 24 | Enhancement chain: band-pass fc/2 to fc, absolute value, high-pass at fc, sum with the original, low-pass 20 kHz; float reference first | A rectified single tone gives even harmonics only; the low-pass removes the higher harmonics and aliasing; see model/goal2/ref.py | CLOSED |
| 25 | GAIN = 1 for now | Not tied to the ANC gains; the gain sets the level of the added treble. Choose from measurement and listening (§9 item 27) | OPEN |
| 26 | Test material: the public-domain Beethoven movement (Commons OGG) and a synthetic master. WAVs are not committed; they are rebuilt from the tracked MP3s | The WAVs total about 60 MB and are ignored by .gitignore; make_abx_wavs.py rebuilds them | CLOSED |
| 27 | Pushes go to the member branch d/goal2, not main | Project rule (CLAUDE.md; plan §8) | CLOSED |
## 9. Open items and risks
<!-- id: s9 -->
| # | Item | Status | Note |
|---|---|---|---|
| 1 | Instructor confirmation that "active" ANC (anti-noise through a speaker) is meant | OPEN | Relayed words were "noise cancellation" and "two mics"; "active" came from a teammate's question |
| 2 | Two microphones at the same time on the ADAU1761, with bias for both | OPEN | JP1 bias is "Right Channel only" (§6); fallbacks: external bias and preamp into line in, or the AD1 PMOD |
| 3 | ADAU1761 ADC-to-DAC latency | OPEN | Measure during hardware bring-up; it affects the usable frequency range |
| 4 | FxLMS and path-model lengths (L, M), step sizes, word lengths | CLOSED | Fixed by the validated B/C source and its simulation vectors |
| 5 | Divergence thresholds and calibration duration | OPEN | Tune during hardware bring-up |
| 6 | Acoustic test setup: ear cup, microphone placement, noise frequency | OPEN | Build and document before ANC hardware testing |
| 7 | ADAU1761 I2C start-up sequence (two ADC channels, headphone DAC, 48 kHz) | IN_PROGRESS | Aarav's baseline is in main and its supplied testbench passes; verify it in the lab |
| 8 | USB-UART at 230,400 baud with no flow control: zero byte loss over a whole file | CLOSED | Goal-2 lab validation passed 5 Nov |
| 9 | Bare-metal MP3 decoder library for Vitis 2020.x | CLOSED | Included in the validated goal-2 path |
| 10 | MP3 at 44.1 kHz vs codec at 48 kHz | CLOSED | The validated goal-2 test path uses 48 kHz mono |
| 11 | UART receive design: interrupt or DMA into a DDR ring buffer; RX FIFO size | CLOSED | Implemented and validated in the goal-2 path |
| 12 | Laptop sender script and file framing (length header, checksum) | CLOSED | Implemented and validated in the goal-2 path |
| 13 | Goal 2 fixed-point word lengths and filter orders | OPEN | Needed only for treble restoration |
| 14 | Cutoff detector hardware design (candidate set, update rate) | OPEN | Needed only for treble restoration |
| 15 | Training music for the 8 offsets | OPEN | Needed only for the smart-guess extension |
| 16 | Demo slot | OPEN | Swarneel is away 26–30 Nov; book early in 17–25 Nov |
| 17 | Role mapping A–D | CLOSED | Confirmed by the repository plans |
| 18 | Build progress since 19 Oct not recorded | CLOSED | Existing work was validated on 5 Nov; Aarav's week-1 source was merged on 6 Nov |
| 19 | MP3 artifacts below the cutoff | CLOSED | Accepted limitation; stated in the report |
| 20 | UDP throughput on ZedBoard | CLOSED | Relevant only to the Ethernet extra goal (§13) |
| 21 | Examiner acceptance of no noise cancellation | CLOSED | Moot: ANC is goal 1 |
| 22 | EQ preset definitions | CLOSED | EQ moved to extra goals (decision 18) |
| 23 | Status display content | CLOSED | Pmod OLED: mode, noise reduction in dB, detected cutoff, FIFO level |
| 24 | The 32 kbit/s cutoff (7.2 kHz, 40 dB rule) confirmed on a second clip or on real music | OPEN | Measured on one 20 s Beethoven passage; the spectrogram edge looks nearer 8 kHz |
| 25 | ABX listening test, plain vs enhanced at 32 kbit/s | OPEN | 16 passages in test_audio/ABXtesting; run abx.py with a good headset |
| 26 | FIFO path to the board: Vivado block design (PS + music_fifo_axi) and the ARM feeder in sw/app | OPEN | Handoff written 9 Nov, kept off the repo; needs the 11 Nov session first |
| 27 | Enhancement gain (GAIN = 1 for now) | OPEN | Choose from measurement and listening, not from the ANC gains |
| 28 | Hardware session 11 Nov (T0 to T3) | OPEN | docs/hardware_testing_plan.md; T0 is the laptop pre-flight |
## 10. Execution plan
<!-- id: s10 -->

### Work plan submission
<!-- id: s10.workplan -->

STATUS: COMPLETED
UPDATED: 2026-10-19
NOTE: Submission assumed; confirm it was uploaded to the course Drive link.

1. Group-no-16-Work-Plan.pdf: 3 A4 pages, six sections in the guideline order (group details; title and abstract, 180 words; objectives as bullet points, as the guidelines require; hardware; methodology with two drawn block diagrams and the framework mapping; five-week plan).
2. Source: Group-no-16-Work-Plan.md. The PDF was built with Claude's HTML-to-PDF scaffolding (Carlito font, page-numbered footer).
3. The prototype numbers of §5.4 were deliberately left out (Claude's scaffolding, not team code).

### Roles
<!-- id: s10.roles -->

| Member | Name | ID | Area |
|---|---|---|---|
| A | Aarav Barnwal | 2023B3A30512H | Codec: I2C configuration (two ADC channels, headphone DAC), I2S, mode FSM, hardware integration |
| B | Aadyant Lahiri | 2023B3AA1191H | FxLMS controller RTL; owner of the ANC golden model |
| C | Samarth Shreepad Dixit | 2023B1AA1324H | Secondary-path identification (LFSR + LMS), noise-reduction measurement and OLED display, acoustic test setup |
| D | Swarneel Bhattacharjee | 2023AAPS0695H | Goal 2: UART receive, ARM MP3 decoding, PL FIFO, treble restoration (fixed rule, then smart guess) |

### Week 1 — 31 Oct to 6 Nov (restart; old weeks 1 and 2)
<!-- id: s10.w1 -->
STATUS: IN_PROGRESS
DEPENDS: s10.workplan
NOTE: Existing B, C and D work was validated on 5 Nov. Aarav's week-1 codec/I2S source and its supplied simulations were merged into main on 6 Nov; the hardware exits remain pending.

STATUS: NOT_STARTED
DEPENDS: s10.workplan
NOTE: Nothing was built 20–30 Oct; old weeks 1 and 2 are merged here. Proposed 31 Oct, confirm with the team.

1. A: ADAU1761 I2C configuration (two ADC channels, headphone DAC, 48 kHz); I2S RX/TX; microphone-to-headphone passthrough. Decide the second microphone's bias by 3 Nov. Exit: both microphones heard at the same time on hardware.
2. B: fixed-point FxLMS golden model with modelled primary and secondary paths; L, M, step size and word lengths fixed by 3 Nov. Then control filter, filtered reference and weight update RTL. Exit: RTL bit-exact against the golden model.
3. C: LFSR generator and secondary-path identification RTL plus testbench, bit-exact against the golden model; build the acoustic test setup (ear cup, microphone placement, noise source).
4. D: MP3 over the USB-UART at 230,400 baud into DDR; bare-metal decoding; ARM-to-PL FIFO. Exit: an MP3 sent from the laptop plays unprocessed end to end. Fallback: 115,200 baud.
5. All: ask the instructor about §9 item 1 by 2 Nov.

### Week 2 — 7 to 12 Nov (feature freeze 12 Nov)
<!-- id: s10.w2 -->

STATUS: NOT_STARTED
DEPENDS: s10.w1

1. A: mode FSM (calibrate, cancel, bypass, mute, music), switches, LEDs; hardware integration.
2. A, B, C: ANC on hardware: secondary-path calibration, then cancellation; step-size tuning; divergence protection.
3. C: noise-reduction measurement and OLED display.
4. D: fixed-rule treble extension RTL (goal 2, stage 1) plus testbench, in music mode.
5. Exit: measured noise reduction on hardware (goal 1 complete); fixed-rule extension playing on hardware.

### Week 3 — 13 to 14 Nov (report)
<!-- id: s10.w3 -->

STATUS: NOT_STARTED
DEPENDS: s10.w2
NOTE: Report due 14 Nov, before the demo.

1. All: write and submit the final report from what works on 12 Nov, with the measured numbers (claims follow §3.4).
2. B, C: ANC convergence curve and steady-state attenuation from simulation for the report (§7 item 3).

### Week 4 — 15 to 16 Nov (demo preparation)
<!-- id: s10.w4 -->

STATUS: NOT_STARTED
DEPENDS: s10.w3

1. A: final ANC measurements; fix demo-blocking bugs only.
2. D: smart guess (stage 2) only if goal 1 and the fixed-rule extension both work on hardware.
3. All: viva preparation; every member explains every block.

### Week 5 — 17 to 27 Nov (demo, viva, code ZIP)
<!-- id: s10.w5 -->

STATUS: NOT_STARTED
DEPENDS: s10.w4

1. Demo in the 17–25 Nov window (§9 item 16).
2. Viva preparation: every member explains every block.
3. Source code ZIP by 27 Nov.
4. Extra goals (§13), only if everything above is done.

---

## 11. Artifacts
<!-- id: s11 -->

| Artifact | Contents | Note |
|---|---|---|
| Group-no-16-Work-Plan.md / .pdf | Submitted work plan | Source and PDF |
| bwe_listening_test.html + bwe_wavs.zip | 8 kHz ADPCM and 16 kHz PCM with a fixed-rule extension | Showed 8 kHz ADPCM is unacceptable |
| sbr_listening_test.html + sbr_wavs.zip | 16 kHz μ-law/PCM with side-information band replication | Rejected later: needs the master |
| smart_guess_test.html + smart_guess_wavs.zip | 56 kbps MP3 with fixed rule, smart guess, and true-envelope ceiling | Basis of decision 6 |
| Python scripts behind them | Float prototypes | Claude's scaffolding, not team code; not delivered |

---

## 12. Working notes for future chats
<!-- id: s12 -->

1. Updates to this file: patch blocks for `handoff_mgr.py apply` only. Run `handoff_mgr.py ids HANDOFF.md` first; never regenerate the whole file unless explicitly asked (Rev 4 was a full regeneration on request).
2. STATUS values are exactly NOT_STARTED, IN_PROGRESS, BLOCKED, COMPLETED, OPEN or CLOSED.
3. Web-verify any tool, library or download before recommending it.
4. Learning project: review, catch bugs and argue architecture; do not write deliverable RTL. Scaffolding is allowed and must be marked as not team code.

---

5. Git (9 Nov): goal-2 work is on branch d/goal2 (pushed). main has the week-1 codec code. HANDOFF.md stays untracked; to move it to another machine, copy it by hand.
6. ABX excerpt MP3s are tracked; the WAVs are not. Rebuild the WAVs with test_audio/ABXtesting/make_abx_wavs.py.
## 13. Extra goals
<!-- id: s13 -->

STATUS: NOT_STARTED
UPDATED: 2026-10-18
DEPENDS: s10.w4
NOTE: Only after both goals' core work runs on hardware (decision 13).

| # | Extra goal | What it adds | Notes |
|---|---|---|---|
| 1 | ANC while playing music | Music and anti-noise through the same headphones, like commercial ANC headphones | The music must be removed from the error signal: subtract the music filtered through the path model |
| 2 | EQ presets | Biquad presets selected through the mode FSM | Dropped from the core (decision 18) |
| 3 | Library of compressed files on the SD card | Many MP3s stored on the device; select tracks with buttons, name on OLED; no laptop needed | 1 GB at 56 kbps: 1,000,000,000 ÷ 7,000 ≈ 142,857 s ≈ 39.7 hours. Needs a FAT filesystem library on the ARM (web-verify for Vitis 2020.x) |
| 4 | Files kept on the board itself (QSPI flash) | A small built-in library that survives power-off | Capacity and boot-image size to verify; if 32 MB with about 5 MB used: (32,000,000 − 5,000,000) ÷ 7,000 ≈ 3,857 s ≈ 64 minutes |
| 5 | Ethernet streaming from computers | Higher-bitrate files (320 kbps needs 40,000 bytes/s, above the UART's 23,040) and streaming from any PC | Vitis "lwIP UDP Perf Server" template verified in 2020.1 (§6); measure UDP throughput first |
| 6 | Input-source FSM | Select UART, SD card or Ethernet as the source | Extends the mode FSM |
| 7 | Stereo | Second channel | Same PL chain instantiated twice |
| 8 | Tonal-treble handling | Fixes wrong texture on sustained high notes | §5.5 item 2 |
| 9 | VGA spectrum display | Live before/after spectrum, for ANC or goal 2 | Overlaps list title #19; sub-block only |

---

## 14. Goal 1 — Active noise cancellation
<!-- id: s14 -->

STATUS: OPEN
UPDATED: 2026-10-18
NOTE: Instructor direction relayed by a teammate; "active" came from a teammate's question, confirmation open (§9 item 1).

Principle: anti-noise of equal amplitude and opposite phase is played through the headphone driver, so that at the error microphone inside the ear cup it cancels the noise arriving through the air. Feedforward structure: the reference microphone hears the noise before it reaches the cup; the error microphone measures what remains.

Physical limits:

| Limit | Arithmetic | Consequence |
|---|---|---|
| Quiet zone is about a tenth of a wavelength across | 200 Hz: 343 ÷ 200 ≈ 1.7 m wavelength, zone ≈ 17 cm. 1 kHz: 343 ÷ 1,000 ≈ 0.34 m, zone ≈ 3.4 cm | Cancel at one point (the ear cup), at low frequencies |
| Converter and processing delay | Sound travels 343 m/s, which is 34.3 cm per ms | Random noise would need the reference microphone 34.3 cm ahead per millisecond of delay. Periodic noise is predictable, so delay does not matter |
| Target | — | Periodic noise of about 100–500 Hz (hum, fan tone) |

Signal chain:

```
  Noise source ──air──► Reference mic ──ADC──► x(n)
  Noise source ──air (primary path)──► Error mic ──ADC──► e(n)
  x(n) ──► Control filter W ──► y(n) anti-noise ──► Output mux ──DAC──► Headphone driver
  Headphone driver ──air (secondary path)──► Error mic
  x(n) ──► Path model Ŝ ──► x'(n) ─┐
  e(n) ────────────────────────────┴──► FxLMS weight update of W
  Calibration: LFSR white noise ──► output mux ──► headphone driver; LMS learns Ŝ from e(n)
```

Algorithm. Symbols: x(n) is the reference-microphone sample at time n; y(n) the anti-noise sample; e(n) the error-microphone sample; d(n) the noise at the error microphone via the primary path; sⱼ the j-th coefficient of the true secondary path (driver to error microphone); ŝⱼ its identified estimate; wₖ the k-th control-filter weight; L and M the control-filter and path-model lengths; μ and μₛ step sizes; v(n) the LFSR noise sample.

1. Acoustics: the anti-noise adds to the noise at the error microphone, e(n) = d(n) + Σⱼ sⱼ · y(n − j).
2. Control filter: y(n) = Σₖ wₖ · x(n − k), for k = 0 … L − 1.
3. Substituting 2 into 1: e(n) = d(n) + Σⱼ sⱼ · Σₖ wₖ · x(n − j − k).
4. Differentiating with respect to one weight (weights change slowly, so treat them as constant over the path length): ∂e(n)/∂wₖ = Σⱼ sⱼ · x(n − j − k).
5. That sum is the reference filtered through the secondary path. Using the estimate: x'(n) = Σⱼ ŝⱼ · x(n − j), for j = 0 … M − 1, so ∂e(n)/∂wₖ ≈ x'(n − k).
6. Gradient of the squared error: ∂e(n)²/∂wₖ = 2 · e(n) · ∂e(n)/∂wₖ ≈ 2 · e(n) · x'(n − k).
7. Steepest descent, with the factor 2 absorbed into μ: wₖ ← wₖ − μ · e(n) · x'(n − k).
8. Secondary-path identification (CALIBRATE): play y(n) = v(n); prediction error ε(n) = e(n) − Σⱼ ŝⱼ · v(n − j); update ŝⱼ ← ŝⱼ + μₛ · ε(n) · v(n − j). Run with the noise source off for faster, unbiased convergence.

Mode FSM (shared with goal 2):

| State | Action | Exit |
|---|---|---|
| CALIBRATE | Play LFSR noise; adapt Ŝ | After a fixed duration (to tune) → CANCEL |
| CANCEL | FxLMS running; anti-noise out | Switch → BYPASS; divergence → MUTE |
| BYPASS | Output silent (ANC off); meters keep measuring | Switch → CANCEL |
| MUTE | Output zero; weights reset | → CALIBRATE |
| MUSIC | Goal 2 path drives the output | Mode switch |

Divergence: error power above a threshold, or any |wₖ| above a limit (thresholds open, §9 item 5).

PL blocks:

| Block | Function | Cost per sample |
|---|---|---|
| I2C config FSM | ADAU1761 start-up: two ADC channels, headphone DAC, 48 kHz | Start-up only |
| I2S RX (two channels) and TX | Reference and error microphone in; anti-noise or music out | — |
| LFSR | Pseudo-random white noise for calibration | — |
| Ŝ identification (LMS) | Learns the secondary path | Calibration only |
| Ŝ filter | Filtered reference x'(n) | M multiply-accumulates |
| Control filter W | Anti-noise y(n) | L multiply-accumulates |
| Weight update | wₖ update | L multiply-accumulates |
| Power meters and dB | Error power with ANC off and on; 10 · log₁₀ of the ratio via log2 (leading-zero count + LUT) | Few |
| Divergence monitor | Thresholds on error power and weight magnitude | Few |

Compute: at 100 MHz and 48 kHz, 100,000,000 ÷ 48,000 ≈ 2,083 clock cycles per sample. Example with L = 64 and M = 128: 64 + 128 + 64 = 256 multiply-accumulates per sample. Final values come from the golden model (§9 item 4).

Test setup: a phone playing a 100–500 Hz tone (or a small fan) outside the ear cup, near the reference microphone; the error microphone inside the cup, close to the driver; the headphones driven from the codec's headphone output.

Fallbacks: one-microphone feedback ANC if two microphones cannot be used at the same time; the AD1 and DA2 PMODs for extra analog inputs and outputs.
