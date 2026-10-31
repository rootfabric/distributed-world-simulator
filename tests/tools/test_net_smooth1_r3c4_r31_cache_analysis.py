"""Falsifiers for R3.1a GUI cache trace source verification."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "net_smooth1"))
import analyze_r3c4_r31_cache as subject


def event(n: int, *, hit=True, bypass="", gen=1, replay=0.12) -> dict:
    return {"n": n, "measure": True, "kind": "checkpoint_capture", "data": {
        "r3c4r2_worker_envelope": True, "r31_cache_hit": hit,
        "r31_cache_bypassed": bypass, "r31_projection_generation": gen,
        "capture_ms": 12.0, "authority_ms": 11.6,
        "replay_ms": replay, "handoff_ms": .15}}


def write_trace(path: Path, values: list[dict]) -> None:
    path.write_text("".join(json.dumps(x) + "\n" for x in values), encoding="utf-8")


class CacheAuditTest(unittest.TestCase):
    def test_valid_first_miss_followed_by_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "server.jsonl"
            write_trace(path, [event(1, hit=False, replay=16.0)] +
                        [event(i) for i in range(2, 80)])
            result = subject.audit(path)
            self.assertEqual(result["verdict"], "CACHE_DIAGNOSTIC_PASS")
            self.assertEqual(result["checkpoint_count"], 79)
            self.assertGreater(result["cache_hit_fraction"], .98)
            self.assertEqual(result["timings_ms"]["replay_ms"]["p50"], .12)
            self.assertTrue(result["never_merge_automatically"])

    def test_no_reuse_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "server.jsonl"
            write_trace(path, [event(i, hit=False) for i in range(1, 81)])
            result = subject.audit(path)
            self.assertEqual(result["verdict"], "CACHE_DIAGNOSTIC_FAIL")
            self.assertTrue(any("cache reuse" in x for x in result["problems"]))

    def test_over_budget_bypass_fails_even_if_reuse_high(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "server.jsonl"
            write_trace(path, [event(1, hit=False, bypass="REPLAY_BYTES_BUDGET", gen=-1)] +
                        [event(i) for i in range(2, 81)])
            result = subject.audit(path)
            self.assertEqual(result["verdict"], "CACHE_DIAGNOSTIC_FAIL")
            self.assertEqual(result["cache_bypasses"].get("REPLAY_BYTES_BUDGET"), 1)

    def test_unknown_flag_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "server.jsonl"
            values = [event(i) for i in range(1, 81)]
            del values[2]["data"]["r31_cache_hit"]
            write_trace(path, values)
            result = subject.audit(path)
            self.assertEqual(result["verdict"], "CACHE_DIAGNOSTIC_FAIL")
            self.assertTrue(any("r31_cache_hit" in x for x in result["problems"]))

    def test_generation_reversal_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "server.jsonl"
            values = [event(i, gen=3 if i < 30 else 2) for i in range(1, 81)]
            write_trace(path, values)
            result = subject.audit(path)
            self.assertEqual(result["verdict"], "CACHE_DIAGNOSTIC_FAIL")
            self.assertIn("cache generation regressed", result["problems"])

    def test_empty_trace_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "server.jsonl"
            write_trace(path, [])
            result = subject.audit(path)
            self.assertEqual(result["verdict"], "CACHE_DIAGNOSTIC_FAIL")
            self.assertEqual(result["checkpoint_count"], 0)


if __name__ == "__main__":
    unittest.main()
