"""Static, source-only P1-B R2 safety checks. NOT a Godot runtime verdict."""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
P2 = (ROOT / "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd").read_text(encoding="utf-8")
V0 = (ROOT / "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd").read_text(encoding="utf-8")
PROOF = (ROOT / "scripts/persistence/m6_async_durable_command_proof.gd").read_text(encoding="utf-8")
WRITER = (ROOT / "scripts/persistence/async_checkpoint_writer.gd").read_text(encoding="utf-8")


def method(source: str, name: str) -> str:
    match = re.search(r"^func " + re.escape(name) + r"\(", source, flags=re.MULTILINE)
    if not match:
        raise AssertionError("missing " + name)
    end = re.search(r"^func ", source[match.end():], flags=re.MULTILINE)
    return source[match.start():match.end() + end.start()] if end else source[match.start():]


class P1BProductionSourceSafetyTests(unittest.TestCase):
    def test_feature_requires_explicit_persistence(self):
        setup = method(P2, "setup")
        self.assertIn("async_durable_item_canary", setup)
        self.assertIn("DWS_NET_P1B_ITEM_ASYNC", setup)
        self.assertIn("P1B_CANARY_REQUIRES_PERSISTENT_PLAYABLE_WORLD", setup)
        self.assertIn("P1B_ITEM_SINGLE_WRITER_REQUIRED", setup)

    def test_item_reservation_before_real_mutation(self):
        item = method(P2, "_handle_item_command")
        self.assertLess(item.index("reserve_mutation("), item.index("_service.handle_canonical_item_command("))
        self.assertLess(item.index("_p1b_begin_item_async_commit("), item.index("_persist_command_result("))
        self.assertIn("release_noncommitting_reservation(", item)

    def test_detached_outbox_before_worker_submit(self):
        submit = method(P2, "_p1b_begin_item_async_commit")
        self.assertLess(submit.index("_replay_outbox.stage_committed("), submit.index("export_recovery_state()"))
        self.assertLess(submit.index("_p1b_item_pending = {"), submit.index(".submit_frozen("))
        self.assertIn("_enter_persistence_failure(", submit)
        self.assertNotIn("wait_completed(", submit)

    def test_nonblocking_process_owns_commit_completion(self):
        process = method(P2, "_process")
        self.assertLess(process.index("_p1b_poll_item_async_commit()"), process.index("_complete_async_movement_checkpoint(false)"))
        self.assertNotIn("wait_completed(", process)
        self.assertNotIn("OS.delay_", process)

    def test_snapshot_and_resync_visibility_fences(self):
        for name in ("_maybe_publish_movement_snapshot", "_broadcast_snapshot",
                     "_broadcast_item_snapshot", "_broadcast_item_delta"):
            body = method(P2, name)
            self.assertIn("_p1b_item_pending.is_empty()", body, name)
        self.assertIn("_p1b_item_resync_waiters[peer_id]", method(P2, "_handle_item_graph_resync_request"))
        self.assertIn("_p1b_flush_item_resync_waiters()", method(P2, "_p1b_publish_committed_item"))

    def test_publish_only_after_exact_worker_commit(self):
        poll = method(P2, "_p1b_poll_item_async_commit")
        self.assertIn("poll_command_completion()", poll)
        self.assertIn('get("committed", false)', poll)
        finish = method(P2, "_p1b_finish_item_committed")
        self.assertLess(finish.index("_checkpoint_generation = generation"), finish.index("_p1b_item_pending.clear()"))
        publish = method(P2, "_p1b_publish_committed_item")
        self.assertIn("peek_publication(", publish)
        self.assertIn("mark_enqueued(", publish)
        self.assertIn("_mark_operation_delivered(", publish)

    def test_shutdown_barrier_is_separate_from_frame_poll(self):
        shutdown = method(P2, "_p1b_finish_item_shutdown_barrier")
        self.assertIn(".wait_completed()", shutdown)
        self.assertIn("_p1b_finish_item_committed(accepted, false)", shutdown)

    def test_actual_v0_resource_mutation_has_gate(self):
        resource = method(V0, "_handle_resource_command")
        self.assertLess(resource.index("_gate_can_accept()"), resource.index("_service.handle_resource_mine("))
        self.assertIn("_resource_rejections += 1", resource)

    def test_actual_v0_construction_durability_gate(self):
        construction = method(V0, "_handle_construction_command")
        self.assertLess(construction.index("_gate_can_accept()"), construction.index("submit_player_command("))
        self.assertLess(construction.index("_construction_durability_allowed()"), construction.index("submit_player_command("))
        self.assertIn("M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED", construction)

    def test_previous_periodic_cannot_be_silently_discarded(self):
        proof = method(PROOF, "observe_periodic_completion")
        self.assertIn("P1B_PERIODIC_COMPLETION_OUT_OF_PHASE", proof)
        self.assertIn("return fail_closed(", proof)
        poll = method(WRITER, "poll_completed")
        self.assertIn("_completion.duplicate(true)", poll)


if __name__ == "__main__":
    unittest.main()
