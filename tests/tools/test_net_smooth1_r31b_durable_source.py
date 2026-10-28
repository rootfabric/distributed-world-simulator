"""Fail-closed R31b instrumentation source contracts. Python stdlib only."""
from __future__ import annotations
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SEAM = ROOT / "scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd"
M6 = ROOT / "scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd"
SERVER = ROOT / "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
HARNESS = ROOT / "tools/net_smooth1/run_net_smooth1.py"

def method(text: str, name: str) -> str:
    m = re.search(r"(?m)^func " + re.escape(name) + r"\(.*?(?=^func |^\#.*?\nfunc |\Z)", text, re.S)
    if m is None:
        raise AssertionError(f"missing {name}")
    return m.group(0)

class Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.seam = SEAM.read_text(encoding="utf-8")
        cls.m6 = M6.read_text(encoding="utf-8")
        cls.srv = SERVER.read_text(encoding="utf-8")
        cls.runner = HARNESS.read_text(encoding="utf-8")

    def test_default_export_retains_exact_canonical_fields(self):
        normal = method(self.seam, "export_durable_state")
        self.assertIn("super.export_durable_state()", normal)
        self.assertIn("create_snapshot()", normal)
        self.assertIn("_build_remote_player_durable_state", normal)
        self.assertIn("_build_remote_ownership_durable_state", normal)
        self.assertIn("_shared_items.export_durable_state()", normal)
        self.assertIn("_canonical_multiplayer_items.export_durable_state()", normal)
        self.assertIn("_resource_mining.export_durable_state()", normal)
        self.assertIn("SeamUtils.finalize_json_checksum(state)", normal)
        self.assertIn("validate_durable_state(state)", normal)
        self.assertNotIn("r31b", normal)

    def test_new_path_is_explicitly_seam_fenced_and_validation_equivalent(self):
        observed = method(self.seam, "export_durable_state_r31b_profiled")
        tokens = (
            "_seam_transfers_quiescent()",
            "super.export_durable_state()",
            "create_snapshot()",
            "_build_remote_player_durable_state(snapshot)",
            "_build_remote_ownership_durable_state(snapshot)",
            "_shared_items.export_durable_state()",
            "_canonical_multiplayer_items.export_durable_state()",
            "_resource_mining.export_durable_state()",
            "SeamUtils.finalize_json_checksum(durable)",
            "validate_durable_state(durable)",
            '"server_tick": _tick',
            '"authority_owner_id": _authority_owner_id',
        )
        for token in tokens:
            self.assertIn(token, observed)
        for stage in (
            "snapshot_ms", "players_ms", "ownership_ms", "shared_item_ms",
            "item_graph_ms", "resource_ms", "final_checksum_ms",
            "validation_ms", "total_ms",
        ):
            self.assertIn(stage, observed)
        self.assertNotIn("await ", observed)
        self.assertNotIn("Thread.new", observed)

    def test_m6_still_owns_full_single_frame_capture(self):
        adapter = method(self.m6, "capture_frozen_gameplay_source_r31b_profiled")
        self.assertIn("_service.export_durable_state_r31b_profiled()", adapter)
        self.assertIn('"logical_session_id": _logical_session_id', adapter)
        self.assertNotIn("get_node", adapter)
        self.assertIn("wrap_frozen_gameplay_source", self.m6)

    def test_server_diagnostic_opt_in_cannot_run_alone(self):
        setup = method(self.srv, "setup")
        self.assertIn('DWS_NET_R3C4_R31B_DURABLE_ATTRIBUTION', setup)
        self.assertIn("R3C4_R31B_INVALID_MODE", setup)
        self.assertIn("R3C4_R31B_REQUIRES_R31_REPLAY_PROJECTION", setup)
        self.assertIn("R3C4_R31B_REQUIRES_PRODUCT_SEAM", setup)
        self.assertIn("r3c4r31b_durable_attribution_canary", setup)
        submit = method(self.srv, "_submit_async_movement_checkpoint")
        self.assertIn("_recovery_authority.capture_frozen_gameplay_source_r31b_profiled()", submit)
        self.assertIn("_recovery_authority.capture_frozen_gameplay_source_for_worker()", submit)
        self.assertIn('capture_event["r31b_durable_stages"]', submit)
        self.assertIn("submit_frozen_gameplay_source(", submit)
        self.assertIn("_checkpoint_generation + 1", submit)
        self.assertNotIn("wait_completed()", submit)

    def test_r31b_harness_passes_server_only_flag(self):
        self.assertIn("r3c4r31b_durable_attribution=args.r3c4r31b_durable_attribution", self.runner)
        self.assertIn("if role == 'server' and args.r3c4r31b_durable_attribution:", self.runner)
        self.assertIn("env['DWS_NET_R3C4_R31B_DURABLE_ATTRIBUTION']='1'", self.runner)
        self.assertIn("R3C4 R3.1b durable attribution requires --r3c4r31-replay-projection", self.runner)


if __name__ == "__main__":
    unittest.main()
