from __future__ import annotations

import json
import unittest
from pathlib import Path


class I26IntegratedOneWriterContractTests(unittest.TestCase):
    def test_i2_6_contract_01_exact_lineage_scope_and_gates(self) -> None:
        repo_root = Path(__file__).resolve().parents[4]
        path = repo_root / "config/research/seamless/i2/i2-6-integrated-one-writer-contract.v1.json"
        contract = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(
            "distributed_world_simulator.sm1_i2_6_integrated_one_writer_contract.v1",
            contract["schema"],
        )
        self.assertEqual("SM1-I2.6", contract["checkpoint"])
        self.assertEqual(
            "f430bef4b8c942e860ba228e0a5c62fb9ac4eb9d",
            contract["accepted_i2_5_base"],
        )
        self.assertEqual(
            "SM1_I2_5_FRESH_INDEPENDENT_REVIEW_PASS",
            contract["accepted_i2_5_review"],
        )
        self.assertFalse(contract["production_activation"])
        self.assertTrue(contract["donor_only"])
        self.assertEqual(
            "AT_MOST_ONE_AUTHORIZED_PROCESS_INCARNATION_PER_STABLE_CANONICAL_ROUND",
            contract["proof_scope"]["safety_claim"],
        )
        self.assertEqual(
            "INDETERMINATE_NEVER_COUNT_AS_PASS",
            contract["proof_scope"]["canonical_move_during_round"],
        )
        self.assertEqual(
            "MUST_ROTATE_AUTHORITY_INCARNATION_AND_FENCING_TOKEN_VIA_ACCEPTED_I2_3_REPLACEMENT_BEFORE_MUTATION",
            contract["process_lifecycle_invariant"]["overlapping_restart"],
        )
        self.assertEqual(
            "PROBE_MUST_REPORT_MULTIPLE_AUTHORIZED_VIOLATION",
            contract["process_lifecycle_invariant"]["duplicate_exact_tuple_behavior"],
        )
        self.assertIn("ATOMIC_GAMEPLAY_STATE_COMMIT", contract["out_of_scope"])
        self.assertIn(
            "CRYPTOGRAPHIC_PREVENTION_OF_CURRENT_TUPLE_CLONING",
            contract["out_of_scope"],
        )
        self.assertEqual(
            [f"I2.6-OW-{i:02d}" for i in range(1, 18)] + ["I2.6-CONTRACT-01"],
            contract["required_tests"],
        )
        self.assertEqual(
            "FRESH_INDEPENDENT_EXACT_HEAD_REVIEW_OF_I2_6",
            contract["next_gate"],
        )


if __name__ == "__main__":
    unittest.main()
