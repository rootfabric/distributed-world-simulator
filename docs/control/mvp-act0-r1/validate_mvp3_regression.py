"""MVP3 regression against an explicitly audited main; historical MVP2 code is unchanged."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import validate_mvp2 as workload

AUDITED_MAIN = '7dfc68ab5a1e90254a1b7039807f275b5da04eef'
HISTORICAL_MAIN = '127c732a56cc5c25d5712f24a7627ed4bb877374'
MVP2_FROZEN = '287df80c69840fea7ae9ac0ea69a07581f192d34'
CLOSURE = '0b297f6afe2ca6e97efaddb0e6cd4278108d8936'
CONSUMER_BLOB = '847746b047cf249d45b52b5047ccea830809552b'
AUDITED_MAIN_PATHS = {
    'AGENTS.md',
    'config/control/harness/continuation-policy.v1.json',
    'config/control/harness/harness-policy.v1.json',
    'docs/control/HARNESS_CHANNEL_RECOVERY_RU.md',
    'scripts/harness/contracts.py',
    'scripts/harness/project_overview.py',
    'tests/harness/test_execution_channel_recovery_policy.py',
    'tests/harness/test_execution_channel_routing_policy.py',
    'tests/harness/test_v0_product_train_policy.py',
}
PROTECTED_MVP2 = [
    'scripts/runtime/networked_gameplay/mvp/v0_mvp_two_client_shared_world.gd',
    'scenes/labs/mvp/v0_mvp_two_client_shared_world.tscn',
    'tests/fixtures/v0_mvp/two_client_process.gd',
    'tests/runtime/test_v0_mvp_two_client_shared_world.gd',
    'tests/integration/test_v0_mvp_two_client_evidence.py',
    'docs/control/mvp-act0-r1/validate_mvp2.py',
]


def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], cwd=workload.ROOT, text=True).strip()


def audit_main(expected: str, observed: str, paths: set[str]) -> None:
    workload.require(observed == expected, 'NEW_MAIN_DRIFT_REQUIRES_AUDIT')
    workload.require(paths == AUDITED_MAIN_PATHS, 'UNAUDITED_MAIN_CHANGESET')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True)
    args = parser.parse_args()
    out = workload.ROOT / 'artifacts/mvp2-exact'
    out.mkdir(parents=True, exist_ok=False)
    record = {'schema': 'distributed_world_simulator.mvp3_regression_epoch_audit.v1',
              'passed': False, 'historical_main': HISTORICAL_MAIN, 'audited_main': AUDITED_MAIN,
              'independent_verdict': False, 'predicate_verified': False,
              'historical_validator_modified': False, 'runtime_checks_disabled': False}
    try:
        head = git('rev-parse', 'HEAD')
        record['subject_head'] = head
        workload.require(head == os.environ.get('EXPECTED_HEAD', head), 'EXACT_HEAD_MISMATCH')
        workload.require(not git('status', '--porcelain', '--untracked-files=no'), 'TRACKED_CHECKOUT_DIRTY')
        workload.require(git('hash-object', 'docs/control/mvp-act0-r1/validate_mvp2.py') == CONSUMER_BLOB, 'HISTORICAL_CONSUMER_CHANGED')
        workload.require(workload.MAIN == HISTORICAL_MAIN, 'HISTORICAL_PIN_CHANGED')
        git('merge-base', '--is-ancestor', HISTORICAL_MAIN, AUDITED_MAIN)
        git('merge-base', '--is-ancestor', CLOSURE, head)
        paths = set(git('diff', '--name-only', HISTORICAL_MAIN, AUDITED_MAIN).splitlines())
        audit_main(AUDITED_MAIN, git('rev-parse', 'origin/main'), paths)
        workload.require(not git('diff', '--name-only', MVP2_FROZEN, head, '--', *PROTECTED_MVP2), 'MVP2_WORKLOAD_CHANGED')
        record['audited_changes'] = [{'path': path, 'new_blob': git('rev-parse', AUDITED_MAIN + ':' + path)} for path in sorted(paths)]
        for name, main_sha, altered in [
            ('different_main', '0' * 40, paths),
            ('runtime_change', AUDITED_MAIN, paths | {'scripts/network/unapproved.gd'}),
            ('missing_audited_change', AUDITED_MAIN, paths - {'AGENTS.md'}),
        ]:
            try:
                audit_main(AUDITED_MAIN, main_sha, altered)
            except RuntimeError:
                record.setdefault('negative_controls', []).append(name)
            else:
                raise RuntimeError('EPOCH_NEGATIVE_CONTROL_ACCEPTED:' + name)
        record['passed'] = True
        workload.write(out / 'epoch-audit.json', record)
        # Only the execution-context pin is rebound, after exact ancestry/scope checks.
        # BASE, every runtime/negative-control assertion, full Harness and both PC0
        # gates remain the original implementation. No fake refs or source rewriting.
        workload.MAIN = AUDITED_MAIN
        run = workload.Run(Path(args.engine), out, runtime_only=False)
        run.result['execution_context'] = record
        run.result['purpose'] = 'MVP1_MVP2_NONREGRESSION_FOR_MVP3_NOT_NEW_ACCEPTANCE'
        return run.execute()
    except Exception as exc:
        record['passed'] = False
        record['error'] = type(exc).__name__ + ':' + str(exc)
        workload.write(out / 'epoch-audit.json', record)
        print(json.dumps(record, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    sys.exit(main())
