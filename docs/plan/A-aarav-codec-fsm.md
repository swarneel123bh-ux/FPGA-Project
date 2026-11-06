# Member A — Aarav Barnwal: codec, mode FSM, output mux, integration

Read [README.md](README.md) first (goals, schedule, interface table §5, agent rules §9).

**Your role:** everything else depends on you. Until both mics come in and the headphones play
out, nobody can test on hardware. You also own the top level and the `.xdc`, so you are the
integrator in week 2.

**Status (6 Nov):** `codec_cfg`, `i2s_rx`, `i2s_tx`, the temporary passthrough top, a week-1
constraint scaffold and their supplied simulations are merged into `main`. Vivado project
generation, hardware validation, the mode FSM, output mux and final integration remain pending.

## Your modules

| File | Module | Function |
|---|---|---|
| `rtl/codec_cfg.v` | `codec_cfg` | I2C master + ROM of register writes; configures the ADAU1761 at start-up |
| `rtl/i2s_rx.v` | `i2s_rx` | Deserialises left/right ADC samples → `x_ref`, `e_err`, `sample_tick` |
| `rtl/i2s_tx.v` | `i2s_tx` | Serialises `dac_out` to the DAC on the next `sample_tick` |
| `rtl/mode_fsm.v` | `mode_fsm` | CALIBRATE / CANCEL / BYPASS / MUTE / MUSIC (README §5) |
| `rtl/out_mux.v` | `out_mux` | Selects `v_lfsr`, `y_anti`, `music` or zero |
| `rtl/top.v` | `top` | Wires every block; switches, buttons, LEDs |
| `constraints/zedboard.xdc` | — | Pins and clocks |
| `sim/tb_*.v` | — | Testbenches for each of the above |

## Week 1 — 31 Oct to 6 Nov

1. **Sat–Sun:** read the ADAU1761 datasheet sections on the I2C control port, the clock
   generator (PLL), the record path (ADC, mic inputs, mic bias) and the playback path to the
   headphone output. Read the ZedBoard hardware user guide sections on the audio codec and
   jumper JP1. Useful reference: the TU Kaiserslautern ZedBoard audio interface document,
   <https://kluedo.ub.rptu.de/files/4034/zedboard_audio_doc.pdf>.
2. **By Mon 2 Nov:** finalise the interface table in README §5 (widths, reset polarity,
   `sample_tick` timing). Tell B, C and D.
3. **By Tue 3 Nov: decide how the second mic gets bias.** The ZedBoard's electret bias jumper JP1
   is documented as "Right Channel only", so a second electret mic needs bias from somewhere
   else. Options, in order of preference:
   1. ADAU1761 mic bias available to both channels (check the datasheet and the ZedBoard
      schematic).
   2. An external bias resistor and preamp feeding the blue line-in jack (both channels).
   3. The AD1 PMOD (two-channel ADC) for the second mic.
   4. Last resort: one-mic feedback ANC (needs B to change the algorithm; tell everyone early).
   Write the decision in README §3.
4. `codec_cfg`: the register sequence for 48 kHz, both ADC channels on, headphone DAC on.
   Testbench checks the I2C waveform (start, address, ACK slot, data, stop) for each write.
5. `i2s_rx` / `i2s_tx`: testbench with a behavioural I2S source/sink that sends known samples
   and checks they come back out unchanged.
6. **Exit (Fri 6 Nov):** on hardware, mic → headphones passthrough, *both* mics heard at the
   same time (e.g. left mic in the left ear, right mic in the right ear).

## Week 2 — 7 to 12 Nov

1. `mode_fsm` + `out_mux` + testbench that walks every state transition in README §5.
   Calibration duration is a parameter (start at about 5 s; C tunes it).
2. `top.v`: integrate C's `lfsr` + `sec_path_id`, then B's `fxlms`, then D's music path.
   Integrate one block at a time and test on hardware after each.
3. Switches and buttons: ANC on/off, mode select (ANC / music / bypass), recalibrate. LEDs: mode,
   divergence, FIFO underrun.
4. With B and C: first ANC run on hardware; measure the ADC-to-DAC latency (play a click, record
   it at the error mic) and give the number to B.

## Weeks 3–5

Report sections on the codec interface, FSM and integration; final ANC measurements on 15–16 Nov;
demo setup.

## Open questions you own

1. Two mics with bias at the same time (above).
2. The I2C start-up register sequence.
3. ADC-to-DAC latency of the ADAU1761 (datasheet first, then measure).
4. How the codec's master clock is produced on the ZedBoard (check the user guide/schematic).

## First prompt for your AI agent

> Read `docs/plan/README.md` and `docs/plan/A-aarav-codec-fsm.md`. I am member A. I will write
> the RTL myself. Start by helping me understand the ADAU1761 I2C register sequence I need for
> 48 kHz, two ADC channels and the headphone output, citing datasheet sections. Do not write
> `rtl/` files for me; review what I write.
