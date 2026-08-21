from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RECORD = ROOT / "config/control/harness/acceptance/V0-P5-R2-CHECKPOINT-ACCEPTED-001.v1.json"


class V0P5CheckpointAcceptanceRecordTests(unittest.TestCase):
    def test_acceptance_is_exact_and_does_not_self_activate_p6(self) -> None:
        record = json.loads(RECORD.read_text(encoding="utf-8"))
        self.assertEqual(record["decision"], "V0_P5_CHECKPOINT_ACCEPTED")
        self.assertEqual(record["status"], "ACCEPTED")
        self.assertEqual(
            record["accepted_runtime_head"],
            "5434558856c00b588eed5369d2c613cd4b9858bb",
        )
        self.assertEqual(
            record["accepted_product_lineage_head"],
            "491ca7d058690d3de5fcea5e41aaee230a31b3ab",
        )
        proposal = record["checkpoint_proposal"]
        self.assertEqual(proposal["proposal_commit"], "e42c23efbdd6bc37366a789a71986dd4aa920679")
        self.assertEqual(proposal["sequence"], 33)
        self.assertEqual(proposal["work_state"], "CHECKPOINT_PROPOSED")
        evidence = record["machine_evidence"]
        self.assertEqual(evidence["standard_pc0"], "NON_RED")
        self.assertEqual(evidence["directional_pc0"], "NON_RED")
        self.assertEqual(evidence["cross_branch_overlaps"], [])
        self.assertEqual(evidence["findings"], [])
        self.assertTrue(evidence["all_required_predicates_complete"])
        self.assertEqual(evidence["post_integration_continuous"], "239/239 PASS")
        self.assertIsNone(evidence["post_integration_first_failure"])
        successor = record["successor"]
        self.assertEqual(successor["checkpoint"], "V0_P6_PERSISTENT_SHARED_OUTPOST")
        self.assertEqual(successor["runtime_branch"], "feature/v0-p6-persistent-shared-outpost")
        self.assertEqual(
            successor["main_declared_exact_successor_base"],
            record["accepted_product_lineage_head"],
        )
        self.assertTrue(successor["activation_still_requires_main_owned_control_update"])
        self.assertFalse(successor["runtime_mutation_authorized_by_this_record"])


if __name__ == "__main__":
    unittest.main()
