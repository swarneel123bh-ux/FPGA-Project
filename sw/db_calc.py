"""Software reference for rtl/db_calc.v (centi-dBFS output)."""
from __future__ import annotations

LOG2_FRAC_Q8 = (0, 22, 44, 63, 82, 100, 118, 134,
                150, 165, 179, 193, 207, 220, 232, 244)


def _round_div_away(numerator: int, denominator: int) -> int:
    if numerator >= 0:
        return (numerator + denominator // 2) // denominator
    return -(((-numerator) + denominator // 2) // denominator)


def power_q46_to_db_centi(power_q46: int) -> int:
    power = int(power_q46)
    if power < 0 or power >= (1 << 64):
        raise ValueError("power_q46 must be an unsigned 64-bit integer")
    if power == 0:
        return -12000
    msb = power.bit_length() - 1
    if msb >= 4:
        mantissa_index = (power >> (msb - 4)) & 0xF
    else:
        mantissa_index = (power << (4 - msb)) & 0xF
    log2_q8 = (msb - 46) * 256 + LOG2_FRAC_Q8[mantissa_index]
    return _round_div_away(log2_q8 * 30103, 25600)
