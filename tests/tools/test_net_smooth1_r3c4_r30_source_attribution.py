"""R3.0 source falsifiers: instrumentation must not change M6 critical path."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "scripts/persistence/async_checkpoint_writer.gd"
OUTBOX = ROOT / "scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox_p2.gd"
SERVER = ROOT / "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
HARNESS = ROOT / "tools/net_smooth1/run_net_smooth1.py"

def function(body: str, name: str) -> str:
    match = re.search(r"(?m)^func " + re.escape(name) + r"\(.*?(?=^func |\Z)", body, re.S)
    if not match:
        raise AssertionError("missing function " + name)
    return match.group()

class R30Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = WRITER.read_text(encoding="utf-8")
        cls.o = OUTBOX.read_text(encoding="utf-8")
        cls.s = SERVER.read_text(encoding="utf-8")
        cls.h = HARNESS.read_text(encoding="utf-8")

    def test_r2_main_source_still_frozen_and_exact(self):
        src = function(self.s, "_submit_async_movement_checkpoint")
        self.assertIn("prepare_product_persistence_quiescence_only", src)
        self.assertIn("capture_frozen_gameplay_source_for_worker()", src)
        self.assertIn("_replay_outbox.to_dict_profiled()", src)
        self.assertIn("_replay_outbox.to_dict()", src)
        self.assertIn("_movement_checkpoint_writer.submit_frozen_gameplay_source(", src)
        self.assertIn("_checkpoint_generation + 1", src)
        self.assertIn("_r3c4r30_stage_attribution_enabled", src)

    def test_envelope_and_legacy_path_unchanged(self):
        old = function(self.o, "to_dict")
        self.assertIn('"gameplay_replay": _service.export_replay_state()', old)
        self.assertIn('"committed_outbox": _records', old)
        self.assertIn("Utils.finalize_json_checksum(value)", old)
        profiled = function(self.o, "to_dict_profiled")
        self.assertIn('_service.export_replay_state()', profiled)
        self.assertIn('"committed_outbox": _records', profiled)
        self.assertIn("Utils.finalize_json_checksum(value)", profiled)
        self.assertNotIn("await ", profiled)
        self.assertNotIn("_records.clear(", profiled)

    def test_worker_always_deep_copies_before_waking(self):
        sub = function(self.w, "submit_frozen_gameplay_source")
        self.assertIn('frozen_gameplay.duplicate(true)', sub)
        self.assertIn('replay_state.duplicate(true)', sub)
        self.assertLess(sub.index('.duplicate(true)'), sub.index('_wake.post()'))
        self.assertIn('profile_handoff_copy: bool = false', sub)
        self.assertIn('"handoff_copy_ms"', sub)
        worker = function(self.w, "_run")
        self.assertIn('M6Adapter.wrap_frozen_gameplay_source(', worker)
        self.assertIn('_repository.save_atomic(checkpoint)', worker)
        self.assertNotIn('get_node(', worker)

    def test_server_canary_and_fail_closed_dependency(self):
        setup = function(self.s, "setup")
        self.assertIn('R3C4_R30_INVALID_MODE', setup)
        self.assertIn('R3C4_R30_REQUIRES_R2_WORKER_ENVELOPE', setup)
        self.assertIn('DWS_NET_R3C4_R30_STAGE_ATTRIBUTION', setup)
        self.assertIn('r3c4r30_stage_attribution_canary', setup)

    def test_stage_names_distinguish_replay_from_submit_copy(self):
        capture = function(self.s, "_submit_async_movement_checkpoint")
        for token in ("r30_replay_gameplay_ms", "r30_replay_checksum_ms",
                      "r30_writer_deep_copy_ms", "r30_replay_ledger_count", "r30_outbox_count"):
            self.assertIn(token, capture)
        self.assertIn("to_dict(), *not* writer duplicate(true)", capture)

    def test_runner_is_server_only(self):
        self.assertIn("r3c4r30_stage_attribution=args.r3c4r30_stage_attribution", self.h)
        self.assertIn("if role == 'server' and args.r3c4r30_stage_attribution:", self.h)
        self.assertIn("env['DWS_NET_R3C4_R30_STAGE_ATTRIBUTION']='1'", self.h)
        self.assertIn("attribution requires --r3c4r2-worker-envelope", self.h)

if __name__ == "__main__":
    unittest.main()
