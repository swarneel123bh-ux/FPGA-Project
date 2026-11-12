# Goal 2: findings, grades and next steps (13 Nov 2026)

*Claude's summary (not team code). Written for Swarneel and the team. Every number here comes from the logs
named below. Listening results are Swarneel's blind tests (one listener, one headset). Nothing has run on the
board for the new methods.*

## 1. The goal, as Swarneel states it

The enhancement runs on the board. The file sent over the UART is plain MP3, and the board's output should sound
as close to the original as possible, using a smaller file. The enhanced output should score higher than the
plain file at the same bitrate.

## 2. What the grades say (passage 3, 6:40–7:10, 30 s; one listener)

Original = 10. Each bitrate was graded plain and enhanced (enhancement = note-harmonic method, one note per frame,
offline model in Python, cutoff set per bitrate).

| Bitrate | Plain | Enhanced | Enhancement effect | Whole-song size | UART time |
|---|---|---|---|---|---|
| 32 kbit/s | 4 | 4.9 | +0.9 | 1.93 MB | 1.4 min |
| 48 kbit/s | 7 | 8 | +1.0 | 2.90 MB | 2.1 min |
| 52 kbit/s | 8.5 | 8 | −0.5 | 3.14 MB | 2.3 min |
| 56 kbit/s | 9.4 | 9.5 | +0.1 | 3.38 MB | 2.4 min |
| 64 kbit/s | 10 | 9.5 | −0.5 | 3.86 MB | 2.8 min |
| 96 kbit/s | 10 | 9.5 | −0.5 | 5.80 MB | 4.2 min |
| 128 kbit/s | 10 | 10 | 0 | 7.73 MB | 5.6 min |

Points to keep:
- Enhancement helps at 32 and 48 kbit/s (about +1 point). At 52 kbit/s and above it does not help, and at 64 and
  above it costs about half a point.
- Plain 64 kbit/s is the smallest file that scores 10. Plain 48 kbit/s scores 7.
- Every score from 8 to just under 10 has drum cymbals merging into one sound. It is present at 56 kbit/s and below,
  both plain and enhanced, and absent at 64 kbit/s and above. The original WAV does not show it.
- The link carries up to 128 kbit/s (1.44× headroom at 230,400 baud). Whole-song sizes assume 483 s and no protocol
  overhead.

Sources: `docs/goal2_observations.md` (section "Full grading set"), `build/bitrate_set_p3/full/` (key-hidden
set; the key was opened only after grading).

## 3. Enhancement in the board's current design

- The board's current enhancement is the **rectifier** chain (`rtl/treble_fixed.v`, `rtl/treble_coefs.mem`), tuned
  for the 7.2 kHz cutoff of 32 kbit/s, and bit-exact with `model/goal2/ref_fixed.py` (tuning 0).
- The 8/10 result at 48 kbit/s comes from the **note-harmonic** method, an offline float model
  (`model/goal2/exp_note_harmonics.py`). The board does **not** run that method.
- The rectifier at 32 kbit/s scored 4/10 in grading, against 2/10 plain. Its 48 kbit/s version (cutoff 11.5 kHz)
  has not been modelled or graded.

## 4. Strum and passage hiss: what was tried (all rejected unless marked)

Full table with evidence and verdicts: `docs/goal2_hiss_candidates.md` (candidates 1–19). Summary:

- Retune (fc 9 kHz, shelf, gain −8): less hiss, duller voice (rejected by Swarneel).
- Envelope gate on the added treble: cuts hiss only by cutting treble (rejected).
- Wiener gate: no audible hiss change (rejected).
- Rectifier smoothed at 3 kHz: LSD proxy improved by about 5 dB, but listening was worse (rejected).
- Octave copy-up (phase vocoder): jingle still in both (rejected).
- Note-only harmonics, loose detector: preferred over the original on passages 1 and 2 (the current best).
- Strict detector, persistence gates (5 and 3 frames), source-strength floor, decay law, attack shaping, window
  length 4096, level smoothing: each rejected or no audible change.
- One note per frame (`NOTE_MAX=1`): much better than the original on passage 3 (continuous hiss removed; a slight
  periodic hiss synced with strums remains).

## 5. Analysis of the strum hiss (not solved)

- At strum attacks, most of the added 7.2–10 kHz energy lies off the note harmonics (about 14 dB above the gaps on
  passage 1). The synthesis itself spreads about half its energy off-harmonic.
- On passage 3, the one-note version adds no more energy at strums than between them (−0.4 dB at 7–10 kHz), so the
  strum-synced hiss is not extra added energy in that sense.
- The plain 32 kbit/s file has its own codec hiss, always present (Swarneel's listening). Judge the enhancement
  against the plain file's own noise floor, not against silence.

Sources: `docs/goal2_observations.md` (13 Nov sections).

## 6. Evidence quality and limits

- One listener, one headset, one song, three 30 s passages. Not tested on other songs or other instruments.
- The log-spectral distance proxy disagreed with listening twice (the 3 kHz smoothing and the copy-up candidate).
  It is not used for decisions.
- The 128 kbit/s reference is a second lossy pass from the song file (the song file is itself 128 kbit/s).
- The note-harmonic method is offline: it looks two frames ahead in the persistence variants, and uses a 2048-sample
  window (about 43 ms). A real-time version has not been written.
- The 48 and 52 kbit/s cutoffs were measured on passage 3 only (11.5 kHz and 15 kHz).

## 7. Proposed next steps (not started; in order)

1. **Model the rectifier at the 48 kbit/s cutoff (11.5 kHz)** on the 48 kbit/s file, and grade it blind against the
   note-harmonic 8/10 version. This is the cheapest way to know what the board's current chain can reach at 48 kbit/s.
   It needs only new coefficients (`design_sos` in `model/goal2/ref_fixed.py` with the new cutoff), not new RTL.
2. **Decide the board method:** if the rectifier at 11.5 kHz is not close to 8/10, the note-harmonic method has to run
   on the ARM. First check whether an ARM float implementation fits the time budget, and measure it.
3. **Causal version of the note-harmonic method** (no look-ahead), with the latency measured. The current detector
   uses two frames of look-ahead only in the persistence variants; the one-note version used in grading is causal in
   its detector but its output is still computed offline.
4. **Second and third songs or passages** at 48 kbit/s (plain and enhanced), graded against the original. Current
   evidence is one song.
5. **Strum hiss:** test whether the plain file's codec hiss accounts for what remains on passage 3, judged against
   the plain file's noise floor; then decide if any further work on strum hiss is worth the time before 19 Nov.
6. **Board test (lab only, after the model is settled):** the send path at 48 or 56 kbit/s (sender, decoder, FIFO,
   streaming playback) and the enhancement output versus the model file. Encode from the master at 48 kHz mono in one
   ffmpeg pass, so the board never sees a second lossy encode.

## 8. Files and commits

- Logs: `docs/goal2_observations.md` (dated measurements and listening), `docs/goal2_hiss_candidates.md` (every
  candidate with verdict), `docs/goal2_current_best.md` (write-up of the current best, with the judging rule).
- Experiment code (not team code, in `model/goal2/`): `exp_hiss_gate.py`, `exp_rect_smooth.py`, `exp_copyup.py`,
  `exp_note_harmonics.py`, `make_stairway_ab.py`. Synthetic strum set: `test_audio/strum_synth/make_strum_clips.py`.
- Recent commits on `claude/guitar-hissing-reduction-2f2a5c` (based on `origin/d/goal2`, 39d2a76): 0596629 (gate
  experiment), 5d72180 (findings file), 825f9d6 (note harmonics), 21b3400 (pair 4), 5effcfc (release option),
  f138081 and b7bf5de (strict detector, pair 5), e282467 and 4580f27 (persistence, pairs 7–8), a8eb140 (attack),
  aa925f3 (window), 01884aa, 255a54a and 99a7769 (source floor), ababdfa and 20b2f07 (decay law), 53365cb and 9503355
  (second passage), f3d8ed4 (write-up), 254ab7c and 8edbefc and a161eee (third passage), 83f611f (one note, pair 15),
  d82052e (revised write-up), 7caa703 and 3c114ce (smoothing, pair 16), b1e7745 and 469b7b5 (bitrate grading), ec8fddd
  (56k), 870a7d5 (sizes), 579aa07 (cutoff option), a22f346 (grades).
- Audio is git-ignored (`test_audio/stairway/`, `build/`), and so is the song file `test_audio/stairway_source.mp3`,
  which must stay out of git.
