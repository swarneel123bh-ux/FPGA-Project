# EXPERIMENT, NOT TEAM CODE. Written by Claude (Swarneel's agent), 12 Nov 2026, at Swarneel's request.
#
# Problem being tested (from the 12 Nov board run on "Stairway to Heaven"): the original tuning
# (fc 7.2 kHz, gain 1, SW5 down, SW6 down) adds jingle/hiss on strummed guitar. Swarneel has chosen to
# keep the original enhancement parameters and remove the noise the algorithm adds.
#
# Hypothesis: the rectifier turns MP3 quantisation noise in the fc/2..fc band into broadband hiss above
# fc, and it does so in the gaps between notes, where the source band holds nothing but noise. Gating the
# added treble by the source-band level should remove most of that hiss.
#
# Variants (all keep the original fc = 7.2 kHz, gain 1; only the added treble differs):
#   V0  plain enhancement (ref.enhance, the original tuning)
#   V1  envelope gate: added treble x g(n), g = soft gate on the source-band envelope in dB
#   V2  STFT Wiener gate on the added treble only (offline noise floor, experiment only)
#
# Metrics (both reference = 128 kbit/s decode of the same master):
#   LSD_hi   log-spectral distance above fc, dB (lower = closer to the reference)
#   gap_add  added energy (variant minus plain) in 7.2-20 kHz, in the quietest 20% of frames, dB re
#            full scale (lower = less hiss in the gaps)
#
# Usage: .venv/bin/python model/goal2/exp_hiss_gate.py [plain.mp3] [ref.mp3]

import os
import subprocess
import sys

import numpy as np
from scipy.signal import stft, istft

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ref  # float reference chain (original tuning); no changes to it

FS = 48000
FC = 7200          # original tuning (SW6 down)
GAIN = 1           # original tuning (SW5 down)
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def decode(path):
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(FS), "-f", "s16le", "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype="<i2").astype(float)


def source_band_and_added(x):
    """Return the source band (fc/2..fc) and the added treble before gain (original chain)."""
    band = ref.bandpass_octave(x, FC)
    added = ref.lowpass(ref.highpass(np.abs(band), FC), ref.LIMIT_HZ)
    return band, added


def envelope(x, attack_ms=1.0, release_ms=40.0):
    """Peak envelope follower (one pole per direction)."""
    a = np.exp(-1.0 / (FS * attack_ms / 1000.0))
    r = np.exp(-1.0 / (FS * release_ms / 1000.0))
    env = np.empty_like(x)
    e = 0.0
    for n, v in enumerate(np.abs(x)):
        e = a * e + (1 - a) * v if v > e else r * e + (1 - r) * v
        env[n] = e
    return env


def gate_v1(band, threshold_db, knee_db=10.0):
    """Soft gate: fully open above threshold_db (dBFS), closed knee_db below it."""
    env_db = 20 * np.log10(envelope(band) / 32768.0 + 1e-12)
    return np.clip((env_db - threshold_db) / knee_db + 1.0, 0.0, 1.0)


def wiener_v2(added, beta=1.0, floor_db=-12.0):
    """STFT Wiener gain on the added treble. Noise floor = 10th percentile per bin over the file."""
    f, t, E = stft(added, fs=FS, nperseg=1024, noverlap=512)
    mag2 = np.abs(E) ** 2
    noise2 = np.percentile(mag2, 10, axis=1, keepdims=True) + 1e-12
    G = mag2 / (mag2 + beta * noise2)
    G = np.maximum(G, 10 ** (floor_db / 20))
    _, out = istft(E * G, fs=FS, nperseg=1024, noverlap=512)
    return out[: len(added)]


def lsd_hi(y, ref_sig):
    """Log-spectral distance above FC (dB), 1024-point Hann STFT."""
    n = min(len(y), len(ref_sig))
    _, _, Y = stft(y[:n], fs=FS, nperseg=1024, noverlap=512)
    _, _, R = stft(ref_sig[:n], fs=FS, nperseg=1024, noverlap=512)
    f = np.fft.rfftfreq(1024, 1 / FS)
    hi = f >= FC
    d = 10 * np.log10(np.abs(Y[hi]) ** 2 + 1e-9) - 10 * np.log10(np.abs(R[hi]) ** 2 + 1e-9)
    return float(np.sqrt(np.mean(d ** 2)))


def gap_add_db(y, plain, full_scale=32768.0):
    """Added energy in 7.2-20 kHz in the quietest 20% of frames (by plain frame power), dB re FS."""
    n = min(len(y), len(plain))
    _, _, Y = stft(y[:n] - plain[:n], fs=FS, nperseg=1024, noverlap=512)
    _, _, P = stft(plain[:n], fs=FS, nperseg=1024, noverlap=512)
    f = np.fft.rfftfreq(1024, 1 / FS)
    hi = f >= FC
    frame_power = np.sum(np.abs(P) ** 2, axis=0)
    quiet = frame_power <= np.percentile(frame_power, 20)
    add = np.mean(np.abs(Y[hi][:, quiet]) ** 2)
    return float(10 * np.log10(add / full_scale ** 2 + 1e-20))


def main():
    plain_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "test_audio", "beethoven5_ogg_32k.mp3")
    ref_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "test_audio", "beethoven5_ogg_128k.mp3")
    x = decode(plain_path)
    ref_sig = decode(ref_path)
    n = min(len(x), len(ref_sig))
    x, ref_sig = x[:n], ref_sig[:n]

    band, added = source_band_and_added(x)
    v0 = x + GAIN * added                       # plain enhancement, original tuning (= ref.enhance)
    assert np.allclose(v0, ref.enhance(x, FC, GAIN), atol=1e-6)

    rows = [("V0 original (ref.enhance)", v0)]
    for thr in (-70, -60, -50, -40, -30, -20, -10):
        g = gate_v1(band, thr)
        rows.append((f"V1 envelope gate, T={thr} dB (open rate {np.mean(g > 0.5):.0%})", x + GAIN * added * g))
    rows.append(("V2 Wiener gate on added treble", x + GAIN * wiener_v2(added)))

    print(f"file: {os.path.basename(plain_path)}  ref: {os.path.basename(ref_path)}  "
          f"{n / FS:.2f} s, FC {FC} Hz, gain {GAIN}")
    print(f"{'variant':<58}{'LSD_hi dB':>10}{'gap_add dB':>12}")
    print(f"{'plain 32k (no enhancement)':<58}{lsd_hi(x, ref_sig):>10.2f}{gap_add_db(x, x):>12.1f}")
    for name, y in rows:
        print(f"{name:<58}{lsd_hi(y, ref_sig):>10.2f}{gap_add_db(y, x):>12.1f}")


if __name__ == "__main__":
    main()
