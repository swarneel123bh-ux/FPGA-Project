#!/usr/bin/env python3
# EXPERIMENT, NOT TEAM CODE (Claude, 13 Nov 2026, planned by Swarneel). Adds treble only at the harmonics of
# the notes that are actually sounding, found per frame by an FFT harmonic sieve. Each added harmonic m*f0
# (fc < m*f0 < 2fc) is copied from the partial one octave below, n*f0 with n = round(m/2), by a phase
# vocoder, so every added partial sits on a note's harmonic series. Nothing is added between notes.
# Same high-pass (fc) and low-pass (20 kHz) as the original; gain set so the added level in note frames
# matches the original's added level in the same frames.
# Writes test_audio/stairway/enhanced_notes_s135_30s.wav and a blind pair (original vs notes) in
# build/stairway_blind4/, key in key_do_not_open_until_done.json. Also prints note statistics.
import json, os, random, shutil, sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import stft, istft
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exp_hiss_gate as e

FS, FC = e.FS, e.FC
N, H = 2048, 512
BINW = FS / N
ROOT = e.ROOT
MAX_NOTES = 2
MIN_PARTIALS = int(os.environ.get('NOTE_MINP', 4))
NHARM = 8                      # partials searched per note, below fc
THR_DB = float(os.environ.get('NOTE_THR', 25))                    # partial must be within this many dB of the frame's peak in band

def f0_grid():
    return np.exp(np.arange(np.log(80.0), np.log(1000.0), np.log(1.002)))

def sieve_tables(grid):
    idx = np.full((len(grid), NHARM), -1)
    for c, f0 in enumerate(grid):
        for n in range(1, NHARM + 1):
            fb = n * f0
            if fb >= FC: break
            idx[c, n - 1] = int(round(fb / BINW))
    return idx

def detect(Mdb, idx, grid):
    """Per frame: up to MAX_NOTES fundamentals, each with its harmonic bins."""
    K, T = Mdb.shape
    band = slice(int(80 / BINW), int(FC / BINW))
    notes = []
    for t in range(T):
        col = Mdb[:, t]
        thr = np.max(col[band]) - THR_DB
        pk = np.zeros(K, bool)
        pk[1:-1] = (col[1:-1] > col[:-2]) & (col[1:-1] >= col[2:]) & (col[1:-1] > thr)
        used = np.zeros(K, bool)
        found = []
        for _ in range(MAX_NOTES):
            ok = (idx >= 0)
            hits = np.zeros(len(grid), int)
            energy = np.zeros(len(grid))
            for c in range(len(grid)):
                b = idx[c][ok[c]]
                pb = pk[b] & ~used[b]
                hits[c] = pb.sum()
                energy[c] = col[b][pb].sum() if pb.any() else 0
            c = int(np.lexsort((-energy, -hits))[0])
            if hits[c] < MIN_PARTIALS:
                break
            if not (pk[idx[c][0]] or pk[idx[c][1]]) if idx[c][1] >= 0 else True:
                break
            found.append(c)
            b = idx[c][ok[c]]
            for bb in b:
                used[max(bb - 2, 0):bb + 3] = True
        notes.append([(grid[c], idx[c][idx[c] >= 0]) for c in found])
    return notes

DECAY = float(os.environ.get('NOTE_DECAY', 0.0))   # per-frame amplitude release (0 = off, no smoothing)

def synth(Z, notes):
    """Phase-vocoder synthesis of the added harmonics, mapping dst bins m*f0 from source n*f0."""
    K, T = Z.shape
    k = np.arange(K)
    ph = np.zeros(K)
    out = np.zeros((K, T), complex)
    prev = np.angle(Z[:, 0])
    ph[:] = prev
    active_prev = np.zeros(K, bool)
    amp_state = np.zeros(K)
    for t in range(T):
        cur = np.angle(Z[:, t])
        if t > 0:
            dev = np.angle(np.exp(1j * (cur - prev - 2 * np.pi * k * H / N)))
            w_all = 2 * np.pi * k * H / N + dev            # true advance per hop, every bin
        else:
            w_all = 2 * np.pi * k * H / N
        prev = cur
        dst_amp = np.zeros(K)
        active = np.zeros(K, bool)
        ratio_src = {}
        for f0, _ in notes[t]:
            m = 2
            while True:
                fm = m * f0
                if fm >= 2 * FC or fm > 20000: break
                if fm > FC:
                    n = int(round(m / 2))
                    fs = n * f0
                    if fs < FC:
                        sb = int(round(fs / BINW)); db = int(round(fm / BINW))
                        for d in (db - 1, db, db + 1):
                            if 0 < d < K:
                                s = sb if d == db else sb
                                active[d] = True
                                dst_amp[d] = max(dst_amp[d], np.abs(Z[sb, t]))
                                ratio_src[d] = (s, m / n)
                m += 1
        target = dst_amp * active
        amp_state = np.maximum(target, amp_state * DECAY)      # rise at once, release over frames
        live = amp_state > 1e-3 * max(1.0, np.max(amp_state))
        for d in np.where(live)[0]:
            if d in ratio_src:
                s, r = ratio_src[d]
            else:
                s, r = d, 1.0                                   # released bin: keep its phase track
            if not active_prev[d]:
                ph[d] = r * cur[s]                          # lock new partial to its source phase
            else:
                ph[d] = ph[d] + r * w_all[s]
            out[d, t] = amp_state[d] * np.exp(1j * ph[d])
        active_prev = live
    return out

def main():
    p = e.decode(os.path.join(ROOT, "test_audio/stairway/plain_32k_s135_30s.mp3"))
    f, t, Z = stft(p, fs=FS, nperseg=N, noverlap=N - H, boundary=None, padded=False)
    Mdb = 20 * np.log10(np.abs(Z) + 1e-9)
    grid = f0_grid()
    idx = sieve_tables(grid)
    notes = detect(Mdb, idx, grid)
    n_frames = len(notes)
    with_notes = sum(1 for nt in notes if nt)
    print(f"frames {n_frames}, frames with >=1 note {with_notes} ({100*with_notes/n_frames:.0f}%), "
          f"with 2 notes {sum(1 for nt in notes if len(nt)==2)}")
    print("note f0 range (Hz):", round(min(f0 for nt in notes for f0,_ in nt), 1) if with_notes else None,
          round(max(f0 for nt in notes for f0,_ in nt), 1) if with_notes else None)
    Yout = synth(Z, notes)
    _, y = istft(Yout, fs=FS, nperseg=N, noverlap=N - H, boundary=False)
    add_notes = np.zeros(len(p)); m_ = min(len(p), len(y)); add_notes[:m_] = y[:m_]
    add_notes = e.ref.lowpass(e.ref.highpass(add_notes, FC), e.ref.LIMIT_HZ)
    # level: match added energy in note frames to the original's added energy in the same frames
    band, added = e.source_band_and_added(p)
    _, _, Oz = stft(added, fs=FS, nperseg=N, noverlap=N - H, boundary=None, padded=False)
    _, _, Nz = stft(add_notes, fs=FS, nperseg=N, noverlap=N - H, boundary=None, padded=False)
    mask = np.array([len(nt) > 0 for nt in notes[: Nz.shape[1]]])
    ratio = np.sqrt(np.sum(np.abs(Oz[:, mask]) ** 2) / max(np.sum(np.abs(Nz[:, mask]) ** 2), 1e-12))
    add_notes *= ratio
    print(f"gain to match original in note frames: {20*np.log10(ratio):.1f} dB")
    y_out = np.clip(np.round(p + add_notes), -32768, 32767).astype("<i2")
    tag = os.environ.get("NOTE_TAG", "notes")
    cand = os.path.join(ROOT, f"test_audio/stairway/enhanced_{tag}_s135_30s.wav")
    wavfile.write(cand, FS, y_out)
    orig = os.path.join(ROOT, "test_audio/stairway/enhanced_32k_s135_30s.wav")
    d = os.path.join(ROOT, f"build/stairway_blind_{tag}"); os.makedirs(d, exist_ok=True)
    pair = [("original", orig), (tag, cand)]
    random.SystemRandom().shuffle(pair)
    shutil.copy(pair[0][1], os.path.join(d, "A.wav")); shutil.copy(pair[1][1], os.path.join(d, "B.wav"))
    json.dump({"A": pair[0][0], "B": pair[1][0]}, open(os.path.join(d, "key_do_not_open_until_done.json"), "w"))
    gap = np.array([len(nt) == 0 for nt in notes[: Nz.shape[1]]])
    print("added energy in gap frames (dB re FS):", round(10*np.log10(np.mean(np.abs(Nz[:, gap])**2)/32768**2 + 1e-20) if gap.any() else -999, 1))
    print("candidate:", cand)
    print("blind pair 4:", os.path.join(d, "A.wav"), os.path.join(d, "B.wav"))

if __name__ == "__main__":
    main()
