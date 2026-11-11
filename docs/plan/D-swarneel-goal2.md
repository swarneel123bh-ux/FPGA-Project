# Member D — Swarneel Bhattacharjee: goal 2, compressed-audio enhancement

Read [README.md](README.md) first (goals, schedule, interface table §5, agent rules §9).

**Your role:** goal 2 is best-effort; goal 1 comes first for the team. Your path is independent
of ANC until week 2, when it plugs into A's output mux as `music` (MUSIC state).

## Status and next steps (updated 11 Nov 2026)

Done:
- Decoder reports the bitrate (`res.bitrate`, read on every frame; the 32k file reads 32).
- Cutoff measured for 32–96 kbit/s on the Beethoven clip (40 dB rule): see
  `test_audio/beethoven5_ogg_knee_table.md`. 32 kbit/s: 7.2 kHz.
- `model/goal2/ref.py`: float reference model (band-pass fc/2–fc, |x|, high-pass fc, low-pass 20 kHz,
  add with gain 1). Runs on the 32k decode with no clipping.
- ABX test (11 Nov): 14/16 correct on 20 s passages, p = 0.0021 (one listener, Sony WH-CH520,
  no EQ). See `test_audio/ABXtesting/README.md`.
- Blind preference test (11 Nov, 2 s clips): enhanced preferred 16/16, p ≈ 0.000015.
- ABX on the 2 s clips (11 Nov): 14/16, p = 0.0021; misses in bass-heavy passages.
  Log: `docs/goal2_observations.md`.

Next:
1. Hardware session today (11 Nov): `docs/hardware_testing_plan.md`, T0 to T3.
2. Treble RTL before the 12 Nov freeze, following `docs/goal2_rtl_plan.md`: fixed-point model
   first, then `rtl/treble_fixed.v` bit-exact against it, then `sim/tb_treble_fixed.v`.
3. Combined mode (music + ANC, switch 11) is a proposal in `docs/goal2_rtl_plan.md` §6. It changes
   A's FSM, mux, top and constraints, and touches B's and C's blocks, so agree it with them first.
4. Confirm the 32 kbit/s cutoff on a second clip, and choose the gain.

## Data path

```
Laptop: MP3 file (bytes unchanged)
  │ PS USB-UART, 230,400 baud (CY7C64225 → PS UART1, MIO 48/49, no RTS/CTS)
  ▼
ARM, bare-metal (Vitis 2020.x):
  UART RX interrupt → DDR ring buffer → MP3 decoder → AXI → PL   (48 kHz only; see Targets)
  ▼
PL: music_fifo (drained at sample_tick) → treble_fixed → music → out_mux (A) → I2S → headphones
```

Link budget: 230,400 baud ÷ 10 bits per byte = 23,040 bytes/s. A 56 kbps MP3 needs 7,000 bytes/s
(3.3× headroom); 128 kbps needs 16,000 (1.44×). Fallback 115,200 baud: 11,520 bytes/s.
Proof of on-board processing: the board outputs 48,000 × 2 × 2 = 192,000 bytes/s, about 8.3×
what the link can carry, and an A/B switch changes the sound live.

## Your files

| File | Function |
|---|---|
| `sw/sender/` | Laptop script: sends the MP3 with a length header and checksum |
| `sw/app/` | ARM: UART RX interrupt → ring buffer, decoder, resampler, AXI writes |
| `rtl/music_fifo.v` | AXI-written FIFO in the PL, read on `sample_tick`; `fifo_underrun` |
| `rtl/treble_fixed.v` | Stage 1: fixed-rule treble extension |
| `model/goal2/` | Fixed-point golden model of `treble_fixed` |
| `sim/tb_music_fifo.v`, `sim/tb_treble_fixed.v` | Testbenches |

## Week 1 — 31 Oct to 6 Nov

1. **Choose the bare-metal MP3 decoder library** (must build in Vitis 2020.x without an OS).
   Web-verify licence, build and memory needs before choosing.
2. **Sample rate: decided (9 Nov).** Resampling is done on the laptop with ffmpeg, not on the
   ARM. No ARM resampler is written. See Targets below.
3. UART receive: interrupt-driven (or DMA) into a DDR ring buffer; the hardware RX FIFO is small,
   so polling will drop bytes. Check the UART FIFO size in the Zynq TRM.
4. Laptop sender with framing; test zero byte loss over a whole file at 230,400 baud (checksum
   matches).
5. Decode on the ARM; compare PCM against a laptop decode of the same file.
6. `music_fifo` + AXI: the ARM fills it, the PL drains one sample per `sample_tick`.
7. **Exit (Fri 6 Nov):** an MP3 sent from the laptop plays unprocessed through the headphones
   (needs A's `i2s_tx`; until then, check in simulation and with an ILA).

## Week 2 — 7 to 12 Nov

1. Fixed-rule treble extension: find the cutoff fc, take the top octave below it, generate
   harmonics (rectifier) plus envelope-shaped noise above fc, high-pass at fc, add at a fixed
   gain, limit to 20 kHz.
2. Golden model in `model/goal2/`, then `treble_fixed.v` bit-exact against it.
3. A/B switch: plain vs enhanced, live.
4. **Exit (Thu 12 Nov):** fixed-rule extension playing on hardware.

## After the report (15–16 Nov), only if goal 1 and stage 1 both work

Smart guess (stage 2): per 5 ms frame, measure the level slope of 4 bands just below the cutoff,
continue it into 8 bands above the cutoff plus 8 learned offsets, copy texture up from the octave
below with an NCO, and gain each band to the predicted level. The float prototype beat the plain
MP3 by a wide margin, but it is not team code and needs a fixed-point model first.

## Targets (decided 9 Nov 2026)

- **Primary: 32 kbit/s MP3 at 48 kHz mono.** The lowest rate the 48 kHz MPEG-1 Layer III format
  allows. Cutoff is about 10 kHz (measured on the synthetic master and the OGG-derived Beethoven
  clip). The octave-below-cutoff rule fits this case: the 2nd harmonic of 5–10 kHz lands at 10–20 kHz.
- **Secondary: lower rates** (16–24 kbit/s, 24 kHz files resampled on the laptop). Cutoff drops to
  about 5–6 kHz, so the enhancement must rebuild about 2 octaves. Only after the primary target works.
- **Sample rate:** resampling is done on the laptop before sending, with
  `ffmpeg -i master -ar 48000 -ac 1 -b:a 32k out.mp3` (one encode, from the master). The sender's
  `--to48k` option re-encodes an existing MP3, which is a second lossy pass; use it for demos only.
  The board accepts only 48 kHz mono; no resampler on the ARM.
- **Claim:** the enhanced 32 kbit/s version is compared with the plain 32 kbit/s version. It is not
  compared with 128 kbit/s as a target; 128 kbit/s is only the ceiling reference.

## Claims for the report

Lost detail cannot be recovered: the board generates plausible treble, not the original. Claim
improvement over the plain MP3 (log-spectral distance to the master above the cutoff, plus a
blind listening test). Never "better than the master".

## First prompt for your AI agent

> Read `docs/plan/README.md` and `docs/plan/D-swarneel-goal2.md`. I am member D. I will write the
> code myself. Start by helping me compare bare-metal MP3 decoder libraries for Vitis 2020.x
> (web-verify each). Do not write `rtl/` or `sw/` files for me; review what I write.
