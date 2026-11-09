# Cutoff (knee) per bitrate: Beethoven 5, 3rd movement, seconds 20–40 (not team code)

Source clip: `beethoven5_ogg_reference_20s_48k_mono.wav`, encoded with ffmpeg at each rate
(`beethoven5_ogg_<rate>k.mp3`), decoded with `decode_pc`.

Method (the 40 dB rule): take the Welch power spectrum (4096-point segments, 48 kHz).
Passband level = median dB in 2–4 kHz. Cutoff = first frequency above 4 kHz where the level
is 40 dB below the passband level.

| Rate | Cutoff | Reach (2 × cutoff) |
|---|---|---|
| 32 kbit/s | 7.2 kHz | 14.4 kHz |
| 40 kbit/s | 8.7 kHz | 17.4 kHz |
| 48 kbit/s | 11.3 kHz | 20 kHz (limited by the 20 kHz low-pass) |
| 56 kbit/s | 13.6 kHz | 20 kHz (limited) |
| 64 kbit/s | 13.7 kHz | 20 kHz (limited) |
| 96 kbit/s | 15.7 kHz | 20 kHz (limited) |

Rejected criteria (kept for the record):
- Midpoint between passband and 15–16 kHz levels: not valid. Non-monotonic (64k gives 6.9 kHz),
  because the 15–16 kHz band still has content at 64k and above.
- 20 dB below passband: returns 5.4 kHz for every rate, because the level falls 20 dB just
  above 4 kHz.

Caveats: the 40 dB threshold is a definition chosen for this table, and it must be stated when
the numbers are quoted. One 20-second clip only. The 32k spectrogram edge looks closer to 8 kHz,
because the knee is steep. Real music will give different values.
