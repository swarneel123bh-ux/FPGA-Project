# ABX test: plain vs enhanced, 32 kbit/s (not team code)

Material: 16 non-overlapping 20 s passages from the Beethoven 5, 3rd movement (Commons source,
`../beethoven5_source_commons.ogg`). These are 16 different passages of one movement, not 16 pieces.

The WAVs are not in git (they are ignored, 60 MB). Rebuild them from the tracked MP3s:
```bash
python3 test_audio/ABXtesting/make_abx_wavs.py   # from the repository root
```
This decodes each `excerpt_NN_32k.mp3` with ffmpeg, applies `model/goal2/ref.py`, and writes
`_plain.wav` and `_enhanced.wav`.

Files per passage (`excerpt_NN_*.wav`, 48 kHz mono, 16-bit):
- `_plain.wav`: 32 kbit/s encode, decoded (the A reference).
- `_enhanced.wav`: same encode after `model/goal2/ref.py` (FC = 7200 Hz, GAIN = 1), loudness-matched
  to the plain file (the level difference is 0.0 dB, no clipping).

Run (macOS, headphones, volume fixed):
```bash
cd test_audio/ABXtesting
python3 abx.py
```
Each trial: A (plain) and B (enhanced) are known. X is randomly A or B and hidden. Listen as often as
you like, then guess. The script keeps the key in memory only and reveals the score at the end.
Scores: 12/16 or more gives p < 0.05, so the difference is real at that level.

## Results

| Date | Set | Test | Result | Listener and setup |
|---|---|---|---|---|
| 11 Nov 2026 | 20 s passages | ABX (`abx.py`) | 14/16 correct, p = 0.0021 | Swarneel; Sony WH-CH520, no EQ |
| 11 Nov 2026 | 2 s clips (`short_2s`) | Preference (`pref.py`) | enhanced preferred 16/16, p ≈ 0.000015 | Swarneel; Sony WH-CH520, no EQ |

Notes from the listener: the difference was clear in most passages, harder in bass-heavy or noisy ones
(coughs, page turns). 20 s was too long to remember A by the time X played. The listener also found the
enhanced version better; the blind preference test on 2 s clips confirmed it (16/16).
Full log: `docs/goal2_observations.md`.

## Short set (2 s clips) and preference test

`short_2s/` holds 2 s clips cut from the middle of each passage (seconds 9–11, chosen without
listening), with the same 10 ms fade on plain and enhanced. Rebuild them after the 20 s WAVs:
```bash
python3 test_audio/ABXtesting/short_2s/make_short_wavs.py
```
Run (from `test_audio/ABXtesting`):
```bash
python3 pref.py short_2s   # blind preference: which of "1" and "2" do you prefer?
python3 abx.py short_2s    # optional ABX re-run on the short clips
```
`pref.py` presents plain and enhanced as "1" and "2" in random order and prints how often the
enhanced version was preferred, with the chance probability. 12/16 or more gives p < 0.05.
