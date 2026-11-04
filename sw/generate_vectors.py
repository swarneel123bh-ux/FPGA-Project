"""Generate LFSR and secondary-path reference vectors for the Verilog testbenches.

Run from member_c_package root:
    python -m member_c.generate_vectors --lfsr-samples 256 --id-samples 8000
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from .lfsr import generate, SEED
from .sec_path_id import (
    identify_secondary_path_fixed, make_lfsr_plant_vectors,
    coefficient_error_norm, fixed_to_float,
)


def write_hex(path: Path, values: list[int], bits: int) -> None:
    width = (bits + 3) // 4
    mask = (1 << bits) - 1
    path.write_text("".join(f"{int(v) & mask:0{width}x}\n" for v in values), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lfsr-samples", type=int, default=256)
    parser.add_argument("--id-samples", type=int, default=8000)
    parser.add_argument("--output-dir", type=Path, default=Path("sim/vectors"))
    args = parser.parse_args()
    if args.lfsr_samples <= 0 or args.id_samples <= 0:
        raise SystemExit("sample counts must be positive")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    lfsr_sequence = generate(args.lfsr_samples, SEED)
    write_hex(args.output_dir / "lfsr_state.hex", [x.state for x in lfsr_sequence], 23)
    write_hex(args.output_dir / "lfsr_sample.hex", [x.sample for x in lfsr_sequence], 24)

    probe, measured, _s_q = make_lfsr_plant_vectors(args.id_samples)
    result = identify_secondary_path_fixed(probe, measured, model_length=128, mu_s_shift=6)
    write_hex(args.output_dir / "sec_expected_shat.hex", list(result.coefficients), 24)

    true_taps = (0.0, 0.0, 0.70, 0.20)
    error_norm = coefficient_error_norm(result.coefficients, true_taps)
    metrics = {
        "seed_hex": f"0x{SEED:06X}",
        "lfsr_taps": "state[22] XOR state[17]",
        "probe_peak_real": 0.25,
        "probe_raw_q1_23": 1 << 21,
        "calibration_samples": args.id_samples,
        "model_length_M": 128,
        "mu_s": 2.0 ** -6,
        "sample_format": "signed 24-bit Q1.23",
        "coefficient_format": "signed 24-bit Q2.22",
        "true_nonzero_secondary_taps": {"S[2]": 0.70, "S[3]": 0.20},
        "estimated_S2": fixed_to_float(result.coefficients[2], 22),
        "estimated_S3": fixed_to_float(result.coefficients[3], 22),
        "coefficient_error_norm": error_norm,
        "sample_count": result.samples_processed,
        "expected_id_cycles_per_sample": 256,
    }
    (args.output_dir / "member_c_expected_metrics.json").write_text(
        json.dumps(metrics, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(metrics, indent=2))
    print(f"Vectors written to {args.output_dir.resolve()}")


if __name__ == "__main__":
    main()
