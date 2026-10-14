from __future__ import annotations
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')

class R3SourceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = read('scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd')
        cls.client = read('scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd')
        cls.view = read('scripts/runtime/networked_gameplay/contracts/committed_movement_view.gd')
        cls.writer = read('scripts/persistence/async_checkpoint_writer.gd')
        cls.proof = read('scripts/persistence/m6_async_durable_command_proof.gd')
        cls.service = read('scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd')

    def test_safe_wire_projection(self):
        self.assertIn('P1B_COMMITTED_VIEW_MOVEMENT', self.server)
        self.assertIn('_build_p1b_committed_movement_snapshot()', self.server)
        self.assertIn('_p1b_committed_view = before_gameplay_snapshot', self.server)
        self.assertIn('FullSnapshot.validate(before_gameplay_snapshot)', self.server)
        self.assertIn('CommittedView.peer_is_fenced', self.server)
        self.assertIn('Full.create(', self.view)
        for field in ('position', 'velocity', 'orientation_yaw', 'last_input_sequence'):
            self.assertIn('"' + field + '"', self.view)
        for forbidden in ('frozen["inventory"] =', 'frozen["state_revision"] =',
                          'frozen["ownership_epoch"] =', 'frozen["transport_session_id"] ='):
            self.assertNotIn(forbidden, self.view)
        self.assertIn('or int(live.get("ownership_epoch", -1))', self.view)

    def test_client_canonical_revision_never_advanced(self):
        self.assertIn('_accept_committed_view_movement_snapshot', self.client)
        self.assertIn('CompactGameplaySnapshot.decode(wire)', self.client)
        self.assertIn('CommittedView.project(', self.client)
        start = self.client.index('func _accept_committed_view_movement_snapshot(')
        end = self.client.index('func _same_snapshot_state_except_clock(', start)
        overlay = self.client[start:end]
        self.assertNotIn('_replica.accept_snapshot(', overlay)
        self.assertNotIn('_replica.accept_delta(', overlay)
        self.assertIn('replica_updated.emit(presentation.duplicate(true))', overlay)
        self.assertIn('r3_committed_view_received', overlay)

    def test_async_writer_ownership_and_m6_barrier(self):
        self.assertIn('func submit_owned(', self.writer)
        self.assertIn('return submit_owned(authority_state.duplicate(true)', self.writer)
        self.assertIn('if _writer.has_method("submit_owned")', self.proof)
        self.assertIn('mark_submitted(operation_id, generation)', self.proof)
        self.assertIn('poll_command_completion()', self.server)
        self.assertIn('accept_command_completion(completed)', self.server)
        self.assertIn('DWS_NET_SMOOTH_TEST_HOOKS', self.writer)
        self.assertIn('OS.delay_msec(test_delay_ms)', self.writer)

    def test_nonblocking_20hz_and_true_periodic_route_evidence(self):
        self.assertIn('NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS', self.server)
        self.assertIn('"periodic_checkpoint_dispatch"', self.server)
        self.assertIn('"SYNC_FALLBACK"', self.server)
        self.assertIn('"LEGACY_COMMAND_SYNC"', self.server)
        self.assertIn('"prior_writer_wait_ms"', self.server)
        self.assertIn('"authority_export_ms"', self.server)
        self.assertIn('prepare_product_persistence_quiescence_only', self.server)
        self.assertIn('func prepare_product_persistence_quiescence_only', self.service)

    def test_only_detached_state_enters_writer(self):
        self.assertIn('export_recovery_state()', self.server)
        self.assertIn('_replay_outbox.to_dict()', self.server)
        self.assertNotIn('authority_state.duplicate(true),\n\t\t"replay": replay_state.duplicate(true)', self.writer)
        self.assertIn('var durable_players_view: Dictionary = create_snapshot()', self.service)

if __name__ == '__main__':
    unittest.main()
