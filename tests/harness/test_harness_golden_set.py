from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOLDEN = ROOT / "tests/harness/golden/cases.v1.json"


class HarnessGoldenSetTests(unittest.TestCase):
    def test_golden_set_has_behavioral_breadth_and_negative_criteria(self):
        value = json.loads(GOLDEN.read_text(encoding="utf-8"))
        self.assertEqual(
            "distributed_world_simulator.harness_golden_cases.v1",
            value["schema"],
        )
        cases = value["cases"]
        self.assertGreaterEqual(len(cases), 15)
        ids = [item["id"] for item in cases]
        self.assertEqual(len(ids), len(set(ids)))
        categories = {item["category"] for item in cases}
        self.assertGreaterEqual(len(categories), 4)
        self.assertIn("safety", categories)
        self.assertGreaterEqual(sum(item["difficulty"] >= 3 for item in cases), 8)
        for item in cases:
            self.assertTrue(item["accept"])
            self.assertTrue(item["reject"])

    def test_self_closing_execution_failures_are_pinned(self):
        cases = {
            item["id"]: item
            for item in json.loads(GOLDEN.read_text(encoding="utf-8"))["cases"]
        }
        for case_id in (
            "GH10_AUTOMATABLE_FIX_REQUIRED",
            "GH11_REVIEW_FAIL_ROUTING",
            "GH12_REPEATED_DEFECT_TAKEOVER",
            "GH13_UNFINISHED_ACTIVE_ROLE",
            "GH14_CLOSE_GATE",
            "GH15_PREMATURE_REVIEW",
        ):
            self.assertIn(case_id, cases)
            self.assertTrue(cases[case_id]["accept"])
            self.assertTrue(cases[case_id]["reject"])


if __name__ == "__main__":
    unittest.main()
