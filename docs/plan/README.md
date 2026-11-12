# Project plan — FPGA-Based Audio Enhancement System (Group 16)

EEE F314 FPGA-Based System Design, BITS Pilani Hyderabad, section P2. ZedBoard (Zynq-7020),
Vivado 2020 / Vitis 2020.x.

**Read this file first, then your own file:**

| Member | Name | Area | Plan |
|---|---|---|---|
| A | Aarav Barnwal | Codec (I2C, I2S), mode FSM, output mux, top level, integration | [A-aarav-codec-fsm.md](A-aarav-codec-fsm.md) |
| B | Aadyant Lahiri | ANC golden model, FxLMS controller RTL | [B-aadyant-fxlms.md](B-aadyant-fxlms.md) |
| C | Samarth Shreepad Dixit | LFSR, secondary-path identification, noise meter and OLED, divergence monitor, acoustic rig | [C-samarth-pathid-meter.md](C-samarth-pathid-meter.md) |
| D | Swarneel Bhattacharjee | Goal 2: MP3 over UART, ARM decoding, PL FIFO, treble restoration | [D-swarneel-goal2.md](D-swarneel-goal2.md) |

**Priority change (11 Nov 2026, team decision): goal 2, compressed-audio enhancement, is now the
primary goal; goal 1, ANC, is secondary.** ANC hardware (second mic, rig) is not available, so the
demo build is the enhancement build: `rtl/enh_top.v`, built by `scripts/build_enh.tcl`; how to run it
is in [`docs/enh_build.md`](../enh_build.md). ANC work continues once enhancement works on the
board. The names "goal 1" (ANC) and "goal 2" (enhancement) are kept, because files and branches use
them.

Status on 6 Nov 2026: existing B, C and D work was validated on 5 Nov, including the goal-2 lab
run. Aarav's week-1 codec/I2S scaffolding and supplied simulations were merged into `main` on
6 Nov; Vivado generation and audio-path hardware validation remain pending. The schedule below
is compressed from the submitted five-week plan. Role mapping follows the group-sheet order;
tell Swarneel if it is wrong.

---

## 1. What we are building

1. **Goal 1 (secondary since 11 Nov; was the main goal): active noise cancellation.** Cancel a steady 100–500 Hz
   tone (hum, fan) at one point inside an over-ear headphone cup by playing anti-noise through
   the headphone driver. Feedforward FxLMS in the PL: a *reference mic* outside the cup hears the
   noise first, an *error mic* inside the cup hears what is left.
2. **Goal 2 (primary since 11 Nov; was best-effort): compressed-audio enhancement.** A low-bitrate MP3 is sent over the
   USB-UART, decoded on the ARM, streamed to the PL, which regenerates the treble the encoder cut.

Course framework mapping: mics (input) → ADAU1761 codec over I2S (FPGA interface) → FxLMS /
treble restoration (processing) → mode FSM (decision/control) → headphones + OLED + LEDs (output).

What we may claim: the measured noise reduction in dB at the error mic, ANC off vs on, for the
tested tone. Never "silence", room-wide or broadband cancellation. For goal 2: measurable
improvement over the plain MP3, never "better than the original".

## 2. Deadlines

| Item | Date |
|---|---|
| Week 1 exit | Fri 6 Nov |
| Feature freeze | Thu 12 Nov |
| Final report | Sat 14 Nov (before the demo) |
| Demo + presentation + viva | 17–25 Nov (book early; Swarneel is away 26–30 Nov) |
| Source code ZIP | Fri 27 Nov |

Marks (20): work plan 4 (done), simulation 3, source code 3, hardware demo 4, report 3,
presentation and viva 3. **In the viva every member must explain every block**, so read the
other three plans too.

## 3. Schedule

| Week | A (Aarav) | B (Aadyant) | C (Samarth) | D (Swarneel) |
|---|---|---|---|---|
| **1: 31 Oct–6 Nov** | Codec I2C config, I2S RX/TX, mic → headphone passthrough with both mics. Second-mic bias decided **by 3 Nov** | Fixed-point golden model; L, M, μ, word lengths fixed **by 3 Nov**; then FxLMS RTL bit-exact | LFSR + path-ID RTL and testbench, bit-exact; build the ear-cup rig | UART → DDR → MP3 decode → PL FIFO; an MP3 plays unprocessed |
| **2: 7–12 Nov** | Mode FSM, switches, LEDs, top-level integration | ANC on hardware with A and C: tuning | Noise meter + OLED; divergence monitor | Fixed-rule treble extension RTL |
| **3: 13–14 Nov** | Report | Report + simulation convergence plot | Report | Report |
| **4: 15–16 Nov** | Final measurements | Viva prep | Viva prep | Smart guess only if everything else works |
| **5: 17–27 Nov** | Demo, viva, code ZIP | | | |

Exit for goal 1: measured noise reduction in dB shown on the OLED, on hardware.

Everyone, by Mon 2 Nov: one person asks the instructor whether she means *active* ANC
(anti-noise through a speaker), not cleaning a recording with a reference mic. Record the answer
in this file.

## 4. Block diagram

```
 ref mic ─┐                         ┌────────────── PL (100 MHz) ───────────────────────────┐
          ├─ ADAU1761 ─ I2S ─► i2s_rx (A) ─► x_ref, e_err, sample_tick                     │
 err mic ─┘   ▲                     │            │                                          │
              │ I2C                 │            ├─► fxlms (B) ── y_anti ─────┐             │
         codec_cfg (A)              │            │      ▲ reads ŝ             │             │
                                    │            ├─► sec_path_id (C) ◄─ v ─ lfsr (C)       │
                                    │            │      owns ŝ RAM            │  v ──┐      │
                                    │            └─► meter + divergence (C) ──┼──► OLED     │
                                    │                                         ▼      ▼      │
 laptop ─UART─► ARM (D) ─AXI─► music_fifo (D) ─► treble_fixed (D) ─ music ─► out_mux (A)   │
                                    │                                         │ ◄─ mode_fsm (A)
 headphones ◄─ ADAU1761 ◄─ I2S ◄─ i2s_tx (A) ◄───────────────────── dac_out ┘             │
                                    └───────────────────────────────────────────────────────┘
```

## 5. Interfaces between members (proposed; A finalises by 2 Nov)

These are the contracts that let four people build separately and still integrate in week 2.
**Change one only by agreement, and update this table in the same commit.**

Conventions:
- One clock, `clk` (100 MHz). One reset, `rst`, active-high, synchronous.
- `sample_tick`: one-cycle pulse at 48 kHz, from `i2s_rx`. On that cycle a new `x_ref` / `e_err`
  pair is valid and stays valid until the next tick. Everything for sample n must be done
  within 2,083 cycles (100 MHz ÷ 48 kHz); results are taken by `i2s_tx` at the next tick.
- Samples at block boundaries: `signed [23:0]`, two's complement, full scale = codec full
  scale. Internal word lengths are each owner's choice, from the golden model.

| Signal | Width | From | To | Meaning |
|---|---|---|---|---|
| `sample_tick` | 1 | A `i2s_rx` | all | New sample pair valid |
| `x_ref` | s24 | A `i2s_rx` | B, C | Reference mic sample |
| `e_err` | s24 | A `i2s_rx` | B, C | Error mic sample |
| `cal_en` | 1 | A `mode_fsm` | C `sec_path_id` | Adapt ŝ (CALIBRATE state) |
| `anc_en` | 1 | A `mode_fsm` | B `fxlms` | Run FxLMS (CANCEL state) |
| `w_reset` | 1 | A `mode_fsm` | B `fxlms`, C `sec_path_id` | Clear weights (MUTE state) |
| `cal_done` | 1 | A `mode_fsm` (timer) | A | Calibration time elapsed |
| `v_lfsr` | s24 | C `lfsr` | A `out_mux`, C | White calibration noise, fixed amplitude |
| `shat_addr` | log2(M) | B `fxlms` | C ŝ RAM | Read address for ŝ |
| `shat_data` | from model | C ŝ RAM | B `fxlms` | ŝ coefficient (1-cycle read latency) |
| `y_anti` | s24 | B `fxlms` | A `out_mux` | Anti-noise sample |
| `w_over` | 1 | B `fxlms` | C divergence | Some \|w_k\| above limit |
| `diverge` | 1 | C divergence | A `mode_fsm` | Error power or weights out of range |
| `music` | s24 | D `treble_fixed` | A `out_mux` | Enhanced music sample |
| `fifo_underrun` | 1 | D `music_fifo` | A `mode_fsm` | No PCM available this tick |
| `nr_db` | 8 | C meter | C OLED, A LEDs | Noise reduction, whole dB |
| `dac_out` | s24 | A `out_mux` | A `i2s_tx` | Selected output |

Mode FSM (A):

| State | Output mux | Enables | Exit |
|---|---|---|---|
| CALIBRATE | `v_lfsr` | `cal_en` | `cal_done` → CANCEL |
| CANCEL | `y_anti` | `anc_en` | switch → BYPASS; `diverge` → MUTE |
| BYPASS | zero (ANC off; meters keep measuring) | — | switch → CANCEL |
| MUTE | zero | `w_reset` | → CALIBRATE |
| MUSIC | `music` | — | mode switch; `fifo_underrun` → zero output |

## 6. ANC algorithm (everyone must know this for the viva)

Symbols: x(n) reference mic, e(n) error mic, y(n) anti-noise, w_k control-filter weights
(k = 0 … L−1), ŝ_j secondary-path estimate (j = 0 … M−1), v(n) LFSR noise, μ and μₛ step sizes.
The *secondary path* is everything from `dac_out` to `e_err`: DAC, headphone driver, air, mic,
ADC and our own pipeline delay.

1. Control filter: y(n) = Σ_k w_k · x(n − k)
2. Filtered reference: x'(n) = Σ_j ŝ_j · x(n − j)
3. FxLMS update: w_k ← w_k − μ · e(n) · x'(n − k)
4. Path identification (CALIBRATE, noise source off): play y(n) = v(n);
   ε(n) = e(n) − Σ_j ŝ_j · v(n − j); ŝ_j ← ŝ_j + μₛ · ε(n) · v(n − j)

Why x' and not x: the anti-noise reaches the error mic only through the secondary path, so the
gradient of e² with respect to w_k is e(n) times x filtered through that path. Without the
filtering the update points the wrong way and diverges.

Starting values to test in the golden model: L = 64, M = 128 (256 MACs per sample, far below
2,083 cycles). Final values come from B's model.

Physical limits: the quiet zone is about a tenth of a wavelength (≈ 17 cm at 200 Hz, 3.4 cm at
1 kHz), so we cancel at one point at low frequency. Converter delay rules out random noise; a
steady tone is predictable, so delay does not matter.

## 7. Verification (3 marks for simulation)

1. Golden models in Python, fixed point, in `model/`. They write test vectors to
   `sim/vectors/<block>_<signal>.hex`, one sample per line, for `$readmemh`.
2. Every RTL block has a testbench in `sim/` that compares its output against the golden model
   **bit for bit**.
3. The headline simulation: the RTL FxLMS + path ID running against modelled acoustic paths in a
   testbench, showing the convergence curve and the steady-state attenuation.
4. Hardware: ANC off vs on, dB at the error mic on the OLED.

## 8. Repository and git

```
rtl/          PL Verilog, one file per module, named after the module
sim/          testbenches (tb_<module>.v) and sim/vectors/
model/        Python golden models (model/anc/, model/goal2/)
sw/           Vitis bare-metal ARM code and the laptop sender script
constraints/  ZedBoard .xdc (A owns it)
docs/         plans, report, diagrams, measurements
```

- Each person works on a branch named after their area (`a/codec`, `b/fxlms`, `c/pathid`,
  `d/goal2`) and opens a pull request into `main`. Do not push straight to `main`.
- Edit only your own modules. Changes to another member's file go through that member.
- Commit sources only. Vivado/Vitis project folders, bitstreams, `.vcd` and audio files are
  git-ignored. A keeps the Vivado project local and later adds a Tcl script that rebuilds it.

## 9. Rules for everyone's AI coding agent

Copy this section into your agent's instructions if it does not read `CLAUDE.md` on its own.

1. This is a **graded course project with a viva**. The member writes the deliverable RTL,
   testbenches and golden models and must be able to explain every line. The agent explains,
   reviews, finds bugs, argues design and suggests the next step.
2. Scaffolding the agent writes (helper scripts, vector dumpers, example code) gets a header
   comment saying it is not team code.
3. Check any tool, library or download on the web before recommending it; the lab runs Vivado
   2020 / Vitis 2020.x, which older or newer examples may not match.
4. Do not change another member's files or the interface table in §5 without asking.
5. Do not push to `main`; work on your branch.
