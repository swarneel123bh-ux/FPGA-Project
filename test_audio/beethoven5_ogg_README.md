# Beethoven 5, 3rd movement: encodes from the original Commons source (not team code)

Source: `beethoven5_source_commons.ogg`, Wikimedia Commons, public domain
(Musopen recording). Ogg Vorbis, stereo, 48 kHz, 5 min 36 s, about 138 kbit/s average.
This is the original upload, not the MP3 transcode used by the older `beethoven5_20s_*` files.

Clip: seconds 20–40, converted to 48 kHz mono PCM (`beethoven5_ogg_reference_20s_48k_mono.wav`).
Encodes: `beethoven5_ogg_<rate>k.mp3` (ffmpeg, `-ar 48000 -ac 1 -b:a <rate>k`), decoded with `decode_pc`.

The source is itself lossy, so every encode here is a second lossy step. Treat these files as
listening and bandwidth references, not as a lossless master.

Bandwidth vs the reference clip (average dB difference per band; 0 = same as reference):

| Rate | Bytes | 20 dB-down point | 8–10k | 10–12k | 12–14k | 14–16k | 16–18k | 18–20k |
|---|---|---|---|---|---|---|---|---|
| 32k | 80,396 | 10.0 kHz | −33.0 | −34.4 | −32.7 | −29.7 | −0.6 | 0.0 |
| 40k | 100,436 | 10.5 kHz | −6.8 | −27.2 | −32.7 | −29.7 | −0.6 | 0.0 |
| 48k | 120,476 | 11.3 kHz | −1.5 | −13.4 | −32.7 | −29.7 | −0.6 | 0.0 |
| 56k | 140,516 | 13.8 kHz | −0.4 | −1.0 | −4.7 | −28.1 | −0.6 | 0.0 |
| 64k | 160,556 | 14.3 kHz | −0.1 | −0.0 | −1.2 | −12.5 | −0.6 | 0.0 |
| 96k | 240,812 | none | −0.0 | 0.2 | 0.1 | −0.2 | −0.0 | 0.0 |
| 128k | 321,068 | none | −0.3 | −0.2 | −0.1 | −0.2 | 0.1 | 0.1 |

The reference itself has little content above about 16 kHz, so the 16–20 kHz columns barely move.
`beethoven5_ogg_compare.py` reproduces this table. It expects `clip_20s_48k_mono.wav` and `dec_<rate>k.raw` (decoder output) in the working folder, so it is a record of the method rather than a turnkey script.

The reference WAV is not in git (WAVs are ignored). Rebuild it from the source with:
```bash
ffmpeg -ss 20 -t 20 -i test_audio/beethoven5_source_commons.ogg -ar 48000 -ac 1 -c:a pcm_s16le test_audio/beethoven5_ogg_reference_20s_48k_mono.wav
```
