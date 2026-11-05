"""FIR path models used by the ANC golden model.

Coefficient convention: h[0] multiplies the current input sample; h[k]
multiplies the input delayed by k samples. All filters are causal.
"""
from __future__ import annotations

from dataclasses import dataclass
import numpy as np


@dataclass(frozen=True)
class PathSet:
    primary: np.ndarray
    secondary: np.ndarray
    secondary_estimate: np.ndarray


def fir_filter(signal: np.ndarray, taps: np.ndarray) -> np.ndarray:
    """Return causal FIR output, with zero-valued prehistory."""
    x = np.asarray(signal, dtype=np.float64)
    h = np.asarray(taps, dtype=np.float64)
    if x.ndim != 1 or h.ndim != 1 or h.size == 0:
        raise ValueError("signal and taps must be non-empty 1-D arrays")
    return np.convolve(x, h, mode="full")[: x.size]


def synthetic_paths(path_model_length: int = 128) -> PathSet:
    """Small deterministic paths with a causal feed-forward cancellation margin.

    The primary path starts at sample 6; the secondary path starts at sample 2.
    Therefore the reference disturbance is available four samples before the
    anti-noise reaches the error microphone. Coefficients are deliberately
    modest and the unused tail is zero-padded to M.
    """
    if path_model_length < 4:
        raise ValueError("path_model_length must be at least 4")
    primary = np.zeros(8, dtype=np.float64)
    primary[6] = 0.80
    primary[7] = 0.15

    secondary = np.zeros(4, dtype=np.float64)
    secondary[2] = 0.70
    secondary[3] = 0.20

    shat = np.zeros(path_model_length, dtype=np.float64)
    shat[: secondary.size] = secondary
    return PathSet(primary, secondary, shat)


def make_reference(
    samples: int,
    sample_rate: int = 48_000,
    tone_hz: float = 200.0,
    tone_amplitude: float = 0.45,
    noise_std: float = 0.005,
    seed: int = 7,
) -> np.ndarray:
    """Generate the reference-microphone waveform for the Week-1 experiment."""
    if samples <= 0 or sample_rate <= 0:
        raise ValueError("samples and sample_rate must be positive")
    if not 0.0 < tone_hz < sample_rate / 2:
        raise ValueError("tone_hz must be below Nyquist")
    rng = np.random.default_rng(seed)
    n = np.arange(samples, dtype=np.float64)
    tone = tone_amplitude * np.sin(2.0 * np.pi * tone_hz * n / sample_rate)
    noise = rng.normal(0.0, noise_std, samples)
    return tone + noise

@dataclass
class PathIDResult:
    estimate: np.ndarray
    coefficient_error: np.ndarray


def identify_secondary_path(
    probe: np.ndarray,
    measured_error: np.ndarray,
    model_length: int,
    mu_s: float,
    true_path: np.ndarray,
) -> PathIDResult:
    """Floating-point LMS reference for the CALIBRATE-mode path identifier.

    This is included to help Member B choose mu_s and agree the coefficient
    format. Member C owns the path-ID RTL. The measured signal should be the
    output of the true secondary path driven by ``probe``.
    """
    v = np.asarray(probe, dtype=np.float64)
    e = np.asarray(measured_error, dtype=np.float64)
    if v.ndim != 1 or e.ndim != 1 or v.size != e.size:
        raise ValueError("probe and measured_error must be equal-length 1-D arrays")
    if model_length <= 0 or mu_s <= 0:
        raise ValueError("model_length and mu_s must be positive")

    shat = np.zeros(model_length, dtype=np.float64)
    history = np.zeros(model_length, dtype=np.float64)
    true_path = np.asarray(true_path, dtype=np.float64)
    if true_path.ndim != 1 or true_path.size > model_length:
        raise ValueError("true_path must be 1-D and no longer than model_length")
    true_shat = np.zeros(model_length, dtype=np.float64)
    true_shat[: true_path.size] = true_path
    coefficient_error = np.zeros(v.size, dtype=np.float64)
    for n in range(v.size):
        history[1:] = history[:-1]
        history[0] = v[n]
        estimate = float(np.dot(shat, history))
        epsilon = e[n] - estimate
        shat += mu_s * epsilon * history
        coefficient_error[n] = np.linalg.norm(shat - true_shat)
    return PathIDResult(shat, coefficient_error)
