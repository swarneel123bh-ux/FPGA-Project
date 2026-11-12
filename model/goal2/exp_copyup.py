#!/usr/bin/env python3
# EXPERIMENT, NOT TEAM CODE (Claude, 13 Nov 2026). Replaces the rectifier with an octave copy-up:
# the fc/2..fc band is shifted up by a factor of 2 with a phase vocoder, so partials map onto
# partials (harmonic) instead of producing rectifier intermodulation (inharmonic, metallic).
# Otherwise the original chain: high-pass at fc, low-pass at 20 kHz, gain 1, SW5/SW6 down.
# Writes test_audio/stairway/enhanced_copyup_s135_30s.wav and a blind pair (original vs copy-up)
# in build/stairway_blind3/, key in key_do_not_open_until_done.json.
import json, os, random, shutil, sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import stft, istft
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exp_hiss_gate as e

N, H = 2048, 512
FC = e.FC
ROOT = e.ROOT

def octave_up(band):
    f_, t_, Z = stft(band, fs=e.FS, nperseg=N, noverlap=N - H, boundary=None, padded=False)
    K = Z.shape[0]
    out = np.zeros_like(Z)
    k = np.arange(K)
    lo, hi = int(FC / 2 / (e.FS / N)), int(FC / (e.FS / N))
    src = np.arange(lo, hi + 1)
    dst = 2 * src
    dst = dst[dst < K]; src = src[:len(dst)]
    prev = np.angle(Z[:, 0])
    ph = np.angle(Z[:, 0]).copy()
    for n in range(Z.shape[1]):
        cur = np.angle(Z[:, n])
        if n > 0:
            dev = np.angle(np.exp(1j * (cur - prev - 2 * np.pi * k * H / N)))
            w = 2 * np.pi * k * H / N + dev                  # true advance per hop, per bin
            ph[dst] = ph[dst] + 2 * w[src]                    # output bin 2k advances twice as fast
        prev = cur
        out[dst, n] = np.abs(Z[src, n]) * np.exp(1j * ph[dst])
    _, y = istft(out, fs=e.FS, nperseg=N, noverlap=N - H, boundary=False)
    res = np.zeros(len(band))
    m = min(len(band), len(y))
    res[:m] = y[:m]
    return res

def main():
    p = e.decode(os.path.join(ROOT, "test_audio/stairway/plain_32k_s135_30s.mp3"))
    band = e.ref.bandpass_octave(p, FC)
    up = octave_up(band)
    ref_add = e.ref.lowpass(e.ref.highpass(np.abs(band), FC), e.ref.LIMIT_HZ)
    added = e.ref.lowpass(e.ref.highpass(up, FC), e.ref.LIMIT_HZ)
    added *= np.sqrt(np.mean(ref_add ** 2) / np.mean(added ** 2))   # level-match to the rectifier chain
    y = np.clip(np.round(p + added), -32768, 32767).astype("<i2")
    cand = os.path.join(ROOT, "test_audio/stairway/enhanced_copyup_s135_30s.wav")
    wavfile.write(cand, e.FS, y)
    orig = os.path.join(ROOT, "test_audio/stairway/enhanced_32k_s135_30s.wav")
    d = os.path.join(ROOT, "build/stairway_blind3"); os.makedirs(d, exist_ok=True)
    pair = [("original", orig), ("copyup", cand)]
    random.SystemRandom().shuffle(pair)
    shutil.copy(pair[0][1], os.path.join(d, "A.wav")); shutil.copy(pair[1][1], os.path.join(d, "B.wav"))
    json.dump({"A": pair[0][0], "B": pair[1][0]}, open(os.path.join(d, "key_do_not_open_until_done.json"), "w"))
    print("candidate:", cand)
    print("added level, copy-up vs rectifier (dB):", round(20 * np.log10(np.sqrt(np.mean(added**2)) / np.sqrt(np.mean(e.ref.lowpass(e.ref.highpass(np.abs(band), FC), e.ref.LIMIT_HZ)**2))), 1))
    print("blind pair 3:", os.path.join(d, "A.wav"), os.path.join(d, "B.wav"))

if __name__ == "__main__":
    main()
