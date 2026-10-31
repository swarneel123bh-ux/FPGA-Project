# Member C — Samarth Shreepad Dixit: path identification, measurement, OLED, test rig

Read [README.md](README.md) first (goals, schedule, interface table §5, algorithm §6, agent
rules §9).

**Your role:** FxLMS only works if it knows the secondary path (DAC → headphone driver → air →
error mic → ADC). You learn that path at start-up by playing white noise and adapting ŝ. You
also produce the number the demo is judged on: noise reduction in dB, on the OLED. And you
build the physical test rig.

## Your files

| File | Module | Function |
|---|---|---|
| `rtl/lfsr.v` | `lfsr` | Pseudo-random white noise `v_lfsr`, fixed amplitude |
| `rtl/sec_path_id.v` | `sec_path_id` | LMS that learns ŝ while `cal_en`; owns the ŝ RAM and gives B a read port |
| `rtl/power_meter.v` | `power_meter` | Error-mic power, averaged; stores the ANC-off level |
| `rtl/db_calc.v` | `db_calc` | 10·log10 of the ratio via log2 (leading-zero count + small LUT) → `nr_db` |
| `rtl/divergence_mon.v` | `divergence_mon` | `diverge` if error power above limit or B's `w_over` |
| `rtl/oled_display.v` | `oled_display` | Pmod OLED: mode and noise reduction in dB |
| `model/anc/path_id.py` | — | Path-ID golden model, using B's `model/anc/fixed.py` |
| `sim/tb_*.v` | — | Testbenches for each of the above |

## Week 1 — 31 Oct to 6 Nov

1. **Sat–Sun:** read README §6 step 4 (path identification). Pick an LFSR (e.g. a maximal-length
   polynomial of 23 bits or more, so it does not repeat audibly) and how to scale its output to
   a fixed amplitude.
2. `path_id.py` + `gen_vectors`: given a known synthetic S, show that ŝ converges to S. Agree
   with B **by Tue 3 Nov** on the ŝ word length, μₛ and M.
3. `lfsr.v`, `sec_path_id.v`, testbenches bit-exact against the vectors. The ŝ RAM needs two
   ports: your write/read port for adaptation and B's read port (`shat_addr` → `shat_data`,
   1-cycle latency).
4. **Acoustic rig:** over-ear headphones; error mic inside the cup close to the driver;
   reference mic outside the cup, between the noise source and the cup; noise source = a phone
   playing a 100–500 Hz tone or a small fan. Fix everything in place (tape or a stand) so
   measurements repeat. Photograph it for the report.
5. **Exit (Fri 6 Nov):** path ID bit-exact in simulation; rig built.

## Week 2 — 7 to 12 Nov

1. With A: path ID on hardware. Read ŝ back (ILA, or dump over UART with D's help) and check it
   looks like a delayed impulse response. Tune calibration time and μₛ.
2. `power_meter`, `db_calc`, `oled_display`: show "ANC ON −xx dB". Test the dB maths against
   Python for a range of ratios.
3. `divergence_mon` with the limits from B's model.
4. Measurement procedure for the report: tone on, ANC off for N seconds, ANC on for N seconds,
   at several frequencies (100, 200, 300, 500 Hz). Record the OLED reading and a phone SPL app
   reading as a cross-check.

## Weeks 3–5

Report sections on path identification, measurement method and results; viva prep.

## Things to watch

- Run path ID with the noise source off: the tone is uncorrelated with v(n) but slows and biases
  convergence.
- The LFSR level: loud enough to be well above the mic noise, quiet enough not to clip the error
  mic ADC.
- The dB number must be the measured error-mic power, ANC off vs on. Never claim "silence".

## First prompt for your AI agent

> Read `docs/plan/README.md` and `docs/plan/C-samarth-pathid-meter.md`. I am member C. I will
> write the RTL and model myself. Start by explaining LMS system identification with a white
> noise probe and how to pick an LFSR polynomial. Do not write `rtl/` or `model/` files for me;
> review what I write.
