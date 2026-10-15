"""Fail-closed R3C.2 source and tooling contracts; Windows Godot remains authoritative."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p):
    return (ROOT / p).read_text(encoding="utf-8")

SERVER = read("scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
EARTH = read("scripts/app/earth_app.gd")
EARTH_AVATAR = read("scripts/app/earth_char1_avatar_app.gd")
AVATAR = read("scripts/characters/runtime/earth_network_avatar_presenter.gd")
HARNESS = read("tools/net_smooth1/run_net_smooth1.py")
APP = read("scripts/app/simulator_app.gd")


def func(src, name):
    found = re.search(r"^func " + re.escape(name) + r"\(", src, re.M)
    if found is None:
        raise ValueError("function missing: " + name)
    next_func = re.search(r"^func ", src[found.end():], re.M)
    return src[found.start(): found.end()+next_func.start() if next_func else len(src)]


class R3C2SourceSafety(unittest.TestCase):
    def test_manifest_exact_injected_ms_instead_of_silent_zero(self):
        self.assertIn("slow_item_writer_ms=args.slow_item_writer_ms", HARNESS)
        self.assertIn("DWS_NET_SMOOTH_TEST_ITEM_DELAY_MS", HARNESS)
        self.assertIn("'--slow-item-writer-ms'", HARNESS)
        self.assertIn("args.slow_item_writer_ms > 0", HARNESS)

    def test_client_cache_is_local_opt_in_and_bounded(self):
        self.assertIn('DWS_NET_R3C2_AVATAR_PREWARM', EARTH_AVATAR)
        self.assertIn('runtime_role == "game-client"', EARTH_AVATAR)
        self.assertIn("R3C2_MAX_RETAINED_REMOTE_VISUALS := 2", EARTH_AVATAR)
        self.assertIn("_r3c2_prewarmed_remote_presenter", EARTH_AVATAR)
        self.assertIn("func _retire_m3_remote_player_presenter(", EARTH_AVATAR)
        self.assertIn("func _create_m3_remote_player_presenter_for(", EARTH_AVATAR)
        self.assertIn("prewarm_visual(", AVATAR)
        self.assertIn("_avatar_host != null", AVATAR)
        self.assertIn("R3C2_AVATAR_PREWARM_IDENTITY_MISMATCH", AVATAR)
        self.assertIn("_delegate.free()", AVATAR)
        self.assertIn("super.setup(record, snapshot, map_position)", AVATAR)
        self.assertIn("has_input_authority() -> bool:", AVATAR)
        self.assertIn("return false", func(AVATAR, "has_input_authority"))

    def test_earth_reconnect_factory_hooks_preserve_original_default(self):
        self.assertIn("_create_m3_remote_player_presenter_for(logical_id)", EARTH)
        self.assertIn("_retire_m3_remote_player_presenter(logical_id, stale_presenter)", EARTH)
        self.assertIn("return _create_m3_remote_player_presenter()",func(EARTH,"_create_m3_remote_player_presenter_for"))
        self.assertIn("presenter.queue_free()",func(EARTH,"_retire_m3_remote_player_presenter"))

    def test_durability_canary_explicitly_disabled_by_default(self):
        self.assertIn("_r3c2_phased_item_publication_enabled := false", SERVER)
        self.assertIn('DWS_NET_R3C2_PHASED_ITEM_PUBLICATION', SERVER)
        self.assertIn('r3c2_phased_publication_canary', SERVER)
        self.assertIn("if not _r3c2_postcommit_pending.is_empty():\n\t\treturn false",func(SERVER,"_gate_can_accept"))
        self.assertIn("if not _r3c2_postcommit_pending.is_empty():\n\t\treturn",func(SERVER,"_maybe_persist_movement_checkpoint"))

    def test_worker_commit_before_staged_ack_and_snapshot(self):
        committed = func(SERVER,"_p1b_finish_item_committed")
        self.assertLess(committed.index("_checkpoint_generation = generation"),
                        committed.index('_r3c2_postcommit_pending = {'))
        self.assertIn('String(pending.get("kind", "ITEM")) == "ITEM"', committed)
        drained = func(SERVER,"_r3c2_drain_postcommit_stage")
        self.assertIn("stage := int(", drained)
        self.assertIn("match stage:", drained)
        self.assertIn("_p1b_item_async_owner.peek_publication(", drained)
        self.assertIn("_p1b_item_async_owner.mark_enqueued(", drained)
        self.assertIn("_p1b_item_async_owner.discard_stale_session(", drained)
        self.assertLess(drained.index("ready: Dictionary"), drained.index("_broadcast_snapshot("))
        self.assertIn("_r3c2_postcommit_pending.clear()", drained)
        self.assertIn("R3C2_POSTCOMMIT_ACK_FIFO_FAILED", drained)

    def test_shutdown_uses_quarantine_not_pretend_delivery(self):
        stop = func(SERVER,"_p1b_finish_item_shutdown_barrier")
        self.assertIn("_p1b_item_async_owner.discard_stale_session(", stop)
        self.assertIn("_r3c2_postcommit_pending.clear()", stop)
        self.assertIn("_p1b_item_resync_waiters.clear()", stop)

    def test_postcommit_stages_are_drained_on_server_process_not_client(self):
        process = func(SERVER,"_process")
        self.assertLess(process.index("_r3c2_drain_postcommit_stage()"), process.index("_p1b_poll_item_async_commit()"))
        self.assertIn('SmoothTrace.emit("r3c2_postcommit_stage"', func(SERVER,"_r3c2_drain_postcommit_stage"))
        self.assertNotIn("wait_completed(", func(SERVER,"_r3c2_drain_postcommit_stage"))

    def test_client_attach_counters_do_not_mutate_m6(self):
        self.assertIn('SmoothTrace.emit("r3c2_client_connect_attach"', APP)
        self.assertIn('SmoothTrace.emit("r3c2_join_ack_breakdown"',
                      read("scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"))
        self.assertIn('SmoothTrace.emit("r3c2_earth_attach"', EARTH)
        self.assertIn("r3c2_resource_attach", read("scripts/app/earth_p3_resource_mining_app.gd"))
        self.assertIn('--r3c2-avatar-prewarm', HARNESS)
        self.assertIn('--r3c2-server-phased', HARNESS)

    def test_normative_checker_not_replaced(self):
        stages = read("tools/net_smooth1/analyze_r3c2_stages.py")
        self.assertIn('DIAGNOSTIC_ONLY', stages)
        self.assertIn('normative_acceptance_must_use_analyze_net_smooth1', stages)
        original = read("tools/net_smooth1/analyze_net_smooth1.py")
        self.assertIn('frame p99 >25ms', original)
        self.assertIn('simulation <59Hz', original)


if __name__ == "__main__":
    unittest.main()
