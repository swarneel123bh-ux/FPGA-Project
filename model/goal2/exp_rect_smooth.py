#!/usr/bin/env python3
# EXPERIMENT, NOT TEAM CODE (Claude, 13 Nov 2026, at Swarneel's request). No gate: the added treble is
# the original chain (fc 7.2 kHz, gain 1, SW5/SW6 down) except that the rectifier output is smoothed by a
# one-pole low-pass (3 kHz) before the high-pass. Algorithmic test only; the board is not used.
#   usage: python3 model/goal2/exp_rect_smooth.py [LPF_HZ]   (default 3000)
# Writes test_audio/stairway/enhanced_rect<LPF>_s135_30s.wav and a blind pair in build/stairway_blind2/
# (A/B randomised, key in key_do_not_open_until_done.json).
import json, os, random, shutil, sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exp_hiss_gate as e

LPF = float(sys.argv[1]) if len(sys.argv) > 1 else 3000.0
ROOT = e.ROOT
TAG = "s135_30s"
plain = e.decode(os.path.join(ROOT, "test_audio/stairway/plain_32k_s135_30s.mp3"))
band = e.ref.bandpass_octave(plain, e.FC)
rect = sosfilt(butter(1, LPF, fs=e.FS, output="sos"), np.abs(band))
added = e.ref.lowpass(e.ref.highpass(rect, e.FC), e.ref.LIMIT_HZ)
out = np.clip(np.round(plain + added), -32768, 32767).astype("<i2")
cand = os.path.join(ROOT, f"test_audio/stairway/enhanced_rect{int(LPF)}_{TAG}.wav")
wavfile.write(cand, e.FS, out)

orig = os.path.join(ROOT, f"test_audio/stairway/enhanced_32k_{TAG}.wav")
d = os.path.join(ROOT, "build/stairway_blind2")
os.makedirs(d, exist_ok=True)
rng = random.SystemRandom()
pair = [("original", orig), (f"rect{int(LPF)}", cand)]
rng.shuffle(pair)
shutil.copy(pair[0][1], os.path.join(d, "A.wav"))
shutil.copy(pair[1][1], os.path.join(d, "B.wav"))
json.dump({"A": pair[0][0], "B": pair[1][0]}, open(os.path.join(d, "key_do_not_open_until_done.json"), "w"))
print("candidate:", cand)
print("blind pair:", os.path.join(d, "A.wav"), os.path.join(d, "B.wav"))
