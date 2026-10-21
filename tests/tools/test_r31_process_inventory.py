import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("inventory", ROOT/"tools/net_smooth1/capture_r31_process_inventory.py")
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)

EVIDENCE = [{"run_id": "0123456789abcdef", "wrapper_pids": {"a": 7},
             "trace_header_main_pids": {"a": 8}}]

def row(command, pid=8):
    return {"pid": pid, "parent_pid": 7, "creation_utc": "2026-10-21T10:00:00Z",
            "name": "Godot.exe", "command_line": command, "executable": "C:\\Godot\\Godot.exe"}


class InventoryTest(unittest.TestCase):
    def test_tokens_redacted_equals_quotes_and_split(self):
        for s in ('--automation-control-token=secret', '--automation-control-token="two words"',
                  '--automation-control-token secret'):
            x = inventory.sanitize_command('Godot.exe '+s+' --instance-id=0123456789abcdef')
            self.assertNotIn('secret', x)
            self.assertNotIn('two words', x)
            self.assertIn('<redacted>', x)

    def test_different_pid_and_run_not_silently_claimed_owned(self):
        out = inventory.classify_rows([row('Godot.exe --instance-id=fedcba9876543210', 99)], EVIDENCE)
        self.assertFalse(out[0]['pid_seen_in_old_evidence'])
        self.assertEqual(out[0]['matching_instance_markers'], [])
        self.assertEqual(out[0]['ownership_verdict'], 'UNPROVEN_READ_ONLY_NO_KILL')

    def test_pid_match_is_not_ownership_due_to_pid_reuse(self):
        out = inventory.classify_rows([row('another application')], EVIDENCE)
        self.assertTrue(out[0]['pid_seen_in_old_evidence'])
        self.assertEqual(out[0]['matching_instance_markers'], [])
        self.assertEqual(out[0]['ownership_verdict'], 'UNPROVEN_READ_ONLY_NO_KILL')

    def test_marker_observation_not_kill_permission(self):
        out = inventory.classify_rows([row('Godot --instance-id="0123456789abcdef"')], EVIDENCE)
        self.assertEqual(out[0]['matching_instance_markers'], ['0123456789abcdef'])
        self.assertEqual(out[0]['ownership_verdict'], 'UNPROVEN_READ_ONLY_NO_KILL')

    def test_invalid_pid_fails(self):
        with self.assertRaisesRegex(ValueError, 'INVALID_INVENTORY_PID'):
            inventory.classify_rows([row('', pid=True)], EVIDENCE)

    def test_strict_literal_marker_no_substring_match(self):
        out = inventory.classify_rows([row('Godot --instance-id=0123456789abcdef000')], EVIDENCE)
        self.assertEqual(out[0]['matching_instance_markers'], [])


if __name__ == '__main__':
    unittest.main()
