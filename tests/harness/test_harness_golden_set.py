from __future__ import annotations
import json, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; GOLDEN=ROOT/"tests/harness/golden/cases.v1.json"
class HarnessGoldenSetTests(unittest.TestCase):
    def test_golden_set_has_behavioral_breadth_and_negative_criteria(self):
        value=json.loads(GOLDEN.read_text(encoding="utf-8")); self.assertEqual("distributed_world_simulator.harness_golden_cases.v1",value["schema"]); cases=value["cases"]; self.assertGreaterEqual(len(cases),8); ids=[x["id"] for x in cases]; self.assertEqual(len(ids),len(set(ids))); categories={x["category"] for x in cases}; self.assertGreaterEqual(len(categories),4); self.assertIn("safety",categories); self.assertGreaterEqual(sum(x["difficulty"]>=3 for x in cases),2)
        for item in cases: self.assertTrue(item["accept"]); self.assertTrue(item["reject"])
if __name__=="__main__": unittest.main()
