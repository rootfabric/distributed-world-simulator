"""Exercise real CI shell bodies with fake processes, never fake physics evidence.

PyYAML==6.0.2; Linux failure injection and hosted PowerShell Core checks.
FABRIC_CI_SOURCE_ROOT can select frozen parent workflows for RED reproduction.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml

ROOT = Path(os.environ.get('FABRIC_CI_SOURCE_ROOT', Path(__file__).resolve().parents[2]))
P0_PATH = '.github/workflows/fabric-r563-p0-coupled-pair-exact.yml'
WIN_PATH = '.github/workflows/fabric-bake-b0-4-c-windows-double.yml'
T14_PATH = '.github/workflows/fabric-r5-2-t14-observation-refinement.yml'
if os.environ.get('FABRIC_CI_REQUIRE_PWSH') == '1' and not shutil.which('pwsh'):
    raise RuntimeError('POWERSHELL_CORE_REQUIRED_FOR_CI_REGRESSIONS')

LINUX_SHA = 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7'
WINDOWS_SHA = '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'


def workflow(path: str) -> dict:
    return yaml.safe_load((ROOT / path).read_text(encoding='utf-8'))


def step(path: str, job: str, name: str) -> dict:
    return next(s for s in workflow(path)['jobs'][job]['steps'] if s.get('name') == name)


class WorkflowContracts(unittest.TestCase):
    def test_physics_gates_and_hashes_are_not_relaxed(self):
        source = (ROOT / P0_PATH).read_text()
        for pin in [LINUX_SHA, 'cd36048523a7f86928d8891e9f6a0fc8362b1f23',
                    '5f27f60092a05bccfb928adcabdff37648238c66',
                    'obj["checks"]==438', 'obj["negatives"]==12',
                    'obj["failures"]==[]', 'obj["max_energy_drift_ratio"]<0.01',
                    'assert lines[0]==lines[1]']:
            self.assertIn(pin, source)
        self.assertNotIn('continue-on-error', source)

    def test_t14_expression_syntax_and_original_trigger_preserved(self):
        text = (ROOT / T14_PATH).read_text()
        self.assertNotIn('${{{', text)
        expressions = re.findall(r'\$\{\{(.*?)\}\}', text)
        self.assertEqual([x.strip() for x in expressions],
                         ['github.ref', 'github.event_name', 'github.sha'])
        self.assertEqual(text.count('${{'), len(expressions))
        obj = workflow(T14_PATH)
        trigger = obj.get('on', obj.get(True))
        self.assertEqual(trigger['push']['branches'], ['research/fabric-r5-2-t14-observation-refinement-r1'])

    def test_windows_requires_core_and_exact_hash_without_cmdlet(self):
        obj = workflow(WIN_PATH)['jobs']['exact-double']
        self.assertEqual(obj['defaults']['run']['shell'], 'pwsh')
        resolver = step(WIN_PATH, 'exact-double', 'Resolve exact double Godot')['run']
        self.assertIn("GODOT_SHA256_MISMATCH", resolver)
        self.assertIn(WINDOWS_SHA, resolver)
        self.assertNotIn('(Get-FileHash', resolver)
        self.assertIn('$engineExit = $LASTEXITCODE', resolver)
        init = step(WIN_PATH, 'exact-double', 'Initialize isolated evidence')['run']
        self.assertIn('POWERSHELL_CORE_REQUIRED', init)
        self.assertIn('APPDATA', init)
        self.assertIn('LOCALAPPDATA', init)
        self.assertIn('RUNNER_TEMP', init)

    def test_always_finalization_precedes_strict_upload(self):
        steps = workflow(P0_PATH)['jobs']['linux-double']['steps']
        seal = next(i for i, s in enumerate(steps) if s.get('name') == 'Seal available logs even on failure')
        upload = next(i for i, s in enumerate(steps) if s.get('uses', '').startswith('actions/upload-artifact@'))
        self.assertLess(seal, upload)
        self.assertEqual(steps[seal]['if'], 'always()')
        self.assertEqual(steps[upload]['if'], 'always()')
        self.assertEqual(steps[upload]['with']['if-no-files-found'], 'error')
        self.assertEqual(steps[upload]['with']['path'], 'artifacts/fabric-r563-p0-ci/**')

    def test_windows_import_retains_nonzero_and_parse_guards(self):
        code = step(WIN_PATH, 'exact-double', 'Fresh Godot import')['run']
        for marker in ['--recovery-mode', 'Tee-Object', '$LASTEXITCODE',
                       'GODOT_IMPORT_FAILED', 'SCRIPT ERROR', 'Parse Error']:
            self.assertIn(marker, code)


@unittest.skipIf(os.name == 'nt', 'Linux shell fault matrix; PowerShell tests run on Windows')
class LinuxFailureEvidence(unittest.TestCase):
    def run_case(self, scenario: str) -> tuple[int, dict[str, bytes], str]:
        with tempfile.TemporaryDirectory(prefix='fabric-ci-space ') as folder:
            root = Path(folder)
            subprocess.run(['git', 'init', '-q', str(root)], check=True, capture_output=True)
            subprocess.run(['git', '-c', 'user.name=CI Fixture', '-c', 'user.email=fixture@example.invalid',
                            'commit', '--allow-empty', '-qm', 'fixture'], cwd=root, check=True, capture_output=True)
            tools = root / 'fake tools'
            tools.mkdir()
            fake = tools / 'godot'
            fake.write_text('#!' + sys.executable + '\n' + r'''
import json, os, pathlib, sys
scenario=os.environ['FABRIC_TEST_SCENARIO']
args=sys.argv[1:]
if '--import' in args:
    phase='import-recovery' if '--recovery-mode' in args else 'import'
else:
    counter=pathlib.Path('.fake-counter')
    n=int(counter.read_text())+1 if counter.exists() else 1
    counter.write_text(str(n))
    phase='pair-'+str(n)
print('FAKE_PROCESS_PHASE='+phase,flush=True)
if scenario==phase:
    print('INJECTED_FAILURE_'+phase,file=sys.stderr,flush=True)
    sys.exit(23)
if scenario=='parse-import' and phase=='import':
    print('SCRIPT ERROR: deliberate import error',flush=True)
if phase.startswith('pair-'):
    result={'checks':438,'failures':[],'negatives':12,'max_energy_drift_ratio':0.0020370820818046043}
    if scenario=='bad-count':result['checks']=437
    if scenario=='energy':result['max_energy_drift_ratio']=0.02
    if scenario=='mismatch' and phase=='pair-2':result['max_energy_drift_ratio']=0.0021
    if scenario=='parse-pair':print('SCRIPT ERROR: deliberate acceptance error')
    print('FABRIC_R563_P0_RESULT='+json.dumps(result,separators=(',',':')),flush=True)
''', encoding='utf-8')
            fake.chmod(0o755)
            real_sha = shutil.which('sha256sum')
            self.assertIsNotNone(real_sha)
            shim = tools / 'sha256sum'
            # Only the fake executable hash is substituted; log hashes use real sha256sum.
            shim.write_text('#!/bin/bash\nif [[ "$1" == "$DWS_GODOT_DOUBLE_BIN" ]]; then\n'
                            f'  printf "%s  %s\\n" "{LINUX_SHA if scenario != "hash" else "0"*64}" "$1"\n'
                            f'else exec "{real_sha}" "$@"; fi\n')
            shim.chmod(0o755)
            env = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ['PATH'],
                       DWS_GODOT_DOUBLE_BIN=str(fake if scenario != 'missing' else tools/'absent'),
                       RUNNER_TEMP=str(root/'runner temp'), GITHUB_RUN_ID='fixture',
                       GITHUB_RUN_ATTEMPT='1', FABRIC_TEST_SCENARIO=scenario)
            command = step(P0_PATH, 'linux-double', 'Strict isolated Godot 4.7.1 double P0 proof')['run']
            script = root/'run.sh'
            script.write_text(command)
            result = subprocess.run(['bash', '--noprofile', '--norc', str(script)], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=40)
            finalizer = next((x for x in workflow(P0_PATH)['jobs']['linux-double']['steps']
                              if x.get('name') == 'Seal available logs even on failure'), None)
            if finalizer:
                sealed = subprocess.run(['bash', '-c', finalizer['run']], cwd=root, env=env,
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(sealed.returncode, 0, sealed.stdout+sealed.stderr)
            evidence = root/'artifacts/fabric-r563-p0-ci'
            files = {p.name:p.read_bytes() for p in evidence.iterdir() if p.is_file()} if evidence.exists() else {}
            return result.returncode, files, result.stdout+result.stderr

    def assert_manifest(self, files: dict[str, bytes]) -> None:
        self.assertIn('SHA256SUMS', files)
        seen=set()
        for row in files['SHA256SUMS'].decode().splitlines():
            expected, path = row.split(None, 1)
            name = path.strip().removeprefix('./')
            self.assertIn(name, files)
            self.assertEqual(hashlib.sha256(files[name]).hexdigest(), expected)
            seen.add(name)
        self.assertEqual(seen, set(files)-{'SHA256SUMS'})

    def test_positive_keeps_results_and_complete_manifest(self):
        rc, files, output = self.run_case('success')
        self.assertEqual(rc, 0, output)
        self.assertIn('canonical-result.json', files)
        self.assertEqual(files.get('run-exit-code.txt'), b'0\n')
        self.assert_manifest(files)

    def test_each_native_failure_keeps_partial_logs_and_exit(self):
        for phase in ['import-recovery', 'import', 'pair-1', 'pair-2']:
            with self.subTest(phase=phase):
                rc, files, output = self.run_case(phase)
                self.assertEqual(rc, 23, output)
                self.assertIn(phase+'.log', files)
                self.assertIn(('INJECTED_FAILURE_'+phase).encode(), files[phase+'.log'])
                self.assertIn('INJECTED_FAILURE_'+phase, output)
                self.assertEqual(files.get('run-exit-code.txt'), b'23\n')
                self.assertNotIn('canonical-result.json', files)
                self.assert_manifest(files)

    def test_validation_failures_never_become_success(self):
        for scenario in ['bad-count', 'energy', 'mismatch', 'parse-pair', 'parse-import']:
            with self.subTest(scenario=scenario):
                rc, files, output = self.run_case(scenario)
                self.assertNotEqual(rc, 0, output)
                self.assertIn('identity.txt', files)
                self.assertNotIn('canonical-result.json', files)
                self.assert_manifest(files)

    def test_missing_or_wrong_engine_keeps_preflight_evidence(self):
        for scenario in ['missing', 'hash']:
            with self.subTest(scenario=scenario):
                rc, files, output = self.run_case(scenario)
                self.assertNotEqual(rc, 0, output)
                self.assertIn('identity.txt', files)
                self.assertIn('run-exit-code.txt', files)
                self.assertNotIn('pair-1.log', files)
                self.assert_manifest(files)


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell Core unavailable locally; required in hosted matrix')
class PowerShellResolver(unittest.TestCase):
    def run_resolver(self, scenario: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory(prefix='fabric windows space ') as folder:
            root=Path(folder)
            fake=root/('godot.cmd' if os.name=='nt' else 'godot')
            version='4.7.1.stable.double.custom_build.a13da4feb' if scenario != 'version' else 'wrong-engine'
            exit_code=9 if scenario=='exit' else 0
            fake.write_text((f'@echo {version}\n@exit /b {exit_code}\n' if os.name=='nt'
                             else f'#!/bin/sh\necho {version}\nexit {exit_code}\n'))
            fake.chmod(0o755)
            code=step(WIN_PATH,'exact-double','Resolve exact double Godot')['run']
            # Substitute only the known fixture digest in a temporary script. No production bypass.
            if scenario != 'hash':
                code=code.replace(WINDOWS_SHA,hashlib.sha256(fake.read_bytes()).hexdigest())
            script=root/'resolve.ps1'
            script.write_text("function Get-FileHash { throw 'UNEXPECTED_CMDLET_DEPENDENCY' }\n"+code,encoding='utf-8')
            env=dict(os.environ,CONFIGURED_GODOT_BIN=str(fake),GITHUB_OUTPUT=str(root/'output.txt'))
            return subprocess.run(['pwsh','-NoLogo','-NoProfile','-File',str(script)],cwd=root,
                                  env=env,capture_output=True,text=True,timeout=30)

    def test_valid_binary_with_missing_hash_cmdlet(self):
        result=self.run_resolver('success')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('GODOT_SHA256=',result.stdout)

    def test_changed_binary_is_rejected(self):
        result=self.run_resolver('hash')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('GODOT_SHA256_MISMATCH',result.stdout+result.stderr)

    def test_wrong_version_is_rejected(self):
        result=self.run_resolver('version')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('GODOT_IDENTITY_MISMATCH',result.stdout+result.stderr)

    def test_nonzero_version_exit_is_rejected(self):
        result=self.run_resolver('exit')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('GODOT_VERSION_QUERY_FAILED',result.stdout+result.stderr)


if __name__=='__main__':
    unittest.main()
