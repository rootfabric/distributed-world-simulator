#!/usr/bin/env python3
"""Inspect exact A7 R3 artifact bytes; not an independent verdict or acceptance."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import zipfile

HEAD = '8eccf6304078bec3a3ccaa5860c5aab6ee311209'
TREE = '24e876b7377cb3e1e521f08ff9766331fe4e895a'
BASE = '993271eb46880b77f0e7584f931131d4bd0a5125'
GODOT = 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7'
PROTOCOL = '4264c7590762d65dbd65a8e951c6a008e4cac2ced0cc04bb43d8d3a66ef01ce4'
ERROR = re.compile(r'SCRIPT ERROR|Parse Error|ERROR:|FAIL:')
RM = {11:9,12:29,13:13,14:21,15:12,16:10,17:13,18:12,19:10,20:12,21:8,22:13,23:16,25:11,26:11,27:13,28:12,29:9,30:7,32:12,33:17,34:19}


def require(ok: bool, label: str) -> None:
    if not ok:
        raise ValueError(label)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def expectations() -> tuple[dict[str, tuple[int, str]], set[str]]:
    result = {'cold-import': (0, ''), 'a7-verifier-guard': (0, 'OK')}
    pairs: set[str] = set()
    suites = {'a7-protocol': (106, 'EVO_ARCH2_A7_PROTOCOL'), 'a7-core': (158, 'EVO_ARCH2_A7_EXACT'),
              'a7-ui': (30, 'EVO_ARCH2_A7_UI'), 'a6-core': (77, 'EVO_ARCH2_A6_EXACT'),
              'a6-adversarial': (76, 'EVO_ARCH2_A6_ADVERSARIAL'), 'a6-lineage': (11, 'EVO_ARCH2_A6_LINEAGE'),
              'a5-core': (69, 'EVO_ARCH2_A5_EXACT'), 'a5-repairs': (29, 'EVO_ARCH2_A5_REPAIRS')}
    suites.update({f'rm{k}': (n, f'EVO_ARCH2_A5_RM{k}') for k, n in RM.items()})
    for name, (count, marker) in suites.items():
        pairs.add(name)
        for n in (1, 2):
            result[f'{name}-{n}'] = (count, f'{marker} assertions={count} failed=0')
    for stage in ('a7', 'a6'):
        for phase in ('write', 'read'):
            name = f'{stage}-restart-{phase}'
            pairs.add(name)
            for n in (1, 2):
                result[f'{name}-{n}'] = (0, f'EVO_ARCH2_{stage.upper()}_RESTART phase={phase} failed=0')
    for stage, count in (('a4', 32), ('a03', 86)):
        result[stage] = (count, f'EVO_ARCH2_{stage.upper()}_EXACT assertions={count} failed=0')
    for n, count in enumerate((87, 70, 57, 101, 92, 114)):
        result[f'vis5-{n}'] = (count, f'PASS ({count} assertions)')
    result['a7-graphical'] = (32, 'EVO_ARCH2_A7_UI assertions=32 failed=0')
    return result, pairs


def inspect(path: Path, expected_sha: str) -> dict:
    require(path.stat().st_size < 64 * 1024 * 1024, 'ZIP_BYTE_BOUND')
    require(sha(path.read_bytes()) == expected_sha, 'ZIP_DIGEST')
    expected, pairs = expectations()
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        require(len(names) == len(set(names)) and len(names) < 512, 'ZIP_MEMBER_SET')
        require(all(not PurePosixPath(n).is_absolute() and '..' not in PurePosixPath(n).parts for n in names), 'ZIP_PATH')
        require(sum(i.file_size for i in z.infolist()) < 64 * 1024 * 1024, 'ZIP_EXPANSION_BOUND')
        s = json.loads(z.read('exact/summary.json'))
        require((s['subject_head'], s['subject_tree'], s['accepted_base']) == (HEAD, TREE, BASE), 'EXACT_SUBJECT')
        require(s['verdict'] == 'PASS' and s['graphical_required'] is True, 'INCOMPLETE_VERDICT')
        require(s['godot'] == {'version': '4.7.1.stable.double.custom_build.a13da4feb', 'sha256': GODOT}, 'GODOT_IDENTITY')
        checks = {c['name']: c for c in s['checks']}
        require(len(checks) == len(s['checks']) and set(checks) == set(expected), 'CHECK_SET')
        require(set(s['repeat_pairs']) == pairs and len(s['repeat_pairs']) == len(pairs), 'REPEAT_SET')
        for name, (count, marker) in expected.items():
            c = checks[name]
            data = z.read(f'exact/{name}.log')
            text = data.decode('utf-8-sig')
            require(c['result'] == 'PASS' and c['exit_code'] == 0 and c['assertions'] == count, 'CHECK:' + name)
            require(sha(data) == c['sha256'], 'LOG_DIGEST:' + name)
            require(not ERROR.search(text) and (not marker or marker in text), 'LOG_RESULT:' + name)
            require(isinstance(c.get('command'), list) and len(c['command']) > 1, 'COMMAND:' + name)
        for name in pairs:
            require(z.read(f'exact/{name}-1.log') == z.read(f'exact/{name}-2.log'), 'REPEAT_BYTES:' + name)
        require(s['assertion_executions'] == sum(c['assertions'] for c in s['checks']) == 2361, 'ASSERTIONS')
        require('Ran 2 tests' in z.read('exact/a7-verifier-guard.log').decode(), 'PYTHON_GUARD_COUNT')
        pin_lines = z.read('source-pins.log').decode().strip().splitlines()
        require(len(pin_lines) == 18 and len(set(pin_lines)) == 18, 'PIN_COUNT')
        for line in pin_lines:
            m = re.fullmatch(r'SOURCE_BLOB_PASS (\S+) ([0-9a-f]{40}) expected=([0-9a-f]{40})', line)
            require(m is not None and m[2] == m[3], 'PIN_RESULT')
        png = z.read('observatory.png')
        require(png[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', png[16:24]) == (1440, 960), 'VIEWPORT')
        require(sha(png) == s['viewport_sha256'], 'VIEWPORT_DIGEST')
        capture = z.read('capture-sources.json')
        require(sha(capture) == s['viewport_source_report_sha256'], 'CAPTURE_DIGEST')
        r = json.loads(capture)
        require(r['success'] is True and r['step'] == r['horizon'] == 16, 'CAPTURE_HORIZON')
        require(r['source_a6'] == BASE and r['protocol_hash'] == PROTOCOL, 'CAPTURE_PROTOCOL')
        require(r['scope'] == 'FOUNDER_CONTROLS_NOT_MULTI_GENERATION_EVOLUTION', 'CAPTURE_SCOPE')
        require(r['treatment'] == {'seed': 20260912, 'common_garden': False, 'effects_enabled': True, 'mutations_enabled': True}, 'CAPTURE_TREATMENT')
        require([site['id'] for site in r['sites']] == ['wet', 'dry', 'dark'], 'CAPTURE_SITES')
        genomes = set()
        observations = []
        for site in r['sites']:
            study = next(e for e in site['entries'] if e['id'] == 'study')
            genomes.add(study['phenotype']['genome_hash'])
            b = site['balance']
            for resource in ('material_mg', 'water_mg', 'energy_mj'):
                require(b['initial'][resource] + b['external'][resource] == b['current'][resource] + b['sinks'][resource], 'BALANCE:' + site['id'])
            observations.append({'site': site['id'], 'source_hash': site['source_hash'],
                                 'modules': study['phenotype']['statistics']['module_count'],
                                 'births': study['reproduction_count'], 'pending_propagules': site['pending_propagules']})
        require(len(genomes) == 1, 'GENOTYPE_PARITY')
        require(f"A7_CAPTURE_SOURCE {r['experiment_hash']} 16" in z.read('exact/a7-graphical.log').decode('utf-8-sig'), 'CAPTURE_LOG_BINDING')
        control = json.loads(z.read('control/control-observation.json'))
        require(control['a7_authority'] == 'ISOLATED_RESEARCH_ONLY' and control['global_green_inferred'] is False, 'CONTROL_SCOPE')
        return {'inspection': 'PASS', 'research_acceptance_claimed': False, 'subject_head': HEAD, 'subject_tree': TREE,
                'zip_sha256': expected_sha, 'summary_sha256': sha(z.read('exact/summary.json')),
                'process_checks': len(checks), 'assertion_executions': 2361, 'python_guard_tests': 2,
                'byte_identical_pairs': len(pairs), 'viewport_sha256': sha(png), 'capture_sha256': sha(capture),
                'observations': observations, 'control': control,
                'files': {name: sha(z.read(name)) for name in names if not name.endswith('/')}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--sha256', required=True, help='Expected digest from trusted Actions artifact metadata')
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = inspect(args.archive, args.sha256)
        args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        print('A7_ARTIFACT_INSPECTION_PASS')
        return 0
    except (ValueError, KeyError, OSError, UnicodeError, zipfile.BadZipFile, StopIteration, struct.error) as exc:
        print(f'A7_ARTIFACT_INSPECTION_FAIL: {exc}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
