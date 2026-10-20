"""Synthetic fail-closed tests for read-only R3C4 R2 paired GUI reducer."""
from __future__ import annotations
import json
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "net_smooth1"))
import compare_r3c4r2_gui_evidence as reducer  # noqa: E402


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value), encoding="utf-8")


def create_run(root: Path, arm: str, idx: int, server_p99: float = 40) -> Path:
    path = root / f"gui-{arm}-{idx}"
    path.mkdir()
    on = arm == "on"
    manifest = {
        "identity": {
            "head": reducer.EXPECTED_HEAD, "tree": reducer.EXPECTED_TREE,
            "godot_sha256": reducer.EXPECTED_GODOT_SHA,
            "godot_version": "4.7.1.stable.double.custom_build.a13da4feb",
            "tracked_dirty": False, "platform": "Windows-10-10.0.19045-SP0",
            "asset_count": 222, "asset_manifest_sha256": "same-assets",
        },
        "mode": "gui", "profile": "LOCAL", "scenario": "r31-reconnect-roundtrip",
        "duration_s": 120, "completed": True, "errors": [],
        "phase_results": [{"phase": "r31_reconnect_roundtrip", "result": {"ok": True}}],
        "process_exit_codes": {"server": 0, "a": 0, "b": 0},
        "r3c4_periodic_frame_pacing": True, "r3c4r2_worker_envelope": on,
        "r3c_async_admission": True, "r3c2_avatar_prewarm": True,
        "r3c2_server_phased": True, "r3c3_staged_earth": True,
        "r3c21_frame_paced_presentation": True,
    }
    write_json(path / "manifest.json", manifest)
    write_json(path / "r31-roundtrip.json", {"stages": {"ok": True}})
    reports = []
    for role in ("server", "a", "b"):
        p99 = server_p99 if role == "server" else 16
        failures = ["frame p99 >25ms"] if p99 > 25 else []
        reports.append({
            "role": role, "verdict": "FAIL" if failures else "PASS",
            "failures": failures, "problems": [], "duration_s": 120,
            "metrics": {"frame_ms": {"p99": p99, "p999": 35, "max": 60}},
            "tick_hz": 60 if role == "server" else None,
            "durable_stage_failures": 0,
            "dropped_time_delta_s": 0,
        })
        loc = path / role
        loc.mkdir()
        (loc / "runtime.log").write_text("ok\n", encoding="utf-8")
        if role in ("a", "b"):
            write_json(loc / "screenshot.json", {"success": True})
            write_json(loc / "avatar-status.json", {"details": {"remote_players": {
                "remote-player": {"provider_id": "avatar/quaternius",
                                  "asset_mode": "QUATERNIUS_RETARGET",
                                  "ready": True, "legacy_capsule_visible": False}
            }}})
        lines = []
        if role == "server":
            lines = [
                {"kind": "checkpoint_capture", "measure": True,
                 "data": {"r3c4r2_worker_envelope": on, "capture_ms": 4,
                          "quiesce_ms": 1, "authority_ms": 2, "replay_ms": .5,
                          "handoff_ms": .5}},
                {"kind": "checkpoint_complete", "measure": True,
                 "data": {"wrap_ms": 1, "build_ms": 2, "write_ms": 3, "worker_ms": 6}},
            ]
        (loc / "trace.jsonl").write_text(
            "".join(json.dumps(item) + "\n" for item in lines), encoding="utf-8")
    write_json(path / "report.json", {
        "verdict": "FAIL" if server_p99 > 25 else "PASS",
        "functional_scenario": "PASS",
        "evidence_class": "GUI_LOCAL_CANDIDATE",
        "processes": reports,
    })
    return path


def suite_root(root: Path, off_p99: float = 40, on_p99: float = 39) -> None:
    for idx in (1, 2, 3):
        create_run(root, "off", idx, off_p99)
        create_run(root, "on", idx, on_p99)


class EvidenceReducerTest(unittest.TestCase):
    def test_percentiles_and_invalid_numbers(self):
        self.assertEqual(reducer.percentile([20, 10, 30, 40], .5), 20)
        for value in (float("nan"), float("inf"), -1, True):
            with self.assertRaises(ValueError):
                reducer.number(value)

    def test_performance_failure_does_not_hide_functionality(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suite_root(root)
            result = subprocess.run(
                [sys.executable, str(reducer.__file__), "--root", str(root)],
                capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            data = json.loads((root / "comparison.json").read_text())
            self.assertEqual(data["verdict"], "PERF_FAIL")
            self.assertEqual(data["runs"][1]["status"], "PERF_FAIL")
            self.assertTrue(data["no_merge"])

    def test_gui_gates_pass_but_still_no_merge(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suite_root(root, off_p99=40, on_p99=15)
            result = subprocess.run(
                [sys.executable, str(reducer.__file__), "--root", str(root)],
                capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads((root / "comparison.json").read_text())
            self.assertEqual(data["verdict"], "GUI_PERF_GATE_PASS_ONLY")
            self.assertTrue(data["no_merge"])

    def test_missing_trace_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suite_root(root)
            (root / "gui-on-1" / "server" / "trace.jsonl").unlink()
            result = subprocess.run(
                [sys.executable, str(reducer.__file__), "--root", str(root)],
                capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            data = json.loads((root / "comparison.json").read_text())
            self.assertEqual(data["verdict"], "INCONCLUSIVE")

    def test_cross_run_asset_drift_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suite_root(root)
            p = root / "gui-on-2" / "manifest.json"
            value = json.loads(p.read_text())
            value["identity"]["asset_manifest_sha256"] = "changed-assets"
            write_json(p, value)
            result = subprocess.run(
                [sys.executable, str(reducer.__file__), "--root", str(root)],
                capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            data = json.loads((root / "comparison.json").read_text())
            self.assertEqual(data["verdict"], "INCONCLUSIVE")


if __name__ == "__main__":
    unittest.main()
