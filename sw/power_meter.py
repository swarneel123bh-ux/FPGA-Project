"""Software reference for the RTL block mean-square power meter."""
from __future__ import annotations
from typing import Iterable

SAMPLE_BITS = 24
SAMPLE_FRAC = 23


def mean_square_q46(samples: Iterable[int]) -> int:
    values = [max(-(1 << 23), min((1 << 23) - 1, int(x))) for x in samples]
    if not values:
        raise ValueError("at least one sample is required")
    # RTL rounds down by dropping the low WINDOW_LOG2 bits of the sum.
    return sum(x * x for x in values) // len(values)


def mean_square_float(samples: Iterable[int]) -> float:
    return mean_square_q46(samples) / float(1 << 46)
