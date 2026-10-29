"""Regression: R3 source trace events crossing measurement boundaries are paired globally.

The server's monotonic clock cannot be compared with either client's.
Synthetic traces include complete headers/footers and chronological pre-window
SUBMIT / post-window COMMIT records with only the movement frames measured.
"""
from __future__ import annotations
import json
import sys
import tempfile
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "net_smooth1"))
import analyze_r3_committed_view as analyzer


def write_trace(root: Path, role: str, run_id: str, *,
                missing_submit: bool = False,
                bad_peer: bool = False,
                dropped: bool = False) -> None:
    folder = root / role
    folder.mkdir(parents=True, exist_ok=True)
    records = []
    def emit(kind: str, tick: int, data: dict, measure: bool) -> None:
        records.append({"kind": kind, "n": len(records) + 1, "t_us": tick,
                        "data": data, "measure": measure})
    emit("header", 0, {"schema": "dws.net_smooth.trace.v1",
                        "role": role, "run_id": run_id}, False)
    if role == "server":
        for window in (0, 1):
            anchor = 100000 + window * 700000
            generation = window + 11
            token = f"op-hash-{window}"
            if not (missing_submit and window == 0):
                emit("p1b_item_async_stages", anchor,
                     {"stage": "SUBMIT", "generation": generation,
                      "operation_hash": token}, window != 0)
            for frame in range(11):
                emit("movement_snapshot_stages", anchor + (frame + 1) * 50000,
                     {"committed_view": True, "peers": 2,
                      "committed_enqueues": 1 if bad_peer and frame == 5 else 2,
                      "all_enqueued": not (bad_peer and frame == 5),
                      "tick": window * 100 + (frame + 1) * 3}, True)
            emit("p1b_item_async_stages", anchor + 600000,
                 {"stage": "DURABLE_COMMIT", "generation": generation,
                  "operation_hash": token}, window == 0)
    else:
        for frame in range(18):
            emit("r3_committed_view_received", (frame + 1) * 50000,
                 {"tick": (frame + 1) * 3, "session": role}, True)
    last_us = records[-1]["t_us"] + 1000
    records.append({"kind": "end", "t_us": last_us,
                    "data": {"dropped": 1 if dropped else 0,
                             "io_errors": 0,
                             "written": len(records),
                             "produced": len(records)}})
    (folder / "trace.jsonl").write_text(
        "\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8"
    )


class R3MeasurementWindows(unittest.TestCase):
    def fixture(self, root: Path, *, missing_submit=False,
                bad_peer=False, dropped=False):
        (root / "manifest.json").write_text(json.dumps({
            "run_id": "r3-test",
            "mode": "gui",
            "scenario": "r3-slow-item",
            "completed": True,
            "slow_item_writer_ms": 1800,
        }), encoding="utf-8")
        for role in ("server", "a", "b"):
            write_trace(root, role, "r3-test",
                        missing_submit=missing_submit if role == "server" else False,
                        bad_peer=bad_peer if role == "server" else False,
                        dropped=dropped if role == "server" else False)

    def test_pre_window_submit_and_post_window_commit_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            report = analyzer.examine(root)
            self.assertEqual(report["verdict"], "PASS", report["issues"])
            self.assertEqual(report["fully_paired_windows"], 2)
            self.assertEqual(report["measurement_overlapping_windows"], 2)
            self.assertEqual(report["measured_pending_frames"], 22)
            self.assertEqual(report["tick_intervals"]["not_three"], 0)
            self.assertFalse(report["ack_after_commit_verified_here"])

    def test_truly_missing_submit_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, missing_submit=True)
            report = analyzer.examine(root)
            self.assertEqual(report["verdict"], "FAIL")
            self.assertTrue(any("commit without" in issue for issue in report["issues"]))

    def test_missing_peer_enqueue_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, bad_peer=True)
            report = analyzer.examine(root)
            self.assertEqual(report["verdict"], "FAIL")
            self.assertGreater(report["bad_dual_peer_enqueues"], 0)

    def test_dropped_evidence_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, dropped=True)
            with self.assertRaisesRegex(ValueError, "trace loss"):
                analyzer.examine(root)


if __name__ == "__main__":
    unittest.main()
