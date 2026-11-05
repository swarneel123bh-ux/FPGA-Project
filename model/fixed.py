"""Bit-accurate fixed-point arithmetic shared by the Python model and RTL.

Formats used by the initial Group 16 implementation:
  PCM samples / error / y / filtered reference: signed 24-bit, 23 fraction bits
  secondary-path coefficients shat:             signed 24-bit, 22 fraction bits
  control-filter weights:                        signed 32-bit, 28 fraction bits
  products and accumulators:                      signed 64-bit (no wrap expected)

Rounding is round-to-nearest, ties away from zero. Every narrowing conversion
saturates; the Verilog module must use the same rules.
"""
from __future__ import annotations

from typing import Iterable

SAMPLE_BITS = 24
SAMPLE_FRAC = 23
SHAT_BITS = 24
SHAT_FRAC = 22
WEIGHT_BITS = 32
WEIGHT_FRAC = 28
ACCUM_BITS = 64

DEFAULT_L = 64
DEFAULT_M = 128
MU_SHIFT = 7                  # mu = 2**-7 = 0.0078125
MU = 2.0 ** -MU_SHIFT
MU_S_SHIFT = 6                # mu_s = 2**-6 for the tested +/-0.25 probe
MU_S = 2.0 ** -MU_S_SHIFT
W_LIMIT_REAL = 1.5
W_LIMIT = int(W_LIMIT_REAL * (1 << WEIGHT_FRAC))
ERROR_POWER_LIMIT_REAL = 0.25 # C's mean-square error limit, normalized to FS^2
ERROR_POWER_LIMIT_Q46 = int(ERROR_POWER_LIMIT_REAL * (1 << (2 * SAMPLE_FRAC)))


def signed_bounds(bits: int) -> tuple[int, int]:
    if bits <= 0:
        raise ValueError("bits must be positive")
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1


def saturate(value: int, bits: int) -> int:
    """Clamp an integer to a signed two's-complement width."""
    lo, hi = signed_bounds(bits)
    return min(max(int(value), lo), hi)


def round_shift(value: int, shift: int) -> int:
    """Right shift with round-to-nearest, ties away from zero.

    This is symmetric for positive and negative values. For shift <= 0 the
    value is shifted left, which is useful for generic Q-format conversion.
    """
    value = int(value)
    shift = int(shift)
    if shift < 0:
        return value << (-shift)
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def q_mul(
    a: int,
    b: int,
    frac_a: int,
    frac_b: int,
    frac_out: int,
    out_bits: int,
) -> int:
    """Multiply two fixed-point integers, round to frac_out, then saturate."""
    raw = int(a) * int(b)
    narrowed = round_shift(raw, frac_a + frac_b - frac_out)
    return saturate(narrowed, out_bits)


def float_to_fixed(value: float, frac_bits: int, bits: int) -> int:
    """Convert real value to fixed point using nearest/ties-away rounding."""
    scaled = float(value) * (1 << frac_bits)
    if scaled >= 0:
        rounded = int(scaled + 0.5)
    else:
        rounded = -int(-scaled + 0.5)
    return saturate(rounded, bits)


def fixed_to_float(value: int, frac_bits: int) -> float:
    return int(value) / float(1 << frac_bits)


def float_array_to_fixed(values: Iterable[float], frac_bits: int, bits: int) -> list[int]:
    return [float_to_fixed(float(v), frac_bits, bits) for v in values]


def fir_fixed(signal: Iterable[int], taps: Iterable[int], tap_frac: int = SHAT_FRAC) -> list[int]:
    """Causal FIR; input/output are Q1.23 samples and taps are Q2.22."""
    x = [int(v) for v in signal]
    h = [int(v) for v in taps]
    if not h:
        raise ValueError("taps must not be empty")
    history = [0] * len(h)
    out: list[int] = []
    for sample in x:
        history[1:] = history[:-1]
        history[0] = sample
        acc = sum(a * b for a, b in zip(h, history))
        out.append(saturate(round_shift(acc, tap_frac), SAMPLE_BITS))
    return out


