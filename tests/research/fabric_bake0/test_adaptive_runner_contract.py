#!/usr/bin/env python3
"""Exercise fail-closed runner plumbing with the attached canonical Godot only."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / 'scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh'
IMPORT = ROOT / 'scripts/research/fabric_bake0/validate_adaptive_import.py'
SENTINEL = 'B06_RUNNER_CONTRACT_SENTINEL: PASS'


def main() -> None:
    if not os.environ.get('GODOT_BIN'):
        raise SystemExit('GODOT_BIN must point to the attached canonical double runtime')
    cases: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix='b06-runner-contract-') as temporary:
        base = Path(temporary)
        positive = 'extends SceneTree\nfunc _initialize():\n\tprint("' + SENTINEL + '")\n\tquit(0)\n'
        programs = {
            'positive': (positive, 0),
            'missing-sentinel': ('extends SceneTree\nfunc _initialize():\n\tquit(0)\n', 6),
            'runtime-error': (
                'extends SceneTree\nfunc broken():\n\tvar value: Variant = null\n'
                '\tvalue.missing_method()\nfunc _initialize():\n'
                '\tprint("' + SENTINEL + '")\n\tbroken()\n\tquit(0)\n', 5),
            'nonzero-exit': (positive.replace('quit(0)', 'quit(9)'), 9),
            'log-sink-failure': (positive, 7),
        }
        for name, (program, expected) in programs.items():
            script = base / (name + '.gd')
            script.write_text(program, encoding='utf-8')
            environment = os.environ.copy()
            if name == 'log-sink-failure':
                executable_dir = base / 'bin'
                executable_dir.mkdir()
                tee = executable_dir / 'tee'
                tee.write_text('#!/bin/sh\ncat > /dev/null\nexit 7\n', encoding='utf-8')
                tee.chmod(0o755)
                environment['PATH'] = str(executable_dir) + os.pathsep + environment['PATH']
            result = subprocess.run(
                ['bash', str(HELPER), str(script), SENTINEL], cwd=ROOT,
                env=environment, capture_output=True, text=True, timeout=30,
            )
            if result.returncode != expected:
                raise RuntimeError(f'{name}: expected {expected}, got {result.returncode}\n'
                                   + result.stdout + result.stderr)
            cases.append({'case': name, 'expected_exit': expected, 'actual_exit': result.returncode})
        banner = 'Godot Engine v4.7.1.stable.double.custom_build.a13da4feb\n'
        for name, text, success in [
            ('import-clean', banner, True),
            ('import-error', banner + 'ERROR: unexpected importer failure\n', False),
        ]:
            log = base / (name + '.log')
            log.write_text(text, encoding='utf-8')
            result = subprocess.run(['python3', str(IMPORT), str(log)], cwd=ROOT,
                                    capture_output=True, text=True, timeout=30)
            if (result.returncode == 0) != success:
                raise RuntimeError(f'{name}: unexpected importer validator result')
            cases.append({'case': name, 'expected_success': success, 'actual_exit': result.returncode})
    print('B06_RUNNER_CONTRACT_CASES=' + json.dumps(cases, sort_keys=True, separators=(',', ':')))
    print(f'FABRIC B0.6 Runner Contracts: PASS ({len(cases)} assertions)')


if __name__ == '__main__':
    main()
