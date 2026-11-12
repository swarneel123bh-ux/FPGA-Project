# Goal 2 observations log

*Kept by Claude for the team (not team code). Dated measurements and listening results for goal 2.
Raw files: `test_audio/`. Method details: the README next to each test set.*

## Measurements

| Date | What | Result | Where |
|---|---|---|---|
| 9 Nov 2026 | Cutoff vs bitrate, Beethoven clip, 40 dB rule | 32k: 7.2 kHz; 40k: 8.7; 48k: 11.3; 56k: 13.6; 64k: 13.7; 96k: 15.7 kHz | `test_audio/beethoven5_ogg_knee_table.md` |
| 9 Nov 2026 | 32k cutoff by eye on the spectrogram | Edge near 6 kHz in quiet passages, 7–8 kHz in loud ones | `model/goal2/explore.py` plots |
| 9 Nov 2026 | Bandwidth at 24 kHz sample rate (synthetic master, resampled to 48 kHz) | 16k: about 5 kHz; 24k: about 6 kHz; 32k at 24 kHz: about 8 kHz (32k at 48 kHz: about 10 kHz) | session record; supports the 32 kbit/s at 48 kHz target |
| 9 Nov 2026 | Enhanced output (ref.py, FC 7.2 kHz, gain 1) on the 32k decode | Energy added at 8–20 kHz (about −5 to −20 dB vs −55 dB plain); 0 clipped samples | `build/enhanced_32k.*` (not in git) |

## Listening tests

| Date | Test | Material | Result | Setup |
|---|---|---|---|---|
| 9 Nov 2026 | Informal | Beethoven 56k vs 128k (Commons MP3 source) | No audible difference | Dubstep X3 earphones with eqMac; then Sony headphones |
| 9 Nov 2026 | Informal | Synthetic master vs 56k vs 128k | Hi-hats quieter at 56k; audible | Same |
| 11 Nov 2026 | ABX, blind X (`abx.py`) | 16 × 20 s passages, plain vs enhanced, 32k, level-matched | **14/16 correct, p = 0.0021** | Swarneel; Sony WH-CH520, no EQ |
| 11 Nov 2026 | Blind preference (`pref.py short_2s`) | 16 × 2 s clips from the same passages | **Enhanced preferred 16/16, p = 1/65,536 ≈ 0.000015** | Same |
| 11 Nov 2026 | ABX, blind X (`abx.py short_2s`) | Same 16 × 2 s clips | **14/16 correct, p = 0.0021**; missed excerpts 12 and 05 | Same |

Listener notes (11 Nov):
- The difference was clear in most passages and harder in bass-heavy or noisy ones (coughs, page
  turns). Expected: the added treble is built from the fc/2–fc band, which carries little energy there.
- 20 s passages felt too long to remember A by the time X played. The ABX on 2 s clips scored the
  same (14/16), so clip length did not change ABX accuracy.
- The listener heard all four ABX misses (20 s: excerpts 09 and 13; 2 s: excerpts 05 and 12) as
  bass-heavy passages.

Check of the bass-heavy explanation (share of energy in the 3.6–7.2 kHz band the enhancement builds
from, Welch spectrum of the plain clip, 11 Nov):
- Excerpt 12 has the lowest share of all 16 clips (−42.7 dB on 2 s; −39.2 dB on 20 s): little for the
  enhancement to work with, which fits the miss.
- Excerpts 05, 09 and 13 are mid-ranked (9th, 10th and 8th of 16), so band energy does not explain
  those misses.
- The music is bass-dominated throughout (energy below 500 Hz is within 4.2 dB of the total in every
  clip), so "bass-heavy" does not separate the missed clips by that measure.

Limits for the report: one listener, one headset, one piece of music (16 passages of one movement).
The claim is "preferred over the plain 32 kbit/s file in a blind test", not "as good as the original".

## 12 Nov 2026: hiss on strummed guitar, and a gate experiment

*Claude's log (not team code). Experiment script: `model/goal2/exp_hiss_gate.py` (float, offline).*

**Problem (from the 12 Nov board run, "Stairway to Heaven"):** with the original tuning (fc 7.2 kHz,
gain 1, SW5 and SW6 down), the added treble gives jingle and hiss on strummed guitar. The 12 Nov
retune (SW6 up) reduces it but dulls the voice. Swarneel's blind-test result (12 Nov): listeners prefer
SW2 and SW3 up (−6 and −12 dB, −18 dB volume), SW4, SW5 and SW6 down (original parameters). So the
enhancement stays at the original parameters and the algorithm's own noise is removed.

**Blind-test setting for the report:** SW2 up, SW3 up, SW4 down, SW5 down, SW6 down.

**Experiment (Beethoven 20 s, 32k vs 128k reference, original parameters):**

| Variant | LSD above fc (dB, lower = closer to 128k) | Added energy 7.2–20 kHz in quietest 20% of frames (dB re FS) |
|---|---|---|
| Plain 32k | 22.22 | −200 (nothing added) |
| V0 original | 18.56 | −90.6 |
| V1 envelope gate, T = −70 dBFS (open 96%) | 18.62 | −90.6 |
| V1 envelope gate, T = −60 dBFS (open 90%) | 18.72 | −90.7 |
| V1 envelope gate, T = −50 dBFS (open 74%) | 18.74 | −91.0 |
| V1 envelope gate, T = −40 dBFS (open 39%) | 18.23 | −95.2 |
| V2 Wiener gate on added treble (offline floor) | 18.63 | −90.7 |

**Reading:**
- The original enhancement closes about 3.7 dB of the LSD gap to the 128k decode, on this clip.
- A gate with a fixed threshold removes hiss in quiet frames only at a threshold that also closes
  39% of the time. At that setting the gate removes about 4.6 dB of added energy in the quiet frames
  and lowers LSD slightly (18.23), so there is a small gain without a loss of treble in loud parts
  on this clip. At the milder thresholds it does nothing useful.
- The Wiener gate does nothing measurable here. The noise floor estimate is offline and per-bin
  (10th percentile over the file), so this is an upper bound on what a real-time version could do.
- **Not tested:** strums. This clip is orchestral and has no strum passage. The hiss in the 12 Nov
  report is the case that matters. Need a strum recording (the Stairway excerpt, or another clip with
  guitar strums) before any of this is judged for the hiss problem.
- LSD and the gap metric are objective proxies, defined in `exp_hiss_gate.py`. They are not listening
  results; a blind test on strum material is the judge.

### Synthetic strum set (12 Nov, `test_audio/strum_synth/`, 2 s, not team code)

No strum recording is in the repo, and the Stairway clip is not in the repo either. So this set is
made: four open-string strums of E minor (Karplus-Strong plucks, 12 ms string spacing, 0.5 s apart),
encoded to 32k (plain) and 128k (reference). It tests the same event, a fast strum over ringing
strings, not the song. Generator: `make_strum_clips.py`.

| Variant | LSD above fc (dB) | Added energy in quietest 20% of frames (dB re FS) |
|---|---|---|
| Plain 32k | 37.30 | nothing added |
| V0 original | 32.21 | −75.2 |
| V1 gate, T = −40 dBFS (open 100%) | 32.20 | −75.2 |
| V1 gate, T = −30 dBFS (open 83%) | 30.18 | −77.8 |
| V1 gate, T = −20 dBFS (open 37%) | **23.63** | −106.7 |
| V1 gate, T = −10 dBFS (open 0%) | 29.00 | nothing added |
| V2 Wiener (offline floor) | 31.38 | −76.0 |

**Reading (provisional):**
- On the strum set the original adds far more energy than the 128k reference has in the quiet
  frames, and a gate near −20 dBFS cuts it by about 31 dB and lowers LSD from 32.2 to 23.6 dB.
  That is a much larger effect than on Beethoven, and it is the direction the hiss problem needs.
- The result is very sensitive to the threshold: −30 dBFS gives 30.2 dB and −10 dBFS gives 29.0 dB.
  A fixed dBFS threshold depends on the file's level. A usable version needs a threshold relative to
  the signal's own level (or an adaptive one), and that is not yet tested.
- LSD on 2 s of synthetic strums is a weak proxy. The 128k reference is not a true master, and the
  quiet frames here are the ringing decay, not hiss. **Only a blind listening test on strum material
  can say whether the gated version sounds better.**
