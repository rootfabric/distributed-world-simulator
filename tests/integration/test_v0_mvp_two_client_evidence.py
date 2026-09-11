"""Synthetic falsifiers for the MVP2 observation consumer, not runtime evidence."""
import copy
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'docs/control/mvp-act0-r1'))
from validate_mvp2 import BUILD, SCENE, PROCESS_DRIVER, observation_errors, shared_errors, neutral_boundary_errors
HEAD = '1' * 40


def fixture():
    snapshot = {'schema': 'synthetic', 'server_tick': 100, 'checksum': 'clock-dependent',
                'authority_owner_id': 'authority/one', 'authority_epoch': 1, 'revision': 4,
                'players': [dict(logical_player_id=p, player_entity_id='player/' + p,
                                 connected=True, ownership_epoch=1, last_input_sequence=2,
                                 position={'x': x, 'y': 1.0, 'z': 0.0}, velocity={'x': 0.0, 'y': 0.0, 'z': 0.0}) for p, x in [('a', 0.0), ('b', 2.0)]]}
    item = {'checksum': 'a' * 64, 'revision': 2, 'items': [{'item_id': 'one', 'quantity': 1}]}
    fp = {'git_commit': HEAD, 'world_id': 'moon', 'build_id': BUILD, 'session_token': 'same'}
    surface = dict(configured=True, bootstrap_hash='b' * 64, descriptor={'anchor': [0, 1, 0]},
                   canonical_state_owned=False, mutable_matter_store_retained=False, mesh_count=4)
    result = []
    for index, name in enumerate(('server', 'a', 'b')):
        server = name == 'server'
        result.append(dict(configured=True, stopped=False, input_active=False, error='', scene_path=SCENE, world_id='moon',
                           process_id=index + 1, user_data_dir='/isolated/' + name,
                           role='dedicated-server' if server else 'game-client', player_id=name,
                           server_runtime_present=server, client_runtime_present=not server,
                           local_body_visible=not server, active_camera='/camera' if not server else '',
                           surface=copy.deepcopy(surface), snapshot=copy.deepcopy(snapshot),
                           item_graph_snapshot=copy.deepcopy(item),
                           runtime=dict(last_error_code='', network_fingerprint=copy.deepcopy(fp),
                                        connected_peer_count=2, peer_to_player={'peerA': 'a', 'peerB': 'b'},
                                        joined=True, compatibility_handshake={'verified': True},
                                        server_disconnects=0, transport_session_id='session/' + name),
                           remote_presenters={} if server else {
                               'b' if name == 'a' else 'a': dict(input_authority=False, body_visible_in_tree=True,
                                                              inside_camera_frustum=True)}))
    return result


class MVP2EvidenceTests(unittest.TestCase):
    def test_complete_shared_observation_passes(self):
        self.assertEqual([], shared_errors(*fixture(), HEAD))

    def test_only_clock_and_its_checksum_may_differ(self):
        values = fixture()
        values[1]['snapshot'].update(server_tick=101, checksum='new-clock')
        self.assertEqual([], shared_errors(*values, HEAD))

    def test_one_client_is_not_a_two_client_world(self):
        o = fixture()[1]
        o['snapshot']['players'].pop()
        self.assertIn('TWO_PLAYERS_REQUIRED', observation_errors(o, HEAD, 'a'))

    def test_hidden_remote_rejected(self):
        values = fixture()
        values[1]['remote_presenters']['b']['body_visible_in_tree'] = False
        self.assertIn('a:REMOTE_VISIBILITY', shared_errors(*values, HEAD))

    def test_remote_outside_frustum_rejected(self):
        values = fixture()
        values[2]['remote_presenters']['a']['inside_camera_frustum'] = False
        self.assertIn('b:REMOTE_VISIBILITY', shared_errors(*values, HEAD))

    def test_foreign_session_fingerprint_rejected(self):
        values = fixture()
        values[2]['runtime']['network_fingerprint']['session_token'] = 'foreign'
        self.assertIn('SHARED_FINGERPRINT_MISMATCH', shared_errors(*values, HEAD))

    def test_same_process_or_data_directory_rejected(self):
        for field, expected in [('process_id', 'PROCESS_ISOLATION'), ('user_data_dir', 'USER_DATA_ISOLATION')]:
            values = fixture()
            values[2][field] = values[1][field]
            self.assertIn(expected, shared_errors(*values, HEAD))

    def test_tampered_player_state_rejected(self):
        values = fixture()
        values[2]['snapshot']['players'][0]['position']['x'] += 1
        self.assertIn('SHARED_GAMEPLAY_MISMATCH', shared_errors(*values, HEAD))

    def test_equal_checksum_does_not_hide_item_payload_mismatch(self):
        values = fixture()
        values[2]['item_graph_snapshot']['items'][0]['quantity'] = 9
        self.assertIn('SHARED_ITEM_GRAPH_MISMATCH', shared_errors(*values, HEAD))

    def test_mutable_client_or_remote_input_owner_rejected(self):
        values = fixture()
        values[1]['surface']['mutable_matter_store_retained'] = True
        values[2]['remote_presenters']['a']['input_authority'] = True
        errors = shared_errors(*values, HEAD)
        self.assertIn('a:CLIENT_MATTER_AUTHORITY', errors)
        self.assertIn('b:REMOTE_INPUT_AUTHORITY', errors)

    def test_foreign_exact_head_rejected(self):
        values = fixture()
        values[2]['runtime']['network_fingerprint']['git_commit'] = '2' * 40
        self.assertIn('b:FINGERPRINT_IDENTITY', shared_errors(*values, HEAD))


    def test_neutral_barrier_accepts_only_acknowledged_stopped_state(self):
        self.assertEqual([], neutral_boundary_errors(*fixture(), HEAD, {'a': 2, 'b': 2}))

    def test_shared_but_moving_snapshot_is_not_a_neutral_boundary(self):
        values = fixture()
        for observation in values:
            observation['snapshot']['players'][0]['velocity']['x'] = 6.0
        self.assertEqual([], shared_errors(*values, HEAD))
        self.assertIn('PLAYER_NOT_SETTLED:server:a', neutral_boundary_errors(*values, HEAD, {'a': 2, 'b': 2}))

    def test_stale_neutral_acknowledgement_is_rejected(self):
        self.assertIn('NEUTRAL_NOT_ACKNOWLEDGED:server:a',
                      neutral_boundary_errors(*fixture(), HEAD, {'a': 10, 'b': 2}))

    def test_active_input_is_not_a_neutral_boundary(self):
        values = fixture()
        values[1]['input_active'] = True
        self.assertIn('INPUT_NOT_NEUTRAL:a', neutral_boundary_errors(*values, HEAD, {'a': 2, 'b': 2}))

    def test_missing_neutral_target_is_rejected(self):
        self.assertIn('NEUTRAL_TARGET_MISSING:a', neutral_boundary_errors(*fixture(), HEAD, {'b': 2}))

    def test_driver_is_fixture_but_focused_test_is_standalone(self):
        driver = Path(PROCESS_DRIVER.removeprefix('res://'))
        focused = Path('tests/runtime/test_v0_mvp_two_client_shared_world.gd')
        self.assertIn('fixtures', driver.parts[:-1])
        self.assertNotIn('fixtures', focused.parts[:-1])
        self.assertTrue(focused.match('test_*.gd'))
        # On a repository checkout also bind this classification to the actual runner.
        runner = ROOT / 'RUN_WORLD_REGRESSION_TESTS.ps1'
        if runner.exists():
            self.assertIn('$ExcludedTestDirectoryNames = @("fixtures")', runner.read_text(encoding='utf-8'))
            self.assertTrue((ROOT / driver).is_file())
            self.assertFalse((ROOT / 'tests/integration/test_v0_mvp_two_client_process.gd').exists())


if __name__ == '__main__':
    unittest.main()
