# Member B — Aadyant Lahiri: ANC golden model and FxLMS controller

Read [README.md](README.md) first (goals, schedule, interface table §5, algorithm §6, agent
rules §9).

**Your role:** you own the maths. Your golden model fixes the numbers everyone else builds to
(filter lengths, step sizes, word lengths), and it is the reference that C's and your RTL are
checked against bit for bit. The simulation marks mostly come from your convergence plot.

## Your files

| File | Function |
|---|---|
| `model/anc/fixed.py` | Fixed-point helpers (saturate, round, Q-format multiply) shared with C |
| `model/anc/paths.py` | Primary path P and secondary path S as FIR filters (synthetic first, measured later) |
| `model/anc/fxlms.py` | FxLMS controller, bit-true to the RTL |
| `model/anc/sim_anc.py` | Closed loop: tone through P, anti-noise through S, plots e(n) and dB reduction |
| `model/anc/gen_vectors.py` | Writes `sim/vectors/fxlms_*.hex` |
| `rtl/fxlms.v` | Control filter W, filtered reference x', weight update (README §6) |
| `sim/tb_fxlms.v` | Bit-exact testbench against the vectors |
| `sim/tb_anc_loop.v` | Headline sim: RTL `fxlms` + C's `sec_path_id` against modelled paths |

## Week 1 — 31 Oct to 6 Nov

1. **Sat–Sun: floating-point model first.** Tone of 200 Hz (+ a little white noise) at the
   reference mic; P and S as short FIR filters with a few samples of delay; ŝ = S exactly.
   Show e(n) decaying. Then make ŝ slightly wrong and see how much error it tolerates.
2. **By Tue 3 Nov: fixed-point model and the numbers.** Choose and write into README §5/§6:
   - L (control filter length) and M (path model length); start at L = 64, M = 128.
   - μ and μₛ, as powers of two so the RTL multiplies by shifting.
   - Word lengths: sample (24-bit in), weights, ŝ, accumulators, and where you round or saturate.
   - Weight limit for `w_over` and an error-power limit for C's divergence monitor.
   Agree the ŝ format with C.
3. `fxlms.v`: one sample per `sample_tick`, time-shared MACs are fine (2,083 cycles available,
   about L + M + L = 256 MACs needed). Read ŝ from C's RAM through `shat_addr`/`shat_data`
   (1-cycle latency).
4. **Exit (Fri 6 Nov):** `tb_fxlms` passes bit-exact; the closed-loop model shows convergence
   with your chosen numbers.

## Week 2 — 7 to 12 Nov

1. `tb_anc_loop.v`: RTL controller + C's path ID + modelled paths. Plot convergence and
   steady-state attenuation from the sim output. **This is the main simulation result.**
2. With A and C on hardware: replace the synthetic S with the one measured by path ID; tune μ.
   Update the model with A's measured latency.
3. Divergence: check `w_over` triggers MUTE before the output clips.

## Weeks 3–5

Report sections on the algorithm and the simulation results (convergence curve, attenuation in
dB); viva prep.

## Things to watch

- The sign: with e = d + S·y, the update is w ← w − μ·e·x'. A sign error makes it diverge
  instantly; the model catches this before hardware does.
- The total delay (pipeline + codec + air) is inside the secondary path; ŝ must be long enough
  (M) to cover it. A's latency measurement tells you if M = 128 is enough (128 samples ≈ 2.7 ms).
- μ too large → divergence; too small → slow convergence. Normalised LMS is a possible extension;
  agree with the team before adding it.

## First prompt for your AI agent

> Read `docs/plan/README.md` and `docs/plan/B-aadyant-fxlms.md`. I am member B. I will write the
> golden model and RTL myself. Start by explaining FxLMS step by step and help me check my
> floating-point Python model as I write it. Do not write `model/` or `rtl/` files for me;
> review what I write.
