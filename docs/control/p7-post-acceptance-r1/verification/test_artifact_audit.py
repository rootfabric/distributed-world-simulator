"""Fault-injection controls for the evidence auditor (never mutate original ZIPs)."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import tempfile
import unittest
import warnings
from zipfile import ZipFile, ZIP_DEFLATED
from audit_artifact import audit, sha

SOURCE = Path('/mnt/data/p7-control-62ae.zip')
EXPECTED = '496676242011a3e704eac083dd1cfca54fdbe2c17bb62b0f1b9137f3f0aa672d'


class ArtifactAuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='p7-proof-audit-')
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'case.zip'
        with ZipFile(SOURCE) as z:
            self.data = {n: z.read(n) for n in z.namelist()}
        self.prefix = next(n.removesuffix('manifest.json') for n in self.data if n.endswith('/manifest.json'))

    def obj(self, name):
        return json.loads(self.data[self.prefix + name])

    def put(self, name, value):
        self.data[self.prefix + name] = (json.dumps(value, indent=2) + '\n').encode()

    def write_case(self, *, rehash=False, duplicate=False):
        if rehash:
            manifest = self.obj('manifest.json')
            for entry in manifest['files']:
                raw = self.data[self.prefix + entry['path']]
                entry.update(bytes=len(raw), sha256=sha(raw))
            self.put('manifest.json', manifest)
        with ZipFile(self.path, 'w', ZIP_DEFLATED) as z:
            for name, data in self.data.items():
                z.writestr(name, data)
            if duplicate:
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    z.writestr(self.prefix + 'result.json', self.data[self.prefix + 'result.json'])
        return sha(self.path.read_bytes())

    def rejected(self, code, **kwargs):
        digest = self.write_case(**kwargs)
        with self.assertRaisesRegex(ValueError, code):
            audit(self.path, digest)

    def test_original_positive(self):
        result = audit(SOURCE, EXPECTED)
        self.assertTrue(result['passed'])
        self.assertEqual(274, result['details']['harness_tests'])

    def test_zip_digest_mismatch(self):
        self.write_case()
        with self.assertRaisesRegex(ValueError, 'ZIP_DIGEST_MISMATCH'):
            audit(self.path, '0' * 64)

    def test_modified_member(self):
        self.data[self.prefix + 'harness.log'] += b'changed\n'
        self.rejected('MEMBER_MISMATCH')

    def test_duplicate_zip_entries(self):
        self.rejected('DUPLICATE_ZIP_ENTRIES', duplicate=True)

    def test_unsafe_zip_path(self):
        self.data['../outside.json'] = b'{}'
        self.rejected('UNSAFE_ZIP_PATH')

    def test_unindexed_member(self):
        self.data[self.prefix + 'extra.json'] = b'{}'
        self.rejected('UNINDEXED_OR_MISSING_MEMBERS')

    def test_foreign_head(self):
        manifest = self.obj('manifest.json')
        manifest['subject']['head'] = '0' * 40
        self.put('manifest.json', manifest)
        self.rejected('SUBJECT_OR_RUN_MISMATCH')

    def test_dirty_postflight(self):
        post = self.obj('postflight.json')
        post['tracked_status'] = ' M scripts/test.gd'
        self.put('postflight.json', post)
        self.rejected('CHECKOUT_DRIFT', rehash=True)

    def test_failed_result_cannot_be_rehashed_to_pass(self):
        result = self.obj('result.json')
        result['passed'] = False
        self.put('result.json', result)
        self.rejected('RESULT_NOT_PASS', rehash=True)

    def test_machine_cannot_grant_acceptance(self):
        result = self.obj('result.json')
        result['canonical_acceptance'] = True
        self.put('result.json', result)
        self.rejected('MACHINE_REPORT_CLAIMS_ACCEPTANCE', rehash=True)

    def test_command_declaration_mismatch(self):
        command = self.obj('harness.command.json')
        command['command'] = ['true']
        self.put('harness.command.json', command)
        self.rejected('COMMAND_DECLARATION_MISMATCH', rehash=True)

    def test_unexpected_exit_is_not_negative_control(self):
        for name in ['harness.command.json', 'harness.result.json']:
            value = self.obj(name)
            value['expected_exit'] = 1
            if name.endswith('.result.json'):
                value['exit_code'] = 1
            self.put(name, value)
        self.rejected('UNDECLARED_NEGATIVE_EXIT', rehash=True)

    def test_advisory_must_be_exact_boolean_false(self):
        for invalid in [True, None, 0, 'false', 'False', '0', '']:
            with self.subTest(value=invalid):
                value = self.obj('raw/control/directional-watch-report.json')
                for finding in value['findings']:
                    if finding.get('level') == 'RED':
                        finding['global_blocking'] = invalid
                self.put('raw/control/directional-watch-report.json', value)
                self.rejected('DIRECTIONAL_BLOCKING', rehash=True)

    def test_missing_advisory_flag_fails_closed(self):
        value = self.obj('raw/control/directional-watch-report.json')
        for finding in value['findings']:
            if finding.get('level') == 'RED':
                finding.pop('global_blocking', None)
        self.put('raw/control/directional-watch-report.json', value)
        self.rejected('DIRECTIONAL_BLOCKING', rehash=True)

    def test_forged_pc0_authority(self):
        value = self.obj('raw/control/project-control-report.json')
        value['main_head'] = '1' * 40
        self.put('raw/control/project-control-report.json', value)
        self.rejected('PC0_AUTHORITY_MISMATCH', rehash=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--control-zip', type=Path, default=SOURCE)
    args, rest = parser.parse_known_args()
    SOURCE = args.control_zip
    unittest.main(argv=[__file__, *rest])
