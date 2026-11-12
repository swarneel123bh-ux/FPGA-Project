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

### Stairway A/B material (13 Nov, `model/goal2/make_stairway_ab.py`, not team code)

Source: the song file (`test_audio/stairway_source.mp3`, git-ignored, 128 kbit/s stereo 44.1 kHz,
483 s), decoded to 48 kHz mono. **Placeholder window 120–140 s**: the phrase timestamp was not known,
so the clip was not chosen by ear. Re-cut with `make_stairway_ab.py START LEN` once it is known.
Reference is the same clip encoded at 128 kbit/s, which is a second lossy pass (not lossless).

Quality judgement (the user's rule: total quality, not hiss alone): distance to the 128k reference,
full band and above fc, plus added energy in quiet frames as a hiss proxy.

| Variant | LSD full band (dB) | LSD above fc (dB) | Added energy, quiet frames (dB re FS) | Gate open |
|---|---|---|---|---|
| Plain 32k | 20.09 | 22.00 | none | — |
| **V0 original (SW5/SW6 down)** | **18.18** | **20.60** | −89.9 | — |
| V1 gate −50 dBFS | 18.56 | 20.79 | −90.3 | 63% |
| V1 gate −40 dBFS | 18.70 | 20.57 | −93.7 | 23% |
| V1 gate −30 dBFS | 19.60 | 21.40 | −109.3 | 1% |
| V2 Wiener gate (offline floor) | 18.14 | 20.51 | −90.0 | — |

**Reading:** the gate lowers the hiss proxy only where it also lowers total quality (−40 dBFS:
hiss −3.8 dB, LSD +0.5 dB). It is a trade, which the user rejects. The Wiener gate is neutral: no hiss
change, LSD unchanged within 0.04 dB. No variant so far passes the total-quality rule. The hiss
judgement is still the blind test on the real A/B files.

Files (git-ignored, in `test_audio/stairway/`): `plain_32k_s120_20s.wav`, `enhanced_32k_s120_20s.wav`
(original enhancement), plus the 48k master and the 32k and 128k MP3s.

### Stairway 30 s clip at 2:15 (13 Nov, user-supplied timestamp: first strums)

Clip 135–165 s, 30 s, same chain as above (`make_stairway_ab.py 135 30`). Files in `test_audio/stairway/`:
`plain_32k_s135_30s.wav`, `enhanced_32k_s135_30s.wav` (original enhancement), with the 128k reference
and the 48k master.

| Variant | LSD full band (dB) | LSD above fc (dB) | Hiss proxy (dB re FS) |
|---|---|---|---|
| Plain 32k | 23.22 | 25.44 | none |
| **Original enhancement** | **19.89** | **22.64** | −88.3 |
| Gate −40 dBFS (open 47%) | 19.77 | 21.93 | −91.2 |
| Gate −30 dBFS (open 6%) | 22.00 | 24.07 | −101.5 |
| Wiener (offline floor) | 19.83 | 22.50 | −88.4 |

**Reading:** on this clip the −40 dBFS gate is slightly better on both LSD measures and lowers the hiss
proxy by 2.9 dB. It is the first candidate that does not trade quality. But on the 20 s clip at 120 s the
same threshold made quality worse (full band 18.70 vs 18.18). The gate flips sign between clips, so this
is not a pass. Only the blind A/B on these 30 s files can decide, and the total quality must hold.

### Strum hiss: where it comes from, and an algorithmic candidate (13 Nov, not team code)

Listening (Swarneel, blind, 30 s from 2:15): plain A has no hiss, enhanced B sounds better overall, but
has a clear hiss at every guitar strum. The lab gain was judged larger. B was checked against the board's
fixed-point model (`ref_fixed.py`, tuning 0): it matches to within 1 LSB, so the algorithm is not the
difference from the lab.

Where the hiss is (B minus A, 150 ms after each strum onset vs between strums, 30 s clip, dB):
7.2–10 kHz +4.6 dB at onsets; 10–14 kHz +7.1 dB; 14–20 kHz +4.6 dB. The added treble follows the strums.

Candidate (no gate, same chain, fc 7.2 kHz, gain 1, SW5/SW6 down): the rectifier output is smoothed
by a one-pole low-pass before the high-pass (`model/goal2/exp_rect_smooth.py`).

| Rectifier LPF | LSD full, 30 s | LSD full, 20 s | Added 7.2–20 kHz, 30 s (dB re FS) |
|---|---|---|---|
| none (original) | 19.89 | 18.18 | −80.0 |
| 8 kHz | 15.73 | 14.37 | −83.6 |
| 4 kHz | 14.69 | 13.50 | −88.3 |
| **3 kHz** | **14.63** | **13.49** | −90.5 |
| 2 kHz | 14.89 | 13.78 | −93.8 |
| 1.5 kHz | 15.28 | 14.15 | −96.3 |

The 3 kHz candidate improves the full-band distance to the 128k reference on both clips, and it is not a
gate, so it does not trade treble away in loud parts. It also reduces the added energy at strums by about
10 dB. The distance is a proxy and the reference is itself a re-encode, so only the blind test decides.
Candidate file: `test_audio/stairway/enhanced_rect3000_s135_30s.wav`; blind pair (original vs rect3000)
in `build/stairway_blind2/`, key in `key_do_not_open_until_done.json`.

### Blind pair 2 result (13 Nov, Swarneel): rectifier smoothing rejected

Key: A = original, B = rect3000. Listening: A (original) overall better; B (3 kHz smoothing) worse
and still has the hiss. The hiss is present in both. The rect3000 candidate is rejected.

Lesson: the full-band LSD proxy improved by about 5 dB while the listening result got worse. The
LSD proxy is not reliable for this decision; listening decides.

Diagnostic file: `test_audio/stairway/added_only_original_s135_30s.wav`, the added treble alone (original
chain), scaled to −6 dBFS peak so it can be heard. It is not a playback candidate.

### Hiss character and octave copy-up candidate (13 Nov, not team code)

Listening to the added-only file (Swarneel): the hiss sounds like cicadas or tiny metallic jingles, louder
in step with each strum, dying a little between strums, plus a continuous baseline hiss from 0:14 onward.

Analysis (30 s clip): the 3.6–7.2 kHz source band is tonal (spectral flatness −22 dB during strums,
−25 dB between) and the added 7.2–20 kHz treble is peaky (top-10 peaks 23–25 dB above the median). The
rectifier turns the MP3's sparse tonal components into intermodulation products, which are inharmonic and
sound metallic. The 3 kHz smoothing did not change that, which fits the blind result.

Candidate (`model/goal2/exp_copyup.py`): octave copy-up by phase vocoder. The fc/2..fc band is shifted up by
×2, so partials map to partials (harmonic). Same chain otherwise (high-pass fc, low-pass 20 kHz, gain 1, SW5/SW6
down), level-matched to the rectifier chain (RMS equal). Three clipped samples in the 30 s file. The LSD proxy
is worse than the original (20.81 vs 19.92), and the proxy has already misled once, so listening decides.

Blind pair 3 (original vs copy-up): `build/stairway_blind3/`, key in `key_do_not_open_until_done.json`.
Candidate file: `test_audio/stairway/enhanced_copyup_s135_30s.wav`.

### Blind pair 3 result (13 Nov, Swarneel): octave copy-up rejected

Key: A = original, B = copy-up. Listening: A (original) sounds better overall; the metallic jingle is
still present in both. The copy-up candidate is rejected.

Consequence: the jingle survives a harmonic-preserving method. So the rectifier's intermodulation is not
the only cause. The source band is tonal (MP3 artifacts), and any method that builds treble from it copies
that tonality up. The next experiment needs to limit what is copied from the tonal artifacts, not change
the method. Still open.

### Where the strum hiss comes from (13 Nov, analysis of the loose note-harmonic candidate)

Strum windows = 150 ms after each detected strum onset (50 onsets, 30 s clip). Added energy = candidate minus plain.

- Added energy at strums is mostly OFF the note harmonics: 7.2–10 kHz is about 14 dB louder at strums than
  between strums on the off-harmonic bins (−38 vs −52 dB); only 14–16% of the added 7.2–20 kHz energy sits within
  ±1 bin of a detected harmonic.
- The synthesis itself produces this, before any filtering: with ±2 bins around the harmonics, 50% of the
  synthesised energy is on harmonic bins (±3 bins: 62%). So the phase-vocoder synthesis spreads energy
  off-harmonic, and most of that spread happens at strum attacks, where partials change amplitude and
  frequency fastest.
- The original chain's added energy is also off-harmonic at strums (by construction), so this is not specific
  to the note method. The note method adds fewer off-harmonic components in gaps (gap level −98 dB), but at
  strums its spreading is the likely hiss.

Working hypothesis: strum hiss = spectral splatter from fast amplitude/frequency change of the synthesised
partials at attacks. Test next: a longer analysis window (or amplitude smoothing across frames) for the
synthesis, and check whether the off-harmonic energy at strums falls. Not yet tested by ear.

Window-length test on the note synthesis (same clip, same strum windows, off-harmonic energy at strums, dB re FS):
N=2048 (current): 7.2–10 kHz −53.5, 10–20 kHz −61.8, on-harmonic share 48%.
N=4096: −57.5, −66.2, 35%. N=8192: −33.5, −29.5, 17% (much worse). Release 0.7 at N=2048: −48.2, −56.0.
Reading: N=4096 lowers the off-harmonic strum energy by about 4 dB, but that metric depends on mask width,
which changes with N, and the on-harmonic share also falls. Blind pair 9 (N=2048 vs N=4096) tests it by ear.

### Strum hiss on the second passage (13 Nov, loose note-only vs original)

Added energy at strum onsets (150 ms after onset) against between strums, dB re FS, same method as before:

| Passage | Variant | 7.2–10 kHz at strums | between | difference | 10–20 kHz difference |
|---|---|---|---|---|---|
| 1:00–1:30 | loose | −62.9 | −68.1 | +5.2 | +10.9 |
| 1:00–1:30 | original | −73.1 | −76.5 | +3.4 | +3.5 |
| 2:15–2:45 | loose | −58.0 | −71.9 | +14.0 | +8.3 |
| 2:15–2:45 | original | −73.0 | −77.7 | +4.7 | +7.3 |

Reading: the strum-linked added energy is present on the second passage too, with the same pattern, but about
5 dB lower in absolute terms than on 2:15. Listening (pair 13) has not checked strum hiss yet.

### Step 3 check and strum-synced hiss on passage 3 (6:40–7:10), 13 Nov

- Crossover: the note harmonics are already added only above the 7.2 kHz cutoff. Added energy below 7 kHz
  is −81 dB re FS (one-note version), so a blend above the cutoff would change nothing. Step 3 is in place.
- Strum link (one-note version, 51 strum onsets): added energy at strums minus between strums is −0.4 dB at
  7–10 kHz and −2.5 dB at 10–20 kHz (loose: −0.9 and −3.3). So the strum-synced hiss Swarneel hears in B is not
  extra added energy at strums.
- Next checks: (1) listen to the plain 32k file on passage 3 for the same strum-synced hiss, to see whether it is
  in the source; (2) if plain is clean, check how the added harmonic level follows strum loudness.

### Plain 32k on passage 3 (6:40–7:10): is the strum-synced hiss in the source? (13 Nov)

Plain (no enhancement), 51 strum onsets, strum window minus between-strum level:
- 7.2–10 kHz: +1.5 dB at strums (plain level −68 dB re FS).
- 10–20 kHz: −0.1 dB (plain level −132 dB, effectively nothing up there).

So the plain file has a small strum-linked rise at 7–10 kHz, but the 10–20 kHz hiss in the one-note version
(−71 dB) comes from the enhancement, not the source. The plain file was sent for listening: does the strum-synced
hiss appear without the enhancement?

Listening (13 Nov, Swarneel): the plain 32k file on passage 3 has a hiss too, the kind expected from a 32 kbit/s
file, always present. The rest of the song is loud enough that it isn't noticed. So part of the hiss heard in B is
the codec's own noise, not added by the enhancement. The added 10–20 kHz hiss is still the enhancement's
contribution, measured above. Going forward, judge the enhancement against the plain file's own noise floor.

### Bitrate set, passage 3 (13 Nov): can a better source be sent, and how does it score?

Link budget at 230,400 baud (10 bits per byte, 23,040 bytes/s), full song of 483 s:
- 32 kbit/s: 1.93 MB, 1.4 min, 5.8x headroom
- 48 kbit/s: 2.90 MB, 2.1 min, 3.8x headroom
- 64 kbit/s: 3.86 MB, 2.8 min, 2.9x headroom
- 96 kbit/s: 5.80 MB, 4.2 min, 1.9x headroom
- 128 kbit/s: 7.73 MB, 5.6 min, 1.4x headroom

So 128 kbit/s fits the link (1.4x headroom) and is about 4x the 32 kbit/s file. The project plan treats 32 kbit/s
as the target and 128 kbit/s as the ceiling reference, so sending 128 kbit/s changes the claim (it stops being
an enhancement project).

Blind scoring set (passage 3, 30 s, 6:40–7:10): 7 items numbered 1–7 in random order, key in
`build/bitrate_set_p3/key_do_not_open_until_done.json` (not opened). Items: original (master, 10/10 reference),
plain 32k, enhanced 32k (one-note), and 48, 64, 96, 128 kbit/s encodes. 30-second file sizes: 180 KB (48k),
240 KB (64k), 361 KB (96k), 481 KB (128k).
