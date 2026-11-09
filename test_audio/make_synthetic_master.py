# Not team code. Generates a synthetic 48 kHz mono test master with energy up to 24 kHz.
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

fs = 48000
dur = 20
t = np.arange(fs * dur) / fs
rng = np.random.default_rng(1)

# Low/mid body: a pulsing harmonic tone stack, 110 Hz fundamental, up to ~5 kHz.
body = sum(np.sin(2*np.pi*110*k*t) / k for k in range(1, 46) if 110*k < 5000)
kick = (np.sin(2*np.pi*2*t) > 0.0).astype(float) * np.exp(-((t*2) % 1) * 6)
body = body * (0.3 + 0.7*kick)

# Hi-hat style bursts: white noise, high-passed at 8 kHz (full band to 24 kHz), 16th-note decays.
noise = rng.standard_normal(len(t))
sos = butter(6, 8000, btype="highpass", fs=fs, output="sos")
hats = sosfilt(sos, noise)
period = fs // 8                      # eighth-note spacing, 0.125 s
env = np.zeros_like(t)
for start in range(0, len(t), period):
    seg = np.arange(min(period, len(t)-start))
    env[start:start+len(seg)] += np.exp(-seg / (fs*0.02))
hats = hats * env

x = body / np.max(np.abs(body)) * 0.4 + hats / np.max(np.abs(hats)) * 0.4
x = x / np.max(np.abs(x)) * 0.7      # about -3 dBFS peak
wavfile.write("master_treble_48k_mono.wav", fs, (x * 32767).astype(np.int16))
print("wrote", len(x), "samples")
