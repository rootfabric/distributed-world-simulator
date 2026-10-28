"""Synthetic evidence tests; never substitute for actual Windows traces."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("tail", ROOT/"tools/net_smooth1/analyze_r31_server_tail.py")
tail = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tail)


def fixture(root, run_id, arm, count=7200):
    root.mkdir()
    ident = {"head": tail.EXPECTED_HEAD, "tree": tail.EXPECTED_TREE,
             "godot_sha256": "wrapper-sha", "asset_manifest_sha256": "assets-sha",
             "tracked_dirty": False}
    m = {"mode": "gui", "profile": "LOCAL", "scenario": "r31-reconnect-roundtrip",
         "completed": True, "duration_s": 120, "run_id": run_id, "errors": [],
         "identity": ident, "cleanup": {"verified": True},
         "r31bp20_validator_attribution": arm == "on", **{k: True for k in tail.BASE_FLAGS}}
    (root/"manifest.json").write_text(json.dumps(m))
    (root/"report.json").write_text(json.dumps({"verdict": "FAIL"}))
    (root/"server").mkdir()
    rows = []
    def emit(kind, at, data, measure=True):
        rows.append({"n": len(rows)+1, "kind": kind, "t_us": at,
                     "measure": measure, "data": data})
    emit("header", 1000, {"schema": "dws.net_smooth.trace.v1", "role": "server",
                         "run_id": run_id, "clock": "PROCESS_LOCAL_MONOTONIC_US", "pid": 42}, False)
    emit("frame", 1500, {"interval_ms": .5}, False)
    emit("measure_start", 2000, {})
    t = 2000
    for i in range(count):
        capture = i % 90 == 10
        wall_only = i % 101 == 10
        interval = 28 if capture or wall_only else 16.667
        t += interval*1000
        if capture:
            emit("checkpoint_capture", t-200, {"capture_ms": 7.0, "authority_ms": 5.0,
                 "replay_ms": .1, "handoff_ms": .1, "r31b_durable_stages": {"validation_ms": 3.0}})
        emit("server_loop", t-100, {"process_ms": 10.0 if capture else 2.0,
             "message_ms": .2, "fixed_ms": .1, "snapshot_ms": .3,
             "persistence_ms": 8.0 if capture else .01,
             "capture_ms": 700.0})  # Stale field: must NEVER imply a current capture.
        emit("frame", t, {"interval_ms": interval, "engine_process_ms": 999.0})
    emit("measure_end", t+1, {})
    n = len(rows)
    rows.append({"kind": "end", "t_us": t+2,
                 "data": {"written": n, "produced": n, "dropped": 0, "io_errors": 0}})
    path = root/"server/trace.jsonl"
    path.write_text("".join(json.dumps(x)+"\n" for x in rows))
    return rows


def save(root, rows):
    (root/"server/trace.jsonl").write_text("".join(json.dumps(x)+"\n" for x in rows))


class TailReview(unittest.TestCase):
    def test_same_process_process_and_uncovered_intervals_not_host_causality(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"on"
            fixture(root, "run-1", "on", count=300)
            x = tail.analyze_trace(tail.read_trace(root/"server/trace.jsonl", "run-1"))
            matched = [r for r in x["highest_intervals"] if r["association"] != "UNRESOLVED"]
            self.assertTrue(any(r["capture_overlap"] and r["uncovered_probe_interval_ms"] == 18 for r in matched))
            self.assertTrue(any(not r["capture_overlap"] and r["uncovered_probe_interval_ms"] == 26 for r in matched))
            self.assertGreater(x["no_capture_overlap_frames"]["frames"], 280)
            self.assertEqual(x["measured_capture_events"], 4)
            self.assertGreater(x["all_measured_frames"]["unaligned_frames"], 0)

    def test_six_old_reports_preserved_and_hashes_unchanged(self):
        with tempfile.TemporaryDirectory() as d:
            pairs = []
            for i in range(3):
                off, on = Path(d)/f"off{i}", Path(d)/f"on{i}"
                fixture(off, f"off-{i}", "off")
                fixture(on, f"on-{i}", "on")
                pairs.append((off, on))
            result = tail.compare(pairs)
            self.assertIn("NOT_PERFORMANCE_ACCEPTANCE", result["verdict"])
            self.assertEqual(len(result["pairs"]), 3)
            for row in result["pairs"]:
                for arm in ("off", "on"):
                    v = row[arm]
                    self.assertEqual(v["normative_verdict_unmodified"], "FAIL")
                    self.assertGreater(v["server"]["all_measured_frames"]["frame_ms"]["p99"], 25)
                    for path, digest in v["source_sha256_before_after"].items():
                        self.assertEqual(tail.sha256(Path(path)), digest)

    def test_missing_end_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            rows = fixture(root, "run", "on", 300)
            save(root, rows[:-1])
            with self.assertRaisesRegex(ValueError, "INCOMPLETE_OR_LOSSY"):
                tail.read_trace(root/"server/trace.jsonl", "run")

    def test_sequence_gap_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            rows = fixture(root, "run", "on", 300)
            rows[25]["n"] += 1
            save(root, rows)
            with self.assertRaisesRegex(ValueError, "SEQUENCE_LOSS"):
                tail.read_trace(root/"server/trace.jsonl", "run")

    def test_wrong_role_or_clock_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            rows = fixture(root, "run", "on", 300)
            rows[0]["data"]["role"] = "a"
            save(root, rows)
            with self.assertRaisesRegex(ValueError, "WRONG_HEADER"):
                tail.read_trace(root/"server/trace.jsonl", "run")

    def test_trace_loss_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            rows = fixture(root, "run", "on", 300)
            rows[-1]["data"]["dropped"] = 1
            save(root, rows)
            with self.assertRaisesRegex(ValueError, "INCOMPLETE_OR_LOSSY"):
                tail.read_trace(root/"server/trace.jsonl", "run")

    def test_clock_reversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            rows = fixture(root, "run", "on", 300)
            rows[25]["t_us"] = 1
            save(root, rows)
            with self.assertRaisesRegex(ValueError, "CLOCK_OR_END"):
                tail.read_trace(root/"server/trace.jsonl", "run")

    def test_ambiguous_process_window_not_silently_used(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            rows = fixture(root, "run", "on", 300)
            for r in rows:
                if r["kind"] == "server_loop":
                    r["data"]["process_ms"] = 900
            save(root, rows)
            r = tail.analyze_trace(tail.read_trace(root/"server/trace.jsonl", "run"))
            self.assertEqual(r["all_measured_frames"]["unaligned_frames"], 300)
            self.assertEqual(r["all_measured_frames"]["uncovered_probe_interval_ms"]["n"], 0)

    def test_measurement_flag_not_retroactively_filtered(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            rows = fixture(root, "run", "on", 300)
            rows[25]["measure"] = False
            save(root, rows)
            with self.assertRaisesRegex(ValueError, "OUTSIDE_WINDOW"):
                tail.read_trace(root/"server/trace.jsonl", "run")

    def test_wrong_product_head_not_called_exact(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            fixture(root, "run", "on", 300)
            p = root/"manifest.json"
            m = json.loads(p.read_text())
            m["identity"]["head"] = "another-head"
            p.write_text(json.dumps(m))
            with self.assertRaisesRegex(ValueError, "WRONG_EXACT"):
                tail.review_run(root, "on")

    def test_engine_drift_between_pairs_is_rejected(self):
        calls = 0
        def fake(root, arm):
            nonlocal calls
            calls += 1
            return {"run_id": str(calls), "identity": {
                "head": tail.EXPECTED_HEAD, "tree": tail.EXPECTED_TREE,
                "godot_sha256": "A" if calls < 5 else "B",
                "asset_manifest_sha256": "assets"}}
        with mock.patch.object(tail, "review_run", side_effect=fake):
            with self.assertRaisesRegex(ValueError, "ENGINE_OR_ASSET_DRIFT"):
                tail.compare([(Path("off"), Path("on")) for _ in range(3)])

    def test_short_window_not_treated_as_full_benchmark(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            fixture(root, "run", "on", count=300)
            with self.assertRaisesRegex(ValueError, "MEASURED_WINDOW_TOO_SHORT"):
                tail.review_run(root, "on")

    def test_duplicate_runs_cannot_be_three_repetitions(self):
        def fake(root, arm):
            return {"run_id": "same", "identity": {
                "head": tail.EXPECTED_HEAD, "tree": tail.EXPECTED_TREE,
                "godot_sha256": "engine", "asset_manifest_sha256": "assets"}}
        with mock.patch.object(tail, "review_run", side_effect=fake):
            with self.assertRaisesRegex(ValueError, "DUPLICATE_RUN"):
                tail.compare([(Path("off"), Path("on")) for _ in range(3)])

    def test_incomplete_footer_count_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"run"
            rows = fixture(root, "run", "on", count=300)
            rows[-1]["data"]["produced"] += 1
            save(root, rows)
            with self.assertRaisesRegex(ValueError, "INCOMPLETE_OR_LOSSY_TRACE"):
                tail.read_trace(root/"server/trace.jsonl", "run")

    def test_pair_count_required(self):
        with self.assertRaisesRegex(ValueError, "THREE_HISTORICAL"):
            tail.compare([])

    def test_nonfinite_metrics_rejected(self):
        with self.assertRaises(ValueError):
            tail.number(float("nan"), "frame")
        with self.assertRaises(ValueError):
            tail.number(True, "frame")


if __name__ == "__main__":
    unittest.main()
