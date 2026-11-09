# Bitrate sweep: synthetic master, 48 kHz mono, 20 s (not team code)

Source: `master_treble_48k_mono.wav` (synthetic; hi-hat noise up to 24 kHz).
Encoder: ffmpeg `-ar 48000 -ac 1 -b:a <rate>k`. Decoder: team `decode_pc`.
"20 dB-down point" = first frequency above 10 kHz where the decoded file is 20 dB below the master.
Values per band are the average dB difference from the master (0 = unchanged).

| Rate | Bytes | 20 dB-down point | 10–12 | 12–14 | 14–16 | 16–18 | 18–20 | 20–22 kHz |
|---|---|---|---|---|---|---|---|---|
| 32k  | 80,396  | 10.0 kHz | −72.7 | −72.7 | −73.0 | −72.7 | −72.8 | −72.7 |
| 40k  | 100,436 | 10.7 kHz | −44.2 | −72.7 | −72.9 | −72.7 | −72.9 | −72.7 |
| 48k  | 120,476 | 11.4 kHz | −17.1 | −72.6 | −72.9 | −72.7 | −72.8 | −72.7 |
| 56k  | 140,516 | 15.2 kHz | −0.8 | −1.9 | −27.1 | −72.7 | −72.8 | −72.7 |
| 64k  | 160,556 | 16.6 kHz | −0.0 | −0.7 | −1.6 | −44.8 | −72.8 | −72.7 |
| 96k  | 240,812 | 20.4 kHz | 0.0 | 0.0 | −0.0 | −0.1 | −0.2 | −51.9 |
| 128k | 321,068 | 20.4 kHz | −0.3 | −0.2 | −0.2 | −0.4 | −0.4 | −52.5 |

Notes
- The encoder's bandwidth follows the bitrate. Below 56k, the loss starts near 10–11 kHz.
- 32 kbit/s is the lowest valid rate at 48 kHz (MPEG-1 Layer III). Lower rates would need a 24 kHz file resampled on the ARM.
- The decoder reports `bitrate_kbps` for each frame (`sw/app/minimp3.h`), so the board can pick the cutoff from the file.
