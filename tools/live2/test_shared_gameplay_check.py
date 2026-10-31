"""Falsifiers for the gameplay evidence oracle; also run under python -O."""
import copy
import unittest
from unittest.mock import patch

from shared_gameplay_check import SharedGameplayCheck, require, verify_world


def states():
    state = {'report': {'connection_state': 'CONNECTED'},
             'items': {'checksum': 'a' * 64, 'items': [
                 {'item_id': 'item/shared/ore/1', 'definition_id': 'item/ore',
                  'quantity': 8, 'location': {'kind': 'WORLD'}},
                 {'item_id': 'item/server-output/test', 'definition_id': 'item/ore',
                  'quantity': 3, 'location': {'kind': 'INVENTORY', 'player_id': 'b'}}]},
             'resource': {'checksum': 'b' * 64, 'nodes': [
                 {'resource_node_id': 'resource/earth/ore-demo/1', 'remaining_units': 5}]},
             'construction': {'checksum': 'c' * 64},
             'outpost': {'completed_stage_count': 0, 'construct_checksum': ''}}
    return {'a': copy.deepcopy(state), 'b': copy.deepcopy(state)}


class EvidenceOracleTests(unittest.TestCase):
    def test_optimized_guards_active(self):
        with self.assertRaises(AssertionError):
            require(False, 'negative')

    def test_transferred_ore(self):
        verify_world(states(), 5, 0, 3, 0)

    def test_lost_or_duplicated_ore(self):
        for quantity in (0, 2, 4, 6):
            value = states()
            value['b']['items']['items'][1]['quantity'] = quantity
            with self.subTest(quantity=quantity), self.assertRaises(AssertionError):
                verify_world(value, 5, 0, 3, 0)

    def test_hidden_duplicate_in_world(self):
        value = states()
        value['a']['items']['items'].append({'item_id': 'duplicate', 'definition_id': 'item/ore',
                                           'quantity': 1, 'location': {'kind': 'WORLD'}})
        with self.assertRaises(AssertionError):
            verify_world(value, 5, 0, 3, 0)

    def test_seed_ore_cannot_pay_build_cost(self):
        value = states()
        for state in value.values():
            state['items']['items'][0]['quantity'] = 6
            state['outpost'] = {'completed_stage_count': 1, 'construct_checksum': 'd' * 64}
        with self.assertRaises(AssertionError):
            verify_world(value, 5, 0, 3, 1)

    def test_empty_construction_cannot_pass_foundation(self):
        value = states()
        for state in value.values():
            state['items']['items'][1]['quantity'] = 1
            state['outpost']['completed_stage_count'] = 1
        with self.assertRaises(AssertionError):
            verify_world(value, 5, 0, 1, 1)

    def test_replica_disagreement(self):
        value = states()
        value['b']['resource']['checksum'] = 'x' * 64
        with self.assertRaises(AssertionError):
            verify_world(value, 5, 0, 3, 0)

    def test_disconnected_state_not_accepted(self):
        value = states()
        value['b']['report']['connection_state'] = 'RECONNECTING'
        with self.assertRaises(AssertionError):
            verify_world(value, 5, 0, 3, 0)

    def test_retry_keeps_operation_id(self):
        runner = object.__new__(SharedGameplayCheck)
        runner.commands = []
        replies = [{'success': False, 'error_code': 'P1A_WAIT_PRIOR_PERIODIC'}, {'success': True}]
        with patch.object(runner, '_rpc_once', side_effect=replies) as once, patch('time.sleep'):
            runner.rpc('a', 'mine')
        self.assertEqual(once.call_args_list[0], once.call_args_list[1])

    def test_unknown_rejection_and_timeout_fail(self):
        runner = object.__new__(SharedGameplayCheck)
        runner.commands = []
        for error in ('DURABLE_GATE_BACKPRESSURE', 'V0_P3_RESOURCE_COMMAND_TIMEOUT', 'TEST_DISK_FAILURE'):
            with patch.object(runner, '_rpc_once', return_value={'success': False, 'error_code': error}):
                with self.subTest(error=error), self.assertRaises(AssertionError):
                    runner.rpc('a', 'mine')

    def test_retry_is_bounded(self):
        runner = object.__new__(SharedGameplayCheck)
        runner.commands = []
        with patch.object(runner, '_rpc_once', return_value={
            'success': False, 'error_code': 'P1A_WAIT_PRIOR_PERIODIC'}) as once, patch('time.sleep'):
            with self.assertRaises(RuntimeError):
                runner.rpc('a', 'mine')
        self.assertEqual(once.call_count, 20)


if __name__ == '__main__':
    unittest.main()
