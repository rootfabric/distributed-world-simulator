"""MVP8 historical evidence-map enum repair: fail closed without schema expansion.

These are control-only source/evidence tests. R1 receipt status being PASS
does NOT make the independent R1 verifier's EVIDENCE_GAP into VERIFIED,
and does NOT modify the main-owned product checkpoint/acceptance record.
"""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
PREFIX = Path("config/control/harness/executions/E2026-09-09-V0-MVP-R1")
PATH = PREFIX / "evidence/MVP8-EVIDENCE-MAP-90BC1026-R1.v1.json"
SCHEMA_PATH = Path("config/control/harness/evidence-map.schema.v1.json")
SUBJECT = "90bc1026f0f5749492107191233330f87c8c70df"
TREE = "4b6f2d48f7ef8d9c441ae89d2cbb02c730ef7f71"
OLD_VALUES = {
    "focused_validation": "PASS_TWO_EXACT_RUNS",
    "full_regression": "PENDING",
    "pc0": "PENDING",
    "directional_pc0": "PENDING",
    "review_verdict": "PASS_READY_FOR_FRESH_REVIEW",
}
NEW_VALUES = {
    "focused_validation": "PASS",
    "full_regression": "PASS",
    "pc0": "NON_RED",
    "directional_pc0": "NON_RED",
    "review_verdict": "PASS",
}


def load(path: Path) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


class HistoricalMvp8EvidenceMapEnumRepair(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = load(SCHEMA_PATH)
        cls.record = load(PATH)
        Draft202012Validator.check_schema(cls.schema)
        cls.validator = Draft202012Validator(cls.schema)

    def test_full_historical_record_conforms_to_strict_current_schema(self):
        errors = list(self.validator.iter_errors(self.record))
        self.assertEqual(errors, [], "\n".join(str(error) for error in errors))
        self.assertEqual(self.record["schema"], "distributed_world_simulator.harness_evidence_map.v1")
        self.assertEqual(self.record["evidence_head_sha"], SUBJECT)
        self.assertEqual(self.record["work_order_id"], "V0-MVP-R1-WO-001")
        self.assertEqual(self.record["canonical_truth_changed"], False)
        self.assertEqual(self.record["architecture_ownership_changed"], False)

    def test_exactly_five_status_keys_normalized_without_new_enum_values(self):
        for key, value in NEW_VALUES.items():
            self.assertEqual(self.record[key], value)
            self.assertIn(value, self.schema["properties"][key]["enum"])
        for key, old_value in OLD_VALUES.items():
            self.assertNotIn(old_value, self.schema["properties"][key]["enum"])

    def test_old_illegal_tokens_cannot_pass_the_current_schema(self):
        for key, old_value in OLD_VALUES.items():
            with self.subTest(key=key):
                tampered = deepcopy(self.record)
                tampered[key] = old_value
                self.assertFalse(self.validator.is_valid(tampered))

    def test_focused_two_exact_runs_belong_to_the_same_frozen_subject(self):
        receipt = load(PREFIX / "evidence/MVP8-IMPLEMENTER-EXACT-EVIDENCE-90BC1026-R1.v1.json")
        self.assertEqual(receipt["frozen_product"]["head_sha"], SUBJECT)
        self.assertEqual(receipt["frozen_product"]["tree_sha"], TREE)
        attempts = receipt["exact_linux_ci"]["attempts"]
        self.assertGreaterEqual(len(attempts), 2)
        self.assertTrue(all(a["conclusion"] == "success" for a in attempts[:2]))
        self.assertTrue(all(a["acceptance_checks"] == "20/20" for a in attempts[:2]))
        self.assertEqual(self.record["focused_validation"], "PASS")

    def test_full_world_and_pc0_exact_subject_receipts(self):
        regression = load(PREFIX / "evidence/MVP8-FULL-WORLD-CORE-90BC1026-R1.v1.json")
        self.assertEqual((regression["subject_head"], regression["subject_tree"]),
                         (SUBJECT, TREE))
        self.assertIs(regression["world_regression"]["passed"], True)
        self.assertEqual(regression["world_regression"]["declared_test_count"], 349)
        self.assertEqual(regression["world_regression"]["failed_steps"], 0)
        self.assertEqual(self.record["full_regression"], "PASS")

        pc0 = load(PREFIX / "evidence/MVP8-PC0-90BC1026-R1.v1.json")
        self.assertEqual((pc0["subject_head"], pc0["subject_tree"]), (SUBJECT, TREE))
        self.assertIs(pc0["standard_non_red"], True)
        self.assertIs(pc0["directional_non_red"], True)
        self.assertEqual(pc0["standard_pc0"], "YELLOW")
        self.assertEqual(pc0["directional_pc0"], "YELLOW")
        self.assertEqual((self.record["pc0"], self.record["directional_pc0"]),
                         ("NON_RED", "NON_RED"))

    def test_independent_r1_review_pass_is_not_a_verifier_or_product_acceptance(self):
        review = load(PREFIX / "verifications/MVP8-INDEPENDENT-REVIEW-90BC1026-R1.v1.json")
        self.assertEqual((review["reviewed_head_sha"], review["reviewed_tree_sha"]),
                         (SUBJECT, TREE))
        self.assertEqual(review["role"], "FRESH_INDEPENDENT_REVIEWER")
        self.assertEqual(review["verdict"], "PASS")
        self.assertEqual(self.record["review_verdict"], "PASS")

        verify = load(PREFIX / "verifications/MVP8-INDEPENDENT-VERIFICATION-90BC1026-R1.v1.json")
        self.assertEqual((verify["PRODUCT_HEAD"], verify["PRODUCT_TREE"]), (SUBJECT, TREE))
        self.assertEqual(verify["verdict"], "EVIDENCE_GAP")
        self.assertFalse(verify["predicate_verified"])
        self.assertFalse(verify["merge_performed"])
        self.assertNotIn("verifier_verdict", self.record)
        self.assertNotIn("mvp8_predicate_verified", self.record)

    def test_new_statuses_do_not_claim_schema_expansion_or_main_authorization(self):
        self.assertEqual(self.schema["properties"]["focused_validation"]["enum"],
                         ["PASS", "FAIL", "NOT_REQUIRED"])
        self.assertEqual(self.schema["properties"]["full_regression"]["enum"],
                         ["PASS", "FAIL", "NOT_REQUIRED"])
        for field in ("pc0", "directional_pc0"):
            self.assertEqual(self.schema["properties"][field]["enum"],
                             ["NON_RED", "RED", "NOT_RUN"])
        self.assertEqual(self.schema["properties"]["review_verdict"]["enum"],
                         ["PASS", "FAIL", "INSUFFICIENT_EVIDENCE"])
        self.assertTrue(self.record["remaining_risks"])
        self.assertTrue(self.record["evidence_gaps"])


if __name__ == "__main__":
    unittest.main()
