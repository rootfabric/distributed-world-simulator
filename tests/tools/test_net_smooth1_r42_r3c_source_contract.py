"""R3C fail-closed architectural assertions (NOT a Windows runtime verdict)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/net_smooth1/run_net_smooth1.py").read_text(encoding="utf-8")


def method(name: str) -> str:
    start = SERVER.index("func " + name + "(")
    end = SERVER.find("\nfunc ", start + 5)
    return SERVER[start:] if end < 0 else SERVER[start:end]


class R3CSourceContract(unittest.TestCase):
    def test_disabled_by_default_and_optin_only(self):
        self.assertIn("var _r3c_async_admission_enabled := false", SERVER)
        self.assertIn('DWS_NET_R3C_ASYNC_ADMISSION', SERVER)
        self.assertIn('r3c_async_admission_canary', SERVER)
        self.assertIn("--r3c-async-admission", RUNNER)

    def test_join_backpressure_before_mutation_and_no_success_ack(self):
        join = method("_handle_join")
        self.assertLess(join.index('_r3c_defer_admission("JOIN"'), join.index("_service.join("))
        self.assertIn("if not _gate_can_accept():", join)
        enq = method("_r3c_defer_admission")
        self.assertIn("R3C_MAX_DEFERRED_ADMISSIONS", enq)
        self.assertIn("R3C_ADMISSION_IDENTITY_CONFLICT", enq)
        self.assertIn("not _p1b_item_pending.is_empty()", enq)

    def test_leave_reserved_before_mutation_or_writer(self):
        leave = method("_handle_leave")
        self.assertLess(leave.index('_r3c_defer_admission("LEAVE"'),
                        leave.index("_service.leave("))
        self.assertLess(leave.index(".reserve_mutation("),
                        leave.index("_service.leave("))
        self.assertLess(leave.index("_service.leave("),
                        leave.index("_p1b_begin_item_async_commit("))
        self.assertIn('before_gameplay_snapshot, "LEAVE"', leave)

    def test_only_after_commit_can_send_leave_ack(self):
        poll = method("_p1b_finish_item_committed")
        self.assertIn("_checkpoint_generation = generation", poll)
        self.assertIn("_r3c_publish_committed_leave(pending)", poll)
        send = method("_r3c_publish_committed_leave")
        self.assertIn("_p1b_item_async_owner.peek_publication(", send)
        self.assertIn('delivered = _send(peer_id, "LEAVE_ACK"', send)
        self.assertIn("_p1b_item_async_owner.mark_enqueued(", send)
        self.assertIn("_p1b_item_async_owner.discard_stale_session(", send)
        self.assertIn("mapped_to_original", send)
        self.assertIn("if delivered:", send)

    def test_stale_session_invalidation_and_nonblocking_drain(self):
        disconnect = method("_handle_disconnect")
        self.assertIn("_r3c_discard_session_admissions(", disconnect)
        self.assertLess(disconnect.index("_r3c_discard_session_admissions("),
                        disconnect.index("_commit_disconnect("))
        drain = method("_r3c_drain_deferred_admissions")
        self.assertIn("_is_peer_compatible(", drain)
        self.assertIn("R3C_ADMISSION_TIMEOUT_MS", drain)
        self.assertIn("_movement_checkpoint_writer.is_busy()", drain)
        self.assertIn("_handle_join(", drain)
        self.assertIn("_handle_leave(", drain)
        self.assertNotIn("wait_completed(", drain)

    def test_single_m6_writer_and_existing_proof_unmodified(self):
        begin = method("_p1b_begin_item_async_commit")
        self.assertIn('commit_kind not in ["ITEM", "DISCONNECT", "LEAVE"]', begin)
        self.assertIn("_p1b_item_async_owner.submit_frozen(", begin)
        self.assertIn("_replay_outbox.stage_committed(", begin)
        self.assertIn("_recovery_authority.export_recovery_state()", begin)
        self.assertIn("_replay_outbox.to_dict()", begin)
        self.assertIn('_p1b_item_pending = {', begin)
        self.assertNotIn("wait_completed(", begin)


if __name__ == "__main__":
    unittest.main()
