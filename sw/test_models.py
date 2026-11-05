"""Self-tests for Member C Python reference models."""
from __future__ import annotations

import unittest

from .lfsr import generate, SEED
from .sec_path_id import make_lfsr_plant_vectors, identify_secondary_path_fixed, coefficient_error_norm
from .db_calc import power_q46_to_db_centi


class LfsrTests(unittest.TestCase):
    def test_seed_and_output_levels(self):
        seq = generate(32)
        self.assertNotEqual(seq[0].state, SEED)
        self.assertEqual({x.sample for x in seq}, {-(1 << 21), (1 << 21)})

    def test_no_zero_state(self):
        self.assertTrue(all(x.state != 0 for x in generate(1000)))


class SecondaryPathTests(unittest.TestCase):
    def test_fixed_point_identification_converges(self):
        probe, measured, _ = make_lfsr_plant_vectors(8000)
        result = identify_secondary_path_fixed(probe, measured, 128, 6)
        err = coefficient_error_norm(result.coefficients, (0.0, 0.0, 0.70, 0.20))
        self.assertLess(err, 0.005)
        self.assertEqual(result.samples_processed, 8000)


class DbTests(unittest.TestCase):
    def test_known_power_levels(self):
        self.assertEqual(power_q46_to_db_centi(1 << 46), 0)
        self.assertEqual(power_q46_to_db_centi(1 << 44), -602)
        self.assertEqual(power_q46_to_db_centi(1 << 43), -903)
        self.assertEqual(power_q46_to_db_centi(0), -12000)


if __name__ == "__main__":
    unittest.main()
