"""R31b durable stage raw trace reducer: exact and fail-closed negatives."""
from __future__ import annotations
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
from analyze_r31b_durable_stages import analyze, FIELDS

def capture(t: int, *, valid=True, missing="", sum_over=False, seam=1) -> dict:
    stages={k:1.0 for k in FIELDS}
    stages["total_ms"] = 8.5 if not sum_over else 2.0
    stages.update(valid=valid, seam_coordinator_count=seam, player_count=2)
    stages.pop(missing,None)
    return {
        "t_us":t, "kind":"checkpoint_capture", "measure":True,
        "data":{"r3c4r2_worker_envelope":True, "r31_cache_hit":True,
                "authority_ms":12.0,
                "r31b_durable_stages":stages}
    }

def run(events: list[dict]) -> dict:
    with tempfile.TemporaryDirectory() as d:
        p=Path(d)/"server.jsonl"
        p.write_text("".join(json.dumps(ev)+"\n" for ev in events),encoding="utf-8")
        return analyze(p)

class DurableMetrics(unittest.TestCase):
    def test_all_exact(self):
        r=run([capture(i) for i in range(50)])
        self.assertEqual(r["verdict"],"R31B_SOURCE_ATTRIBUTION_VALID_ONLY")
        self.assertEqual(r["checkpoint_count"],50)
        self.assertEqual(r["metrics_ms"]["snapshot_ms"]["p99"],1.0)
        self.assertEqual(r["metrics_ms"]["total_ms"]["p50"],8.5)

    def test_missing_stage_fails(self):
        with self.assertRaisesRegex(ValueError,"R31B_INVALID_resource_ms"):
            run([capture(i,missing="resource_ms") for i in range(50)])

    def test_invalid_state_fails(self):
        with self.assertRaisesRegex(ValueError,"R31B_INVALID_DURABLE_STATE"):
            run([capture(i,valid=False) for i in range(50)])

    def test_unbound_seam_fails(self):
        with self.assertRaisesRegex(ValueError,"R31B_ACTIVE_SEAM_NOT_MEASURED"):
            run([capture(i,seam=0) for i in range(50)])

    def test_stage_overshoot_fails(self):
        with self.assertRaisesRegex(ValueError,"R31B_STAGE_ACCOUNTING_OVERSHOOT"):
            run([capture(i,sum_over=True) for i in range(50)])

    def test_missing_capture_fails(self):
        with self.assertRaisesRegex(ValueError,"R31B_INSUFFICIENT_SAMPLES"):
            run([])

    def test_fallback_captures_are_separate_population(self):
        # Warmup seam-unbound fallback captures must not poison the domain
        # population, but the run still needs enough seam-bound captures.
        fallback = {
            "t_us": 0, "kind": "checkpoint_capture", "measure": True,
            "data": {"r3c4r2_worker_envelope": True, "r31_cache_hit": True,
                     "authority_ms": 9.0,
                     "r31b_durable_stages": {"fallback_ms": 8.9,
                                             "total_ms": 8.9,
                                             "seam_coordinator_count": 0}},
        }
        r = run([fallback] * 5 + [capture(i) for i in range(20)])
        self.assertEqual(r["verdict"], "R31B_SOURCE_ATTRIBUTION_VALID_ONLY")
        self.assertEqual(r["fallback_captures"], 5)
        self.assertEqual(r["domain_captures"], 20)
        self.assertEqual(r["checkpoint_count"], 25)

    def test_zero_domain_captures_fails(self):
        fallback = {
            "t_us": 0, "kind": "checkpoint_capture", "measure": True,
            "data": {"r3c4r2_worker_envelope": True, "r31_cache_hit": True,
                     "authority_ms": 9.0,
                     "r31b_durable_stages": {"fallback_ms": 8.9,
                                             "total_ms": 8.9,
                                             "seam_coordinator_count": 0}},
        }
        with self.assertRaisesRegex(ValueError, "R31B_INSUFFICIENT_SAMPLES"):
            run([fallback] * 30)

    def test_broken_stage_dict_still_fails(self):
        broken = {
            "t_us": 0, "kind": "checkpoint_capture", "measure": True,
            "data": {"r3c4r2_worker_envelope": True, "r31_cache_hit": True,
                     "authority_ms": 9.0, "r31b_durable_stages": {}},
        }
        with self.assertRaisesRegex(ValueError, "R31B_DOMAIN_STAGES_MISSING"):
            run([capture(i) for i in range(20)] + [broken])

if __name__ == "__main__":
    unittest.main()
