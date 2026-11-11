# Fixed-point golden model of rtl/treble_fixed.v (goal 2, stage 1).
#
# WRITTEN BY CLAUDE (Swarneel's agent) on 11 Nov 2026, at Swarneel's request: Swarneel assigned
# the treble RTL port to Claude while the team brings up ANC. Not written by a team member.
# Swarneel reviews it and must be able to explain it in the viva.
#
# Same chain as model/goal2/ref.py (float reference), with every number an integer:
#
#   x (s24) -> band-pass fc/2..fc (4 sections) -> |.| -> high-pass fc (4) -> low-pass 20 kHz (4)
#           -> enh;   out = sat24(x + enh)        (GAIN = 1)
#
# Fixed-point decisions (docs/goal2_rtl_plan.md section 3):
#   Input / output   s24, two's complement. Music arrives as int16 << 8 (the FIFO feeder).
#   Coefficients     25-bit signed, Q2.22 (range [-4, 4), step 2^-22 = 2.4e-7).
#                    ROM order per section: b0, b1, b2, -a1, -a2 (a negated so every MAC adds).
#   Internal samples 32-bit signed: 4 guard bits above s24 (16x headroom) and 4 fraction
#                    bits below its LSB (x << 4 on entry). With 0 fraction bits the rounding
#                    noise was only 49 dB below the added treble; 4 bits gives the 60 dB target.
#                    Worst-case chain gain (L1 norm) is about 1.86 * 2.45 * 2.99 = 13.6 < 16,
#                    so the saturations below never fire for in-range input; they are a guard.
#   Section          Direct Form I. acc = b0*x0 + b1*x1 + b2*x2 + (-a1)*y1 + (-a2)*y2,
#                    exact in a 60-bit accumulator (32x25 -> 57-bit products, 5 terms).
#   Rounding         Once per section: y = sat32((acc + 2^21) >> 22), arithmetic shift
#                    (round half up; Python >> on negative ints and Verilog >>> agree).
#                    At the end of the chain: enh = (v + 8) >> 4, back to the s24 LSB.
#   Saturation       Each section output (32 bit), after |.| (|-2^31| -> 2^31-1), final sum (24 bit).
#   enh_en = 0       out = x exactly; the filters keep running so switching back is click-free.
#
# Usage:
#   .venv/bin/python model/goal2/ref_fixed.py              # checks + vectors + coefficient ROM
#   .venv/bin/python model/goal2/ref_fixed.py --full       # also the 20 s float-vs-fixed check
# Writes: rtl/treble_coefs.mem, sim/vectors/treble_in.hex, sim/vectors/treble_out.hex,
#         build/enhanced_fixed_32k.wav (for listening).

import os
import subprocess
import sys

import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

FS = 48000
FC = 7200            # 32 kbit/s cutoff (test_audio/beethoven5_ogg_knee_table.md)
LIMIT_HZ = 20000
FILTER_ORDER = 8     # as ref.py: band-pass order 4 (-> 8 poles), high/low-pass order 8

COEF_W = 25          # coefficient width
COEF_FRAC = 22       # fractional bits (Q2.22)
DATA_W = 32          # internal sample width
DATA_FRAC = 4        # internal fraction bits below the s24 LSB
OUT_W = 24           # block-boundary width
N_SECT = 12
ABS_AFTER = 3        # |.| is applied to the output of section 3 (end of the band-pass)

MP3 = os.path.join(ROOT, "test_audio", "beethoven5_ogg_32k.mp3")


def design_sos(fc=FC):
    """The three float filters of ref.py, stacked as 12 sections."""
    bp = butter(FILTER_ORDER // 2, [fc / 2, fc], btype="bandpass", fs=FS, output="sos")
    hp = butter(FILTER_ORDER, fc, btype="highpass", fs=FS, output="sos")
    lp = butter(FILTER_ORDER, LIMIT_HZ, btype="lowpass", fs=FS, output="sos")
    return bp, hp, lp


def quantise(sos_list):
    """Round to Q2.22. Returns an N_SECT x 5 list of ints: b0, b1, b2, -a1, -a2."""
    rows = []
    for sos in sos_list:
        for b0, b1, b2, a0, a1, a2 in sos:
            assert a0 == 1.0
            row = [b0, b1, b2, -a1, -a2]
            q = [int(round(c * (1 << COEF_FRAC))) for c in row]
            lim = 1 << (COEF_W - 1)
            assert all(-lim <= c < lim for c in q), "coefficient out of Q2.22 range"
            rows.append(q)
    assert len(rows) == N_SECT
    return rows


def sat(v, w):
    hi = (1 << (w - 1)) - 1
    lo = -(1 << (w - 1))
    return hi if v > hi else lo if v < lo else v


def enhance_fixed(x24, coefs, enh_en=None):
    """Bit-exact model of treble_fixed. x24: iterable of ints in s24 range.
    enh_en: None (always 1) or a sequence of 0/1 per sample. Returns (out, enh) lists."""
    st = [[0, 0, 0, 0] for _ in range(N_SECT)]      # x1, x2, y1, y2 per section
    half = 1 << (COEF_FRAC - 1)
    amax = (1 << (DATA_W - 1)) - 1
    out, enh_all = [], []
    for n, x in enumerate(x24):
        v = int(x) << DATA_FRAC
        for s in range(N_SECT):
            b0, b1, b2, na1, na2 = coefs[s]
            x1, x2, y1, y2 = st[s]
            acc = b0 * v + b1 * x1 + b2 * x2 + na1 * y1 + na2 * y2
            y = sat((acc + half) >> COEF_FRAC, DATA_W)
            st[s] = [v, x1, y, y1]
            v = y
            if s == ABS_AFTER:
                v = min(abs(v), amax)
        enh = (v + (1 << (DATA_FRAC - 1))) >> DATA_FRAC
        on = 1 if enh_en is None else enh_en[n]
        out.append(sat(int(x) + enh, OUT_W) if on else int(x))
        enh_all.append(enh)
    return out, enh_all


def enhance_float(x, sos_list):
    bp, hp, lp = sos_list
    return sosfilt(lp, sosfilt(hp, np.abs(sosfilt(bp, x))))


def decode_mp3(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(FS), "-"],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.int64)


def write_hex(path, values, width):
    digits = (width + 3) // 4
    mask = (1 << width) - 1
    with open(path, "w") as f:
        for v in values:
            f.write(f"{int(v) & mask:0{digits}x}\n")


def test_vectors(music24):
    """Stimulus: silence, impulses, full-scale tones (saturation), a music passage, silence."""
    fs_pos = (1 << (OUT_W - 1)) - 1
    fs_neg = -(1 << (OUT_W - 1))
    n = np.arange(2000)
    parts = [
        np.zeros(256, dtype=np.int64),
        np.array([fs_pos] + [0] * 999, dtype=np.int64),                  # positive impulse
        np.array([fs_neg] + [0] * 999, dtype=np.int64),                  # negative impulse
        np.round(fs_pos * np.sin(2 * np.pi * 5000 * n / FS)).astype(np.int64),   # in band
        np.tile([fs_pos] * 4 + [fs_neg] * 4, 250).astype(np.int64),      # 6 kHz full-scale square
        music24[5 * FS: 5 * FS + 24000],                                  # 0.5 s of the 32k decode
        np.zeros(500, dtype=np.int64),
    ]
    return np.concatenate(parts)


def main():
    full = "--full" in sys.argv
    sos_list = design_sos()
    coefs = quantise(sos_list)

    rom = os.path.join(ROOT, "rtl", "treble_coefs.mem")
    write_hex(rom, [c for row in coefs for c in row], COEF_W)
    print(f"wrote {rom} ({N_SECT * 5} words, Q2.22)")

    music16 = decode_mp3(MP3)
    music24 = music16 << 8
    print(f"decoded {MP3}: {len(music16)} samples, {len(music16) / FS:.1f} s")

    # Check 1: fixed vs float on the added treble (5 s, or the whole clip with --full).
    seg = music24 if full else music24[: 5 * FS]
    out, enh = enhance_fixed(seg, coefs)
    enh_f = enhance_float(seg.astype(np.float64), sos_list)
    enh = np.array(enh, dtype=np.float64)
    err = enh - enh_f
    snr = 10 * np.log10(np.sum(enh_f ** 2) / np.sum(err ** 2))
    print(f"check 1: treble power / (fixed - float) error power = {snr:.1f} dB "
          f"(target > 60), max |err| = {np.max(np.abs(err)):.1f} LSB of s24")
    clipped = int(np.sum(np.abs(seg + enh) > (1 << 23) - 1))
    print(f"         clipped output samples: {clipped}")

    # Check 2: enh_en = 0 passes the input through exactly.
    off, _ = enhance_fixed(seg[:4800], coefs, enh_en=[0] * 4800)
    assert off == [int(v) for v in seg[:4800]]
    print("check 2: enh_en = 0 -> output equals input: OK")

    # Check 3: full-scale stimulus saturates without sign wrap.
    vec_in = test_vectors(music24)
    vec_out, _ = enhance_fixed(vec_in, coefs)
    lim = 1 << (OUT_W - 1)
    assert all(-lim <= v < lim for v in vec_out)
    pos = vec_in > 0
    wrapped = int(np.sum(np.array(vec_out)[pos] < -(lim // 2)))
    nsat = sum(1 for v in vec_out if v in (lim - 1, -lim))
    print(f"check 3: full-scale stimulus: {nsat} saturated outputs, {wrapped} sign wraps: "
          f"{'OK' if wrapped == 0 else 'FAIL'}")

    vdir = os.path.join(ROOT, "sim", "vectors")
    write_hex(os.path.join(vdir, "treble_in.hex"), vec_in, OUT_W)
    write_hex(os.path.join(vdir, "treble_out.hex"), vec_out, OUT_W)
    print(f"wrote sim/vectors/treble_in.hex and treble_out.hex ({len(vec_in)} samples)")

    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    wav = os.path.join(ROOT, "build", "enhanced_fixed_32k.wav")
    out16 = np.clip(np.array(out) >> 8, -32768, 32767).astype("<i2")
    wavfile.write(wav, FS, out16)
    print(f"wrote {wav} (listening copy)")


if __name__ == "__main__":
    main()
