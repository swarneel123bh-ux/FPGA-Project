"""Fixed-point closed-loop ANC simulation and vector generation helpers."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from .fixed import (
    SAMPLE_BITS, SAMPLE_FRAC, SHAT_BITS, SHAT_FRAC,
    float_array_to_fixed, float_to_fixed, fixed_to_float, saturate,
)
from .fxlms import FixedFxLMS


@dataclass
class FixedLoopResult:
    x_ref: list[int]
    disturbance: list[int]
    y_anti: list[int]
    secondary_output: list[int]
    e_err: list[int]
    w_over: list[int]


def simulate_fixed_loop(
    x_ref: Iterable[int],
    primary_float: Iterable[float],
    secondary_float: Iterable[float],
    shat_float: Iterable[float],
    control_length: int = 64,
    mu_shift: int = 7,
) -> FixedLoopResult:
    """Run the closed loop entirely in the project's fixed-point formats."""
    x = [saturate(v, SAMPLE_BITS) for v in x_ref]
    p_q = float_array_to_fixed(primary_float, SHAT_FRAC, SHAT_BITS)
    s_q = float_array_to_fixed(secondary_float, SHAT_FRAC, SHAT_BITS)
    shat_q = float_array_to_fixed(shat_float, SHAT_FRAC, SHAT_BITS)

    controller = FixedFxLMS(shat_q, control_length=control_length, mu_shift=mu_shift)
    p_hist = [0] * len(p_q)
    s_hist = [0] * len(s_q)
    result = FixedLoopResult([], [], [], [], [], [])

    for xn in x:
        # Current reference enters both physical paths and the controller.
        p_hist[1:] = p_hist[:-1]
        p_hist[0] = xn
        d_acc = sum(a * b for a, b in zip(p_q, p_hist))
        d = saturate(round_shift_local(d_acc, SHAT_FRAC), SAMPLE_BITS)

        y, _xf = controller.begin_sample(xn, anc_en=True)
        s_hist[1:] = s_hist[:-1]
        s_hist[0] = y
        s_acc = sum(a * b for a, b in zip(s_q, s_hist))
        sec = saturate(round_shift_local(s_acc, SHAT_FRAC), SAMPLE_BITS)
        e = saturate(d + sec, SAMPLE_BITS)
        over = controller.adapt(e, anc_en=True)

        result.x_ref.append(xn)
        result.disturbance.append(d)
        result.y_anti.append(y)
        result.secondary_output.append(sec)
        result.e_err.append(e)
        result.w_over.append(1 if over else 0)

    return result


def round_shift_local(value: int, shift: int) -> int:
    """Local import-free copy avoids a circular dependency in this module."""
    value = int(value)
    if shift <= 0:
        return value << (-shift)
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def decode_sample(value: int) -> float:
    return fixed_to_float(value, SAMPLE_FRAC)
