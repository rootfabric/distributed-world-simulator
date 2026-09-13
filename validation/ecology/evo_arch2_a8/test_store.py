"""Storage-only fault controls. Byte fixtures here are not ecology acceptance."""
from __future__ import annotations
import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[3] / 'scripts/research/ecology/v2/snapshot_store.py'
SPEC = importlib.util.spec_from_file_location('a8_snapshot_store', SOURCE)
assert SPEC and SPEC.loader
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)
STAGES = ('blob_staged', 'blob_durable', 'record_staged', 'record_durable', 'pointer_staged', 'pointer_replaced', 'pointer_durable')


def byte_admission(data: bytes) -> bool:
    return data.startswith(b'fixture:')


def crash_worker(root: str, tip: str, stage: str) -> None:
    def fault(at: str) -> None:
        if at == stage:
            os._exit(91)
    S.SnapshotStore(root, fault=fault).commit(tip, b'fixture:new', byte_admission)
    os._exit(92)


def race_worker(root: str, tip: str, value: bytes, ready, results) -> None:
    ready.wait(timeout=10)
    try:
        head = S.SnapshotStore(root).commit(tip, value, byte_admission)
        results.put(('committed', head['tip']))
    except S.Conflict:
        results.put(('conflict', ''))


class StoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix='a8-store-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'store'
        self.store = S.SnapshotStore.initialize(self.root)

    def put(self, data: bytes = b'fixture:old') -> dict:
        tip = self.store.load()[0]['tip']
        return self.store.commit(tip, data, byte_admission)

    def test_initialize_and_reopen(self):
        head, data = S.SnapshotStore(self.root).load()
        self.assertEqual(head['tip'], S.ZERO)
        self.assertIsNone(data)
        with self.assertRaises(FileExistsError):
            S.SnapshotStore.initialize(self.root)

    def test_commit_and_content_address(self):
        head = self.put()
        self.assertEqual(head['sequence'], 1)
        self.assertEqual(head['snapshot_sha256'], S.digest(b'fixture:old'))
        self.assertEqual(S.SnapshotStore(self.root).load(), (head, b'fixture:old'))

    def test_same_bytes_are_idempotent(self):
        head = self.put()
        self.assertEqual(self.put(), head)
        self.assertEqual(len(list((self.root / 'records').glob('*.json'))), 1)

    def test_stale_cas_changes_nothing(self):
        head = self.put()
        before = sorted(p.name for p in (self.root / 'blobs').iterdir())
        with self.assertRaises(S.Conflict):
            self.store.commit(S.ZERO, b'fixture:new', byte_admission)
        self.assertEqual(self.store.load(), (head, b'fixture:old'))
        self.assertEqual(sorted(p.name for p in (self.root / 'blobs').iterdir()), before)

    def test_admission_is_mandatory(self):
        for admit in (None, lambda _: False, lambda _: 1, lambda _: 'PASS'):
            with self.subTest(admit=repr(admit)):
                with self.assertRaisesRegex(S.StoreError, 'SEMANTIC_ADMISSION_REQUIRED'):
                    self.store.commit(S.ZERO, b'fixture:old', admit)
        self.assertEqual(self.store.load()[0]['tip'], S.ZERO)

    def test_admission_exception_does_not_write(self):
        def reject(_):
            raise ValueError('semantic failure')
        with self.assertRaises(ValueError):
            self.store.commit(S.ZERO, b'fixture:old', reject)
        self.assertEqual(list((self.root / 'blobs').iterdir()), [])

    def test_oversize_or_empty_input(self):
        for data in (b'', b'x' * (S.MAX_SNAPSHOT_BYTES + 1), 'text'):
            with self.subTest(size=len(data)):
                with self.assertRaisesRegex(S.StoreError, 'SNAPSHOT_BYTE_BUDGET'):
                    self.store.commit(S.ZERO, data, byte_admission)
        self.assertEqual(self.store.load()[0]['tip'], S.ZERO)

    def test_invalid_expected_tip(self):
        for tip in ('', 'X' * 64, '../CURRENT', None):
            with self.subTest(tip=tip):
                with self.assertRaisesRegex(S.StoreError, 'EXPECTED_TIP_REQUIRED'):
                    self.store.commit(tip, b'fixture:old', byte_admission)

    def test_two_real_writers_one_wins(self):
        head = self.put()
        ctx = multiprocessing.get_context('fork')
        barrier = ctx.Barrier(2)
        results = ctx.Queue()
        children = [ctx.Process(target=race_worker, args=(str(self.root), head['tip'], value, barrier, results))
                    for value in (b'fixture:A', b'fixture:B')]
        for child in children:
            child.start()
        for child in children:
            child.join(15)
            if child.is_alive():
                child.kill(); child.join()
            self.assertEqual(child.exitcode, 0)
        outcomes = sorted(results.get(timeout=3)[0] for _ in children)
        self.assertEqual(outcomes, ['committed', 'conflict'])
        after, data = self.store.load()
        self.assertEqual(after['sequence'], 2)
        self.assertIn(data, (b'fixture:A', b'fixture:B'))
        results.close()

    def test_crash_at_every_durable_boundary(self):
        ctx = multiprocessing.get_context('fork')
        for stage in STAGES:
            with self.subTest(stage=stage):
                root = Path(self.tmp.name) / stage
                store = S.SnapshotStore.initialize(root)
                head = store.commit(S.ZERO, b'fixture:old', byte_admission)
                child = ctx.Process(target=crash_worker, args=(str(root), head['tip'], stage))
                child.start(); child.join(15)
                if child.is_alive():
                    child.kill(); child.join()
                self.assertEqual(child.exitcode, 91)
                recovered, data = S.SnapshotStore(root).load()
                after_replace = stage in ('pointer_replaced', 'pointer_durable')
                self.assertEqual(data, b'fixture:new' if after_replace else b'fixture:old')
                self.assertEqual(recovered['sequence'], 2 if after_replace else 1)
                final = store.commit(recovered['tip'], b'fixture:new', byte_admission)
                self.assertEqual(final['sequence'], 2)

    def test_missing_current_is_not_empty(self):
        self.put()
        (self.root / 'CURRENT').unlink()
        with self.assertRaises(FileNotFoundError):
            S.SnapshotStore(self.root)

    def test_corrupt_current_no_fallback(self):
        self.put()
        (self.root / 'CURRENT').write_bytes(b'partial')
        with self.assertRaises(S.StoreError):
            self.store.load()

    def test_missing_record_no_fallback(self):
        head = self.put()
        (self.root / 'records' / (head['tip'] + '.json')).unlink()
        with self.assertRaises(FileNotFoundError):
            self.store.load()

    def test_missing_blob_no_fallback(self):
        head = self.put()
        (self.root / 'blobs' / (head['snapshot_sha256'] + '.bin')).unlink()
        with self.assertRaises(FileNotFoundError):
            self.store.load()

    def test_tampered_blob_is_rejected(self):
        head = self.put()
        (self.root / 'blobs' / (head['snapshot_sha256'] + '.bin')).write_bytes(b'fixture:bad')
        with self.assertRaisesRegex(S.StoreError, 'SNAPSHOT_HASH_OR_SIZE'):
            self.store.load()

    def test_tampered_old_blob_rejects_entire_chain(self):
        old = self.put()
        self.put(b'fixture:new')
        (self.root / 'blobs' / (old['snapshot_sha256'] + '.bin')).write_bytes(b'x')
        with self.assertRaises(S.StoreError):
            self.store.load()

    def test_tampered_record_is_rejected(self):
        head = self.put()
        (self.root / 'records' / (head['tip'] + '.json')).write_bytes(b'{}')
        with self.assertRaisesRegex(S.StoreError, 'RECORD_HASH'):
            self.store.load()

    def test_rehashed_truncated_chain_rejected(self):
        self.put()
        head = self.put(b'fixture:new')
        p = self.root / 'records' / (head['tip'] + '.json')
        record = json.loads(p.read_bytes()); record['previous'] = S.ZERO
        raw = S._json(record); digest = S.digest(raw)
        (p.parent / (digest + '.json')).write_bytes(raw)
        (self.root / 'CURRENT').write_text(digest + '\n')
        with self.assertRaisesRegex(S.StoreError, 'CHAIN_TRUNCATED'):
            self.store.load()

    def test_orphans_never_become_commits(self):
        head = self.put()
        (self.root / 'blobs' / (S.digest(b'fixture:orphan') + '.bin')).write_bytes(b'fixture:orphan')
        (self.root / 'records' / '.pending.interrupted').write_bytes(b'partial')
        self.assertEqual(self.store.load(), (head, b'fixture:old'))

    def test_root_symlink_rejected(self):
        alias = Path(self.tmp.name) / 'alias'; alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(S.StoreError):
            S.SnapshotStore(alias)

    def test_blob_symlink_rejected(self):
        head = self.put()
        p = self.root / 'blobs' / (head['snapshot_sha256'] + '.bin')
        target = Path(self.tmp.name) / 'target'; target.write_bytes(p.read_bytes())
        p.unlink(); p.symlink_to(target)
        with self.assertRaises(OSError):
            self.store.load()

    def test_fifo_rejected_without_blocking(self):
        head = self.put()
        p = self.root / 'blobs' / (head['snapshot_sha256'] + '.bin')
        p.unlink(); os.mkfifo(p)
        with self.assertRaisesRegex(S.StoreError, 'NOT_BOUNDED_REGULAR_FILE'):
            self.store.load()

    def test_disk_budget_stops_before_publication(self):
        head = self.put()
        with (self.root / 'orphan-sparse').open('wb') as f:
            f.truncate(S.MAX_DISK_BYTES)
        with self.assertRaisesRegex(S.StoreError, 'STORE_CAPACITY_BUDGET'):
            self.put(b'fixture:new')
        self.assertEqual(self.store.load()[0], head)

    def test_record_budget(self):
        self.put(); head = self.put(b'fixture:two')
        with patch.object(S, 'MAX_RECORDS', 2):
            with self.assertRaisesRegex(S.StoreError, 'STORE_CAPACITY_BUDGET'):
                self.put(b'fixture:three')
        self.assertEqual(self.store.load()[0], head)

    def test_no_locking_fallback(self):
        with patch.object(S, 'fcntl', None):
            with self.assertRaisesRegex(S.StoreError, 'LINUX_POSIX_STORE_REQUIRED'):
                S.SnapshotStore(self.root)

    def test_immutable_collision_cannot_replace_bytes(self):
        self.put()
        blob = self.root / 'blobs' / (S.digest(b'fixture:new') + '.bin')
        blob.write_bytes(b'corrupted orphan')
        old_tip = self.store.load()[0]['tip']
        with self.assertRaises((S.StoreError, OSError)):
            self.put(b'fixture:new')
        self.assertEqual(self.store.load()[0]['tip'], old_tip)
        self.assertEqual(blob.read_bytes(), b'corrupted orphan')


if __name__ == '__main__':
    unittest.main()
