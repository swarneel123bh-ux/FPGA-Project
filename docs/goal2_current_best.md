# Goal 2: current best enhancement (13 Nov 2026)

*Claude's write-up (not team code). Status: algorithmic, model only. Not run on the board. Strum hiss is
still present.*

## What it is

"Loose note-harmonic" enhancement, `model/goal2/exp_note_harmonics.py` with default settings
(detector threshold 25 dB, at least 4 partials, up to 2 notes per frame, no persistence gate, no release,
2048-sample window).

1. Find the notes in each 2048-sample frame (hop 512) with an FFT harmonic sieve over 80–1000 Hz, below
   the 7.2 kHz cutoff.
2. Add treble only at the harmonics of those notes between 7.2 kHz and 14.4 kHz (one octave above the
   cutoff). Each added harmonic is copied from the partial one octave below, by phase vocoder.
3. High-pass at 7.2 kHz, low-pass at 20 kHz, level-matched to the original enhancement in note frames.

The original enhancement (rectifier, fc 7.2 kHz, gain 1, SW5 and SW6 down) is kept as the reference.

## Evidence (blind tests, Swarneel)

| Pair | Compared | Result |
|---|---|---|
| 4 | Original vs note-only | Note-only preferred; original has much more hiss |
| 5 | Strict detector vs loose | Loose preferred; strict almost no enhancement, crackles |
| 6 | Loose vs loose + release | No difference; crackles gone in both; strum hiss in both |
| 7 | Loose vs persist-5 | Loose preferred; persist-5 almost no enhancement, odd crackle |
| 8 | Loose vs persist-3 | Loose preferred; persist-3 duller, hiss only slightly weaker |
| 9 | Loose 2048 vs 4096 window | No difference; strum hiss in both |

Rejected candidates, with evidence and verdicts, are in `docs/goal2_hiss_candidates.md`.

## Known problems

- **Strum hiss remains** in all note-based variants. Analysis (`docs/goal2_observations.md`, 13 Nov): at
  strum attacks, most added energy at 7.2–10 kHz is off the note harmonics (about 14 dB above the gaps).
  Synthesis alone spreads about half its energy off-harmonic.
- **Detector is loose.** Notes are found in 95% of frames, so between-note gaps are not silent.
- **Level-matching** uses the original's added energy in note frames, so the level is tied to the old method.
- **Offline only.** The detector looks two frames ahead (persistence) and the synthesis works frame by frame
  with a 2048-sample window (about 43 ms). Real-time use needs a causal version and a latency budget.
- **Not verified on other songs.** Only the 30-second clip from 2:15 of one song has been tested.

## Files

- Code: `model/goal2/exp_note_harmonics.py`, `model/goal2/exp_hiss_gate.py`, `model/goal2/exp_copyup.py`,
  `model/goal2/exp_rect_smooth.py`, `model/goal2/make_stairway_ab.py`.
- Audio (git-ignored): `test_audio/stairway/` (plain 32k, 128k reference, enhanced files).
