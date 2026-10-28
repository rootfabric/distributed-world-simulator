"""Portable logic tests. Explicitly NOT Windows native Job acceptance."""
from pathlib import Path
import ctypes as C
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/net_smooth1'))
import win_job_guard as guard
from run_r31_job_guard import save_receipt


class Clock:
    def __init__(self): self.t = 0.0
    def now(self): return self.t
    def sleep(self, delta): self.t += delta


class Portable(unittest.TestCase):
    def test_redacts_both_token_forms(self):
        self.assertEqual(guard.redact_argv(['python', '--automation-control-token=secret',
            '--password', 'value', '--world=earth']),
            ['python', '--automation-control-token=<redacted>', '--password', '<redacted>', '--world=earth'])

    def test_ordinary_arguments_unchanged(self):
        self.assertEqual(guard.redact_argv(['a', '--node-id=smooth-a', '--port=9001']),
                         ['a', '--node-id=smooth-a', '--port=9001'])

    def test_environment_sorted_double_null(self):
        self.assertEqual(guard.environment_block({'b': '2', 'A': '1'}), 'A=1\0b=2\0\0')

    def test_environment_rejects_nul_and_invalid_names(self):
        for data in ({'A': 'b\0c'}, {'A=B': 'x'}, {'': 'x'}):
            with self.subTest(data=data), self.assertRaises(ValueError):
                guard.environment_block(data)

    def test_empty_proof_needs_both_accounting_and_list(self):
        c = Clock()
        states = iter([{'active': 0, 'pids': [8]}, {'active': 1, 'pids': []}, {'active': 0, 'pids': []}])
        result = guard.wait_empty(lambda: next(states), 1, clock=c.now, sleep=c.sleep)
        self.assertEqual(result, {'active': 0, 'pids': []})
        self.assertGreater(c.t, 0)

    def test_timeout_does_not_fake_empty(self):
        c = Clock()
        result = guard.wait_empty(lambda: {'active': 1, 'pids': [8]}, .1,
                                  clock=c.now, sleep=c.sleep)
        self.assertEqual(result['pids'], [8])
        self.assertGreaterEqual(c.t, .1)

    def test_query_failure_remains_failure(self):
        def fail(): raise OSError('query denied')
        with self.assertRaises(OSError): guard.wait_empty(fail, .1)

    def test_bad_timeouts_rejected(self):
        for value in (-1, float('nan'), float('inf')):
            with self.subTest(value=value), self.assertRaises(ValueError):
                guard.wait_empty(lambda: {}, value)

    def test_only_owned_job_termination_no_pid_scan(self):
        source = (ROOT / 'tools/net_smooth1/win_job_guard.py').read_text()
        self.assertIn('JOB_LIST = 0x2000D', source)
        self.assertIn('KILL_ON_CLOSE = 0x2000', source)
        self.assertIn('TerminateJobObject(self.handle', source)
        self.assertNotIn('taskkill', source)
        self.assertNotIn('AssignProcessToJobObject(', source)
        self.assertIn('identity = api.identity(proc.handle, self.handle)', source)

    def test_pid_and_creation_identity_retained_before_resume(self):
        source = (ROOT / 'tools/net_smooth1/run_r31_job_guard.py').read_text()
        self.assertLess(source.index('save_receipt(receipt, state)'), source.index('process.resume()'))
        self.assertIn('creation_filetime_100ns', (ROOT / 'tools/net_smooth1/win_job_guard.py').read_text())

    def test_non_windows_native_claim_impossible(self):
        if os.name != 'nt':
            with self.assertRaisesRegex(OSError, 'WINDOWS_NATIVE_JOB_REQUIRED'):
                guard.OwnedJob()

    def test_receipt_atomic_replacement(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / 'receipt.json'
            save_receipt(file, {'status': 'RUNNING'})
            save_receipt(file, {'status': 'FAILED'})
            self.assertEqual(json.loads(file.read_text())['status'], 'FAILED')
            self.assertFalse(file.with_suffix('.json.tmp').exists())

    def test_kill_on_close_is_only_job_limit(self):
        limits = guard.ExtendedLimit()
        limits.basic.flags = guard.KILL_ON_CLOSE
        self.assertEqual(limits.basic.priority, 0)
        self.assertEqual(limits.basic.active_limit, 0)
        self.assertEqual(limits.process_memory, 0)
        self.assertEqual(limits.basic.flags & (0x800 | 0x1000), 0)  # no breakaway

    def test_x64_struct_layout_before_native_use(self):
        if C.sizeof(C.c_void_p) == 8:
            self.assertEqual(C.sizeof(guard.ExtendedLimit), 144)
            self.assertEqual(C.sizeof(guard.Startup), 104)
            self.assertEqual(C.sizeof(guard.StartupEx), 112)
            self.assertEqual(C.sizeof(guard.Accounting), 48)


if __name__ == '__main__': unittest.main()
