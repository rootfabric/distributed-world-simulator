"""A preserved runtime report is machine evidence, never self-acceptance."""
from __future__ import annotations

import copy
import hashlib
import io
import json
import shutil
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from harness.verify_p7_closure_packet import ARCHIVES, PACKAGE, audit, audit_execution_provenance, audit_actions_provenance, read_archive, read_json


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

    def test_actions_claim_mutation_matrix_is_rejected(self):
        for key, value in {'runtime_run': 1, 'runtime_job': 1, 'pc0_run': 1,
                           'workflow_head_sha': '0' * 40, 'godot_binary_sha256': '0' * 64,
                           'gate_exit_code': 1, 'tracked_clean_before': False,
                           'tracked_clean_after': False}.items():
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'ACTIONS_CLAIM_MISMATCH'):
                audit_actions_provenance(ROOT / PACKAGE, {**self.manifest, key: value}, self.runtime, self.pc0)

    def test_actions_artifact_identity_mutation_is_rejected(self):
        for role in ('runtime_artifact', 'pc0_artifact'):
            for key, value in (('id', 1), ('zip_sha256', '0' * 64)):
                manifest = copy.deepcopy(self.manifest)
                manifest[role][key] = value
                with self.subTest(role=role, key=key), self.assertRaisesRegex(ValueError, 'ACTIONS_ARTIFACT_IDENTITY_MISMATCH'):
                    audit_actions_provenance(ROOT / PACKAGE, manifest, self.runtime, self.pc0)

    def test_original_member_binding_rejects_changed_log(self):
        runtime = dict(self.runtime)
        runtime[self.manifest['stages'][0]['log']] += b'altered'
        with self.assertRaisesRegex(ValueError, 'ARTIFACT_MEMBER_DIGEST_MISMATCH'):
            audit_actions_provenance(ROOT / PACKAGE, self.manifest, runtime, self.pc0)

    def test_original_actions_capture_matches_all_preserved_members(self):
        provider = audit_actions_provenance(ROOT / PACKAGE, self.manifest, self.runtime, self.pc0)
        self.assertEqual(34034752294, provider['runtime_run']['id'])

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


class ExecutedProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='p7-execution-inputs-')
        self.addCleanup(self.temp.cleanup)
        self.package = Path(self.temp.name)
        shutil.copytree(ROOT / PACKAGE / 'provenance', self.package / 'provenance')
        self.manifest_path = self.package / 'provenance/manifest.v1.json'

    def change_manifest(self, update):
        value = read_json(self.manifest_path.read_bytes())
        update(value)
        self.manifest_path.write_text(json.dumps(value), encoding='utf-8')

    def test_exact_workflow_and_both_runners_verified_without_source_branch(self):
        self.assertEqual(3, len(audit_execution_provenance(self.package)))

    def test_missing_workflow_rejected(self):
        (self.package / 'provenance/original-runtime-workflow.yml').unlink()
        with self.assertRaisesRegex(ValueError, 'EXECUTED_INPUT_MISSING_OR_LINKED'):
            audit_execution_provenance(self.package)

    def test_changed_failure_logic_rejected(self):
        path = self.package / 'provenance/original-runtime-workflow.yml'
        path.write_bytes(path.read_bytes().replace(b'set -euo pipefail', b'set +e'))
        with self.assertRaisesRegex(ValueError, 'EXECUTED_INPUT_DIGEST_MISMATCH'):
            audit_execution_provenance(self.package)

    def test_missing_nested_gate_rejected(self):
        (self.package / 'provenance/RUN_V0_P7_5_TWO_CLIENT_CONVERGENCE_GATE.sh').unlink()
        with self.assertRaisesRegex(ValueError, 'EXECUTED_INPUT_MISSING_OR_LINKED'):
            audit_execution_provenance(self.package)

    def test_wrong_workflow_identity_rejected(self):
        self.change_manifest(lambda m: m.update(workflow_head='0' * 40))
        with self.assertRaisesRegex(ValueError, 'EXECUTED_PROVENANCE_IDENTITY_MISMATCH'):
            audit_execution_provenance(self.package)

    def test_rebound_source_commit_rejected(self):
        self.change_manifest(lambda m: m['files'][0].update(source_commit='0' * 40))
        with self.assertRaisesRegex(ValueError, 'EXECUTED_INPUT_BINDING_MISMATCH'):
            audit_execution_provenance(self.package)

    def test_duplicate_snapshot_rejected(self):
        self.change_manifest(lambda m: m['files'].__setitem__(1, m['files'][0]))
        with self.assertRaisesRegex(ValueError, 'EXECUTED_INPUT_SET_MISMATCH'):
            audit_execution_provenance(self.package)


if __name__ == '__main__':
    unittest.main()
