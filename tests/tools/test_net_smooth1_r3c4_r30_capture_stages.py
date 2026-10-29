"""R3.0 capture analyzer: synthetic positive and fail-closed cases."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "net_smooth1"))
import analyze_r3c4_r30_capture_stages as stages


def capture_event(*, replay: float = 5.0, duplicate: float = 1.0,
                  handoff: float = 2.0, generation: int = 1,
                  r2: bool = True) -> dict:
    return {"kind": "checkpoint_capture", "measure": True, "data": {
        "generation": generation, "r3c4r2_worker_envelope": r2,
        "capture_ms": 13.0, "quiesce_ms": .05, "authority_ms": 5.0,
        "replay_ms": replay, "handoff_ms": handoff,
        "r30_replay_gameplay_ms": 3.0, "r30_replay_checksum_ms": 2.0,
        "r30_writer_deep_copy_ms": duplicate,
        "r30_replay_ledger_count": 3, "r30_outbox_count": 0}}


class R30StageTest(unittest.TestCase):
    def test_exact_attribution(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "server.jsonl"
            path.write_text(json.dumps(capture_event()) + "\n")
            result = stages.analyze(path)
            self.assertEqual(result["checkpoint_count"], 1)
            self.assertEqual(result["stages_ms"]["replay_ms"]["p99"], 5.0)
            self.assertEqual(result["stages_ms"]["r30_writer_deep_copy_ms"]["p99"], 1.0)
            self.assertTrue(result["notes"]["not_normative"])
            self.assertFalse(result["notes"]["merge_approval"])

    def test_outer_replay_window_may_include_host_pause(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "server.jsonl"
            path.write_text(json.dumps(capture_event(replay=20)) + "\n")
            result = stages.analyze(path)
            self.assertEqual(result["replay_unattributed_ms"]["p99"], 15.0)

    def test_impossible_copy_stage_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "server.jsonl"
            path.write_text(json.dumps(capture_event(duplicate=4.5)) + "\n")
            with self.assertRaisesRegex(ValueError, "writer deep-copy larger"):
                stages.analyze(path)

    def test_disabled_r2_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "server.jsonl"
            path.write_text(json.dumps(capture_event(r2=False)) + "\n")
            with self.assertRaisesRegex(ValueError, "R2 envelope disabled"):
                stages.analyze(path)

    def test_duplicate_generation_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "server.jsonl"
            path.write_text(json.dumps(capture_event()) + "\n" +
                            json.dumps(capture_event()) + "\n")
            with self.assertRaisesRegex(ValueError, "duplicate generation"):
                stages.analyze(path)


if __name__ == "__main__":
    unittest.main()
