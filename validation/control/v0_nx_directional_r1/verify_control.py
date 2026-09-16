#!/usr/bin/env python3
"""Unchanged auditors against a local-only projected candidate, NEVER authority."""
from __future__ import annotations
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts/v0-nx-control'
MAIN = '6982a563dd0c88c81449566131852c601ae89868'
REG = 'config/control/directional-watch-clearances.v1.json'
PROPOSAL = 'validation/control/v0_nx_directional_r1/clearance-proposal.json'
FACADE = 'scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd'


def require(value, message):
    if not value:
        raise RuntimeError(message)


def git(*args, cwd=ROOT):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def run(name, argv, cwd, expected=0):
    log = OUT / (name + '.log')
    env = dict(os.environ, GITHUB_ACTIONS='true', PYTHONPATH=str(cwd / 'scripts'), PYTHONDONTWRITEBYTECODE='1')
    with log.open('wb') as stream:
        p = subprocess.run(argv, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=300, check=False)
    require(p.returncode == expected, name + ':EXIT:' + str(p.returncode) + ':' + log.read_text()[-1800:])
    return {'name': name, 'argv': argv, 'exit_code': p.returncode, 'log': log.name}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    result = {'schema': 'dws.v0_nx_control_projection.v1', 'verdict': 'FAIL',
              'authority': 'NON_AUTHORIZING_CANDIDATE_PROJECTION', 'canonical_main_modified': False,
              'independent_verdict': False, 'commands': [], 'controls': []}
    temp = None
    try:
        require(not sys.flags.optimize, 'OPTIMIZED_PYTHON_FORBIDDEN')
        require(git('rev-parse', 'origin/main') == MAIN, 'MAIN_DRIFT')
        result.update(head=git('rev-parse', 'HEAD'), tree=git('rev-parse', 'HEAD^{tree}'), run_id=os.environ.get('GITHUB_RUN_ID'))
        sys.path.insert(0, str(ROOT / 'scripts/control'))
        import project_control_directional_watch as dw
        registry = dw.load_main_owned(dw.REGISTRY_PATH); policy = dw.load_main_owned(dw.POLICY_PATH)
        producer = dw.program_scope('V0', registry['programs']['V0'], policy)
        consumer = dw.program_scope('NX', registry['programs']['NX'], policy)
        require(producer and consumer, 'MISSING_SCOPE')
        critical = sorted(p for p in producer['changed_files'] if dw.matches_any(p, consumer['critical_watched_paths']))
        hits = sorted(p for p in producer['changed_files'] if dw.matches_any(p, consumer['critical_watched_paths'] + consumer['watched_paths']))
        require(critical == hits == [FACADE], 'HIT_SET_DRIFT')
        proposal = json.loads((ROOT / PROPOSAL).read_text())
        def resolve(record, prod=producer, cons=consumer, crit=critical, all_hits=hits, lookup=dw.git_object_sha, ancestry=dw.is_ancestor):
            return dw.resolve_critical_clearance([record], prod, cons, crit, all_hits, lookup, ancestry)
        require(resolve(proposal)[0] is None, 'UNREVIEWED_PROPOSAL_ACCEPTED')
        result['controls'].append('UNREVIEWED_PROPOSAL_REJECTED')
        candidate = copy.deepcopy(proposal)
        candidate.update(status='ACCEPTED', review_id='SIMULATED_REVIEW_NOT_AN_APPROVAL', verification_id='SIMULATED_VERIFICATION_NOT_AN_APPROVAL')
        require(resolve(candidate)[0] is not None, 'EXACT_POSITIVE_REJECTED')
        result['controls'].append('EXACT_POSITIVE_ACCEPTED_ONLY_WITH_SIMULATED_IDS')
        cases = [
            ('STATUS_NOT_ACCEPTED', {'status': 'PROPOSED'}),
            ('DECISION_NOT_ACCEPTED', {'decision': 'IGNORE_RED'}),
            ('INDEPENDENT_EVIDENCE_IDS_REQUIRED', {'review_id': ''}),
            ('INDEPENDENT_EVIDENCE_IDS_REQUIRED', {'verification_id': ''}),
            ('CONSUMER_HEAD_DRIFT', {'consumer_head_sha': '0' * 40}),
            ('CONSUMER_PASSPORT_PATH_DRIFT', {'consumer_passport_path': 'wrong/path'}),
            ('CONSUMER_PASSPORT_BLOB_DRIFT', {'consumer_passport_blob_sha': '0' * 40}),
            ('WATCHED_BLOB_FENCE_INCOMPLETE', {'watched_file_blobs': {}}),
            ('CRITICAL_FILE_SET_MISMATCH', {'critical_files': []}),
            ('WATCHED_FILE_SET_MISMATCH', {'watched_files': []}),
        ]
        for reason, updates in cases:
            bad = copy.deepcopy(candidate); bad.update(updates)
            accepted, rejected = resolve(bad)
            require(accepted is None and any(x['reason'] == reason for x in rejected), 'NEGATIVE_FAILED:' + reason)
            result['controls'].append(reason)
        accepted, rejected = resolve(candidate, all_hits=hits + [FACADE + '.unexpected'])
        require(accepted is None and rejected[0]['reason'] == 'WATCHED_FILE_SET_MISMATCH', 'EXPANDED_WATCH_ACCEPTED')
        result['controls'].append('EXPANDED_WATCH_REJECTED')
        require(resolve(candidate, ancestry=lambda a, b: False)[0] is None, 'BAD_ANCESTRY_ACCEPTED')
        result['controls'].append('BAD_ANCESTRY_REJECTED')
        for name, changed_ref in [('REVIEWED_BLOB_MISMATCH', candidate['reviewed_producer_head']), ('PRODUCER_BLOB_DRIFT', 'origin/' + producer['branch'])]:
            def lookup(ref, path, changed_ref=changed_ref):
                return '0' * 40 if ref == changed_ref and path == FACADE else dw.git_object_sha(ref, path)
            accepted, rejected = resolve(candidate, lookup=lookup)
            require(accepted is None and rejected[0]['reason'].startswith(name + ':'), name + '_NOT_REJECTED')
            result['controls'].append(name + '_REJECTED')
        require(dw.resolve_critical_clearance(dw.load_clearances()[0], producer, consumer, critical, hits, dw.git_object_sha, dw.is_ancestor)[0] is None, 'CANONICAL_BASELINE_NOT_RED')
        result['commands'].append(run('canonical-directional-before', [sys.executable, 'scripts/control/project_control_directional_watch.py'], ROOT, expected=2))
        baseline = json.loads((ROOT / 'artifacts/control/directional-watch-report.json').read_text())
        require(baseline['overall_health'] == 'RED', 'BASELINE_NOT_RED')
        (OUT / 'canonical-before.json').write_text(json.dumps(baseline, indent=2) + '\n')
        # Local clone has a separate gitdir. Never mutate refs in shared worktrees.
        temp = Path(tempfile.mkdtemp(prefix='v0-nx-shadow-', dir=os.environ.get('RUNNER_TEMP')))
        clone = temp / 'repo'
        subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout', str(ROOT), str(clone)], check=True)
        subprocess.run(['git', '-C', str(clone), 'fetch', '--quiet', 'origin', '+refs/remotes/origin/*:refs/remotes/origin/*'], check=True)
        subprocess.run(['git', '-C', str(clone), 'checkout', '--quiet', '--detach', result['head']], check=True)
        old = json.loads((clone / REG).read_text())
        require(old == json.loads(git('show', MAIN + ':' + REG)), 'EXISTING_CANONICAL_CLEARANCES_CHANGED')
        new = copy.deepcopy(old); new['clearances'].append(candidate)
        (clone / REG).write_text(json.dumps(new, ensure_ascii=False, indent=2) + '\n')
        result['commands'].append(run('unmerged-copy-cannot-self-clear', [sys.executable, 'scripts/control/project_control_directional_watch.py'], clone, expected=2))
        require(json.loads((clone / 'artifacts/control/directional-watch-report.json').read_text())['overall_health'] == 'RED', 'UNMERGED_COPY_SELF_CLEARED')
        result['controls'].append('UNMERGED_COPY_CANNOT_SELF_CLEAR')
        subprocess.run(['git', '-C', str(clone), 'add', REG], check=True)
        subprocess.run(['git', '-C', str(clone), '-c', 'user.name=Non-authorizing projection', '-c', 'user.email=projection@example.invalid', 'commit', '--quiet', '-m', 'LOCAL ONLY simulated exact clearance; not approval'], check=True)
        shadow_head = git('rev-parse', 'HEAD', cwd=clone)
        subprocess.run(['git', '-C', str(clone), 'update-ref', 'refs/remotes/origin/main', shadow_head], check=True)
        result['shadow_commit_local_only'] = shadow_head
        result['commands'].append(run('projected-standard', [sys.executable, 'scripts/control/project_control.py', '--no-fetch'], clone))
        result['commands'].append(run('projected-directional', [sys.executable, 'scripts/control/project_control_directional_watch.py'], clone))
        for source, target in [('project-control-report.json', 'projected-standard.json'), ('directional-watch-report.json', 'projected-directional.json')]:
            report = json.loads((clone / 'artifacts/control' / source).read_text())
            require(report['overall_health'] != 'RED', target + ':RED')
            (OUT / target).write_text(json.dumps({'authority': 'NON_AUTHORIZING_CANDIDATE_PROJECTION', 'report': report}, indent=2) + '\n')
        row = run('projected-full-harness', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests/harness', '-p', 'test_*.py'], clone)
        text = (OUT / row['log']).read_text()
        require('OK' in text and 'skipped=' not in text and 'FAILED' not in text, 'HARNESS_NOT_COMPLETE')
        result['commands'].append(row)
        require(git('rev-parse', 'origin/main') == MAIN, 'SHADOW_REF_LEAKED')
        result['controls'].append('REAL_MAIN_REF_UNCHANGED')
        result['verdict'] = 'PASS'
        print('V0_NX_CONTROL_PROJECTION_PASS NOT_CANONICAL_ACCEPTANCE controls=' + str(len(result['controls'])))
        return 0
    except Exception as exc:
        result['error'] = str(exc); print('V0_NX_CONTROL_PROJECTION_FAIL ' + str(exc)); return 1
    finally:
        if temp is not None:
            shutil.rmtree(temp)
        (OUT / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
        files = {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in OUT.iterdir() if p.is_file() and p.name != 'manifest.json'}
        (OUT / 'manifest.json').write_text(json.dumps({'head': result.get('head'), 'tree': result.get('tree'), 'run_id': os.environ.get('GITHUB_RUN_ID'), 'files': files}, indent=2) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
