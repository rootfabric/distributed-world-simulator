#!/usr/bin/env python3
"""Exact A9 qualification plus the unchanged complete A8 regression suite."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE_MAIN = '675c04bb213bbb68b8cdb500d540d57ce1490318'
BASE_TREE = '04b217ff7acfcd6336490f139f9239a7f6b59b7d'
ADDITIONS = {
    'config/ecology/evo-arch2-a9-work-order.v1.json',
    'docs/research/ecology/EVO_ARCH2_A9_FIDELITY_R1_RU.md',
    'scripts/research/ecology/v2/ecological_fidelity_v1.py',
    'scripts/research/ecology/v2/fidelity_runtime_v1.py',
    'scripts/research/ecology/v2/fidelity_admission_v1.gd',
    'validation/ecology/evo_arch2_a9/test_fidelity.py',
    'validation/ecology/evo_arch2_a9/integration.py',
    'validation/ecology/evo_arch2_a9/verify.py',
}


def require(ok, message):
    if not ok: raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_a8_verifier():
    p = ROOT / 'validation/ecology/evo_arch2_a8/verify.py'
    spec = importlib.util.spec_from_file_location('a9_inherited_a8', p)
    require(spec is not None and spec.loader is not None, 'A8_VERIFIER_IMPORT')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--godot', required=True, type=Path)
    ap.add_argument('--head', required=True); ap.add_argument('--tree', required=True)
    args = ap.parse_args()
    require(sys.flags.optimize == 0, 'EXACT_VERIFIER_OPTIMIZATION_FORBIDDEN')
    v8 = load_a8_verifier()
    out = ROOT / 'artifacts/a9/exact'
    # A9 never removes an ancestor of its log directory after opening the first log.
    if out.exists(): shutil.rmtree(out)
    out.mkdir(parents=True)
    result = {'verdict': 'FAIL', 'subject_head': args.head, 'subject_tree': args.tree,
              'base_main': BASE_MAIN, 'base_tree': BASE_TREE, 'checks': []}
    start = time.monotonic()
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1', GIT_NO_REPLACE_OBJECTS='1')
    def run(name, command, marker, timeout=900, scan=True):
        log = out / (name + '.log')
        with log.open('wb') as stream:
            p = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, check=False)
        text = log.read_text(encoding='utf-8-sig', errors='replace')
        require(p.returncode == 0 and marker in text and (not scan or not v8.ERRORS.search(text)), name + ':' + text[-6000:])
        result['checks'].append({'name': name, 'exit_code': p.returncode, 'sha256': sha(log), 'command': command})
        print('PASS ' + name, flush=True)
        return text
    try:
        require(v8.git('rev-parse', 'HEAD') == args.head and v8.git('rev-parse', 'HEAD^{tree}') == args.tree, 'EXACT_SOURCE')
        require(v8.git('rev-parse', BASE_MAIN + '^{tree}') == BASE_TREE, 'BASE_TREE')
        require(v8.git('rev-parse', 'refs/remotes/origin/main') == BASE_MAIN, 'MAIN_EPOCH_MOVED')
        require(v8.gp('merge-base', '--is-ancestor', BASE_MAIN, args.head).returncode == 0, 'FRESH_MAIN_DESCENT')
        require(v8.git('rev-parse', '--is-shallow-repository') == 'false', 'INCOMPLETE_HISTORY')
        require(not v8.git('status', '--porcelain', '--untracked-files=no'), 'SOURCE_DIRTY')
        actual = set()
        for row in v8.git('diff', '--name-status', BASE_MAIN, args.head).splitlines():
            columns = row.split('\t'); require(len(columns) == 2 and columns[0] == 'A', 'MAIN_OWNED_PATH_CHANGED:' + row)
            actual.add(columns[1])
        require(actual == ADDITIONS, 'A9_ADDITIVE_SCOPE')
        sealed = {path: v8.require_exact_resource(args.head, path) for path in sorted(ADDITIONS)}
        result['scope'] = {'additions': sorted(actual), 'modified_main_paths': 0, 'objects': sealed}
        result['native_dependency_closure'] = v8.resource_closure(args.head)
        result['jsonschema'] = v8.harness_dependency()
        args.godot = args.godot.resolve(strict=True)
        require(sha(args.godot) == v8.GODOT_SHA, 'GODOT_SHA')
        require(subprocess.check_output([str(args.godot), '--version'], text=True).strip() == v8.GODOT_VERSION, 'GODOT_VERSION')
        result['godot'] = {'sha256': v8.GODOT_SHA, 'version': v8.GODOT_VERSION}
        for suffix, options in [('normal', []), ('optimized', ['-O'])]:
            text = run('a9-contracts-' + suffix, [sys.executable, *options, '-m', 'unittest', 'discover',
                       '-s', 'validation/ecology/evo_arch2_a9', '-p', 'test_fidelity.py', '-v'], 'OK', timeout=180, scan=False)
            require(v8.unittest_count(text, 32) == 32, 'A9_CONTRACT_COUNT')
        shutil.rmtree(ROOT / '.godot', ignore_errors=True)
        run('a9-cold-import', [str(args.godot), '--headless', '--audio-driver', 'Dummy', '--editor', '--path', str(ROOT), '--import'], '', timeout=300)
        run('a9-native-integration', [sys.executable, 'validation/ecology/evo_arch2_a9/integration.py', '--godot', str(args.godot)],
            'EVO_ARCH2_A9_INTEGRATION checks=13 failed=0', timeout=7200)
        integration = ROOT / 'artifacts/a9/integration/summary.json'
        evidence = json.loads(integration.read_bytes())
        require(evidence.get('verdict') == 'PASS' and len(evidence.get('checks', [])) == 13, 'INTEGRATION_SUMMARY')
        result['integration'] = {'sha256': sha(integration), 'checks': evidence['checks'],
                                 'retained_packet_bytes': evidence['retained_packet_bytes'], 'real_scale': evidence['real_scale']}
        # The inherited implementation is byte-identical to current main. Only its
        # additive path fence is extended for the eight independently sealed A9 files.
        # Base, runtime commands, assertions, repeats, graphics and control gates stay intact.
        inherited_before = set(v8.EXPECTED_ADDITIONS)
        v8.EXPECTED_ADDITIONS = inherited_before | ADDITIONS
        result['inherited_scope_extension'] = {'original': sorted(inherited_before), 'additional': sorted(ADDITIONS)}
        require(v8.main() == 0, 'FULL_A8_INHERITED_REGRESSION')
        p = ROOT / 'artifacts/a8/exact/summary.json'; regression = json.loads(p.read_bytes())
        require(regression.get('verdict') == 'PASS' and regression.get('subject_head') == args.head and regression.get('subject_tree') == args.tree, 'INHERITED_EXACT_SUBJECT')
        result['full_a0_a8_regression'] = {'sha256': sha(p), 'verdict': 'PASS', 'subject_head': args.head}
        for path, oid in sealed.items(): require(v8.require_exact_resource(args.head, path) == oid, 'FINAL_SOURCE_BYTES:' + path)
        require(v8.git('rev-parse', 'HEAD') == args.head and v8.git('rev-parse', 'HEAD^{tree}') == args.tree, 'FINAL_HEAD_TREE')
        require(not v8.git('status', '--porcelain', '--untracked-files=no'), 'FINAL_TRACKED_DIRTY')
        result['verdict'] = 'PASS'
        print('EVO_ARCH2_A9_EXACT verdict=PASS head=' + args.head, flush=True)
        return 0
    except Exception as exc:
        result['error'] = str(exc); print('A9_EXACT_FAILURE: ' + str(exc), flush=True)
        return 1
    finally:
        result['elapsed_seconds'] = round(time.monotonic() - start, 3)
        (out / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
