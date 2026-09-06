"""A preserved runtime report is machine evidence, never self-acceptance."""
from __future__ import annotations

import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from harness.verify_p7_closure_packet import ARCHIVES, PACKAGE, audit, read_archive, read_json


class P7ClosurePacketTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = read_json((ROOT / PACKAGE / 'manifest.v1.json').read_bytes())
        cls.runtime = read_archive(ROOT / PACKAGE / 'runtime-evidence.tar.xz', ARCHIVES['runtime-evidence.tar.xz'])
        cls.pc0 = read_archive(ROOT / PACKAGE / 'pc0-evidence.tar.xz', ARCHIVES['pc0-evidence.tar.xz'])

    def test_exact_packet_counts_each_leaf_once_and_does_not_accept(self):
        report = audit(self.manifest, self.runtime, self.pc0)
        self.assertEqual(2032, report['assertions'])
        self.assertEqual(29, report['stages'])
        self.assertEqual(0, report['fatal_matches'])
        self.assertFalse(report['canonical_acceptance'])
        self.assertFalse(report['runtime_authorized'])
        self.assertIn('FULL_WORLD_CORE_REGRESSION_PASS', report['unresolved_gates'])

    def test_wrong_subject_rejected(self):
        manifest = {**self.manifest, 'subject_head_sha': '0' * 40}
        with self.assertRaisesRegex(ValueError, 'SUBJECT_MISMATCH'):
            audit(manifest, self.runtime, self.pc0)

    def test_missing_or_duplicate_stage_rejected(self):
        for stages in (self.manifest['stages'][:-1], [*self.manifest['stages'][:-1], self.manifest['stages'][0]]):
            with self.subTest(count=len(stages)), self.assertRaisesRegex(ValueError, 'STAGE_COVERAGE_MISMATCH'):
                audit({**self.manifest, 'stages': stages}, self.runtime, self.pc0)

    def test_fatal_log_cannot_be_hidden_by_green_banner(self):
        runtime = dict(self.runtime)
        path = self.manifest['stages'][0]['log']
        runtime[path] += b'\nSCRIPT ERROR: injected negative fixture\n'
        with self.assertRaisesRegex(ValueError, 'FATAL_LOG'):
            audit(self.manifest, runtime, self.pc0)

    def test_wrong_assertion_count_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['stages'][0]['assertions'] += 1
        with self.assertRaisesRegex(ValueError, 'ASSERTION_COUNT_MISMATCH'):
            audit(manifest, self.runtime, self.pc0)

    def test_wrong_pc0_subject_rejected(self):
        pc0 = dict(self.pc0)
        report = json.loads(pc0['project-control-report.json'])
        report['main_head'] = '0' * 40
        pc0['project-control-report.json'] = json.dumps(report).encode()
        with self.assertRaisesRegex(ValueError, 'PC0_SUBJECT_MISMATCH'):
            audit(self.manifest, self.runtime, pc0)

    def test_archive_digest_rejected(self):
        with self.assertRaisesRegex(ValueError, 'ARCHIVE_DIGEST_MISMATCH'):
            read_archive(ROOT / PACKAGE / 'runtime-evidence.tar.xz', '0' * 64)

    def test_archive_traversal_rejected_without_extraction(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'negative.tar.xz'
            with tarfile.open(path, 'w:xz') as archive:
                member = tarfile.TarInfo('../outside.txt')
                member.size = 1
                archive.addfile(member, io.BytesIO(b'x'))
            with self.assertRaisesRegex(ValueError, 'ARCHIVE_MEMBER_INVALID'):
                read_archive(path, hashlib.sha256(path.read_bytes()).hexdigest())

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaisesRegex(ValueError, 'DUPLICATE_JSON_KEY'):
            read_json('{"value":1,"value":2}')


if __name__ == '__main__':
    unittest.main()
