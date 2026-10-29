"""Fail-closed R3C.4 R1 source and fault-mutant contracts; Windows Godot remains authoritative."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p):
    return (ROOT / p).read_text(encoding="utf-8")

SERVER = read("scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
HARNESS = read("tools/net_smooth1/run_net_smooth1.py")
ANALYZER = read("tools/net_smooth1/analyze_net_smooth1.py")
RUNTIME_TEST = read("tests/runtime/test_net_smooth1_r3c4_periodic_frame_headroom.gd")


def func(src, name):
    found = re.search(r"^func " + re.escape(name) + r"\(", src, re.M)
    if found is None:
        raise ValueError("function missing: " + name)
    next_func = re.search(r"^func ", src[found.end():], re.M)
    return src[found.start(): found.end()+next_func.start() if next_func else len(src)]


class R3C4SourceSafety(unittest.TestCase):
    def test_pacing_is_opt_in_default_off(self):
        self.assertIn("_r3c4_periodic_frame_pacing_enabled := false", SERVER)
        self.assertIn("DWS_NET_R3C4_PERIODIC_FRAME_PACING", SERVER)
        self.assertIn("r3c4_periodic_frame_pacing_canary", SERVER)
        self.assertIn("R3C4_INVALID_PACING_MODE", SERVER)
        slot = func(SERVER, "_r3c4_periodic_capture_slot_available")
        self.assertIn("if not _r3c4_periodic_frame_pacing_enabled:\n\t\treturn true", slot)

    def test_gate_sits_after_due_gate_before_dispatch(self):
        persist = func(SERVER, "_maybe_persist_movement_checkpoint")
        self.assertIn("if not _r3c4_periodic_capture_slot_available():\n\t\treturn", persist)
        self.assertLess(persist.index("M7_MOVEMENT_CHECKPOINT_INTERVAL_MS"),
                        persist.index("_r3c4_periodic_capture_slot_available()"))
        self.assertLess(persist.index("_r3c4_periodic_capture_slot_available()"),
                        persist.index('SmoothTrace.emit("periodic_checkpoint_dispatch"'))
        # The durable command barrier keeps priority over any pacing decision.
        self.assertLess(persist.index("if not _r3c2_postcommit_pending.is_empty():"),
                        persist.index("_r3c4_periodic_capture_slot_available()"))

    def test_deferral_is_bounded_and_single_writer_untouched(self):
        slot = func(SERVER, "_r3c4_periodic_capture_slot_available")
        self.assertIn("const R3C4_MAX_DEFERRAL_MS := 64", SERVER)
        self.assertIn("R3C4_MAX_DEFERRAL_MS", slot)
        self.assertIn("_last_movement_snapshot_tick == _server_tick", slot)
        self.assertIn('SmoothTrace.emit("r3c4_periodic_frame_deferred"', slot)
        self.assertIn('SmoothTrace.emit("r3c4_periodic_capture_slot"', slot)
        self.assertIn('"forced": true', slot)
        # No alternate generation, no dirty clearing, no writer bypass.
        for forbidden in ("_checkpoint_generation", "_movement_checkpoint_dirty = false",
                          "_persist_checkpoint", "_submit_async_movement_checkpoint",
                          "wait_completed("):
            self.assertNotIn(forbidden, slot)

    def test_pipeline_calls_are_unchanged(self):
        persist = func(SERVER, "_maybe_persist_movement_checkpoint")
        self.assertIn("_recovery_authority.export_recovery_state()", func(SERVER, "_submit_async_movement_checkpoint"))
        self.assertIn("_replay_outbox.to_dict()", func(SERVER, "_submit_async_movement_checkpoint"))
        self.assertIn("AsyncCheckpointWriter", SERVER)
        self.assertIn("_submit_async_movement_checkpoint()\n\t\treturn", persist)

    def test_harness_flag_is_server_only_and_default_off(self):
        self.assertIn("'--r3c4-periodic-frame-pacing'", HARNESS)
        self.assertIn("env['DWS_NET_R3C4_PERIODIC_FRAME_PACING']='1'", HARNESS)
        self.assertIn("if role == 'server' and args.r3c4_periodic_frame_pacing:", HARNESS)
        self.assertIn("r3c4_periodic_frame_pacing=args.r3c4_periodic_frame_pacing", HARNESS)
        self.assertNotIn("--r3c4-periodic-frame-pacing", read("scripts/app/earth_app.gd"))

    def test_runtime_falsifier_covers_contract(self):
        for token in ("default off without flag/env", "does NOT submit", "forced after 64ms",
                      "R3C4_INVALID_PACING_MODE", "low-work frame submits", "only completion advances generation",
                      "loadable from disk"):
            self.assertIn(token, RUNTIME_TEST)

    def test_analyzer_and_normative_checker_untouched(self):
        self.assertIn('frame p99 >25ms', ANALYZER)
        self.assertIn('simulation <59Hz', ANALYZER)
        self.assertNotIn("r3c4", ANALYZER)


if __name__ == "__main__":
    unittest.main()
