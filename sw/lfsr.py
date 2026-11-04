"""Bit-exact Python reference for rtl/lfsr.v."""
from __future__ import annotations

from dataclasses import dataclass

SEED = 0x5A5A5A
STATE_BITS = 23
STATE_MASK = (1 << STATE_BITS) - 1
SAMPLE_AMPLITUDE_Q23 = 1 << 21  # +/-0.25 in signed Q1.23


@dataclass(frozen=True)
class LFSRSample:
    state: int
    sample: int


def step(state: int) -> LFSRSample:
    """Advance once and return new state plus Q1.23 output sample.

    This follows the RTL exactly: feedback=state[22] XOR state[17], shift
    left, insert feedback in bit zero, and use the new state's LSB as sign.
    """
    if not 0 < int(state) <= STATE_MASK:
        raise ValueError("LFSR state must be a non-zero 23-bit value")
    feedback = ((state >> 22) ^ (state >> 17)) & 1
    new_state = ((state << 1) & STATE_MASK) | feedback
    sample = SAMPLE_AMPLITUDE_Q23 if (new_state & 1) else -SAMPLE_AMPLITUDE_Q23
    return LFSRSample(new_state, sample)


def generate(samples: int, seed: int = SEED) -> list[LFSRSample]:
    if samples < 0:
        raise ValueError("samples must be non-negative")
    if not 0 < seed <= STATE_MASK:
        raise ValueError("seed must be a non-zero 23-bit value")
    out: list[LFSRSample] = []
    state = int(seed)
    for _ in range(samples):
        item = step(state)
        out.append(item)
        state = item.state
    return out


def write_hex_vectors(samples: int, output_dir: str = "sim/vectors") -> None:
    from pathlib import Path

    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    sequence = generate(samples)
    (destination / "lfsr_state.hex").write_text(
        "".join(f"{item.state:06x}\n" for item in sequence), encoding="ascii"
    )
    (destination / "lfsr_sample.hex").write_text(
        "".join(f"{item.sample & 0xFFFFFF:06x}\n" for item in sequence), encoding="ascii"
    )


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=256)
    parser.add_argument("--output-dir", default="sim/vectors")
    args = parser.parse_args()
    write_hex_vectors(args.samples, args.output_dir)
    print(f"Wrote {args.samples} LFSR state/sample vectors to {args.output_dir}")
