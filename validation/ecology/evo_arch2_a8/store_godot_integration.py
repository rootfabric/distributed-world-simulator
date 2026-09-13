#!/usr/bin/env python3
"""A8 end-to-end storage/restart proof; not a substitute for full regression."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('a8_store', ROOT / 'scripts/research/ecology/v2/snapshot_store.py')
assert SPEC and SPEC.loader
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)
STAGES = ('blob_staged', 'blob_durable', 'record_staged', 'record_durable', 'pointer_staged', 'pointer_replaced', 'pointer_durable')
ERRORS = re.compile(r'SCRIPT ERROR|Parse Error|ERROR:|FAIL:')


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def die_commit(root: str, tip: str, data: bytes, stage: str) -> None:
    # These exact immutable bytes have already passed a fresh Godot process.
    def fault(at: str) -> None:
        if at == stage:
            os._exit(91)
    S.SnapshotStore(root, fault=fault).commit(tip, data, lambda raw: raw == data)
    os._exit(92)


def race_commit(root: str, tip: str, data: bytes, barrier, queue) -> None:
    barrier.wait(timeout=20)
    try:
        S.SnapshotStore(root).commit(tip, data, lambda raw: raw == data)
        queue.put('COMMITTED')
    except S.Conflict:
        queue.put('CONFLICT')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--godot', required=True, type=Path)
    args = ap.parse_args()
    out = ROOT / 'artifacts/a8/store-integration'
    # This path contains only this executable test's disposable stores/logs.
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    fixture_dir = ROOT / 'artifacts/a8/checkpoints'
    manifest_path = fixture_dir / 'manifest.json'
    manifest_bytes = manifest_path.read_bytes()
    assert len(manifest_bytes) <= S.MAX_SNAPSHOT_BYTES
    manifest = json.loads(manifest_bytes)
    assert manifest['schema'] == 'dws.ecology.a8-restart-fixtures.v1'
    assert len(manifest['checkpoints']) == 17 and len(manifest['commands']) == 16 and len(manifest['receipts']) == 16
    assert S.HASH.fullmatch(manifest['origin_hash']) and S.HASH.fullmatch(manifest['final_sha256'])
    evidence: dict = {'verdict': 'FAIL', 'semantic_processes': [], 'durable_cuts': [], 'crash_cases': [], 'race': {}}
    admitted: dict[str, bytes] = {}
    fixtures: list[bytes] = []
    godot = args.godot.resolve(strict=True)

    def semantic(name: str, path: Path, data: bytes) -> None:
        assert path.read_bytes() == data
        command = [str(godot), '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT), '--script',
                   'res://tests/research/ecology/v2/arch2_a8_restart.gd', '--', str(path), sha(data),
                   manifest['origin_hash'], str(manifest_path), sha(manifest_bytes)]
        log = out / (name + '.log')
        with log.open('wb') as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                    env=dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1'), timeout=300, check=False)
        text = log.read_text(encoding='utf-8-sig', errors='replace')
        assert result.returncode == 0 and not ERRORS.search(text), text[-12000:]
        assert re.search(r'EVO_ARCH2_A8_RESTART assertions=\d+ failed=0', text)
        assert 'final=' + manifest['final_sha256'] in text
        evidence['semantic_processes'].append({'name': name, 'snapshot_sha256': sha(data),
                                               'log_sha256': sha(log.read_bytes()), 'exit_code': result.returncode})
        admitted[sha(data)] = data
        print('PASS', name, 'snapshot=' + sha(data), flush=True)

    def cached_admission(raw: bytes) -> bool:
        # Content-bound semantic result reuse, not an unconditional admission.
        return admitted.get(sha(raw)) == raw

    def recovered(name: str, store) -> tuple[dict, bytes]:
        head, data = store.load()
        assert data is not None and head['snapshot_sha256'] == sha(data)
        path = out / (name + '.json')
        path.write_bytes(data)
        semantic(name, path, data)
        return head, data

    def join(child) -> None:
        child.join(30)
        if child.is_alive():
            child.kill(); child.join()
            raise AssertionError('OWNED_CHILD_TIMEOUT')

    try:
        store = S.SnapshotStore.initialize(out / 'whole-sequence')
        tip = S.ZERO
        for index, fixture in enumerate(manifest['checkpoints']):
            assert fixture['file'] == f'{index:03d}.json'
            path = fixture_dir / fixture['file']
            data = path.read_bytes()
            assert len(data) <= S.MAX_SNAPSHOT_BYTES and sha(data) == fixture['sha256']
            value = json.loads(data)
            assert value['cut']['revision'] == index
            semantic(f'admit-{index:03d}', path, data)
            head = store.commit(tip, data, cached_admission)
            assert head['sequence'] == index + 1
            loaded, durable = recovered(f'recover-{index:03d}', S.SnapshotStore(store.root))
            assert loaded == head and durable == data
            evidence['durable_cuts'].append({'index': index, 'head': head, 'cursor': fixture['cursor']})
            tip = head['tip']
            fixtures.append(data)
        # The actual commit boundary: source is frozen at 7, target owns at 8.
        old, new = fixtures[7], fixtures[8]
        assert json.loads(old)['cut']['ticket']['state'] == 'TARGET_PREPARED'
        assert json.loads(new)['cut']['ticket']['state'] == 'COMMITTED'
        assert json.loads(old)['cut']['owner_id'] == 'node.a' and json.loads(new)['cut']['owner_id'] == 'node.b'
        ctx = multiprocessing.get_context('fork')
        for stage in STAGES:
            root = out / ('crash-' + stage)
            crash_store = S.SnapshotStore.initialize(root)
            before = crash_store.commit(S.ZERO, old, cached_admission)
            child = ctx.Process(target=die_commit, args=(str(root), before['tip'], new, stage))
            child.start(); join(child)
            assert child.exitcode == 91
            head, data = recovered('restart-' + stage, S.SnapshotStore(root))
            published = stage in ('pointer_replaced', 'pointer_durable')
            assert data == (new if published else old)
            assert head['sequence'] == (2 if published else 1)
            current = crash_store.commit(head['tip'], new, cached_admission)
            assert current['sequence'] == 2  # Retry/ambiguous acknowledgement does not apply twice.
            evidence['crash_cases'].append({'stage': stage, 'exit_code': child.exitcode,
                                             'recovered_owner': json.loads(data)['cut']['owner_id'],
                                             'recovered_tip': head['tip'], 'final_tip': current['tip']})
        root = out / 'concurrent-commit'
        concurrent = S.SnapshotStore.initialize(root)
        before = concurrent.commit(S.ZERO, old, cached_admission)
        barrier = ctx.Barrier(2); queue = ctx.Queue()
        children = [ctx.Process(target=race_commit, args=(str(root), before['tip'], new, barrier, queue)) for _ in range(2)]
        for child in children: child.start()
        for child in children:
            join(child)
            assert child.exitcode == 0
        outcomes = sorted(queue.get(timeout=5) for _ in children)
        queue.close()
        assert outcomes == ['COMMITTED', 'CONFLICT']
        head, data = recovered('concurrent-winner', S.SnapshotStore(root))
        assert data == new and head['sequence'] == 2
        evidence['race'] = {'outcomes': outcomes, 'head': head, 'owner_id': json.loads(data)['cut']['owner_id']}
        assert len(evidence['semantic_processes']) == 42
        evidence.update(verdict='PASS', origin_hash=manifest['origin_hash'], final_sha256=manifest['final_sha256'],
                        checkpoint_count=17, crash_case_count=7, semantic_process_count=42,
                        semantic_admission='REAL_GODOT_REPLAY_BEFORE_AND_AFTER_DURABLE_CAS')
        print('EVO_ARCH2_A8_STORE_GODOT checkpoints=17 crash_cases=7 semantic_processes=42 failed=0', flush=True)
        return 0
    except Exception as exc:
        evidence['error'] = str(exc)
        print('A8_STORE_GODOT_FAIL:', str(exc), flush=True)
        return 1
    finally:
        (out / 'summary.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    raise SystemExit(main())
