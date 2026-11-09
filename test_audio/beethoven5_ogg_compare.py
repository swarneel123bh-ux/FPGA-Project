# Not team code. Band-by-band level of each decoded clip relative to the reference clip (the OGG-derived WAV).
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import welch
fs = 48000
_, ref = wavfile.read("clip_20s_48k_mono.wav")
def spec(x):
    f, P = welch(x.astype(float), fs=fs, nperseg=4096)
    return f, 10*np.log10(P + 1e-20)
f, dr = spec(ref)
bands = [(8,10),(10,12),(12,14),(14,16),(16,18),(18,20)]
print("rate   bytes   20dB-down   " + "  ".join(f"{lo}-{hi}k" for lo,hi in bands))
for b in [32,40,48,56,64,96,128]:
    x = np.fromfile(f"dec_{b}k.raw", dtype="<i2")
    _, d = spec(x)
    diff = d - dr
    idx = np.where((f > 10000) & (diff < -20))[0]
    cut = f"{f[idx[0]]/1000:.1f}k" if len(idx) else "none"
    cols = "  ".join(f"{diff[(f>=lo*1000)&(f<hi*1000)].mean():6.1f}" for lo,hi in bands)
    print(f"{b:4d}k {os.path.getsize(f'beethoven5_20s_48k_mono_{b}k.mp3'):8d}   {cut:>8}   {cols}")
