# Goal 2: hiss on strums, candidates already tried

*Claude's log (not team code), kept so we don't re-test a candidate we have already seen. Update it
whenever a candidate is tried. Evidence: `docs/goal2_observations.md` (dated entries) and the commits
named below. Listening results are Swarneel's blind tests unless marked otherwise.*

## The problem, as heard

- Original enhancement (fc 7.2 kHz, gain 1, SW5 and SW6 down) is the chosen setting. Blind tests prefer it
  overall; the total quality rule is Swarneel's: a fix that costs quality does not pass.
- Plain 32k has no hiss. The original enhancement is better overall but has hiss at every strum.
- The hiss sounds like cicadas or tiny metallic jingles (like a thin chain), louder in step with each strum,
  dying a little between strums. A continuous baseline hiss is also present from about 0:14 onward (30 s clip
  from 2:15).

## Facts established (not candidates)

- The fixed-point board model (tuning 0, `model/goal2/ref_fixed.py`) matches the float model used for the
  A/B files to within 1 LSB on the 30 s clip. The algorithm, not the model, makes the hiss.
- Added treble (B minus A) is 4.6 to 7.1 dB louder 150 ms after strum onsets than between strums, across
  7.2 to 20 kHz.
- The 3.6–7.2 kHz source band is tonal (spectral flatness about −22 dB during strums, −25 dB between). The
  added treble is peaky (top-10 peaks 23–25 dB above the median).
- The full-band distance to the 128 kbit/s re-encode (LSD proxy) disagreed with listening twice (candidates 4
  and 6 below). Do not use it to pick a candidate; listening decides.

## Candidates tried

| # | Candidate | Evidence | Verdict | Why |
|---|---|---|---|---|
| 1 | Retune: fc 9 kHz, shelf −6 dB above 11 kHz, gain −8 dB (SW6 up) | Board, 12 Nov | Rejected by Swarneel | Less hiss on strums but a duller voice; quality loss |
| 2 | SW5 −12 dB on the added treble | Board, 12 Nov | Off (Swarneel) | Quality loss |
| 3 | Envelope gate on the added treble, fixed threshold −70 to −10 dBFS | Model: synthetic strums (`exp_hiss_gate.py`, `test_audio/strum_synth/`), Beethoven 20 s, Stairway 20 s and 30 s | Rejected | Every threshold that cut the hiss also cut quality or was inconsistent between clips; a 30 s result at −40 dBFS (slightly better LSD) reversed on the 20 s clip |
| 4 | Offline Wiener gate on the added treble (10th-percentile noise floor per bin) | Model: Beethoven, Stairway 20 s and 30 s | Rejected | No measurable hiss change; not real-time anyway |
| 5 | Rectifier output smoothed by a 3 kHz one-pole before the high-pass | Model + blind pair 2 (`exp_rect_smooth.py`), commit `b36f0f2`, `193ff00` | Rejected | Full-band LSD improved by about 5 dB, but Swarneel heard it as worse overall and still hissing |
| 6 | Octave copy-up by phase vocoder (fc/2..fc shifted ×2, level-matched) | Blind pair 3 (`exp_copyup.py`), commit `e4c39c9`, `e7febb3` | Rejected | Original sounds better overall; the metallic jingle is still in both |

| 7 | Note-only harmonics (FFT harmonic sieve, treble only at note partials, copied from the octave below) | Blind pair 4 (`exp_note_harmonics.py`), commit `825f9d6` | **Preferred overall, first positive result**. Key: A = original, B = notes. Swarneel: hiss in both, A has much more, B liked overall | Loose detector: notes in 95% of frames, so gaps are not silent. Next: stricter detector (pair 5), rejected (row 8) |

| 8 | Note-only harmonics, strict detector (THR 15 dB, MINP 6; notes in 9% of frames) | Blind pair 5 (`NOTE_THR=15 NOTE_MINP=6`), commit `f138081` | Rejected. Key: A = strict, B = loose. Swarneel: almost no different from the non-enhanced version, plus strum hisses and random crackles mid-clip. Loose preferred | Too sparse: most of the enhancement is gone. The crackles suggest partials switching on and off abruptly between frames |

| 9 | Note-only (loose detector) with partial release over frames (NOTE_DECAY 0.7) | Blind pair 6, commit `5effcfc` | No audible difference from loose without release. Crackles gone in both; strum hiss still in both | Release fixed the crackles, but the strum hiss comes from elsewhere: likely strum transients detected as notes |

| 10 | Note-only, persistence gate 5 frames (about 50 ms; notes in 14% of frames) | Blind pair 7 (`NOTE_PERSIST=5`), commit `5f5f18b` | Rejected. Key: A = persist-5, B = loose. Swarneel: enhancement almost non-existent and an odd crackle in A; B preferred, still with strum hiss | Too aggressive: it removes most of the note harmonics |

| 11 | Note-only, persistence gate 3 frames (about 30 ms; notes in 29% of frames) | Blind pair 8 (`NOTE_PERSIST=3`), commit `e282467` | Rejected. Key: A = loose, B = persist-3. Swarneel prefers A: B sounds duller, hiss slightly weaker but so is everything else; crackle still there; strum hiss in both | Persistence gates trade treble for hiss and do not remove the strum hiss |

| 12 | Note-only, synthesis window 4096 samples (instead of 2048) | Blind pair 9 (`NOTE_N=4096`), commit `aa925f3` | No audible difference from 2048; both have the strum hiss. Off-harmonic energy at strums is about 4 dB lower on paper, but not audible | Window length is not the lever. 8192 is much worse on paper |

| 13 | Note-only, source-strength floor 20 dB (add a harmonic only if its source partial is within 20 dB of the frame peak) | Blind pair 10 (`NOTE_SRC_DB=20`), commit `255a54a` | Rejected. Key: A = src20, B = loose. Swarneel: src20 has almost no hiss but sounds practically the same as the non-enhanced version; loose keeps the hiss | Same trade as the gates: it removes the hiss by removing the enhancement |

| 14 | Note-only, decay law (harmonic level = fundamental × m^-1) instead of copying from the octave below | Blind pair 11 (`NOTE_LAW=decay`), commit `ababdfa` | Rejected. Key: A = decay law, B = loose. Swarneel: decay law has the hiss all through; loose has the hiss only at the strums; both sound like the enhanced version; loose preferred | The copy-from-the-octave-below level keeps the hiss confined to the strums |

| 15 | Note-only, attack shaping (25 ms fade-in of each added partial at onset) | Blind pair 12 (`NOTE_ATTACK_MS=25`), commit `a8eb140` | No audible difference from loose. Hiss at the strums in both | Attack speed is not the lever for the strum hiss |

| 16 | Loose note-only vs original, second passage (60–90 s of the song) | Blind pair 13 (`NOTE_SRC=s60_30s`), commit `53365cb` | Loose preferred largely. Key: A = original, B = loose. Original has a continuous underlying hiss (like speakers maxed out); loose does not | Robustness check: the loose version holds on a second passage of the same song. Re-listen (A = original, B = loose): prefers B; the original has hiss on single guitar notes too (like the mic overloaded), B does not |

| 17 | Loose note-only vs original, near the end of the song (6:40–7:10) | Blind pair 14 (`NOTE_SRC=s400_30s`), key A = original, B = loose | Swarneel: A (original) has a periodic hiss; B (loose) has a weird continuous hiss. Swarneel: neither is acceptable; B sounds too noisy, like an old FM radio, so A (original) is preferred | New problem: on this passage the loose version has a continuous hiss that the original does not have in the same form. Not yet resolved. Write-up on hold |

| 18 | Passage 3 (6:40–7:10): one-note harmonics (strongest note per frame only) vs original | Blind pair 15 (`NOTE_MAX=1`), commit `e86eb79`. Key: A = original, B = one-note | Swarneel: B is much better. B has a slight periodic hiss, synced with the strums; A (original) has a continuous, never-ending hiss. First candidate to work on passage 3 | Limiting the note count per frame fixes the continuous hiss on the loud, dense passage. Strum-synced hiss remains |

## What the candidates show together

- All persistence gates (5 and 3 frames) were rejected: they reduce the level of everything, so they trade quality for a small hiss reduction.
- Strum hiss remains in every note-based variant (loose, persist-3, persist-5). It is not removed by gating or by partial release.

- Methods that build the treble from the whole tonal source band (rectifier, smoothed rectifier, copy-up)
  all keep the jingle. The jingle survives a harmonic-preserving method, so the tonal MP3 artifacts of the
  source band are what get copied up.
- Gating by level (3, 4) removes hiss only by removing treble, which fails the quality rule.

## Next candidate (planned by Swarneel)

Add harmonics only for the actual notes, found with the FFT: detect the notes in each frame, and add treble only
at the harmonics of those notes (no treble between notes, so no baseline hiss). Harmonics are copied from the
partial one octave below, which keeps them on the note's harmonic series.
Status: built as `model/goal2/exp_note_harmonics.py` (30 s clip). Detector: 95% of frames have at least one note
(loose; between-note gaps are not silent), 2 notes in 36% of frames. Level-matched to the original in note frames
(−1.8 dB). Blind pair 4 in `build/stairway_blind4/`. Result (pair 4): the note-only version is preferred overall; the original has much more hiss. Next: stricter detector.
