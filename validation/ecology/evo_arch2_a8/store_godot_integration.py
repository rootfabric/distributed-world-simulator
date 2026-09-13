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
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('a8_store', ROOT / 'scripts/research/ecology/v2/snapshot_store.py')
assert SPEC and SPEC.loader
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)
STAGES = ('blob_staged', 'blob_durable', 'record_staged', 'record_durable', 'pointer_staged', 'pointer_replaced', 'pointer_durable')
ERRORS = re.compile(r'SCRIPT ERROR|Parse Error|ERROR:|FAIL:')


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def die_commit(root: str, anchor: dict, data: bytes, stage: str) -> None:
    # These exact immutable bytes have already passed a fresh Godot process.
    def fault(at: str) -> None:
        if at == stage:
            os._exit(91)
    S.SnapshotStore(root, fault=fault).commit(anchor, data, lambda raw: raw == data)
    os._exit(92)


def race_commit(root: str, anchor: dict, data: bytes, barrier, queue) -> None:
    barrier.wait(timeout=20)
    try:
        S.SnapshotStore(root).commit(anchor, data, lambda raw: raw == data)
        queue.put('COMMITTED')
    except S.Conflict:
        queue.put('CONFLICT')


def sync_dir(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def persist_anchor(directory: Path, name: str, anchor: dict) -> dict:
    """Caller-owned durable anchor, intentionally outside the mutable store."""
    exact = S.validate_anchor(anchor)
    data = json.dumps(exact, sort_keys=True, separators=(',', ':')).encode('ascii') + b'\n'
    fd, raw = tempfile.mkstemp(prefix='.anchor.', dir=directory)
    temp = Path(raw)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        final = directory / (name + '.json')
        os.replace(temp, final)
        sync_dir(directory)
        assert json.loads(final.read_bytes()) == exact
        return exact
    finally:
        temp.unlink(missing_ok=True)


def read_anchor(directory: Path, name: str) -> dict:
    return S.validate_anchor(json.loads((directory / (name + '.json')).read_bytes()))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--godot', required=True, type=Path)
    args = ap.parse_args()
    out = ROOT / 'artifacts/a8/store-integration'
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    anchors = out / 'caller-owned-anchors'
    anchors.mkdir(mode=0o700)
    sync_dir(out)
    fixture_dir = ROOT / 'artifacts/a8/checkpoints'
    manifest_path = fixture_dir / 'manifest.json'
    manifest_bytes = manifest_path.read_bytes()
    assert len(manifest_bytes) <= S.MAX_SNAPSHOT_BYTES
    manifest = json.loads(manifest_bytes)
    assert manifest['schema'] == 'dws.ecology.a8-restart-fixtures.v1'
    assert len(manifest['checkpoints']) == 17 and len(manifest['commands']) == 16 and len(manifest['receipts']) == 16
    assert S.HASH.fullmatch(manifest['origin_hash']) and S.HASH.fullmatch(manifest['final_sha256'])
    evidence: dict = {'verdict': 'FAIL', 'semantic_processes': [], 'durable_cuts': [],
                      'crash_cases': [], 'anchor_rollback_cases': [], 'race': {}}
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
        return admitted.get(sha(raw)) == raw

    def recovered(name: str, store, anchor: dict) -> tuple[dict, bytes]:
        head, data = store.load(anchor)
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
        anchor = persist_anchor(anchors, 'whole-sequence', S.genesis_anchor())
        for index, fixture in enumerate(manifest['checkpoints']):
            assert fixture['file'] == f'{index:03d}.json'
            path = fixture_dir / fixture['file']
            data = path.read_bytes()
            assert len(data) <= S.MAX_SNAPSHOT_BYTES and sha(data) == fixture['sha256']
            value = json.loads(data)
            assert value['cut']['revision'] == index
            semantic(f'admit-{index:03d}', path, data)
            head = store.commit(anchor, data, cached_admission)
            assert head['sequence'] == index + 1
            anchor = persist_anchor(anchors, 'whole-sequence', head)
            loaded, durable = recovered(f'recover-{index:03d}', S.SnapshotStore(store.root), read_anchor(anchors, 'whole-sequence'))
            assert loaded == head and durable == data
            evidence['durable_cuts'].append({'index': index, 'head': head, 'cursor': fixture['cursor']})
            fixtures.append(data)
        old, new = fixtures[7], fixtures[8]
        assert json.loads(old)['cut']['ticket']['state'] == 'TARGET_PREPARED'
        assert json.loads(new)['cut']['ticket']['state'] == 'COMMITTED'
        assert json.loads(old)['cut']['owner_id'] == 'node.a' and json.loads(new)['cut']['owner_id'] == 'node.b'
        ctx = multiprocessing.get_context('fork')
        for stage in STAGES:
            root = out / ('crash-' + stage)
            name = 'crash-' + stage
            crash_store = S.SnapshotStore.initialize(root)
            before = crash_store.commit(S.genesis_anchor(), old, cached_admission)
            acknowledged = persist_anchor(anchors, name, before)
            child = ctx.Process(target=die_commit, args=(str(root), acknowledged, new, stage))
            child.start(); join(child)
            assert child.exitcode == 91
            # External anchor remains the last ACK. A pointer-replaced crash is a
            # valid descendant; a pre-pointer crash keeps the old acknowledged cut.
            head, data = recovered('restart-' + stage, S.SnapshotStore(root), read_anchor(anchors, name))
            published = stage in ('pointer_replaced', 'pointer_durable')
            assert data == (new if published else old)
            assert head['sequence'] == (2 if published else 1)
            acknowledged = persist_anchor(anchors, name, head)
            current = crash_store.commit(acknowledged, new, cached_admission)
            assert current['sequence'] == 2
            acknowledged = persist_anchor(anchors, name, current)
            # Once sequence 2 is durably acknowledged outside the store, a valid
            # rollback of CURRENT to zero or the old sequence must fail closed.
            for label, pointer in (('zero', S.ZERO), ('previous', before['tip'])):
                (root / 'CURRENT').write_text(pointer + '\n', encoding='ascii')
                try:
                    S.SnapshotStore(root).load(acknowledged)
                    raise AssertionError('ANCHOR_ROLLBACK_ACCEPTED:' + label)
                except S.StoreError as exc:
                    assert 'DURABLE_ANCHOR_ROLLBACK_OR_FORK' in str(exc)
                evidence['anchor_rollback_cases'].append({'stage': stage, 'pointer': label,
                                                          'acknowledged_sequence': acknowledged['sequence'],
                                                          'result': 'REJECTED'})
            # Restore only for deterministic artifact inspection; this is test setup,
            # not a fallback path used by store recovery.
            (root / 'CURRENT').write_text(current['tip'] + '\n', encoding='ascii')
            assert S.SnapshotStore(root).load(acknowledged)[0] == current
            evidence['crash_cases'].append({'stage': stage, 'exit_code': child.exitcode,
                                             'recovered_owner': json.loads(data)['cut']['owner_id'],
                                             'recovered_tip': head['tip'], 'final_tip': current['tip'],
                                             'external_anchor_sha256': sha((anchors / (name + '.json')).read_bytes())})
        root = out / 'concurrent-commit'
        concurrent = S.SnapshotStore.initialize(root)
        before = concurrent.commit(S.genesis_anchor(), old, cached_admission)
        acknowledged = persist_anchor(anchors, 'concurrent', before)
        barrier = ctx.Barrier(2); queue = ctx.Queue()
        children = [ctx.Process(target=race_commit, args=(str(root), acknowledged, new, barrier, queue)) for _ in range(2)]
        for child in children: child.start()
        for child in children:
            join(child)
            assert child.exitcode == 0
        outcomes = sorted(queue.get(timeout=5) for _ in children)
        queue.close()
        assert outcomes == ['COMMITTED', 'CONFLICT']
        head, data = recovered('concurrent-winner', S.SnapshotStore(root), acknowledged)
        assert data == new and head['sequence'] == 2
        acknowledged = persist_anchor(anchors, 'concurrent', head)
        # A valid alternate sequence-2 record from the same predecessor must not
        # replace the exact externally acknowledged winning head.
        alternate = b'fixture:alternate-branch'
        blob_hash = S.digest(alternate)
        (root / 'blobs' / (blob_hash + '.bin')).write_bytes(alternate)
        record = {'schema': S.RECORD_SCHEMA, 'sequence': 2, 'previous': before['tip'],
                  'snapshot_sha256': blob_hash, 'snapshot_bytes': len(alternate)}
        encoded = S._json(record); fork_tip = S.digest(encoded)
        (root / 'records' / (fork_tip + '.json')).write_bytes(encoded)
        (root / 'CURRENT').write_text(fork_tip + '\n', encoding='ascii')
        try:
            S.SnapshotStore(root).load(acknowledged)
            raise AssertionError('ANCHOR_FORK_ACCEPTED')
        except S.StoreError as exc:
            assert 'DURABLE_ANCHOR_ROLLBACK_OR_FORK' in str(exc)
        evidence['anchor_rollback_cases'].append({'stage': 'concurrent', 'pointer': 'alternate-valid-fork',
                                                  'acknowledged_sequence': acknowledged['sequence'], 'result': 'REJECTED'})
        (root / 'CURRENT').write_text(head['tip'] + '\n', encoding='ascii')
        evidence['race'] = {'outcomes': outcomes, 'head': head, 'owner_id': json.loads(data)['cut']['owner_id'],
                            'external_anchor_sha256': sha((anchors / 'concurrent.json').read_bytes())}
        assert len(evidence['semantic_processes']) == 42
        assert len(evidence['anchor_rollback_cases']) == 15
        evidence.update(verdict='PASS', origin_hash=manifest['origin_hash'], final_sha256=manifest['final_sha256'],
                        checkpoint_count=17, crash_case_count=7, semantic_process_count=42,
                        anchor_rollback_case_count=15,
                        semantic_admission='REAL_GODOT_REPLAY_BEFORE_AND_AFTER_DURABLE_CAS',
                        external_anchor='CALLER_OWNED_FSYNCED_HEAD_OUTSIDE_STORE_DIRECTORY')
        print('EVO_ARCH2_A8_STORE_GODOT checkpoints=17 crash_cases=7 semantic_processes=42 anchor_rollbacks=15 failed=0', flush=True)
        return 0
    except Exception as exc:
        evidence['error'] = str(exc)
        print('A8_STORE_GODOT_FAIL:', str(exc), flush=True)
        return 1
    finally:
        (out / 'summary.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    raise SystemExit(main())
