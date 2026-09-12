#!/usr/bin/env python3
"""Run the pinned local matrix sequentially; import explicitly labelled CI observations.

Invoke from a control checkout against a clean, separately pinned product worktree.
This is not a daemon, scheduler, freeze tool, or replacement for canonical Harness.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

import qualification as Q


def write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def clean(repo: Path, head: str) -> bool:
    return Q.git(repo, 'rev-parse', 'HEAD') == head and not Q.git(repo, 'status', '--porcelain=v1', '--untracked-files=no')


def execute(argv: list[str], repo: Path, env: dict[str, str], logfile: Path, timeout: int) -> int:
    with logfile.open('wb') as stream:
        process = subprocess.Popen(argv, cwd=repo, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            return 124


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'policy', 'godot', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('head', 'tree', 'policy-sha256'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--ci-observation', action='append', default=[], metavar='GATE_ID=FILE')
    args = parser.parse_args(argv)
    try:
        repo, binary = args.repo.resolve(), args.godot.resolve()
        policy_bytes = args.policy.read_bytes()
        if Q.digest(policy_bytes) != args.policy_sha256:
            raise Q.EvidenceError('POLICY_FILE_DIGEST_MISMATCH')
        policy = Q.load_json(args.policy)
        findings = Q.verify_subject(repo, args.head, args.tree, policy)
        empty = {'schema': Q.REPORT_SCHEMA, 'subject_head': args.head, 'subject_tree': args.tree,
                 'policy_sha256': args.policy_sha256, 'gates': []}
        # Validate policy shape before allowing any policy command execution.
        Q.reduce_evidence(policy, empty, args.out, args.head, args.tree, args.policy_sha256, findings)
        if findings or not clean(repo, args.head):
            raise Q.EvidenceError('PRODUCT_WORKTREE_OR_HISTORICAL_CONTROL_INVALID')
        binary_hash = Q.digest(binary.read_bytes())
        for gate in policy['gates']:
            if not re.fullmatch(r'[a-z0-9_-]+', gate['id']):
                raise Q.EvidenceError('UNSAFE_GATE_ID')
            if gate.get('mode', 'exact_binary') == 'exact_binary':
                if binary_hash != gate['godot_sha256']:
                    raise Q.EvidenceError('GODOT_DIGEST_MISMATCH')
                if type(gate.get('timeout_seconds')) is not int or not 1 <= gate['timeout_seconds'] <= 7200:
                    raise Q.EvidenceError('INVALID_GATE_TIMEOUT')
        ci = {}
        for item in args.ci_observation:
            gate_id, filename = item.split('=', 1)
            if gate_id in ci or not any(g['id'] == gate_id and g.get('mode') == 'ci_workflow' for g in policy['gates']):
                raise Q.EvidenceError('UNKNOWN_OR_DUPLICATE_CI_OBSERVATION')
            ci[gate_id] = Path(filename)
        # Immutable run directory: never overwrite previous evidence.
        args.out.mkdir(parents=True, exist_ok=False)
        (args.out / 'policy.json').write_bytes(policy_bytes)
        write_json(args.out / 'environment.json', {'platform': platform.platform(), 'python': sys.version,
            'godot_binary': str(binary), 'godot_sha256': binary_hash,
            'role': 'IMPLEMENTER_SELF_VALIDATION', 'independent_review': False,
            'source_check': 'tracked git files and exact HEAD; generated untracked cache is not versioned'})
        env = dict(os.environ, GODOT_BIN=str(binary), GODOT=str(binary),
                   GODOT_SILENCE_ROOT_WARNING='1', BREAKPOINT_RUNTIME_DISABLED='1')
        report = empty
        for gate in policy['gates']:
            mode = gate.get('mode', 'exact_binary')
            receipt = {key: gate[key] for key in ('id', 'command_id', 'argv', 'environment_id')}
            receipt.update(mode=mode, subject_head=args.head, subject_tree=args.tree,
                policy_sha256=args.policy_sha256, classification='NONE')
            if mode == 'ci_workflow':
                if gate['id'] not in ci:
                    continue  # Reducer will report MISSING, never an implicit PASS.
                target = args.out / (gate['id'] + '.observation.json')
                shutil.copyfile(ci[gate['id']], target)
                receipt.update(workflow_path=gate['workflow_path'], workflow_blob=gate['workflow_blob'],
                    status='COMPLETED', conclusion='PASS', evidence=[{'role': 'ci_api_observation',
                    'path': target.name, 'sha256': Q.digest(target.read_bytes())}])
                # A declaration cannot bypass the detailed observation checks below.
            else:
                if not clean(repo, args.head):
                    raise Q.EvidenceError('PRODUCT_CHANGED_BETWEEN_GATES')
                target = args.out / (gate['id'] + '.log')
                started = time.monotonic()
                code = execute(gate['argv'], repo, env, target, gate['timeout_seconds'])
                receipt.update(godot_sha256=Q.digest(binary.read_bytes()), status='COMPLETED',
                    conclusion='PASS' if code == 0 else 'FAIL', exit_code=code,
                    source_clean=clean(repo, args.head), duration_seconds=time.monotonic() - started,
                    evidence=[{'role': 'combined_log', 'path': target.name, 'sha256': Q.digest(target.read_bytes())}])
            report['gates'].append(receipt)
            write_json(args.out / 'receipts.json', report)
        findings = Q.verify_subject(repo, args.head, args.tree, policy)
        result = Q.reduce_evidence(policy, report, args.out, args.head, args.tree, args.policy_sha256, findings)
        write_json(args.out / 'qualification.json', result)
        print(json.dumps(result, indent=2))
        return 0 if result['qualification'] == 'PASS' else 2
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(json.dumps({'qualification': 'INVALID_EVIDENCE', 'error': str(exc),
                          'production_freeze_allowed': False, 'checkpoint_accepted': False}))
        return 3


if __name__ == '__main__':
    sys.exit(main())
