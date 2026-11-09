#!/usr/bin/env python3
# Not team code. Rebuilds the ABX WAVs from the committed 32 kbit/s MP3 excerpts.
# Run from the repository root:  python3 test_audio/ABXtesting/make_abx_wavs.py
# Needs: numpy, scipy, imageio-ffmpeg (sw/sender/requirements.txt).
import glob, os, subprocess, sys
import numpy as np
from scipy.io import wavfile
import imageio_ffmpeg

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "model", "goal2"))
import ref  # the reference model: enhance(x, fc, gain)

FS = 48000
FC = 7200   # 32 kbit/s cutoff (40 dB rule), see test_audio/beethoven5_ogg_knee_table.md
GAIN = 1    # as decided

def decode_mp3(path):
    """Decode an MP3 to 48 kHz mono 16-bit PCM with ffmpeg."""
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    out = subprocess.run([ffmpeg, "-v", "error", "-i", path, "-ar", str(FS), "-ac", "1",
                          "-f", "s16le", "pipe:1"], capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype="<i2")

def main():
    mp3s = sorted(glob.glob(os.path.join(HERE, "excerpt_*_32k.mp3")))
    if not mp3s:
        sys.exit("no excerpt_*_32k.mp3 files found")
    for mp3 in mp3s:
        stem = os.path.basename(mp3).replace("_32k.mp3", "")
        plain = decode_mp3(mp3).astype(float)
        enh = ref.enhance(plain, FC, GAIN)
        level = np.sqrt(np.mean(plain**2)) / np.sqrt(np.mean(enh**2))   # loudness match
        enh = enh * level
        clipped = int(np.sum(np.abs(enh) > 32767))
        wavfile.write(os.path.join(HERE, f"{stem}_plain.wav"), FS,
                      np.clip(plain, -32768, 32767).astype("<i2"))
        wavfile.write(os.path.join(HERE, f"{stem}_enhanced.wav"), FS,
                      np.clip(enh, -32768, 32767).astype("<i2"))
        print(f"{stem}: level change {20*np.log10(level):+.2f} dB, clipped {clipped}")

if __name__ == "__main__":
    main()
