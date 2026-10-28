"""R31b P1 measured-window hit-rate, startup contamination and bypass falsifiers."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/net_smooth1"))
from analyze_r31bp1_durable_chunks import analyze


def report(i: int, *, hits: int | None = None, misses: int = 1,
           bypasses: int = 0, reason: str = "", bytes_: int = 2048,
           cached: bool = True, fence: bool = True) -> dict:
    def component(kind: str) -> dict:
        return {
            "hits": 100 + i if hits is None else hits,
            "misses": misses,
            "bypasses": bypasses,
            "bypass_reasons": {reason: bypasses} if reason and bypasses else {},
            "bytes": bytes_ if cached else 0,
            "cached": cached,
            "fence": {
                "kind": kind, "instance_id": 7,
                "authority_owner_id": "authority/m3",
                "authority_epoch": 1, "state_serial": 3,
                **({"revision": 10, "tick": 10}
                   if kind == "item_graph" else {"generation": 5}),
            } if fence else {},
        }
    return {"enabled": True, "max_chunk_bytes": 4 * 1024 * 1024,
            "item_graph": component("item_graph"),
            "resource_mining": component("resource_mining")}


def event(i: int, *, rep=None, fallback=False, valid=True) -> dict:
    stage = ({"fallback_ms": 9.0, "seam_coordinator_count": 0}
             if fallback else {
                 "total_ms": 11.0, "item_graph_ms": .2,
                 "resource_ms": .1, "validation_ms": 7.0,
                 "final_checksum_ms": 3.2,
                 "valid": valid, "seam_coordinator_count": 1,
             })
    return {
        "kind": "checkpoint_capture", "measure": True, "t_us": i * 1200000,
        "data": {
            "r3c4r2_worker_envelope": True, "r31_cache_hit": True,
            "r31b_durable_stages": stage,
            "r31bp1_durable_chunks": report(i) if rep is None else rep,
        },
    }


def run(events: list[dict]) -> dict:
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "server.jsonl"
        path.write_text("".join(json.dumps(ev) + "\n" for ev in events), encoding="utf-8")
        return analyze(path)


class MeasuredWindowFalsifiers(unittest.TestCase):
    def test_active_measured_counter_deltas_not_startup(self):
        r = run([event(i) for i in range(20)])
        self.assertEqual(r["verdict"], "R31BP1_CHUNK_CACHE_ATTRIBUTION_VALID_ONLY")
        self.assertEqual(r["checkpoint_count"], 20)
        self.assertEqual(r["active_measured"], 20)
        for kind in ("item_graph", "resource_mining"):
            c = r["components"][kind]
            self.assertEqual(c["hits"], 19)
            self.assertEqual(c["misses"], 0)
            self.assertEqual(c["startup_baseline"]["hits"], 100)
            self.assertEqual(c["measurement_basis"],
                             "difference_from_first_active_measured_capture")

    def test_legitimate_unbound_population_not_counted_as_active(self):
        rows = [event(i, fallback=True) for i in range(18)]
        rows.extend(event(i) for i in range(18, 79))
        r = run(rows)
        self.assertEqual(r["active_measured"], 61)
        self.assertEqual(r["seam_unbound_fallback_measured"], 18)
        self.assertEqual(r["components"]["item_graph"]["hits"], 60)

    def test_huge_warmup_counts_cannot_fake_good_measured_hit_rate(self):
        rows = [event(i, rep=report(i, hits=999999, misses=i+1))
                for i in range(20)]
        with self.assertRaisesRegex(ValueError, "HIT_RATE_BELOW_90PCT"):
            run(rows)

    def test_missing_report_fails(self):
        rows = [event(i) for i in range(20)]
        rows[1]["data"].pop("r31bp1_durable_chunks")
        with self.assertRaisesRegex(ValueError, "CACHE_REPORT_MISSING"):
            run(rows)

    def test_source_fence_change_reason_fails(self):
        rows = [
            event(i, rep=report(i, misses=1 + (i >= 8),
                                bypasses=int(i >= 8), reason="SOURCE_FENCE_CHANGED"))
            for i in range(20)
        ]
        with self.assertRaisesRegex(ValueError, "UNEXPECTED_BYPASS"):
            run(rows)

    def test_explicit_oversize_bypass_is_accounted(self):
        rows = [
            event(i, rep=report(i, misses=1+int(i>=7), bypasses=int(i>=7),
                                reason="CHUNK_OVERSIZE"))
            for i in range(20)
        ]
        r = run(rows)
        self.assertEqual(r["components"]["item_graph"]["bypasses"], 1)
        self.assertEqual(r["components"]["item_graph"]["bypass_reasons"]["CHUNK_OVERSIZE"], 1)

    def test_inconsistent_bypass_counter_fails(self):
        rows = [event(i) for i in range(20)]
        rows[10]["data"]["r31bp1_durable_chunks"]["item_graph"]["bypasses"] = 9
        with self.assertRaisesRegex(ValueError, "BYPASS_ACCOUNTING"):
            run(rows)

    def test_counter_reset_fails(self):
        rows = [event(i) for i in range(20)]
        rows[14]["data"]["r31bp1_durable_chunks"]["resource_mining"]["hits"] = 3
        with self.assertRaisesRegex(ValueError, "COUNTER_RESET"):
            run(rows)

    def test_disabled_cache_fails(self):
        rows = [event(i) for i in range(20)]
        rows[2]["data"]["r31bp1_durable_chunks"]["enabled"] = False
        with self.assertRaisesRegex(ValueError, "CACHE_REPORT_MISSING_OR_DISABLED"):
            run(rows)

    def test_oversized_cached_chunk_fails(self):
        rows = [event(i, rep=report(i, bytes_=9*1024*1024))
                for i in range(20)]
        with self.assertRaisesRegex(ValueError, "SIZE_INVALID"):
            run(rows)

    def test_invalid_fence_fails(self):
        rows = [event(i, rep=report(i, fence=False)) for i in range(20)]
        with self.assertRaisesRegex(ValueError, "FENCE_INVALID"):
            run(rows)

    def test_insufficient_active_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "INSUFFICIENT_ACTIVE"):
            run([event(i, fallback=True) for i in range(20)])


if __name__ == "__main__":
    unittest.main()
