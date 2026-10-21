"""R31b P1 durable chunk cache analyzer: exact and fail-closed negatives."""
from __future__ import annotations
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/net_smooth1"))
from analyze_r31bp1_durable_chunks import analyze


def report(*, hits=99, misses=1, bypasses=0, bytes_=2048, cached=True, enabled=True,
           fence=True):
    def component(cached_value):
        return {
            "enabled": True, "max_chunk_bytes": 4 * 1024 * 1024,
            "hits": hits, "misses": misses, "bypasses": bypasses,
            "bytes": bytes_ if cached_value else 0,
            "cached": cached_value,
            "fence": {"kind": "x", "instance_id": 1, "authority_owner_id": "a",
                      "authority_epoch": 1, "state_serial": 7}
                      if cached_value and fence else {},
        }
    return {"enabled": enabled,
            "item_graph": component(cached),
            "resource_mining": component(cached)}


def capture(t: int, rep=None, seam=1, valid=True) -> dict:
    stages = {"total_ms": 8.0, "item_graph_ms": 1.0, "resource_ms": 1.0,
              "valid": valid, "seam_coordinator_count": seam}
    data = {"r3c4r2_worker_envelope": True, "r31_cache_hit": True,
            "authority_ms": 12.0, "r31b_durable_stages": stages}
    if rep is not False:
        data["r31bp1_durable_chunks"] = rep if rep is not None else report()
    return {"t_us": t, "kind": "checkpoint_capture", "measure": True, "data": data}


def run(events: list[dict]) -> dict:
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "server.jsonl"
        p.write_text("".join(json.dumps(ev) + "\n" for ev in events), encoding="utf-8")
        return analyze(p)


class ChunkCacheAnalyzer(unittest.TestCase):
    def test_valid_warm_run_passes(self):
        r = run([capture(i) for i in range(20)])
        self.assertEqual(r["verdict"], "R31BP1_CHUNK_CACHE_ATTRIBUTION_VALID_ONLY")
        self.assertEqual(r["checkpoint_count"], 20)
        for kind in ("item_graph", "resource_mining"):
            self.assertGreaterEqual(r["components"][kind]["hit_rate"], 0.9)

    def test_missing_report_fails(self):
        with self.assertRaisesRegex(ValueError, "R31BP1_CACHE_REPORT_MISSING"):
            run([capture(i, rep=False) for i in range(20)])

    def test_hit_rate_below_90_fails(self):
        with self.assertRaisesRegex(ValueError, "HIT_RATE_BELOW_90PCT"):
            run([capture(i, rep=report(hits=5, misses=5)) for i in range(20)])

    def test_disabled_cache_fails(self):
        with self.assertRaisesRegex(ValueError, "R31BP1_CACHE_NOT_ENABLED"):
            run([capture(i, rep=report(enabled=False)) for i in range(20)])

    def test_oversize_bypass_is_measured_allowed(self):
        r = run([capture(i, rep=report(bypasses=1, cached=False)) for i in range(20)])
        self.assertEqual(r["components"]["item_graph"]["bypasses"], 1)

    def test_invalid_chunk_size_fails(self):
        with self.assertRaisesRegex(ValueError, "ITEM_GRAPH_SIZE_INVALID"):
            run([capture(i, rep=report(bytes_=9 * 1024 * 1024)) for i in range(20)])

    def test_invalid_fence_fails(self):
        with self.assertRaisesRegex(ValueError, "ITEM_GRAPH_FENCE_INVALID"):
            run([capture(i, rep=report(fence=False)) for i in range(20)])

    def test_insufficient_samples_fails(self):
        with self.assertRaisesRegex(ValueError, "R31BP1_INSUFFICIENT_SAMPLES"):
            run([capture(0)])

    def test_no_activity_fails(self):
        empty = {"enabled": True, "item_graph": {"hits": 0, "misses": 0,
                 "bypasses": 0, "bytes": 0, "cached": False, "fence": {}},
                 "resource_mining": {"hits": 0, "misses": 0, "bypasses": 0,
                 "bytes": 0, "cached": False, "fence": {}}}
        with self.assertRaisesRegex(ValueError, "NO_MEASURED_ACTIVITY"):
            run([capture(i, rep=empty) for i in range(20)])


if __name__ == "__main__":
    unittest.main()
