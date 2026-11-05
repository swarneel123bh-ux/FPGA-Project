# Test audio

Small MP3s for testing the goal-2 path (laptop → UART → ARM decode). Both are **48 kHz mono**, the
only format the board accepts, and 20 s long.

| File | Bytes | `fnv1a(mp3)` | `res.frame_count` | `res.samples_per_channel` | `res.checksum` |
|---|---|---|---|---|---|
| `beethoven5_20s_48k_mono_56k.mp3`  | 140,516 | `0x6bbdb72d` | 836 | 963,072 | `0xb5f37fd1` |
| `beethoven5_20s_48k_mono_128k.mp3` | 321,068 | `0xab66f6d3` | 836 | 963,072 | `0x1255d35c` |

The numbers come from the PC build of the decoder (`build/decode_pc <file> <out.raw>`, see
`instructions.md` §3) and are what the board must print for the same file. Both files have
`res.channel_count = 1` and `res.sample_rate = 48000`.

## Source and licence

- **Work:** Ludwig van Beethoven, Symphony No. 5 in C minor, Op. 67, iii. Allegro.
- **Recording:** from Musopen, via Wikimedia Commons:
  https://commons.wikimedia.org/wiki/File:Ludwig_van_Beethoven_-_symphony_no._5_in_c_minor,_op._67_-_iii._allegro.ogg
- **Licence:** public domain (Commons: "Public domain", copyrighted: no, attribution not required).
- **Downloaded:** 5 Nov 2026, Commons' MP3 transcode of that file (44.1 kHz stereo, 8,692,179 bytes,
  SHA-256 `426e2aa5e2b9a7a456feb8d81663ba8ca41bbf112d2ed288e749ec2a714326f4`). The full file is not
  stored here.

## How they were made

Seconds 20–40 of the download, converted with the ffmpeg bundled in `imageio-ffmpeg` 0.6.0
(`sw/sender/requirements.txt`):
```bash
ffmpeg -ss 20 -t 20 -i beethoven5_iii.mp3 -map_metadata -1 -ar 48000 -ac 1 -b:a 56k  beethoven5_20s_48k_mono_56k.mp3
ffmpeg -ss 20 -t 20 -i beethoven5_iii.mp3 -map_metadata -1 -ar 48000 -ac 1 -b:a 128k beethoven5_20s_48k_mono_128k.mp3
```

These files went through **two** lossy steps (the Commons transcode, then this one), so use them
for transfer and decode tests only, **not** for treble-restoration measurements. Those need a clip
encoded once from a lossless master (`instructions.md` §4).
