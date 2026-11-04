"""Bit-accurate fixed-point Python model for rtl/sec_path_id.v.

Formats are deliberately aligned with Member B's fixed.py:
  probe, measured, epsilon: signed 24-bit Q1.23
  shat coefficients:        signed 24-bit Q2.22
  estimate accumulator:     signed 64-bit
  mu_s:                      2**-6 by default
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Sequence

SAMPLE_BITS = 24
SAMPLE_FRAC = 23
SHAT_BITS = 24
SHAT_FRAC = 22
DEFAULT_M = 128
MU_S_SHIFT = 6


def signed_bounds(bits: int) -> tuple[int, int]:
    if bits <= 0:
        raise ValueError("bits must be positive")
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1


def saturate(value: int, bits: int) -> int:
    lo, hi = signed_bounds(bits)
    return min(max(int(value), lo), hi)


def round_shift(value: int, shift: int) -> int:
    """Round to nearest, ties away from zero (same as Member B fixed.py)."""
    value = int(value)
    if shift < 0:
        return value << (-shift)
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def float_to_fixed(value: float, frac_bits: int, bits: int) -> int:
    scaled = float(value) * (1 << frac_bits)
    rounded = int(scaled + 0.5) if scaled >= 0 else -int(-scaled + 0.5)
    return saturate(rounded, bits)


def fixed_to_float(value: int, frac_bits: int) -> float:
    return int(value) / float(1 << frac_bits)


@dataclass(frozen=True)
class PathIdResult:
    coefficients: tuple[int, ...]
    final_error: int
    samples_processed: int
    coefficient_error_norm: float


def identify_secondary_path_fixed(
    probe: Iterable[int],
    measured: Iterable[int],
    model_length: int = DEFAULT_M,
    mu_s_shift: int = MU_S_SHIFT,
) -> PathIdResult:
    """Run the same estimate-then-update algorithm as the RTL, bit for bit."""
    v = [saturate(x, SAMPLE_BITS) for x in probe]
    y = [saturate(x, SAMPLE_BITS) for x in measured]
    if len(v) != len(y):
        raise ValueError("probe and measured must have equal lengths")
    if model_length <= 0 or mu_s_shift < 0:
        raise ValueError("model_length must be positive and mu_s_shift non-negative")

    shat = [0] * model_length
    history = [0] * model_length
    final_epsilon = 0
    update_shift = (2 * SAMPLE_FRAC - SHAT_FRAC) + mu_s_shift

    for probe_n, measured_n in zip(v, y):
        history[1:] = history[:-1]
        history[0] = probe_n

        estimate_acc = sum(int(shat[k]) * int(history[k]) for k in range(model_length))
        estimate = saturate(round_shift(estimate_acc, SHAT_FRAC), SAMPLE_BITS)
        epsilon = saturate(int(measured_n) - estimate, SAMPLE_BITS)
        final_epsilon = epsilon

        for k in range(model_length):
            product = int(epsilon) * int(history[k])
            delta = round_shift(product, update_shift)
            shat[k] = saturate(shat[k] + delta, SHAT_BITS)

    return PathIdResult(tuple(shat), final_epsilon, len(v), 0.0)


def make_lfsr_plant_vectors(
    sample_count: int = 8000,
    model_length: int = DEFAULT_M,
    secondary_taps: Sequence[float] = (0.0, 0.0, 0.70, 0.20),
    seed: int = 0x5A5A5A,
) -> tuple[list[int], list[int], list[int]]:
    """Create probe and measured-path vectors from the project's LFSR and S taps."""
    from .lfsr import generate

    if len(secondary_taps) > model_length:
        raise ValueError("secondary path cannot exceed model_length")
    sequence = generate(sample_count, seed)
    probe = [item.sample for item in sequence]
    s_q = [float_to_fixed(tap, SHAT_FRAC, SHAT_BITS) for tap in secondary_taps]
    history = [0] * len(s_q)
    measured: list[int] = []
    for sample in probe:
        if history:
            history[1:] = history[:-1]
            history[0] = sample
            acc = sum(int(s_q[k]) * int(history[k]) for k in range(len(s_q)))
        else:
            acc = 0
        measured.append(saturate(round_shift(acc, SHAT_FRAC), SAMPLE_BITS))
    return probe, measured, s_q


def coefficient_error_norm(coefficients_q22: Sequence[int], true_taps: Sequence[float]) -> float:
    target = [float_to_fixed(t, SHAT_FRAC, SHAT_BITS) for t in true_taps]
    target += [0] * (len(coefficients_q22) - len(target))
    return sum((fixed_to_float(a, SHAT_FRAC) - fixed_to_float(b, SHAT_FRAC)) ** 2
               for a, b in zip(coefficients_q22, target)) ** 0.5
