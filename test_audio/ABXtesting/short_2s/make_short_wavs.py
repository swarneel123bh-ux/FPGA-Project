#!/usr/bin/env python3
# Not team code. Cuts 2 s clips from the 20 s ABX WAVs (seconds 9-11 of each passage, the middle,
# chosen without listening) and applies the same 10 ms fade-in/out to plain and enhanced.
# Run after ../make_abx_wavs.py:  python3 test_audio/ABXtesting/short_2s/make_short_wavs.py
import glob, os
import numpy as np
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
FS = 48000
START, LEN = 9 * FS, 2 * FS
FADE = int(0.010 * FS)
ramp = np.linspace(0.0, 1.0, FADE)

def cut(path):
    _, x = wavfile.read(path)
    y = x[START:START + LEN].astype(float)
    y[:FADE] *= ramp
    y[-FADE:] *= ramp[::-1]
    return np.round(y).astype("<i2")

plains = sorted(glob.glob(os.path.join(SRC, "excerpt_*_plain.wav")))
if not plains:
    raise SystemExit("run ../make_abx_wavs.py first")
for p in plains:
    stem = os.path.basename(p).replace("_plain.wav", "")
    e = p.replace("_plain.wav", "_enhanced.wav")
    wavfile.write(os.path.join(HERE, f"{stem}_plain.wav"), FS, cut(p))
    wavfile.write(os.path.join(HERE, f"{stem}_enhanced.wav"), FS, cut(e))
print(f"wrote {len(plains)} pairs of 2 s clips")
