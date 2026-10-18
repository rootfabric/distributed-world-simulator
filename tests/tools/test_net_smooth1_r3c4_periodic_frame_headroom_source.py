"""NET-SMOOTH1 R3C4 R1 opt-in periodic checkpoint frame separation.

Source contracts are not FPS measurements; GUI, pinned Windows/Linux Godot
and crash/replay validation are separate hard gates.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = (ROOT / "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd").read_text(encoding="utf-8")
HARNESS = (ROOT / "tools/net_smooth1/run_net_smooth1.py").read_text(encoding="utf-8")
CHECKPOINT = (ROOT / "scripts/persistence/authoritative_checkpoint.gd").read_text(encoding="utf-8")
WRITER = (ROOT / "scripts/persistence/async_checkpoint_writer.gd").read_text(encoding="utf-8")
TEST = (ROOT / "tests/runtime/test_net_smooth1_r3c4_periodic_frame_headroom.gd").read_text(encoding="utf-8")


def method(source: str, name: str) -> str:
    m = re.search(r"^func " + re.escape(name) + r"\(", source, re.M)
    if not m:
        raise AssertionError("missing func " + name)
    nxt = re.search(r"^func ", source[m.end():], re.M)
    return source[m.start() : (m.end() + nxt.start()) if nxt else len(source)]


def bounded_periodic(source: str) -> bool:
    m = method(source, "_maybe_persist_movement_checkpoint")
    return all(token in m for token in (
        "_r3c4_periodic_frame_pacing and _movement_checkpoint_writer != null",
        "_movement_checkpoint_writer.is_busy()",
        "_r3c4_snapshot_published_this_frame",
        "_r3c4_pre_capture_work_us > R3C4_PERIODIC_MAX_PRE_CAPTURE_US",
        "deferred_ms < R3C4_PERIODIC_MAX_DEFER_MS",
        "_r3c4_deferred_frames += 1",
        "_r3c4_forced_captures += 1",
        "_r3c4_due_since_ms = -1",
        "_submit_async_movement_checkpoint()",
        '_persist_checkpoint("", "PERIODIC_SYNC_FALLBACK")',
    ))


class R3C4FrameHeadroom(unittest.TestCase):
    def test_bounded_defer_never_starves_periodic(self):
        self.assertTrue(bounded_periodic(RUNTIME))
        self.assertIn("const R3C4_PERIODIC_MAX_DEFER_MS := 64", RUNTIME)
        self.assertIn("const R3C4_PERIODIC_MAX_PRE_CAPTURE_US := 6000", RUNTIME)
        mutant = RUNTIME.replace(
            "deferred_ms < R3C4_PERIODIC_MAX_DEFER_MS",
            "deferred_ms < 2147483647",
        )
        self.assertFalse(bounded_periodic(mutant))

    def test_only_opt_in_persistent_server(self):
        setup = method(RUNTIME, "setup")
        self.assertIn('"r3c4_periodic_frame_pacing_canary"', setup)
        self.assertIn('OS.get_environment("DWS_NET_R3C4_PERIODIC_FRAME_PACING") == "1"', setup)
        self.assertIn("R3C4_PERSISTENT_PLAYABLE_WORLD_REQUIRED", setup)
        self.assertIn('var _r3c4_periodic_frame_pacing := false', RUNTIME)
        self.assertIn("if role == 'server' and args.r3c4_periodic_frame_pacing:", HARNESS)
        self.assertIn("env['DWS_NET_R3C4_PERIODIC_FRAME_PACING']='1'", HARNESS)
        self.assertIn("--r3c4-periodic-frame-pacing", HARNESS)

    def test_sync_durable_before_ack_and_writer_unchanged(self):
        command = method(RUNTIME, "_persist_command_result")
        checkpoint = method(RUNTIME, "_persist_checkpoint")
        self.assertNotIn("_r3c4_", command)
        self.assertNotIn("_r3c4_", checkpoint)
        for token in ("_complete_async_movement_checkpoint(true)",
                      "_recovery_coordinator.persist_checkpoint("):
            self.assertIn(token, checkpoint)
        for token in ("_durable_ack_gate.mark_submitted(", "_durable_ack_gate.complete("):
            self.assertIn(token, command)
        self.assertIn("job = {", WRITER) if "job = {" in WRITER else self.assertIn("var job := {", WRITER)
        self.assertIn("authority_state.duplicate(true)", WRITER)
        self.assertIn("replay_state.duplicate(true)", WRITER)
        self.assertIn("SAME_REVISION_AUTHORITATIVE_MUTATION", CHECKPOINT)

    def test_capture_not_co_scheduled_with_compact_snapshot(self):
        movement = method(RUNTIME, "_maybe_publish_movement_snapshot")
        process = method(RUNTIME, "_process")
        self.assertIn("_r3c4_snapshot_published_this_frame = true", movement)
        self.assertIn("_r3c4_snapshot_published_this_frame = false", process)
        self.assertIn("_r3c4_pre_capture_work_us = smooth_snapshot_done - smooth_started", process)
        self.assertIn("r3c4_periodic_frame_deferred", RUNTIME)
        self.assertIn("r3c4_periodic_capture_slot", RUNTIME)
        self.assertIn("r3c4_periodic_deferral_bound", RUNTIME)

    def test_native_falsifier_covers_generation_and_default_off(self):
        for token in (
            "R3C4_PERSISTENT_PLAYABLE_WORLD_REQUIRED",
            "_r3c4_forced_captures",
            "_movement_checkpoint_writer",
            "_complete_async_movement_checkpoint",
            "_durable_ack_gate",
            "load_committed",
            "_r3c4_deferred_frames",
            "default-off",
            "quit(0 if failures.is_empty() else 1)",
        ):
            self.assertIn(token, TEST)

if __name__ == "__main__":
    unittest.main()
