"""Week-1 floating-point ANC experiment.

Run from the repository root:
    python -m model.anc.sim_anc

Outputs are written to results/anc_float/.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import json
import numpy as np
import matplotlib.pyplot as plt

from .paths import make_reference, synthetic_paths, fir_filter, identify_secondary_path
from .fixed import MU_S_SHIFT
from .fxlms import simulate_closed_loop, windowed_rms


def attenuation_db(disturbance: np.ndarray, residual: np.ndarray, start: int = 0) -> float:
    """20*log10(RMS before / RMS after), with a small denominator guard."""
    d = np.asarray(disturbance, dtype=np.float64)[start:]
    e = np.asarray(residual, dtype=np.float64)[start:]
    rd = np.sqrt(np.mean(d * d))
    re = np.sqrt(np.mean(e * e))
    return float(20.0 * np.log10(max(rd, 1e-15) / max(re, 1e-15)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--mu", type=float, default=2.0 ** -7)
    parser.add_argument("--output-dir", type=Path, default=Path("results/anc_float"))
    args = parser.parse_args()

    fs = 48_000
    count = int(round(args.seconds * fs))
    paths = synthetic_paths(path_model_length=128)
    x = make_reference(count, sample_rate=fs)
    d = np.convolve(x, paths.primary, mode="full")[:count]

    # Exact secondary-path estimate.
    exact = simulate_closed_loop(
        x, paths.primary, paths.secondary, paths.secondary_estimate,
        control_length=64, mu=args.mu,
    )

    # Deliberately perturb gain and one coefficient, keeping the same delay.
    imperfect_shat = paths.secondary_estimate.copy()
    imperfect_shat[2] *= 0.90
    imperfect_shat[3] *= 1.10
    imperfect = simulate_closed_loop(
        x, paths.primary, paths.secondary, imperfect_shat,
        control_length=64, mu=args.mu,
    )

    off = d
    settling = min(int(0.25 * fs), count // 4)
    exact_db = attenuation_db(off, exact.error, start=settling)
    imperfect_db = attenuation_db(off, imperfect.error, start=settling)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    t = np.arange(count) / fs
    window = 480  # 10 ms at 48 kHz
    d_rms = windowed_rms(off, window)
    e_rms_exact = windowed_rms(exact.error, window)
    e_rms_bad = windowed_rms(imperfect.error, window)

    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.plot(t, 20 * np.log10(np.maximum(d_rms, 1e-12)), label="ANC off: disturbance d")
    ax.plot(t, 20 * np.log10(np.maximum(e_rms_exact, 1e-12)), label="ANC on: exact shat")
    ax.plot(t, 20 * np.log10(np.maximum(e_rms_bad, 1e-12)), label="ANC on: imperfect shat", alpha=0.85)
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Windowed RMS level (dB re 1.0 full scale)")
    ax.set_title("FxLMS convergence — 200 Hz reference tone")
    ax.grid(True, alpha=0.3)
    ax.legend()
    ax.set_xlim(0.0, min(args.seconds, 0.15))
    ax.set_ylim(-65.0, 0.0)
    fig.tight_layout()
    fig.savefig(args.output_dir / "convergence.png", dpi=160)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 4.5))
    ax.plot(t, exact.weight_norm, label="||w||, exact shat")
    ax.plot(t, imperfect.weight_norm, label="||w||, imperfect shat", alpha=0.85)
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Control-filter weight norm")
    ax.set_title("FxLMS adaptive-weight norm")
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(args.output_dir / "weight_norm.png", dpi=160)
    plt.close(fig)

    # CALIBRATE-mode reference: identify S using an independent +/-0.25 probe.
    # mu_s=2^-6 is an initial candidate for this probe amplitude; Member C must
    # re-check it against the actual LFSR amplitude and calibration duration.
    rng = np.random.default_rng(19)
    probe = rng.choice(np.array([-0.25, 0.25]), size=count)
    measured_path = fir_filter(probe, paths.secondary)
    path_id = identify_secondary_path(
        probe, measured_path, model_length=128, mu_s=2.0 ** -MU_S_SHIFT, true_path=paths.secondary
    )
    id_err = float(path_id.coefficient_error[-1])
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.plot(t, np.maximum(path_id.coefficient_error, 1e-12))
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("||shat - S||_2 (coefficient error)")
    ax.set_title("Secondary-path identification reference (mu_s = 2^-6)")
    ax.set_yscale("log")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(args.output_dir / "secondary_path_identification.png", dpi=160)
    plt.close(fig)

    metrics = {
        "sample_rate_hz": fs,
        "samples": count,
        "tone_hz": 200,
        "control_length_L": 64,
        "path_model_length_M": 128,
        "mu": args.mu,
        "secondary_estimate_exact_at_start": True,
        "attenuation_exact_after_250ms_db": exact_db,
        "attenuation_imperfect_after_250ms_db": imperfect_db,
        "final_weight_norm_exact": float(np.linalg.norm(exact.weights)),
        "final_weight_norm_imperfect": float(np.linalg.norm(imperfect.weights)),
        "mu_s_candidate": 2.0 ** -MU_S_SHIFT,
        "path_id_probe_peak": 0.25,
        "path_id_final_coefficient_error": float(id_err),
    }
    (args.output_dir / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    print(json.dumps(metrics, indent=2))
    print(f"Plots and metrics saved in: {args.output_dir.resolve()}")


if __name__ == "__main__":
    main()
