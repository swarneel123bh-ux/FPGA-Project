# Member D — Swarneel Bhattacharjee: goal 2, compressed-audio enhancement

Read [README.md](README.md) first (goals, schedule, interface table §5, agent rules §9).

**Your role:** goal 2 is best-effort; goal 1 comes first for the team. Your path is independent
of ANC until week 2, when it plugs into A's output mux as `music` (MUSIC state).

## Data path

```
Laptop: MP3 file (bytes unchanged)
  │ PS USB-UART, 230,400 baud (CY7C64225 → PS UART1, MIO 48/49, no RTS/CTS)
  ▼
ARM, bare-metal (Vitis 2020.x):
  UART RX interrupt → DDR ring buffer → MP3 decoder → 44.1 → 48 kHz (open) → AXI → PL
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
2. **Decide 44.1 vs 48 kHz:** resample on the ARM to 48 kHz, or reconfigure the codec in music
   mode. Resampling keeps the codec at 48 kHz everywhere (A's preference; ask).
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

## Claims for the report

Lost detail cannot be recovered: the board generates plausible treble, not the original. Claim
improvement over the plain MP3 (log-spectral distance to the master above the cutoff, plus a
blind listening test). Never "better than the master".

## First prompt for your AI agent

> Read `docs/plan/README.md` and `docs/plan/D-swarneel-goal2.md`. I am member D. I will write the
> code myself. Start by helping me compare bare-metal MP3 decoder libraries for Vitis 2020.x
> (web-verify each). Do not write `rtl/` or `sw/` files for me; review what I write.
