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
