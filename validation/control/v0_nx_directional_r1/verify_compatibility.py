#!/usr/bin/env python3
"""Bounded dependency proof; preserves the pre-fix negative and exact input hashes."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from fixture_types import adapt

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts/v0-nx-compat'
MAIN = '6982a563dd0c88c81449566131852c601ae89868'
V0 = '9a4d4257f177af16c0a4274be357717c45c169fe'
NX = '1a56fe0e845c941f14ce7b9296ee939e9d0ca8bc'
V0_BRANCH = 'feature/v0-mvp-playable-seamless-planet-r1'
NX_BRANCH = 'feature/h0-2-nx-c1-owner-authority-r3'
FACADE = 'scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd'
BLOB = '44841fb3719b1cf36fd5afdfc0f8a0e4d0eacb30'
JOURNAL = 'scripts/network/prediction/predicted_item_interaction_journal.gd'
JOURNAL_FIXED = 'cb9200f8a92b0f521ffaa4262ed42bce38c1ac68'
FOCUSED = 'validation/control/v0_nx_directional_r1/test_same_revision_projection.gd'
ENGINE_SHA = 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7'
NX_RUNTIME = [
    'scripts/network/authority/movement_authority_profile.gd',
    'scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd',
    'scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd',
    'scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd',
]
NX_TESTS = [
    'tests/network/test_nx_owner_movement_authority.gd',
    'tests/network/test_nx_render_physics_separation.gd',
    'tests/network/test_nx_owner_item_projection_rollback.gd',
    'tests/network/test_nx_client_tick_robustness.gd',
    'tests/network/test_nx6_predicted_item_interactions.gd',
]
V0_TESTS = [
    'tests/runtime/test_v0_mvp_6_native_item_handoff.gd',
    'tests/runtime/test_v0_mvp_6_native_replay_security.gd',
    'tests/runtime/test_v0_mvp3_live_owner_handoff.gd',
    'tests/runtime/test_v0_mvp_5_exactly_once_material.gd',
]
BAD = re.compile(r'SCRIPT ERROR:|Parse Error:|Failed to load script|(?m:^ERROR:)|\bFAIL(?:ED)?\b')


def require(value, message):
    if not value:
        raise RuntimeError(message)


def git(*args, cwd=ROOT):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def raw(ref, path):
    return subprocess.check_output(['git', 'show', ref + ':' + path], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(name, argv, cwd, test=False, negative=False):
    log = OUT / (name + '.log')
    with log.open('wb') as stream:
        p = subprocess.run(argv, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, timeout=600, check=False)
    text = log.read_text(encoding='utf-8-sig', errors='strict')
    if negative:
        require(p.returncode == 1 and re.search(r'V0_NX_SAME_REVISION_PROJECTION FAIL assertions=\d+ failed=[1-9]\d*', text), name + ':EXPECTED_BASELINE_FAILURE_NOT_REPRODUCED')
        require('SCRIPT ERROR:' not in text and 'Parse Error:' not in text and 'Failed to load script' not in text, name + ':INVALID_NEGATIVE_COMPILE_FAILURE')
        for kind in ('item.pickup', 'item.drop', 'item.place', 'item.transfer'):
            require('DUPLICATE_AUTHORITY_ROLLBACK:' + kind in text, name + ':MISSING_SPECIFIC_FALSIFIER:' + kind)
    else:
        require(p.returncode == 0, name + ':EXIT:' + str(p.returncode) + ':' + text[-2000:])
        require(BAD.search(text) is None, name + ':ERROR_OUTPUT:' + text[:2000])
    markers = [line for line in text.splitlines() if re.search(r'\bPASS\b', line) or 'V0_NX_SAME_REVISION_PROJECTION' in line]
    if test:
        require(markers, name + ':MISSING_PASS_MARKER')
    row = {'name': name, 'argv': argv, 'exit_code': p.returncode, 'log': log.name,
           'sha256': sha(log.read_bytes()), 'markers': markers, 'expected_negative': negative}
    print(('EXPECTED_BASELINE_FAIL ' if negative else 'PASS ') + name + ' ' + ' | '.join(markers), flush=True)
    return row


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    result = {'schema': 'dws.v0_nx_dependency_compatibility.v1', 'verdict': 'FAIL',
              'independent_verdict': False, 'clearance_granted': False,
              'scope': 'BOUNDED_DEPENDENCY_REVALIDATION_NOT_NX_OR_MVP_ACCEPTANCE',
              'raw_nx_current_main_compilation': 'KNOWN_FAIL_BASELINE_R2_R3',
              'fixture_scope': 'TYPE_ONLY_ADAPTED_NX_COMPOSITION_EXPRESSIONS_AND_ASSERTIONS_UNCHANGED', 'tests': []}
    roots = {}
    try:
        require(not sys.flags.optimize, 'OPTIMIZED_PYTHON_FORBIDDEN')
        result.update(main=MAIN, producer=V0, consumer=NX, facade_blob=BLOB,
                      verifier_head=git('rev-parse', 'HEAD'), verifier_tree=git('rev-parse', 'HEAD^{tree}'),
                      run_id=os.environ.get('GITHUB_RUN_ID'), attempt=os.environ.get('GITHUB_RUN_ATTEMPT'))
        require(git('rev-parse', 'origin/main') == MAIN, 'MAIN_EPOCH_DRIFT')
        observed_v0 = git('rev-parse', 'origin/' + V0_BRANCH)
        result['producer_observed'] = observed_v0
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', V0, observed_v0], cwd=ROOT, check=False).returncode == 0, 'V0_ANCESTRY_DRIFT')
        require(git('rev-parse', observed_v0 + ':' + FACADE) == BLOB, 'LIVE_FACADE_BLOB_DRIFT')
        require(git('rev-parse', 'origin/' + NX_BRANCH) == NX, 'NX_HEAD_DRIFT')
        require(git('rev-parse', V0 + ':' + FACADE) == BLOB, 'FACADE_BLOB_DRIFT')
        require(git('rev-parse', 'HEAD:' + JOURNAL) == JOURNAL_FIXED, 'JOURNAL_REPAIR_CHANGED')
        require(git('rev-parse', MAIN + ':' + JOURNAL) == 'ed23f0d2b7a9e6cfb3f13b78de70c7f552035b69', 'BASELINE_JOURNAL_CHANGED')
        result['journal_repair'] = {'original_blob': git('rev-parse', MAIN + ':' + JOURNAL), 'fixed_blob': JOURNAL_FIXED, 'sha256': sha((ROOT / JOURNAL).read_bytes()), 'applied_identically_to_pair': True}
        godot = Path(os.environ['GODOT_BIN']).resolve()
        require(sha(godot.read_bytes()) == ENGINE_SHA, 'GODOT_SHA_MISMATCH')
        result.update(engine_sha256=ENGINE_SHA, engine_version=subprocess.check_output([str(godot), '--version'], text=True).strip())
        passport_path = 'config/control/branches/feature__h0-2-nx-c1-owner-authority-r3.v1.json'
        require(git('rev-parse', NX + ':' + passport_path) == 'c3af1974228c9ee5c34bf4d54c72896c99fc4d1a', 'NX_PASSPORT_DRIFT')
        sys.path.insert(0, str(ROOT / 'scripts/control'))
        import project_control_directional_watch as dw
        registry = json.loads(raw(MAIN, dw.REGISTRY_PATH)); policy = json.loads(raw(MAIN, dw.POLICY_PATH))
        producer = dw.program_scope('V0', registry['programs']['V0'], policy)
        consumer = dw.program_scope('NX', registry['programs']['NX'], policy)
        require(producer and consumer, 'MISSING_PROGRAM_SCOPE')
        critical = sorted(p for p in producer['changed_files'] if dw.matches_any(p, consumer['critical_watched_paths']))
        hits = sorted(p for p in producer['changed_files'] if dw.matches_any(p, consumer['critical_watched_paths'] + consumer['watched_paths']))
        require(critical == hits == [FACADE], 'WATCHED_HIT_SET_DRIFT')
        accepted, rejected = dw.resolve_critical_clearance(dw.load_clearances()[0], producer, consumer, critical, hits, dw.git_object_sha, dw.is_ancestor)
        require(accepted is None, 'EXPECTED_BASELINE_UNRESOLVED')
        result['watch'] = {'critical': critical, 'all_hits': hits, 'baseline_clearance': 'UNRESOLVED', 'rejections': rejected}
        (OUT / 'facade.diff').write_text(git('diff', MAIN, V0, '--', FACADE) + '\n')
        (OUT / 'journal.diff').write_text(git('diff', MAIN, 'HEAD', '--', JOURNAL) + '\n')
        overlay = {p: adapt(p, raw(NX, p)) for p in NX_RUNTIME + NX_TESTS}
        result['nx_overlay'] = {p: {'git_blob': git('rev-parse', NX + ':' + p), 'original_sha256': sha(raw(NX, p)), 'executed_sha256': sha(data), 'typing_only_adapter': data != raw(NX, p)} for p, data in overlay.items()}
        temp = Path(tempfile.mkdtemp(prefix='v0-nx-compat-', dir=os.environ.get('RUNNER_TEMP')))
        for label, source in [('baseline', MAIN), ('treatment', MAIN), ('producer', V0)]:
            target = temp / label
            subprocess.run(['git', 'worktree', 'add', '--detach', str(target), source], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
            roots[label] = target
            if label != 'producer':
                for path, data in {**overlay, FOCUSED: (ROOT / FOCUSED).read_bytes()}.items():
                    file = target / path; file.parent.mkdir(parents=True, exist_ok=True); file.write_bytes(data)
                if label == 'treatment':
                    (target / FACADE).write_bytes(raw(V0, FACADE))
                    (target / JOURNAL).write_bytes((ROOT / JOURNAL).read_bytes())
            result['tests'].append(run(label + '-cold-import', [str(godot), '--headless', '--audio-driver', 'Dummy', '--editor', '--path', str(target), '--import', '--quit'], target))
            script = lambda path: [str(godot), '--headless', '--audio-driver', 'Dummy', '--path', str(target), '--script', 'res://' + path]
            if label == 'baseline':
                result['tests'].append(run('pre-fix-falsifier', script(FOCUSED), target, negative=True))
                (target / JOURNAL).write_bytes((ROOT / JOURNAL).read_bytes())
            if label != 'producer':
                result['tests'].append(run(label + '-projection-repair', script(FOCUSED), target, test=True))
            for index, path in enumerate(V0_TESTS if label == 'producer' else NX_TESTS):
                row = run(label + '-' + str(index + 1), script(path), target, test=True)
                row['test_path'] = path; result['tests'].append(row)
            allowed = set(overlay) | {FACADE, JOURNAL, FOCUSED} if label != 'producer' else set()
            changed = set(git('diff', '--name-only', source, cwd=target).splitlines())
            require(changed <= allowed, label + ':UNDECLARED_TRACKED_MUTATION:' + repr(sorted(changed - allowed)))
            if label != 'producer':
                for path, data in {**overlay, JOURNAL: (ROOT / JOURNAL).read_bytes(), FOCUSED: (ROOT / FOCUSED).read_bytes()}.items():
                    require((target / path).read_bytes() == data, label + ':OVERLAY_MUTATED:' + path)
            require((target / FACADE).read_bytes() == raw(V0 if label in ('treatment', 'producer') else MAIN, FACADE), label + ':FACADE_MUTATED')
        files = set(git('ls-tree', '-r', '--name-only', MAIN).splitlines()) | set(overlay) | {FOCUSED}
        deltas = [p for p in sorted(files) if (roots['baseline'] / p).read_bytes() != (roots['treatment'] / p).read_bytes()]
        require(deltas == [FACADE], 'PAIR_NOT_SINGLE_DEPENDENCY:' + repr(deltas))
        result['paired_source_differences'] = deltas
        require(len(result['tests']) == 20, 'MISSING_RUNTIME_STAGES')
        for suffix in ['projection-repair'] + [str(i) for i in range(1, 6)]:
            left = next(row for row in result['tests'] if row['name'] == 'baseline-' + suffix)
            right = next(row for row in result['tests'] if row['name'] == 'treatment-' + suffix)
            require(left['markers'] == right['markers'], 'PAIRED_ASSERTION_SUMMARY_MISMATCH:' + suffix)
        result['verdict'] = 'PASS'
        print('V0_NX_COMPATIBILITY_PASS runtime_suites=14 repair_positives=2 specific_negative=1 cold_imports=3', flush=True)
        return 0
    except Exception as exc:
        result['error'] = str(exc); print('V0_NX_COMPATIBILITY_FAIL ' + str(exc), flush=True); return 1
    finally:
        (OUT / 'summary.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        for target in roots.values():
            subprocess.run(['git', 'worktree', 'remove', '--force', str(target)], cwd=ROOT, check=False, stdout=subprocess.DEVNULL)
        files = {p.name: {'bytes': p.stat().st_size, 'sha256': sha(p.read_bytes())} for p in OUT.iterdir() if p.is_file() and p.name != 'manifest.json'}
        (OUT / 'manifest.json').write_text(json.dumps({'head': result.get('verifier_head'), 'tree': result.get('verifier_tree'), 'run_id': os.environ.get('GITHUB_RUN_ID'), 'files': files}, indent=2) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
