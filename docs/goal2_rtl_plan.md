# Goal 2 treble RTL plan (`treble_fixed`)

*Written by Claude as a plan (not team code). Swarneel writes the model, RTL and testbench; Claude
reviews. Numbers below were measured from `model/goal2/ref.py` on 11 Nov 2026.*

## 0. Status (11 Nov 2026, evening)

Swarneel assigned the port to Claude, so the model, RTL and testbench are Claude's work (each file
header says so). Done:

- `model/goal2/ref_fixed.py`: fixed-point model; writes `rtl/treble_coefs.mem` and
  `sim/vectors/treble_{in,out}.hex` (30,756 samples: silence, ±full-scale impulses, full-scale
  5 kHz sine and 6 kHz square, 0.5 s of the 32k Beethoven decode).
  Fixed vs float on the added treble: 81.3 dB over the whole 20 s clip; no clipping.
- **Change from §3:** internal samples are 32 bits (4 guard bits **and 4 fraction bits** below the
  s24 LSB), not 28. With 28 bits the rounding noise was only 49 dB below the treble, because the
  first band-pass section has gain about 0.002 and later sections amplify its rounding.
- `rtl/treble_fixed.v`: bit-exact with the model (`sim/tb_treble_fixed.v`, 34,056 checks, all
  §5 checks pass). Result ready 112 clocks after the tick. Starts 2 clocks after the tick,
  when `music_fifo` has `music_raw` valid. `enh_en` is synchronised (2 flops).
- Vivado 2026.1 out-of-context, xc7z020clg484-1, 100 MHz: timing met (WNS +3.1 ns), about 900
  LUTs, 1,800 flip-flops, 2 DSP48E1, no block RAM. Not yet built in the lab's Vivado 2020.
- Run: `./sim/run_treble.sh` (needs numpy and scipy in `.venv`).

Integration (Aarav's files, not changed): in `top.v`, `music_fifo_axi.music_raw` → `treble_fixed`
→ `out_mux.music`, with `enh_en` on a free switch (SW2 proposed). Add `rtl/treble_fixed.v` **and
`rtl/treble_coefs.mem`** to `scripts/create_vivado.tcl`; without the `.mem` file the ROM
synthesises as zeros and the output is the plain music.

## 1. Scope for the 12 Nov freeze

- One coefficient set: 32 kbit/s, FC = 7.2 kHz. Bitrate-dependent sets come later.
- `enh_en = 0` passes `music_raw` straight through (the plain/enhanced switch).
- Order of work: fixed-point Python model, vectors, RTL, testbench. Do not start the RTL before
  the fixed-point model matches the float model.

## 2. What the hardware computes (same chain as `ref.py`)

```
music_raw ──► band-pass fc/2..fc ──► |x| ──► high-pass fc ──► low-pass 20 kHz ──► added
    │                                                                               │
    └──────────────────────────────────── + ◄── GAIN (= 1) × ◄──────────────────────┘
                                          │
                                   saturate to s24 ──► music
```

| Filter | Second-order sections | max abs(b) | max abs(a) | Largest pole radius |
|---|---|---|---|---|
| Band-pass 3.6–7.2 kHz | 4 | 2.0 | 1.665 | 0.938 |
| High-pass 7.2 kHz | 4 | 2.0 | 1.015 | 0.853 |
| Low-pass 20 kHz | 4 | 2.0 | 1.578 | 0.907 |

12 sections × 5 multiplies = about 60 multiplies per sample. The budget is 2,083 cycles per sample
(100 MHz / 48 kHz), so one multiplier used in turn is enough.

## 3. Fixed-point model first (`model/goal2/ref_fixed.py`)

Decisions to make and write in the file header (suggested values):

| Item | Suggestion | Reason |
|---|---|---|
| Input | s24 (`int16 << 8`, as the FIFO feeder writes it) | Matches the §5 interface |
| Coefficients | 25 bits, 2 integer bits + sign (range ±4, step 2.4e-7) | The band-pass first section has b ≈ 0.0018; 18-bit coefficients would leave only about 58 steps |
| Internal samples | 28 bits (24 + 4 guard bits) | Section gains can exceed 1 inside the cascade |
| Structure | Direct Form I per section, one wide accumulator (about 56 bits) | Only the accumulator is wide; simple to match bit for bit |
| Rounding | Once per section output: add `2^(k-1)`, arithmetic shift right by `k` | State the same rule in Python and Verilog |
| Saturation | At each section output, at `abs()`, and at the final sum (s24) | `abs(-2^27)` overflows 28 bits; saturate it |

Checks before moving on:
- Fixed vs float output on the 32k Beethoven decode: the difference in the added treble should be
  far below the treble itself (aim for more than 60 dB below).
- `enh_en = 0`: output equals input exactly.
- Full-scale tone input: output saturates, never wraps sign.

Then write the vectors (`$readmemh` format, one 24-bit two's-complement value per line):
`sim/vectors/treble_in.hex`, `sim/vectors/treble_out.hex`, and the coefficient ROM file the RTL
loads (generated from the same quantised numbers, never typed by hand).

## 4. RTL (`rtl/treble_fixed.v`)

Ports stay as they are now: `clk`, `rst`, `sample_tick`, `music_raw` (s24), `music` (s24), `enh_en`.

- On `sample_tick`, latch `music_raw` and start a sequencer.
- Run the 12 sections in order. Each section: 5 multiply-accumulates through one multiplier, then
  round and saturate. Insert `abs()` after section 4 and the final sum after section 12.
- Keep 4 states per section (`x[n-1]`, `x[n-2]`, `y[n-1]`, `y[n-2]`), cleared on reset.
- Coefficients come from a ROM loaded from the generated file.
- Write `music` once at the end of the run and hold it until the next result. The run takes about
  70–100 cycles, far inside one sample.
- Keep the filters running when `enh_en = 0`, so switching back is click-free; only the output
  selection changes.
- The multiply is 28 × 25 bits. Vivado will use more than one DSP slice for it; register its inputs
  and output so it meets 100 MHz.

## 5. Testbench (`sim/tb_treble_fixed.v`)

Build on the harness pattern from 9 Nov (input hex in, expected hex out, output captured at the next
tick). Checks:
1. Bit-exact against `treble_out.hex` for all vectors.
2. `enh_en = 0`: output equals input.
3. Full-scale input: no sign wrap.
4. Reset, then replay: identical output.
5. `music` holds its value between ticks.

## 6. Proposal: music and ANC together (needs A, B and C)

Idea (Swarneel, 11 Nov): run the enhancement alongside ANC so both can be demonstrated.

Switches (the ZedBoard has eight user slide switches, SW0–SW7; SW0 and SW1 are used now):

| SW1 SW0 | Mode | Output |
|---|---|---|
| 00 | ANC | anti-noise |
| 01 | Bypass | zero |
| 10 | Music | music |
| 11 | Music + ANC (new) | saturate(music + anti-noise) |

SW2 = `enh_en` (plain vs enhanced music), for the live A/B demonstration.

What it affects:
1. **FxLMS adaptation (B).** The error mic hears the music. Music is uncorrelated with the reference
   noise, so ANC will not cancel it, but it adds noise to the weight update: slower convergence and
   a larger residual. If that is a problem, subtract the music's predicted contribution at the error
   mic: `e'(n) = e(n) − Σ ŝ_j · music(n − j)`, using C's ŝ (128 more multiplies per sample).
2. **Noise meter (C).** The meter measures error-mic power, so in mode 11 it counts the music as
   residual noise. The dB readout is only valid in mode 00, unless it uses `e'(n)`.
3. **Calibration.** Path identification plays LFSR noise; it must run with the music off.
4. **Headroom.** The sum of two s24 signals needs saturation, and the music level should leave room
   for the anti-noise.
5. **Ownership.** `mode_fsm`, `out_mux`, `top` and the constraints are Aarav's; `fxlms` is
   Aadyant's; the meter is Samarth's. The §5 interface table changes in the same commit, by
   agreement (`docs/plan/README.md` §5).

Suggested order: add mode 11 as a plain sum first and measure ANC with music playing. Add the
`e'(n)` compensation only if ANC gets noticeably worse.

## 7. Integration

- `top.v` currently ties `music` to 0 ("parked until Member D's RTL is merged"). The connection is
  Aarav's file: `music_fifo_axi.music_raw` → `treble_fixed` → `out_mux.music`.
- Review note for Aarav: in `mode_fsm.v`, MUSIC goes to BYPASS on `fifo_underrun` and comes back on
  the next clock while the switch is still on music, so the mode flips every clock during an
  underrun. The plan (§5) keeps MUSIC and lets `out_mux` output zero.
