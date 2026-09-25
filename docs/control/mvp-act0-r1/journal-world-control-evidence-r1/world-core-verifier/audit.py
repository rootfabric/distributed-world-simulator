import json, hashlib, subprocess, re
from pathlib import Path
ROOT = Path('C:/distributed-world-simulator/worktrees/mvp6-journal-main-repair')
E = Path('C:/distributed-world-simulator/artifacts/mvp6-journal-73b88181')
OUT = E / 'world-core-verifier'
HEAD = '3b82145ae946bb51aebf67f048a28420368b40be'
TREE = '6b1b8c9ead5c16d15dc8565813d3abb1bf94d880'
BASE = '6982a563dd0c88c81449566131852c601ae89868'
def git(*args): return subprocess.check_output(['git', *args], cwd=ROOT).decode().strip()
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
checked = {}
def check(p, expected):
    actual = digest(p)
    assert actual == expected, str(p)
    checked[str(p)] = actual
assert git('rev-parse', 'HEAD') == HEAD
assert git('rev-parse', 'HEAD^{tree}') == TREE
assert not git('status', '--porcelain', '--untracked-files=no')
changed = git('diff', '--name-status', BASE, HEAD).splitlines()
modified = [x for x in changed if not x.startswith('A\t')]
assert modified == ['M\tscripts/network/prediction/predicted_item_interaction_journal.gd']
assert not git('diff', BASE, HEAD, '--', 'RUN_WORLD_REGRESSION_TESTS.ps1', 'tests/harness')
f = E / 'world-core-final'
m = read(f / 'manifest.json')
assert (m['subject'], m['tree']) == (HEAD, TREE)
for entry in m['files']:
    p = f / entry['path']
    assert p.stat().st_size == entry['size']
    check(p, entry['sha256'])
r = read(E / 'world-core-review/review.json')
assert (r['verdict'], r['head'], r['tree']) == ('PASS', HEAD, TREE)
check(f / 'manifest.json', r['manifest']['sha256'])
for entry in read(E / 'world-core-review/evidence-hashes.json')['files']:
    check(Path(entry['path']), entry['sha256'])
s = read(f / 'summary.json')
assert s['passed'] and s['declared_test_count'] == s['discovered_test_count'] == 327
assert len(s['steps']) == 332
assert all(t['passed'] and t['exit_code'] == 0 for t in s['steps'])
targets = {t['target'] for t in s['steps'] if t['kind'] == 'headless_script'}
discovered = {'res://' + p.relative_to(ROOT).as_posix() for p in (ROOT/'tests').rglob('test_*.gd') if 'fixtures' not in p.relative_to(ROOT/'tests').parts[:-1]}
assert targets == discovered and len(targets) == 327
log = (f/'world.log').read_text(encoding='utf-8-sig')
assert not re.search(r'SCRIPT ERROR:|Parse Error:|Compile Error:|: FAIL\s*\(|[1-9]\d* failures', log)
assert 'elapsed=1800002 ms (30.00 min), checkpoints=29' in log
assert 'all 51 assertions passed (literal 30.00 real-time minutes, two concurrent client sessions)' in log
assert '6 PASS, 0 FAIL' in log and s['steps'][-1]['name'] == 'main_scene_cli_all'
errors = []; warnings = []; step = ''
for i, line in enumerate(log.splitlines(), 1):
    if line.startswith('Running '): step = line[8:]
    item = dict(line=i, step=step, message=line)
    if 'ERROR:' in line: errors.append(item)
    if 'WARNING:' in line: warnings.append(item)
assert len(errors) == 9 and len(warnings) == 8
assert errors == [{k:v for k,v in x.items() if k != 'classification'} for x in r['world']['errors']]
assert warnings == r['world']['warnings']
baseline_errors = []
for folder in ['world-canonical-baseline','world-canonical-baseline-mw7','world-canonical-baseline-p75']:
    p = E/folder; provenance = read(p/'provenance.json')
    assert provenance['head'] == BASE and provenance['git_status_after'] == ''
    commands = provenance.get('commands', [provenance])
    for c in commands:
        lp = p/(c['name']+'.log' if 'name' in c else 'test.log')
        check(lp,c['sha256']); assert c['exit_code'] == 0
        baseline_errors.extend(x for x in lp.read_text(encoding='utf-8-sig').splitlines() if 'ERROR:' in x)
expected_baseline = [x['message'] for x in errors if x['step'] not in ['test_partition_foundation','test_persistence_roundtrip']]
assert sorted(baseline_errors) == sorted(expected_baseline)
partition = (ROOT/'tests/unit/test_partition_foundation.gd').read_text()
persistence = (ROOT/'tests/integration/test_persistence_roundtrip.gd').read_text()
assert 'not manager.setup' in partition and '"instance_id": "invalid/path"' in partition and '"zones_per_face": 0' in partition
assert 'not foreign_repository.setup' in persistence and 'not incompatible_grid_repository.setup' in persistence
h = E/'full-harness-linux/unpacked'; hs = read(h/'summary.json')
assert (hs['head'], hs['tree'], hs['exit_code'], hs['tracked_status']) == (HEAD,TREE,1,'')
check(h/'tests.log',hs['log_sha256'])
hl = (h/'tests.log').read_text()
assert 'Ran 325 tests' in hl and 'FAILED (failures=2)' in hl
assert "AssertionError: 'RED' == 'RED'" in hl and 'test_all_p7_execution_and_acceptance_blobs_are_unchanged' in hl
wl = (f/'windows-full-harness.log').read_text(encoding='utf-8-sig')
assert 'Ran 303 tests' in wl and 'FAILED (failures=4, errors=8, skipped=3)' in wl
result = dict(role='INDEPENDENT_VERIFIER',verdict='PASS',scope='FULL_WORLD_CORE_EVIDENCE_ADDENDUM_ONLY',head=HEAD,tree=TREE,risk_class='CRITICAL',required_fixes=[],
    summary='Независимый audit подтверждает complete world/core evidence; это не error-free и не принятие MVP6.',
    checks=dict(manifest_members=6,hashed_files=len(checked),standalone_scripts=327,runner_steps=332,all_step_exit_codes_zero=True,soak_elapsed_ms=1800002,soak_checkpoints=29,soak_assertions=51,main_scene_cli_passes=6,existing_assertions_and_runner_unchanged=True,baseline_error_matches=5,intentional_negative_errors=4,raw_errors=errors,raw_warnings=warnings),
    harness=dict(linux='FAIL: 325 tests, 2 failures; directional RED and stale ACT0 fence',windows='FAIL: 303 tests, 4 failures, 8 errors, 3 skips'),
    limits=['Trusted exact-head evidence reused; literal soak not rerun by verifier.','Cleanup/resource errors remain debt; no fatal-free claim.','No MVP6 five-process acceptance, canonical clearance, canonical-main acceptance or merge authorization.','Later control candidate requires its own fresh review and verification.'],
    mvp6_verified=False,main_acceptance=False,canonical_clearance=False,source_edits=False)
(OUT/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(OUT/'evidence-hashes.json').write_text(json.dumps(dict(head=HEAD,tree=TREE,files=checked),indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(verdict='PASS',head=HEAD,tree=TREE,hashed_files=len(checked),result_sha256=digest(OUT/'result.json'))))
