from __future__ import annotations

import json
import unittest
from unittest.mock import patch
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "harness"))

import acceptance_state  # noqa: E402

ACCEPTANCE_ID = "V0-P6-R2-CHECKPOINT-ACCEPTED-001"
ORIGINAL = ROOT / "config/control/harness/acceptance" / f"{ACCEPTANCE_ID}.v1.json"
ADDENDUM = (
    ROOT
    / "config/control/harness/acceptance"
    / "V0-P6-R2-CHECKPOINT-ACCEPTED-ADDENDUM-001.v1.json"
)


class V0P6AcceptanceEffectiveStateTests(unittest.TestCase):
    def test_01_original_acceptance_remains_historically_readable(self) -> None:
        original = acceptance_state.load_acceptance_record(ACCEPTANCE_ID, ROOT)
        self.assertIsNotNone(original)
        raw = json.loads(ORIGINAL.read_text(encoding="utf-8"))
        self.assertEqual(original, raw, "original record must not be rewritten")
        self.assertEqual(original["status"], "ACCEPTED")
        self.assertEqual(
            original["accepted_product_lineage_head"],
            "9ade3233f8d9f16b77edcc8cf273fe8e649d5637",
        )
        self.assertTrue(original["machine_evidence"]["all_required_predicates_complete"])

    def test_02_effective_state_sees_the_addendum(self) -> None:
        addendum = json.loads(ADDENDUM.read_text(encoding="utf-8"))
        self.assertEqual(addendum["references_acceptance_id"], ACCEPTANCE_ID)
        effective = acceptance_state.load_effective_acceptance(ACCEPTANCE_ID, ROOT)
        self.assertIsNotNone(effective)
        self.assertEqual(effective["acceptance_status"], "ACCEPTED_BY_OWNER_AUTHORITY")
        self.assertEqual(
            effective["evidence_reconciliation"]["status"], "PARTIALLY_RETRACTED"
        )
        self.assertTrue(effective["evidence_reconciliation"]["unresolved"])
        self.assertTrue(effective["addendums"])
        self.assertIsNotNone(effective["hardening"])
        self.assertEqual(
            effective["hardening"].get("branch"),
            "repair/v0-p6-persistence-exactly-once-r1",
        )

    def test_03_old_completeness_claim_cannot_authorize_successor_runtime(self) -> None:
        effective = acceptance_state.load_effective_acceptance(ACCEPTANCE_ID, ROOT)
        self.assertTrue(
            effective["original"]["machine_evidence"]["all_required_predicates_complete"]
        )
        successor = effective["successor"]
        self.assertFalse(successor.get("runtime_mutation_authorized", True))
        self.assertEqual(
            successor.get("activation_gate"),
            "MAIN_OWNED_CONTROL_UPDATE_REQUIRED_AFTER_EFFECTIVE_RECONCILIATION",
        )

    def test_04_sm1_eligibility_is_fail_closed_before_activation(self) -> None:
        # Missing activation evidence is a fixture, not an assertion about current main.
        with patch.object(acceptance_state, "_current_sm1_control", return_value=({}, {})):
            eligibility = acceptance_state.sm1_eligibility(ROOT)
        self.assertFalse(eligibility["eligible_for_runtime_activation"])
        self.assertIn(
            "EVIDENCE_RECONCILIATION_MUST_BE_CONSUMED_BY_MAIN_OWNED_CONTROL_UPDATE",
            eligibility["gates"],
        )
        self.assertIn(
            "EG5_EDGE_LOCATOR_CORRECTNESS_REPAIR_REQUIRED_SEPARATE_MISSION",
            eligibility["gates"],
        )
        successor = acceptance_state.load_effective_acceptance(ACCEPTANCE_ID, ROOT)[
            "successor"
        ]
        self.assertEqual(successor.get("checkpoint"), acceptance_state.SM1_CHECKPOINT)
        self.assertTrue(successor["activation_requires_main_owned_control_update"])

    def test_05_eg5_gate_is_evidence_driven_not_permanent(self) -> None:
        activation_without_evidence = {
            "checkpoint": acceptance_state.SM1_CHECKPOINT,
            "state": "PRE_DISPATCH_CONTROL_READY",
            "main_declared_exact_successor_base": "base/current",
        }
        scheduler_without_evidence = {
            "v0_product_train_routing": {
                "current_checkpoint": acceptance_state.SM1_CHECKPOINT,
                "accepted_predecessor_base": "base/current",
            }
        }
        self.assertFalse(
            acceptance_state._eg5_repair_consumed(
                activation_without_evidence, scheduler_without_evidence
            )
        )

        activation_with_evidence = {
            **activation_without_evidence,
            "control_evidence": {
                "eg5_repair_pr": 215,
                "eg5_project_control_result": "SUCCESS",
                "eg5_repair_merge": "21c74307812ffea56ef1aae263f029eec2549460",
            },
        }
        self.assertTrue(
            acceptance_state._eg5_repair_consumed(
                activation_with_evidence, scheduler_without_evidence
            )
        )

        scheduler_with_evidence = {
            "v0_product_train_routing": {
                **scheduler_without_evidence["v0_product_train_routing"],
                "eg5_correctness_repair": {
                    "pr": 215,
                    "project_control_result": "SUCCESS",
                    "main_merge": "21c74307812ffea56ef1aae263f029eec2549460",
                },
            }
        }
        self.assertTrue(
            acceptance_state._eg5_repair_consumed(
                activation_without_evidence, scheduler_with_evidence
            )
        )

    def test_06_reconciliation_consumption_requires_matching_live_control(self) -> None:
        activation = {
            "checkpoint": acceptance_state.SM1_CHECKPOINT,
            "state": "PRE_DISPATCH_CONTROL_READY",
            "main_declared_exact_successor_base": "base/current",
        }
        scheduler = {
            "v0_product_train_routing": {
                "current_checkpoint": acceptance_state.SM1_CHECKPOINT,
                "accepted_predecessor_base": "base/current",
            }
        }
        self.assertTrue(acceptance_state._reconciliation_consumed(activation, scheduler))
        scheduler["v0_product_train_routing"]["accepted_predecessor_base"] = "stale/base"
        self.assertFalse(acceptance_state._reconciliation_consumed(activation, scheduler))


if __name__ == "__main__":
    unittest.main()
