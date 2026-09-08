#!/usr/bin/env python3
"""Recompute a P7 evidence archive; output is audit data, not acceptance."""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
from zipfile import ZipFile

HEAD = '62ae64d3651af81d726134b1f2c5b8661000998c'
TREE = 'b3653e480d42b71a2a2d61fac44086b05a9d73d0'
RUN = '34189730552'
BASE = '438b21d0f5f348d838c2fae0bfae3547ba56a875'
ENGINE = 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7'

def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def audit(path: Path, expected_sha: str) -> dict:
    archive_sha = sha(path.read_bytes())
    require(archive_sha == expected_sha, 'ZIP_DIGEST_MISMATCH')
    with ZipFile(path) as z:
        names = z.namelist()
        require(len(names) == len(set(names)), 'DUPLICATE_ZIP_ENTRIES')
        require(all(n and not PurePosixPath(n).is_absolute() and '..' not in PurePosixPath(n).parts
                    and '\\' not in n for n in names), 'UNSAFE_ZIP_PATH')
        manifests = [n for n in names if n.endswith('/manifest.json')]
        require(len(manifests) == 1, 'MANIFEST_COUNT')
        prefix = manifests[0].removesuffix('manifest.json')
        def read(name): return z.read(prefix + name)
        def obj(name): return json.loads(read(name))
        def text(name): return read(name).decode('utf-8-sig')
        def report(name, test):
            values = [json.loads(line) for line in text(name).splitlines() if line.startswith('{')]
            matches = [v for v in values if isinstance(v, dict) and v.get('test') == test]
            require(len(matches) == 1, 'REPORT_COUNT:' + name)
            return matches[0]
        m = obj('manifest.json')
        identity = {'head': HEAD, 'tree': TREE, 'tracked_status': ''}
        require(m['subject'] == identity and str(m['run_id']) == RUN and str(m['run_attempt']) == '1', 'SUBJECT_OR_RUN_MISMATCH')
        require(obj('preflight.json') == identity == obj('postflight.json'), 'CHECKOUT_DRIFT')
        entries = m['files']
        require(isinstance(entries, list) and entries, 'EMPTY_MANIFEST')
        indexed = [entry['path'] for entry in entries]
        require(all(isinstance(n, str) and n and not PurePosixPath(n).is_absolute()
                    and '..' not in PurePosixPath(n).parts and '\\' not in n for n in indexed), 'UNSAFE_MANIFEST_PATH')
        require(len(indexed) == len(set(indexed)), 'DUPLICATE_MANIFEST_ENTRIES')
        for entry in entries:
            data = read(entry['path'])
            require(len(data) == entry['bytes'] and sha(data) == entry['sha256'], 'MEMBER_MISMATCH:' + entry['path'])
        actual = {n[len(prefix):] for n in names if n.startswith(prefix) and not n.endswith('/')}
        require(actual == set(indexed) | {'manifest.json'}
                and all(n.startswith(prefix) for n in names), 'UNINDEXED_OR_MISSING_MEMBERS')
        r = obj('result.json')
        require(r['subject'] == identity and r['checkout_unchanged'] is True and r['passed'] is True, 'RESULT_NOT_PASS')
        require(r['canonical_acceptance'] is False, 'MACHINE_REPORT_CLAIMS_ACCEPTANCE')
        commands = []
        for name in indexed:
            if name.endswith('.result.json'):
                v = obj(name)
                require(v['exit_code'] == v['expected_exit'] and not v['fatal_matches'], 'COMMAND_FAILED:' + name)
                log_name = name.removesuffix('.result.json') + '.log'
                require(sha(read(log_name)) == v['log_sha256'], 'COMMAND_LOG_MISMATCH:' + name)
                declared = obj(name.removesuffix('.result.json') + '.command.json')
                require(all(declared.get(k) == v.get(k) for k in ('command', 'cwd', 'expected_exit', 'timeout_seconds')),
                        'COMMAND_DECLARATION_MISMATCH:' + name)
                commands.append({'name': name.removesuffix('.result.json'), 'exit': v['exit_code'], 'expected': v['expected_exit']})
        command_names = {v['name'] for v in commands}
        require(commands and len(command_names) == len(commands), 'COMMAND_COVERAGE')
        detail = {}
        if r['kind'] == 'control':
            h = text('harness.log')
            count = re.findall(r'^Ran (\d+) tests in ', h, re.M)
            require(len(count) == 1 and re.search(r'^OK$', h, re.M) and 'FAILED (' not in h, 'HARNESS_SUMMARY')
            require(int(count[0]) == 274, 'HARNESS_TEST_COUNT')
            require(command_names == {'harness', 'pc0', 'controller-Overview', 'controller-CheckConsistency',
                                      'controller-Drive', 'controller-CloseMission'}, 'CONTROL_COMMAND_COVERAGE')
            detail['harness_tests'] = int(count[0])
            for name in ('project-control-report.json', 'directional-watch-report.json'):
                v = obj('raw/control/' + name)
                require(v['overall_health'] in ('GREEN', 'YELLOW'), 'PC0_RED')
                detail[name] = {'overall_health': v['overall_health']}
                if name == 'project-control-report.json':
                    require(v['cross_branch_overlaps'] == [], 'CROSS_BRANCH_OVERLAP')
                    require(v['main_head'] == BASE, 'PC0_AUTHORITY_MISMATCH')
                    detail[name]['main_head'] = v['main_head']
                else:
                    blocking = [f for f in v['findings'] if f.get('level') == 'RED' and f.get('global_blocking', True) is not False]
                    require(not blocking, 'DIRECTIONAL_BLOCKING')
                    detail[name]['advisory_red_count'] = sum(f.get('level') == 'RED' for f in v['findings'])
        elif r['kind'] == 'p7':
            require(m['godot_sha256'] == ENGINE, 'ENGINE_MISMATCH')
            require(command_names == {'version', 'import', 'p7-train'}, 'P7_COMMAND_COVERAGE')
            s = obj('p7-stage-summary.json')
            require(s['passed'] is True and len(s['stages']) == 29 and s['assertions'] == 2032, 'P7_COVERAGE')
            require(len({v['log'] for v in s['stages']}) == 29, 'DUPLICATE_P7_LEAF')
            count = 0
            for stage in s['stages']:
                # Legacy summary uses runtime-relative paths within original artifacts.
                name = 'raw/' + stage['log']
                data = read(name)
                require(sha(data) == stage['sha256'] and stage['failures'] == 0, 'P7_LEAF_HASH')
                t = data.decode('utf-8-sig')
                n = stage['assertions']
                require(re.search(rf'(?m)^.*: (?:PASS \({n} assertions(?:, 0 failures| / [0-9.]+ s)?\)|{n} assertions, 0 failures)$', t), 'P7_LEAF_TERMINAL:' + name)
                require(not re.search(r'SCRIPT ERROR:|Parse Error:|Compile Error:|\[FAIL\]|: FAIL\b|\b[1-9][0-9]* failures\b', t), 'P7_LEAF_FAILED')
                count += n
            require(count == 2032, 'P7_ASSERTION_SUM')
            detail = {'leaves': 29, 'assertions': count, 'failures': 0}
        elif r['kind'] == 'world':
            require(m['godot_sha256'] == ENGINE, 'ENGINE_MISMATCH')
            s = obj('raw/test-results/world-regression-summary.json')
            coverage = obj('world-coverage.json')
            require(s['passed'] is True and s['declared_test_count'] == s['discovered_test_count'] == 326, 'WORLD_SCRIPT_COUNT')
            require(len(s['steps']) == 331 and all(v['passed'] is True and v['exit_code'] == 0 for v in s['steps']), 'WORLD_STAGE_FAILURE')
            require(sha(read('raw/test-results/world-regression-summary.json')) == coverage['summary_sha256'], 'WORLD_SUMMARY_HASH')
            scripts = [v['target'] for v in s['steps'] if v['kind'] == 'headless_script']
            require(len(scripts) == 328 and len(set(scripts)) == 326, 'WORLD_DISTINCT_COVERAGE')
            require('res://tests/matter/transactions/test_matter_repository_lock_reclaim.gd' in scripts, 'NATIVE_MISSING_FROM_WORLD')
            names = [v['name'] for v in s['steps']]
            require(len(names) == len(set(names)) and names[:2] == ['test_manifest_coverage', 'editor_import_parse']
                    and names[-1] == 'main_scene_cli_all', 'AGGREGATE_OR_UNIQUE_NAMES_MISSING')
            p74 = 'res://tests/runtime/test_v0_p7_4_persistence_restart_composition.gd'
            require(Counter(scripts) == Counter({p: 3 if p == p74 else 1 for p in set(scripts)}), 'WORLD_DUPLICATE_SCRIPT')
            phases = ['test_v0_p7_4_persistence_restart_composition[' + p + ']'
                      for p in ('seed', 'recover-deliver', 'recover-replay')]
            indexes = [names.index(p) for p in phases]
            require(indexes == list(range(indexes[0], indexes[0] + 3)), 'P74_PHASE_ORDER')
            required = {'version', 'import', 'baseline-import', 'baseline-aba', 'baseline-control-fixture',
                        'review-baseline-import', 'review-baseline-empty-writer', 'fixture-baseline-import',
                        'fixture-baseline-mw9', 'native-locks', 'test_mw9_durable_handoff_recovery',
                        'test_mw9_durable_handoff_processes', 'test_mw9_lock_release_retry',
                        'mw10-processes', 'full-world-core'}
            required |= {f'{family}-{i}' for family, n in [('eg1', 5), ('eg4', 3)] for i in range(1, n+1)}
            require(required == command_names, 'WORLD_COMMAND_COVERAGE')
            for log, count, codes in (
                ('baseline-aba.log', 22, ['c-must-not-acquire-before-b-release', 'b-marker-must-survive', 'b-must-release-own-lock']),
                ('review-baseline-empty-writer.log', 14, ['fresh-empty-writer-lock-reclaimed', 'fresh-empty-writer-directory-removed'])):
                v = report(log, 'matter_repository_lock_reclaim')
                expected = [repo + ':' + code for repo in ('mw10', 'mw9') for code in codes]
                require(v['verdict'] == 'FAIL' and v['assertions'] == count and v['failures'] == expected, 'NEGATIVE_CONTROL_MISMATCH:' + log)
            t = text('fixture-baseline-mw9.log')
            require(re.findall(r'^ERROR: (.*)$', t, re.M) == ['Fresh ownerless lock was reclaimed without grace',
                    'Fresh ownerless lock disappeared during grace'] and
                    t.count('MW9 durable handoff recovery: FAIL (203 assertions, 2 failures)') == 1, 'MW9_NEGATIVE_CONTROL')
            t = text('baseline-control-fixture.log')
            require('8 != 0' in t and 'FAILED (failures=1)' in t, 'CONTROL_NEGATIVE_CONTROL')
            for name, head in [('baseline-identity.json', BASE),
                               ('review-baseline-identity.json', '912742d1bd7368138c5c057664dfe871b6cf8dbd'),
                               ('fixture-baseline-identity.json', 'dded2e488b161276d7ba679af078c288bd53cf55')]:
                v = obj(name)
                require(v['head'] == head and v['tracked_status'] == '', 'BASELINE_IDENTITY_MISMATCH')
            v = report('native-locks.log', 'matter_repository_lock_reclaim')
            require(v['verdict'] == 'PASS' and v['assertions'] == 82 and v['failures'] == [], 'NATIVE_REPORT_MISMATCH')
            for name,n in (('native-locks.log',82),('test_mw9_durable_handoff_recovery.log',208)):
                require(f'PASS ({n} assertions)' in text(name) or f'PASS ({n} assertions, 0 failures)' in text(name), 'FOCUSED_COUNT:' + name)
            for family,n in (('eg1',5),('eg4',3)):
                require(all(obj(f'{family}-{i}.result.json')['exit_code'] == 0 for i in range(1,n+1)), 'NETWORK_CAMPAIGN')
                for i in range(1, n+1):
                    v = report(f'{family}-{i}.log', f'{family}_gateway_processes_l2')
                    require(v['verdict'] == 'PASS' and v['failures'] == [] and
                            v['assertions'] == (36 if family == 'eg1' else 46), 'NETWORK_REPORT')
            detail = {'distinct_scripts':326, 'stages':331, 'headless_invocations':328, 'eg1_runs':5, 'eg4_runs':3}
        else:
            raise ValueError('UNKNOWN_KIND')
        require(all(v['expected'] == (1 if v['name'] in {'baseline-aba', 'baseline-control-fixture',
                'review-baseline-empty-writer', 'fixture-baseline-mw9'} else 0) for v in commands), 'UNDECLARED_NEGATIVE_EXIT')
        if r['kind'] != 'control':
            require(text('version.log').strip() == '4.7.1.stable.double.custom_build.a13da4feb', 'ENGINE_VERSION')
        return {'classification': 'IMPLEMENTER_RECOMPUTED_EVIDENCE_NOT_INDEPENDENT_VERDICT', 'kind': r['kind'], 'head':HEAD,'tree':TREE,'run_id':RUN,'zip_sha256':archive_sha,'manifest_sha256':sha(read('manifest.json')),'verified_members':len(indexed),'commands':commands,'details':detail,'passed':True}

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('zip', type=Path);p.add_argument('sha256');p.add_argument('--output',type=Path);a=p.parse_args()
    result=audit(a.zip,a.sha256);out=json.dumps(result,indent=2)+'\n'
    if a.output:a.output.write_text(out)
    print(out)
