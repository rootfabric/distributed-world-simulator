"""R31 long-gap forensic tool falsifiers, no network, no third-party deps."""
from __future__ import annotations
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/net_smooth1"))
from diagnose_r31_long_gaps import read_events, role_metrics, compare


def write_run(root: Path, arm: str, *, sha: str = "same", max_gap: float = 136.0) -> None:
    root.mkdir()
    manifest = {
        "mode": "gui", "profile": "LOCAL", "completed": True, "errors": [],
        "scenario": "r31-reconnect-roundtrip",
        "r3c4r31_replay_projection": arm == "on",
        "identity": {
            "head": "exact-head", "godot_sha256": sha,
            "asset_manifest_sha256": "assets",
        },
    }
    (root/"manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    for role in ("server", "a", "b"):
        folder = root/role
        folder.mkdir()
        ev = [{"kind": "header", "t_us": 0, "data": {}}]
        for i in range(360):
            t = 20000 + 16667*i
            gap = max_gap if i == 100 and role == "server" else 16.7
            ev.append({"kind": "frame", "t_us": t, "measure": True,
                       "data": {"interval_ms": gap}})
            if role == "server":
                ev.append({"kind": "server_loop", "t_us": t+1, "measure": True,
                           "data": {"process_ms": 5.0}})
                if i == 100:
                    ev.append({"kind": "checkpoint_capture", "t_us": t+2,
                               "measure": True, "data": {"capture_ms": 12}})
        ev.append({"kind": "end", "t_us": 7000000, "data": {}})
        (folder/"trace.jsonl").write_text(
            "".join(json.dumps(x)+"\n" for x in ev), encoding="utf-8")


class GapTests(unittest.TestCase):
    def test_association_not_causal_claim(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"on"
            write_run(root, "on")
            report = role_metrics(root, "server")
            self.assertEqual(report["gaps_over_100ms"], 1)
            near = report["long_gaps"][0]
            self.assertEqual(near["nearby_engine_stage_counts_125ms"]["checkpoint_capture"], 1)
            self.assertEqual(near["nearby_server_process_max_ms"], 5.0)
            self.assertTrue(near["engine_stage_association_is_not_causality"])

    def test_paired_control(self):
        with tempfile.TemporaryDirectory() as d:
            off, on = Path(d)/"off", Path(d)/"on"
            write_run(off, "off", max_gap=80)
            write_run(on, "on")
            report = compare([(off, on)])
            self.assertEqual(report["off"]["server_long_gap_counts"], [0])
            self.assertEqual(report["on"]["server_long_gap_counts"], [1])
            self.assertIn("not proof of external host noise", report["limitations"][3])

    def test_mismatched_binary_is_invalid_pair(self):
        with tempfile.TemporaryDirectory() as d:
            off, on = Path(d)/"off", Path(d)/"on"
            write_run(off, "off", sha="A")
            write_run(on, "on", sha="B")
            with self.assertRaisesRegex(ValueError, "IDENTITY_MISMATCH_engine_sha256"):
                compare([(off, on)])

    def test_missing_footer_is_invalid(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)/"on"
            write_run(root, "on")
            p = root/"server"/"trace.jsonl"
            p.write_text("\n".join(p.read_text().splitlines()[:-1])+"\n")
            with self.assertRaisesRegex(ValueError, "MISSING_TRACE_END"):
                read_events(p)

    def test_clock_reversal_is_invalid(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/"bad.jsonl"
            p.write_text('{"kind":"header","t_us":12,"data":{}}\n'
                         '{"kind":"frame","t_us":1,"data":{"interval_ms":100}}\n'
                         '{"kind":"end","t_us":14,"data":{}}\n')
            with self.assertRaisesRegex(ValueError, "NONMONOTONE_CLOCK"):
                read_events(p)


if __name__ == "__main__":
    unittest.main()
