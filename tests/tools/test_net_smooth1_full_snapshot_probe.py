"""Deterministic R4.2 forensic correlation tests; no Godot or network required."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "net_smooth1"))
from report_full_snapshot_probe import evaluate  # noqa: E402

GOOD = "a" * 64
OTHER = "b" * 64


def write_role(run: Path, role: str, records: list[dict], *, complete: bool = True):
    dest = run / role
    dest.mkdir(parents=True, exist_ok=True)
    events = [{"kind": "header", "data": {"role": role}}]
    events.extend({"kind": "full_snapshot_wire_probe", "data": data}
                  for data in records)
    if complete:
        events.append({"kind": "end", "data": {"dropped": 0, "io_errors": 0}})
    (dest / "trace.jsonl").write_text(
        "".join(json.dumps(event) + "\n" for event in events),
        encoding="utf-8",
    )


def probe(stage: str, declared: str = GOOD, actual: str = GOOD):
    return {"stage": stage, "revision": 12, "server_tick": 44,
            "declared_sha256": declared, "source_sha256": actual,
            "after_json_sha256": actual, "source_valid": declared == actual,
            "after_json_valid": declared == actual, "source_error": "",
            "after_json_error": ""}


class FullSnapshotProbeTests(unittest.TestCase):
    def test_good_join_pairing_is_only_forensic_not_product_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            write_role(run, "server", [probe("SERVER_JOIN_ACK_BEFORE_FRAME")])
            write_role(run, "a", [probe("CLIENT_JOIN_ACK_AFTER_FRAME")])
            write_role(run, "b", [probe("CLIENT_JOIN_ACK_AFTER_FRAME")])
            report, code = evaluate(run)
            self.assertEqual(code, 0)
            self.assertEqual(report["verdict"], "PROBE_HASHES_MATCH_NOT_PRODUCT_PASS")
            self.assertEqual(report["probe_events"], 3)
            self.assertEqual(report["checksum_mismatch_count"], 0)

    def test_server_json_raw_bypass_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            write_role(run, "server", [probe("SERVER_JOIN_ACK_BEFORE_FRAME", actual=OTHER)])
            write_role(run, "a", [probe("CLIENT_JOIN_ACK_AFTER_FRAME")])
            write_role(run, "b", [probe("CLIENT_JOIN_ACK_AFTER_FRAME")])
            report, code = evaluate(run)
            self.assertEqual(code, 1)
            self.assertEqual(report["checksum_mismatch_count"], 1)
            self.assertEqual(report["mismatch_records"][0]["role"], "server")

    def test_client_rejection_detected_and_no_raw_payload_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            write_role(run, "server", [probe("SERVER_JOIN_ACK_BEFORE_FRAME")])
            bad = probe("CLIENT_JOIN_ACK_AFTER_FRAME", actual=OTHER)
            bad["raw_payload"] = {"transport_session": "private"}
            write_role(run, "a", [bad])
            write_role(run, "b", [probe("CLIENT_JOIN_ACK_AFTER_FRAME")])
            report, code = evaluate(run)
            self.assertEqual(code, 1)
            self.assertNotIn("private", json.dumps(report))
            self.assertEqual(report["mismatch_records"][0]["role"], "a")

    def test_missing_end_is_inconclusive_not_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            write_role(run, "server", [probe("SERVER_JOIN_ACK_BEFORE_FRAME")], complete=False)
            write_role(run, "a", [probe("CLIENT_JOIN_ACK_AFTER_FRAME")])
            write_role(run, "b", [probe("CLIENT_JOIN_ACK_AFTER_FRAME")])
            report, code = evaluate(run)
            self.assertEqual(code, 2)
            self.assertEqual(report["verdict"], "INCONCLUSIVE")

    def test_unpaired_client_hash_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            write_role(run, "server", [probe("SERVER_JOIN_ACK_BEFORE_FRAME")])
            write_role(run, "a", [probe("CLIENT_JOIN_ACK_AFTER_FRAME", declared=OTHER, actual=OTHER)])
            write_role(run, "b", [probe("CLIENT_JOIN_ACK_AFTER_FRAME")])
            report, code = evaluate(run)
            self.assertEqual(code, 2)
            self.assertEqual(report["unpaired_client_join_count"], 1)


if __name__ == "__main__":
    unittest.main()
