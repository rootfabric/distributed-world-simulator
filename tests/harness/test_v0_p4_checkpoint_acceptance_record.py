from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RECORD = ROOT / "config/control/harness/acceptance/V0-P4-R1-CHECKPOINT-ACCEPTED-001.v1.json"


class V0P4CheckpointAcceptanceRecordTests(unittest.TestCase):
    def test_acceptance_is_exact_and_does_not_self_activate_p5(self) -> None:
        record = json.loads(RECORD.read_text(encoding="utf-8"))
        self.assertEqual(record["decision"], "V0_P4_CHECKPOINT_ACCEPTED")
        self.assertEqual(record["status"], "ACCEPTED")
        self.assertEqual(
            record["accepted_runtime_head"],
            "2a6721cdf02fa1134c59d1ab98bb7b597c66821d",
        )
        self.assertEqual(
            record["checkpoint_proposal"]["proposal_commit"],
            "aedc419f24dea2f836a166f0d2ebc88008af7d4f",
        )
        self.assertEqual(record["checkpoint_proposal"]["sequence"], 54)
        self.assertEqual(record["machine_evidence"]["standard_pc0"], "NON_RED")
        self.assertEqual(record["machine_evidence"]["directional_pc0"], "NON_RED")
        self.assertTrue(record["machine_evidence"]["all_required_predicates_complete"])
        self.assertEqual(record["machine_evidence"]["findings"], [])
        successor = record["successor"]
        self.assertEqual(successor["checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(
            successor["main_declared_exact_successor_base"],
            record["accepted_product_lineage_head"],
        )
        self.assertTrue(successor["activation_still_requires_main_owned_control_update"])
        self.assertFalse(successor["runtime_mutation_authorized_by_this_record"])


if __name__ == "__main__":
    unittest.main()
