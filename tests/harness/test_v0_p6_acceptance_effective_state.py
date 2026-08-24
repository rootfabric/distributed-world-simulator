from __future__ import annotations

import json
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "harness"))

import acceptance_state  # noqa: E402

ACCEPTANCE_ID = "V0-P6-R2-CHECKPOINT-ACCEPTED-001"
ORIGINAL = (
    ROOT
    / "config/control/harness/acceptance"
    / f"{ACCEPTANCE_ID}.v1.json"
)
ADDENDUM = (
    ROOT
    / "config/control/harness/acceptance"
    / "V0-P6-R2-CHECKPOINT-ACCEPTED-ADDENDUM-001.v1.json"
)


class V0P6AcceptanceEffectiveStateTests(unittest.TestCase):
    def test_01_original_acceptance_remains_historically_readable(self) -> None:
        """Property 1: the immutable original record is readable verbatim."""
        original = acceptance_state.load_acceptance_record(ACCEPTANCE_ID, ROOT)
        self.assertIsNotNone(original)
        raw = json.loads(ORIGINAL.read_text(encoding="utf-8"))
        self.assertEqual(original, raw, "original record must not be rewritten")
        self.assertEqual(original["status"], "ACCEPTED")
        self.assertEqual(
            original["accepted_product_lineage_head"],
            "9ade3233f8d9f16b77edcc8cf273fe8e649d5637",
        )
        # The historically false claim is still present in the ORIGINAL -
        # history is append-only; it must simply never authorize anything.
        self.assertTrue(
            original["machine_evidence"]["all_required_predicates_complete"]
        )

    def test_02_effective_state_sees_the_addendum(self) -> None:
        """Property 2: the effective view consumes the addendum."""
        addendum = json.loads(ADDENDUM.read_text(encoding="utf-8"))
        self.assertEqual(
            addendum["references_acceptance_id"], ACCEPTANCE_ID
        )
        effective = acceptance_state.load_effective_acceptance(
            ACCEPTANCE_ID, ROOT
        )
        self.assertIsNotNone(effective)
        self.assertEqual(effective["acceptance_status"], "ACCEPTED_BY_OWNER_AUTHORITY")
        self.assertEqual(
            effective["evidence_reconciliation"]["status"],
            "PARTIALLY_RETRACTED",
        )
        self.assertTrue(effective["evidence_reconciliation"]["unresolved"])
        self.assertTrue(effective["addendums"])
        self.assertIsNotNone(effective["hardening"])
        self.assertEqual(
            effective["hardening"].get("branch"),
            "repair/v0-p6-persistence-exactly-once-r1",
        )

    def test_03_old_completeness_claim_cannot_authorize_successor_runtime(
        self,
    ) -> None:
        """Property 3: all_required_predicates_complete=true alone must never
        authorize successor runtime mutation while the reconciliation
        addendum is in force."""
        effective = acceptance_state.load_effective_acceptance(
            ACCEPTANCE_ID, ROOT
        )
        self.assertTrue(
            effective["original"]["machine_evidence"][
                "all_required_predicates_complete"
            ]
        )
        successor = effective["successor"]
        self.assertFalse(successor.get("runtime_mutation_authorized", True))
        self.assertEqual(
            successor.get("activation_gate"),
            "MAIN_OWNED_CONTROL_UPDATE_REQUIRED_AFTER_EFFECTIVE_RECONCILIATION",
        )

    def test_04_sm1_eligibility_is_gated_by_effective_state(self) -> None:
        """Property 4: SM1 eligibility flows through the EFFECTIVE view and
        stays gated (including the explicit EG5 entry blocker)."""
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
        successor_gate = acceptance_state.load_effective_acceptance(
            ACCEPTANCE_ID, ROOT
        )["successor"]
        self.assertEqual(
            successor_gate.get("checkpoint"),
            "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION",
        )
        self.assertTrue(
            successor_gate["activation_requires_main_owned_control_update"]
        )


if __name__ == "__main__":
    unittest.main()
