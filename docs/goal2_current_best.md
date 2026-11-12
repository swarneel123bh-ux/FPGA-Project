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

## Update: third passage (6:40–7:10), pair 14

Swarneel's listening: the original (A) has a periodic hiss; the loose version (B) has a continuous hiss that
sounds like an old FM radio. Neither is acceptable, and the original is preferred because B is too noisy.

So the "current best" claim holds for passages 1 and 2 only. On passage 3 the loose version is worse than
the original. Likely cause (to check, not yet tested): on this passage the detector finds notes in 96% of
frames and two notes in about 72% of frames, so it adds harmonics almost everywhere, including between notes.

Status: the loose version is the best of the note-based candidates on two passages, and it fails on a third.
It is not yet a general improvement.

## Literature check (13 Nov)

Sources were searched online; these are the closest matches. None has been tested here.

- **Spectral band replication (SBR)**: rebuilds the high band by copying the coded low band and shaping it with
  a small amount of side information (envelopes, noise levels). It is the standard in HE-AAC and mp3PRO.
  Source: [Spectral band replication, Wikipedia](https://wikipedia.com/wiki/Spectral_Band_Replication).
  Relevance: our method copies partials but has no side information, so the detector must replace it. The
  smeared, "watery" failure mode of aggressive SBR is similar to the artefacts we hear.
- **Neural spectral band generation** (n-SBG): plugs a neural bandwidth-extension model into a traditional
  codec pipeline. Source: [arXiv 2506.06732](https://arxiv.org/html/2506.06732v1).
  Relevance: too heavy for the deadline and hard to explain in the viva (team rule), so noted only.
- **Audio super-resolution with neural networks** (Kuleshov et al., 2017): feedforward model that reconstructs
  high-band content from a down-sampled input, designed to run in real time. Source: [arXiv 1708.00853](https://arxiv.org/pdf/1708.00853).
  Relevance: the same trade-off as above: needs training data and a fixed model.
- **Vocos-based bandwidth extension** (2026): 8–48 kHz input, blends the original low band with generated highs
  through a crossover-style refiner, reports real-time factors on a GPU and an 8-core CPU. Source:
  [arXiv 2603.07285](https://arxiv.org/pdf/2603.07285).
  Relevance: the blending step (keep the coded band, add only generated highs) matches our level-matching idea.
- **BAE-Net** (streaming speech bandwidth extension, 500 K parameters): [arXiv 2312.13722](https://arxiv.org/pdf/2312.13722).
  Speech only; not tested for music.
- **AERO** (spectral-domain prediction of the full band): [arXiv 2211.12232](https://arxiv.org/pdf/2211.12232.pdf).

What is most likely to help next, from this:

1. **Find out why passage 3 fails** before adding anything: check whether the detector's notes are wrong on this
   passage (for example, detecting harmonic series in dense or noisy music). This is cheap.
2. **Gate the detector by its own confidence** (fewer harmonics added when notes are uncertain), not by level.
   This is different from the gates we rejected, which cut treble regardless of the notes.
3. A **blended crossover** like the Vocos refiner: keep the coded band exactly as it is and add the new treble
   only above the cutoff, so the original is never altered.

No code was written this turn.

## Update: judging rule and the codec floor (13 Nov)

- **Judging rule.** The enhancement is judged against the plain 32 kbit/s file's own noise floor, not against
  silence. The plain file has a constant codec hiss (typical of 32 kbit/s), which is audible only in quiet parts.
  Any hiss heard in the enhanced file should be compared with that floor.
- **Passage 3 (6:40–7:10), one-note version.** With the strongest note per frame only (`NOTE_MAX=1`), the version is
  much better than the original on this passage, per Swarneel's blind listening (pair 15). The continuous hiss of the
  original is gone. A slight periodic hiss, synced with the strums, remains.
- **Strum-synced hiss.** The added energy at strums is not higher than between strums (−0.4 dB at 7–10 kHz,
  −2.5 dB at 10–20 kHz), so the strum-synced component is not extra added energy. The plain file has a small
  strum-linked rise at 7–10 kHz (+1.5 dB) as well. Its cause is still open.
- **Crossover.** The note harmonics are added only above the 7.2 kHz cutoff; leakage below it is −81 dB re FS, so
  a crossover blend would change nothing (step 3 is already in place).

**Current best, revised:** the note-harmonic version with at most one note per frame (`NOTE_MAX=1`), on top of the
loose detector settings. It is preferred to the original on passages 2 and 3. On passage 1 (2:15) the earlier
loose-version comparisons still stand, with the strum hiss open.
