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
