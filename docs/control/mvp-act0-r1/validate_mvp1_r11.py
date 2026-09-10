"""R11 exact evidence producer. No Git writes, role verdicts or acceptance."""
from __future__ import annotations
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = 'b645a738a6a143bee8f7f4a291a3e754cd399996'
BASE_TREE = 'b7cd01061dab492eaa1de3de6680465ac9e7aaf6'
EPOCH = 'E2026-09-09-V0-MVP-R1'
WO = 'V0-MVP-R1-WO-001'
EX = f'config/control/harness/executions/{EPOCH}'
ROLE = f'{EX}/evidence/MVP1-IMPLEMENTER-PROVENANCE-R11.v1.json'
WINDOWS = f'{EX}/evidence/MVP1-WINDOWS-REPORTED-OBSERVATION-R1.v1.json'
EVENT4 = f'{EX}/events/{WO}/0004-mvp1-shared-graphical-scene-implementation.v1.json'
EVENT5 = f'{EX}/events/{WO}/0005-mvp1-implementer-provenance-r11.v1.json'
REPAIR = 'docs/control/mvp-act0-r1/work-order-implementer-provenance-r11.v1.json'
ENGINE_SHA = 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7'
OUT = ROOT / 'artifacts/mvp1-r11-exact'
ENV = os.environ.copy()
ENV.update(PYTHONUTF8='1', BREAKPOINT_RUNTIME_DISABLED='1',
           PLANET_SIMULATOR_INVENTORY_PROFILE='planet_default',
           PYTHONPATH=str(ROOT / 'scripts') + os.pathsep + str(ROOT))


def require(value: bool, message: str) -> None:
    if not value:
        raise RuntimeError(message)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8').strip()


def read(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def provenance_errors(record: dict, event: dict) -> list[str]:
    errors = []
    for field, expected in [('role', 'IMPLEMENTER'), ('work_order_id', WO),
                            ('project_epoch', EPOCH), ('subject_head', BASE),
                            ('subject_tree', BASE_TREE), ('independent_context', False),
                            ('mvp1_predicate_marked_verified', False),
                            ('independent_verdict_issued', False)]:
        actual = record.get(field)
        if type(actual) is not type(expected) or actual != expected:
            errors.append('ROLE_' + field)
    for field, expected in [('actor', 'IMPLEMENTER'), ('work_order_id', WO),
                            ('project_epoch', EPOCH), ('sequence', 5),
                            ('work_state', 'IN_PROGRESS'),
                            ('event_type', 'IMPLEMENTATION_COMMITTED'),
                            ('head_sha', BASE)]:
        actual = event.get(field)
        if type(actual) is not type(expected) or actual != expected:
            errors.append('EVENT_' + field)
    if ROLE not in event.get('evidence_paths', []):
        errors.append('ROLE_REFERENCE_MISSING')
    return errors


def values_for(obj: object, key: str) -> list:
    result = []
    if isinstance(obj, dict):
        if key in obj:
            result.append(obj[key])
        for value in obj.values():
            result.extend(values_for(value, key))
    elif isinstance(obj, list):
        for value in obj:
            result.extend(values_for(value, key))
    return result


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=False)
    result = {'schema': 'distributed_world_simulator.mvp1_r11_exact_result.v1',
              'passed': False, 'errors': [], 'commands': [],
              'independent_verdict': False, 'mvp_accepted': False}
    started = datetime.now(timezone.utc).isoformat()

    def run(name: str, args: list[str], expected: int = 0, timeout: int = 900,
            godot_log: bool = False) -> str:
        begin = time.monotonic()
        log = OUT / (name + '.log')
        with log.open('w', encoding='utf-8') as stream:
            proc = subprocess.run(args, cwd=ROOT, env=ENV, stdout=stream,
                                  stderr=subprocess.STDOUT, timeout=timeout)
        text = log.read_text(encoding='utf-8', errors='replace')
        result['commands'].append({'name': name, 'argv': args,
                                   'exit_code': proc.returncode,
                                   'expected_exit': expected,
                                   'seconds': round(time.monotonic() - begin, 3),
                                   'log': log.name, 'sha256': digest(log)})
        require(proc.returncode == expected, f'{name}:EXIT:{proc.returncode}')
        if godot_log:
            require(not re.search(r'(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error', text),
                    name + ':GODOT_ERROR')
        return text

    try:
        head = git('rev-parse', 'HEAD')
        tree = git('rev-parse', 'HEAD^{tree}')
        result.update(subject_head=head, subject_tree=tree,
                      canonical_main=git('rev-parse', 'origin/main'),
                      source_runtime_head=BASE, source_runtime_tree=BASE_TREE,
                      tracked_before=git('status', '--porcelain', '--untracked-files=no'))
        require(not result['tracked_before'], 'TRACKED_CHECKOUT_DIRTY_BEFORE')
        require(head == os.environ.get('EXPECTED_HEAD', head), 'EXACT_HEAD_MISMATCH')
        require(git('rev-parse', BASE + '^{tree}') == BASE_TREE, 'BASE_TREE_MISMATCH')
        git('merge-base', '--is-ancestor', BASE, head)
        changed = git('diff', '--name-only', BASE, head).splitlines()
        allowed = read(REPAIR)['allowed_paths']
        require(bool(changed) and set(changed) <= set(allowed), 'R11_SCOPE_DRIFT')
        run('diff-check', ['git', 'diff', '--check', BASE, head])
        record, event = read(ROLE), read(EVENT5)
        require(not provenance_errors(record, event), 'IMPLEMENTER_PROVENANCE_INVALID')
        require(git('rev-parse', 'HEAD:' + EVENT4) ==
                '1005fea2edbb49775690e2554e3e8372e9f2cec8', 'EVENT4_CHANGED')
        original_events = git('ls-tree', '-r', BASE, '--', f'{EX}/events')
        current_events = git('ls-tree', '-r', head, '--', f'{EX}/events')
        require(set(original_events.splitlines()) <= set(current_events.splitlines()),
                'HISTORICAL_EVENT_CHANGED')
        ledger = [json.loads(p.read_text(encoding='utf-8'))
                  for p in sorted((ROOT / EX / 'events' / WO).glob('*.json'))]
        require([e['sequence'] for e in ledger] == list(range(1, 6)), 'SEQUENCE_NOT_1_TO_5')
        snapshot = read(f'{EX}/work-orders/{WO}.v1.json')
        require(snapshot['state'] == ledger[-1]['work_state'] == 'IN_PROGRESS', 'SNAPSHOT_MISMATCH')
        fingerprints = {}
        for path in ['scripts', 'scenes', 'tests', 'addons', 'project.godot', 'main.tscn']:
            before, after = git('rev-parse', f'{BASE}:{path}'), git('rev-parse', f'{head}:{path}')
            require(before == after, 'RUNTIME_CONTENT_CHANGED:' + path)
            fingerprints[path] = {'source_blob_or_tree': before, 'candidate_blob_or_tree': after}
        require(git('rev-parse', 'HEAD:' + WINDOWS) ==
                '2a5525fa44c66dd505f7fb8e1bf8abb1d6f41ef4', 'WINDOWS_ATTESTATION_CHANGED')
        for src in [ROLE, EVENT4, EVENT5, REPAIR, WINDOWS]:
            shutil.copyfile(ROOT / src, OUT / Path(src).name)
        result['runtime_content_identity'] = fingerprints
        result['windows_evidence_boundary'] = {
            'classification': 'ATTRIBUTED_USER_REPORT_CONTENT_BOUND_TO_UNCHANGED_RUNTIME',
            'raw_png_and_log_bytes_rehashed': False,
            'new_windows_execution_claimed': False}
        controls = []
        for kind, field, value in [('role', 'role', 'INTEGRATOR'),
                                   ('role', 'independent_context', True),
                                   ('role', 'work_order_id', 'FOREIGN'),
                                   ('event', 'actor', 'INTEGRATOR'),
                                   ('event', 'head_sha', '0' * 40),
                                   ('event', 'work_state', 'VERIFIED')]:
            r, e = copy.deepcopy(record), copy.deepcopy(event)
            (r if kind == 'role' else e)[field] = value
            errors = provenance_errors(r, e)
            require(bool(errors), 'NEGATIVE_CONTROL_FALSE_PASS:' + field)
            controls.append({'kind': kind, 'field': field, 'rejected_with': errors})
        write(OUT / 'negative-controls.json', controls)
        engine = Path(os.environ['GODOT_BIN']).resolve()
        require(digest(engine) == ENGINE_SHA, 'ENGINE_HASH_MISMATCH')
        result['godot_binary_sha256'] = digest(engine)
        version = run('godot-version', [str(engine), '--version'], timeout=30)
        require(version.strip() == '4.7.1.stable.double.custom_build.a13da4feb', 'ENGINE_VERSION_MISMATCH')
        harness = run('full-harness', [sys.executable, '-m', 'unittest', 'discover',
                       '-s', 'tests/harness', '-p', 'test_*.py', '-v'])
        counts = re.findall(r'Ran (\d+) tests?', harness)
        require(bool(counts) and int(counts[-1]) > 0, 'HARNESS_SUMMARY_MISSING')
        result['harness_tests'] = int(counts[-1])
        run('pc0-standard', [sys.executable, 'scripts/control/project_control.py', '--no-fetch'])
        run('pc0-directional', [sys.executable, 'scripts/control/project_control_directional_watch.py'])
        for name in ['project-control-report.json', 'directional-watch-report.json']:
            path = ROOT / 'artifacts/control' / name
            data = json.loads(path.read_text(encoding='utf-8'))
            require(data['overall_health'] != 'RED', 'PC0_RED:' + name)
            if name == 'project-control-report.json':
                require(data.get('cross_branch_overlaps') == [], 'PC0_OVERLAP')
            shutil.copyfile(path, OUT / name)
        run('godot-import', [str(engine), '--headless', '--editor', '--path', str(ROOT), '--import'], godot_log=True)
        smoke = run('mvp1-focused', [str(engine), '--headless', '--path', str(ROOT),
                    '--script', 'res://tests/runtime/test_v0_mvp_shared_graphical_scene.gd'], godot_log=True)
        require('V0 MVP shared graphical scene: PASS (16 assertions)' in smoke, 'MVP1_SMOKE_MARKER_MISSING')
        run('mvp1-headless-lifecycle', [str(engine), '--headless', '--path', str(ROOT),
                'res://scenes/labs/mvp/v0_mvp_shared_graphical_scene.tscn', '--quit-after', '60'],
                timeout=120, godot_log=True)
        drive = json.loads(run('drive', [sys.executable, '-m', 'harness.cli', 'drive']))
        blocked = values_for(drive, 'continuation_blocked')
        require(bool(blocked) and all(v is False for v in blocked), 'DRIVE_CONTINUATION_BLOCKED')
        completed = values_for(drive, 'completed_predicates')
        require(bool(completed) and all(v == [] for v in completed), 'PREMATURE_PRODUCT_PREDICATE')
        run('close-mission', [sys.executable, '-m', 'harness.cli', 'close-mission'], expected=8)
        result['tracked_after'] = git('status', '--porcelain', '--untracked-files=no')
        require(not result['tracked_after'], 'TRACKED_CHECKOUT_DIRTY_AFTER')
        require(git('rev-parse', 'HEAD') == head and git('rev-parse', 'HEAD^{tree}') == tree,
                'SUBJECT_CHANGED_DURING_VALIDATION')
        result['passed'] = True
    except Exception as exc:
        result['errors'].append(type(exc).__name__ + ':' + str(exc))
    finally:
        result['started_at_utc'] = started
        result['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        write(OUT / 'result.json', result)
        files = [{'path': p.relative_to(OUT).as_posix(), 'bytes': p.stat().st_size,
                  'sha256': digest(p)} for p in sorted(OUT.rglob('*')) if p.is_file()]
        write(OUT / 'manifest.json', {
            'schema': 'distributed_world_simulator.mvp1_exact_manifest.v1',
            'head_sha': result.get('subject_head'), 'tree_sha': result.get('subject_tree'),
            'runner': {k: os.environ.get(k, '') for k in
                       ['GITHUB_REPOSITORY', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT',
                        'GITHUB_JOB', 'GITHUB_WORKFLOW', 'RUNNER_NAME', 'RUNNER_OS']},
            'files': files})
        print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
