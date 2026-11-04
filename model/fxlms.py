"""Floating-point FxLMS golden model (project sign convention).

The project defines e[n] = d[n] + (S*y)[n], hence the update is
w <- w - mu * e[n] * x_filtered_history.
"""
from __future__ import annotations

from dataclasses import dataclass
import numpy as np

from .fixed import (
    SAMPLE_BITS, SAMPLE_FRAC, SHAT_BITS, SHAT_FRAC, WEIGHT_BITS,
    WEIGHT_FRAC, DEFAULT_L, DEFAULT_M, MU_SHIFT, W_LIMIT, saturate, round_shift,
)


@dataclass
class FxLMSResult:
    y: np.ndarray
    error: np.ndarray
    filtered_reference: np.ndarray
    weights: np.ndarray
    weight_norm: np.ndarray


class FxLMS:
    """Sample-by-sample feed-forward FxLMS controller."""

    def __init__(self, control_length: int, shat: np.ndarray, mu: float):
        if control_length <= 0:
            raise ValueError("control_length must be positive")
        shat = np.asarray(shat, dtype=np.float64)
        if shat.ndim != 1 or shat.size == 0:
            raise ValueError("shat must be a non-empty 1-D array")
        if not np.isfinite(mu) or mu <= 0:
            raise ValueError("mu must be finite and positive")
        self.L = int(control_length)
        self.M = int(shat.size)
        self.shat = shat.copy()
        self.mu = float(mu)
        self.w = np.zeros(self.L, dtype=np.float64)
        self.x_hist = np.zeros(max(self.L, self.M), dtype=np.float64)
        self.xf_hist = np.zeros(self.L, dtype=np.float64)

    def reset(self) -> None:
        self.w.fill(0.0)
        self.x_hist.fill(0.0)
        self.xf_hist.fill(0.0)

    def begin_sample(self, x_ref: float, anc_en: bool = True) -> tuple[float, float]:
        """Consume x[n], return (y[n], x_filtered[n]).

        This is deliberately separate from adapt(): a closed-loop simulation
        must first generate y, pass it through S, calculate e, and only then
        update the weights using that measured error.
        """
        self.x_hist[1:] = self.x_hist[:-1]
        self.x_hist[0] = float(x_ref)

        y = float(np.dot(self.w, self.x_hist[: self.L])) if anc_en else 0.0
        xf = float(np.dot(self.shat, self.x_hist[: self.M]))
        self.xf_hist[1:] = self.xf_hist[:-1]
        self.xf_hist[0] = xf
        return y, xf

    def adapt(self, e_err: float, anc_en: bool = True) -> None:
        """Update weights after the current sample's error is available."""
        if anc_en:
            self.w -= self.mu * float(e_err) * self.xf_hist


def simulate_closed_loop(
    reference: np.ndarray,
    primary: np.ndarray,
    secondary: np.ndarray,
    shat: np.ndarray,
    control_length: int = 64,
    mu: float = 2.0 ** -7,
    anc_en: bool = True,
) -> FxLMSResult:
    """Simulate d=P*x, e=d+S*y, and the FxLMS adaptation loop."""
    x = np.asarray(reference, dtype=np.float64)
    p = np.asarray(primary, dtype=np.float64)
    s = np.asarray(secondary, dtype=np.float64)
    if x.ndim != 1 or p.ndim != 1 or s.ndim != 1:
        raise ValueError("reference and paths must be one-dimensional")
    if x.size == 0:
        raise ValueError("reference must not be empty")

    ctrl = FxLMS(control_length, shat, mu)
    d_all = np.convolve(x, p, mode="full")[: x.size]
    y_all = np.zeros_like(x)
    sec_all = np.zeros_like(x)
    e_all = np.zeros_like(x)
    xf_all = np.zeros_like(x)
    weight_norm = np.zeros_like(x)
    y_hist = np.zeros(s.size, dtype=np.float64)

    for n, xn in enumerate(x):
        y, xf = ctrl.begin_sample(xn, anc_en=anc_en)
        y_all[n] = y
        xf_all[n] = xf
        y_hist[1:] = y_hist[:-1]
        y_hist[0] = y
        sec = float(np.dot(s, y_hist))
        sec_all[n] = sec
        e = d_all[n] + sec
        e_all[n] = e
        ctrl.adapt(e, anc_en=anc_en)
        weight_norm[n] = np.linalg.norm(ctrl.w)

    return FxLMSResult(y_all, e_all, xf_all, ctrl.w.copy(), weight_norm)


def windowed_rms(x: np.ndarray, window: int = 480) -> np.ndarray:
    """Causal moving RMS, suitable for displaying convergence over time."""
    x = np.asarray(x, dtype=np.float64)
    if window <= 0:
        raise ValueError("window must be positive")
    power = x * x
    kernel = np.ones(window, dtype=np.float64) / window
    # Pad with the first observed power so the early curve is not biased by
    # implicit future values; use a causal convolution thereafter.
    out = np.convolve(power, kernel, mode="full")[: x.size]
    counts = np.minimum(np.arange(1, x.size + 1), window)
    return np.sqrt(out * window / counts)


# Fixed-point class mirrors rtl/fxlms.v operation-for-operation.
class FixedFxLMS:
    """Bit-true fixed-point FxLMS controller.

    begin_sample(x) computes y using the weights that existed at the start of
    the sample, filters x through shat, and updates the filtered-reference
    history. adapt(e) then updates all L weights for the next sample.
    """

    def __init__(
        self,
        shat: Iterable[int],
        control_length: int = DEFAULT_L,
        mu_shift: int = MU_SHIFT,
        weight_limit: int = W_LIMIT,
    ) -> None:
        self.shat = [saturate(v, SHAT_BITS) for v in shat]
        if not self.shat:
            raise ValueError("shat must contain at least one coefficient")
        if control_length <= 0 or mu_shift < 0:
            raise ValueError("control_length must be positive and mu_shift non-negative")
        self.L = int(control_length)
        self.M = len(self.shat)
        self.mu_shift = int(mu_shift)
        self.weight_limit = int(weight_limit)
        self.w = [0] * self.L
        self.x_hist = [0] * max(self.L, self.M)
        self.xf_hist = [0] * self.L
        self.last_y = 0
        self.last_xf = 0
        self.last_w_over = False

    def reset(self) -> None:
        self.w[:] = [0] * self.L
        self.x_hist[:] = [0] * len(self.x_hist)
        self.xf_hist[:] = [0] * self.L
        self.last_y = 0
        self.last_xf = 0
        self.last_w_over = False

    def begin_sample(self, x_ref: int, anc_en: bool = True) -> tuple[int, int]:
        x_ref = saturate(x_ref, SAMPLE_BITS)
        self.x_hist[1:] = self.x_hist[:-1]
        self.x_hist[0] = x_ref

        y_acc = sum(self.w[k] * self.x_hist[k] for k in range(self.L))
        y = saturate(round_shift(y_acc, WEIGHT_FRAC), SAMPLE_BITS) if anc_en else 0

        xf_acc = sum(self.shat[j] * self.x_hist[j] for j in range(self.M))
        xf = saturate(round_shift(xf_acc, SHAT_FRAC), SAMPLE_BITS)
        self.xf_hist[1:] = self.xf_hist[:-1]
        self.xf_hist[0] = xf

        self.last_y = y
        self.last_xf = xf
        return y, xf

    def adapt(self, e_err: int, anc_en: bool = True) -> bool:
        e_err = saturate(e_err, SAMPLE_BITS)
        if anc_en:
            # e and xf are Q1.23; product is Q2.46. Convert to Q4.28
            # and apply mu=2**(-mu_shift), hence right shift 18+mu_shift.
            total_shift = (2 * SAMPLE_FRAC - WEIGHT_FRAC) + self.mu_shift
            for k in range(self.L):
                delta_w = round_shift(e_err * self.xf_hist[k], total_shift)
                self.w[k] = saturate(self.w[k] - delta_w, WEIGHT_BITS)
        self.last_w_over = self.last_w_over or any(abs(w) > self.weight_limit for w in self.w)
        return self.last_w_over

