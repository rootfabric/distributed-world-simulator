from __future__ import annotations

import json
import unittest
from pathlib import Path


class I24DurableDirectoryContractTests(unittest.TestCase):
    def test_i2_4_contract_01_machine_contract_freezes_durable_boundary(self) -> None:
        root = Path(__file__).resolve().parents[4]
        path = root / "config/research/seamless/i2/i2-4-durable-directory-contract.v1.json"
        contract = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual("SM1-I2.4", contract["checkpoint"])
        self.assertEqual(
            "2e709249b5854e1bd0584041c3731e5bf102bde6",
            contract["accepted_i2_3_base"],
        )
        self.assertEqual(
            "SM1_I2_3_FRESH_INDEPENDENT_REVIEW_PASS",
            contract["accepted_i2_3_review"],
        )
        self.assertFalse(contract["production_activation"])
        self.assertTrue(contract["donor_only"])
        self.assertEqual(
            "POSIX_ATOMIC_FILE_SINGLE_ACTIVE_DIRECTORY_PROCESS",
            contract["backend"],
        )
        self.assertIn(
            "ONLY_THEN_PUBLISH_CREATED_OR_CAS_OK",
            contract["durable_commit_protocol"],
        )
        self.assertIn(
            "POST_DURABLE_COMMIT_PRE_RESPONSE_PROCESS_CRASH_RECOVERS_COMMITTED_STATE",
            contract["durability_invariants"],
        )
        self.assertIn(
            "CORRUPT_CANONICAL_SNAPSHOT_FAILS_CLOSED",
            contract["durability_invariants"],
        )
        self.assertIn(
            "MULTIPLE_SIMULTANEOUS_DIRECTORY_PROCESS_WRITERS",
            contract["out_of_scope"],
        )
        self.assertEqual(
            "SM1-I2.5_CRASH_RESTART_PARTITION_FENCING",
            contract["next_checkpoint"],
        )


if __name__ == "__main__":
    unittest.main()
