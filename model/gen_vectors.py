"""Generate bit-exact Verilog $readmemh vectors for tb_fxlms.

Run from the repository root:
    python -m model.anc.gen_vectors --samples 4096
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import numpy as np

from .fixed import (
    DEFAULT_L, DEFAULT_M, MU_SHIFT, SAMPLE_FRAC, SAMPLE_BITS,
    SHAT_FRAC, SHAT_BITS, MU_S_SHIFT, float_array_to_fixed, float_to_fixed,
    fixed_to_float, W_LIMIT, ERROR_POWER_LIMIT_Q46,
)
from .fixed_sim import simulate_fixed_loop
from .paths import make_reference, synthetic_paths


def write_hex(path: Path, values: list[int], bits: int) -> None:
    width = (bits + 3) // 4
    mask = (1 << bits) - 1
    path.write_text("".join(f"{int(v) & mask:0{width}x}\n" for v in values))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=4096)
    parser.add_argument("--output-dir", type=Path, default=Path("sim/vectors"))
    args = parser.parse_args()
    if args.samples <= 0:
        raise SystemExit("--samples must be positive")

    paths = synthetic_paths(path_model_length=DEFAULT_M)
    x_float = make_reference(args.samples, sample_rate=48_000, seed=7)
    x_q = [float_to_fixed(v, SAMPLE_FRAC, SAMPLE_BITS) for v in x_float]

    result = simulate_fixed_loop(
        x_q,
        paths.primary,
        paths.secondary,
        paths.secondary_estimate,
        control_length=DEFAULT_L,
        mu_shift=MU_SHIFT,
    )
    shat_q = float_array_to_fixed(paths.secondary_estimate, SHAT_FRAC, SHAT_BITS)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_hex(args.output_dir / "fxlms_xref.hex", result.x_ref, SAMPLE_BITS)
    write_hex(args.output_dir / "fxlms_eerr.hex", result.e_err, SAMPLE_BITS)
    write_hex(args.output_dir / "fxlms_yanti.hex", result.y_anti, SAMPLE_BITS)
    write_hex(args.output_dir / "fxlms_shat.hex", shat_q, SHAT_BITS)
    write_hex(args.output_dir / "fxlms_w_over.hex", result.w_over, 1)

    d = np.asarray([fixed_to_float(v, SAMPLE_FRAC) for v in result.disturbance])
    e = np.asarray([fixed_to_float(v, SAMPLE_FRAC) for v in result.e_err])
    settle = min(12_000, args.samples // 4)
    rms_d = float(np.sqrt(np.mean(d[settle:] ** 2)))
    rms_e = float(np.sqrt(np.mean(e[settle:] ** 2)))
    attenuation = float(20.0 * np.log10(max(rms_d, 1e-15) / max(rms_e, 1e-15)))

    manifest = {
        "samples": args.samples,
        "sample_rate_hz": 48000,
        "L": DEFAULT_L,
        "M": DEFAULT_M,
        "mu": 2.0 ** -MU_SHIFT,
        "mu_shift": MU_SHIFT,
        "mu_s": 2.0 ** -MU_S_SHIFT,
        "mu_s_shift": MU_S_SHIFT,
        "sample_format": "signed 24-bit Q1.23",
        "shat_format": "signed 24-bit Q2.22",
        "weight_format": "signed 32-bit Q4.28",
        "rounding": "nearest, ties away from zero",
        "narrowing": "saturate",
        "weight_limit_real": W_LIMIT / (1 << 28),
        "error_power_limit_q46": ERROR_POWER_LIMIT_Q46,
        "fixed_model_attenuation_after_settling_db": attenuation,
        "files": [
            "fxlms_xref.hex", "fxlms_eerr.hex", "fxlms_yanti.hex",
            "fxlms_shat.hex", "fxlms_w_over.hex",
        ],
    }
    (args.output_dir / "fxlms_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    print(f"Vectors written to: {args.output_dir.resolve()}")


if __name__ == "__main__":
    main()
