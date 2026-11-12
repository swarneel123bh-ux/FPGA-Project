# Goal 2: current best enhancement (13 Nov 2026)

*Claude's write-up (not team code). Status: algorithmic, model only, offline. Not run on the board.*

## What it is

"Loose note-harmonic" enhancement: `model/goal2/exp_note_harmonics.py` with default settings
(detector threshold 25 dB, at least 4 partials, up to 2 notes per frame, no persistence gate, no release,
no attack shaping, copy law for levels, no source floor, 2048-sample window).

1. Find the notes in each 2048-sample frame (hop 512) with an FFT harmonic sieve over 80–1000 Hz, below the
   7.2 kHz cutoff. The strongest partials give the notes.
2. Add treble only at the harmonics of those notes, between 7.2 kHz and 14.4 kHz (the octave above the cutoff).
   Each added harmonic takes its level from its own partial one octave below in the same frame, and its phase
   from that partial by phase vocoder.
3. High-pass at 7.2 kHz, low-pass at 20 kHz, level-matched to the original enhancement in note frames.

The original enhancement (rectifier, fc 7.2 kHz, gain 1, SW5 and SW6 down) is the reference.

## Evidence (blind tests, Swarneel)

Passage 1: 2:15–2:45 (30 s). Passage 2: 1:00–1:30 (30 s). Same song, one listener, one headset.

| Pair | Passage | Compared | Result |
|---|---|---|---|
| 4 | 2:15 | Original vs note-only | Note-only preferred; original has much more hiss |
| 5 | 2:15 | Strict detector vs loose | Loose preferred; strict almost no enhancement, crackles |
| 6 | 2:15 | Loose vs loose + release | No difference; crackles gone in both; strum hiss in both |
| 7 | 2:15 | Loose vs persist-5 | Loose preferred; persist-5 almost no enhancement, odd crackle |
| 8 | 2:15 | Loose vs persist-3 | Loose preferred; persist-3 duller, hiss only slightly weaker |
| 9 | 2:15 | Window 2048 vs 4096 | No difference; strum hiss in both |
| 10 | 2:15 | Loose vs source floor 20 dB | Loose preferred; floor removes hiss and enhancement together |
| 11 | 2:15 | Loose vs decay law | Loose preferred; decay law hisses throughout |
| 12 | 2:15 | Loose vs attack 25 ms | No audible difference; strum hiss in both |
| 13 | 1:00 | Original vs loose | Loose preferred; original has hiss on single notes too, loose does not |

Rejected candidates, with evidence and verdicts, are in `docs/goal2_hiss_candidates.md`.

## Known problems

- **Strum hiss remains on passage 1 (2:15)** in every note-based variant. Analysis (`docs/goal2_observations.md`,
  13 Nov): at strum attacks, most added energy at 7.2–10 kHz is off the note harmonics, about 14 dB above the gaps.
  The synthesis alone spreads about half its energy off-harmonic.
- **Passage 2 (1:00–1:30): strum-linked energy is present** (7.2–10 kHz +5.2 dB at strums, 10–20 kHz +10.9 dB),
  about 5 dB lower in absolute terms than on passage 1. The re-listen of pair 13 did not report strum hiss,
  so this has not been confirmed by ear.
- **Loose detector.** Notes are found in 95% of frames on passage 1 and 87% on passage 2, so between-note gaps
  are not silent.
- **Level-matching** uses the original's added energy in note frames, so the level is tied to the old method.
- **Offline only.** Note detection uses two frames of look-ahead (only in the persistence variants, not this one),
  and the synthesis window is 2048 samples (about 43 ms). A real-time version needs a causal detector and a
  latency budget.
- **Two passages of one song.** Not tested on other songs or other instruments.

## Files

- Code: `model/goal2/exp_note_harmonics.py` (current best, default settings), `model/goal2/exp_hiss_gate.py`,
  `model/goal2/exp_copyup.py`, `model/goal2/exp_rect_smooth.py`, `model/goal2/make_stairway_ab.py`.
- Audio (git-ignored): `test_audio/stairway/` (plain 32k, 128k reference and enhanced files for both passages).
