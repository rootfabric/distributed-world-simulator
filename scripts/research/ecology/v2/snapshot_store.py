"""Linux research snapshot journal. Opaque bytes; admission belongs to the caller.

Publication is a locked compare-and-swap of CURRENT after durable immutable blobs
and records. The caller MUST semantically admit an A8 proposal before publication,
keep the last acknowledged head as an external durable anchor, and reload with that
anchor after a conflict/ambiguous acknowledgement. This is not a network consensus
service or authentication boundary. Use a trusted local POSIX directory.
"""
from __future__ import annotations

from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile
from typing import Callable, Iterator

try:
    import fcntl
except ImportError:  # Fail explicitly; no weaker Windows locking fallback.
    fcntl = None  # type: ignore[assignment]

ZERO = "0" * 64
MAX_SNAPSHOT_BYTES = 2 * 1024 * 1024
MAX_RECORDS = 256
MAX_DISK_BYTES = 64 * 1024 * 1024
HASH = re.compile(r"[0-9a-f]{64}\Z")
RECORD_SCHEMA = "dws.ecology.a8-store-record.v1"
ANCHOR_FIELDS = {"tip", "sequence", "snapshot_sha256"}


class StoreError(RuntimeError):
    """Corruption, invalid input or a failed durability operation."""


class Conflict(StoreError):
    """The expected durable head is stale. Discard the local proposal and reload."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _json(value: dict) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def genesis_anchor() -> dict:
    """External anchor for a store that has never acknowledged a commit."""
    return {"tip": ZERO, "sequence": 0, "snapshot_sha256": None}


def validate_anchor(value: object) -> dict:
    """Normalize a caller-owned durable anchor; never infer it from CURRENT."""
    if not isinstance(value, dict) or set(value) != ANCHOR_FIELDS:
        raise StoreError("EXTERNAL_DURABLE_ANCHOR_REQUIRED")
    tip = value.get("tip")
    sequence = value.get("sequence")
    snapshot = value.get("snapshot_sha256")
    if not isinstance(tip, str) or HASH.fullmatch(tip) is None or type(sequence) is not int:
        raise StoreError("EXTERNAL_DURABLE_ANCHOR_INVALID")
    if sequence < 0 or sequence > MAX_RECORDS:
        raise StoreError("EXTERNAL_DURABLE_ANCHOR_INVALID")
    if sequence == 0:
        if tip != ZERO or snapshot is not None:
            raise StoreError("EXTERNAL_DURABLE_ANCHOR_INVALID")
    elif tip == ZERO or not isinstance(snapshot, str) or HASH.fullmatch(snapshot) is None:
        raise StoreError("EXTERNAL_DURABLE_ANCHOR_INVALID")
    return {"tip": tip, "sequence": sequence, "snapshot_sha256": snapshot}


def _sync_dir(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _read(path: Path, limit: int) -> bytes:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise StoreError("NOT_BOUNDED_REGULAR_FILE:" + path.name)
        chunks: list[bytes] = []
        remaining = limit + 1
        while remaining:
            chunk = os.read(fd, min(65536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        if len(data) > limit or len(data) != info.st_size:
            raise StoreError("FILE_SIZE_CHANGED:" + path.name)
        return data
    finally:
        os.close(fd)


class SnapshotStore:
    """Open an initialized single-coordinator research store.

    Public reads require a caller-owned durable anchor. The current chain must be
    equal to or descend from that exact acknowledged head. Thus a syntactically
    valid rollback of CURRENT to ZERO/old/forked history fails closed, while an
    ambiguous commit after pointer replacement can be recovered as a descendant.

    `admit` on commit is mandatory and must return exactly True after semantic
    validation. For A8 that means GDScript replay against trusted origin/hash
    anchors, not merely json.loads or a checksum. Tests of storage alone may use
    an explicit byte-fixture validator; those tests do not qualify biology.
    """

    def __init__(self, root: Path | str, *, fault: Callable[[str], None] | None = None):
        if fcntl is None or os.name != "posix":
            raise StoreError("LINUX_POSIX_STORE_REQUIRED")
        self.root = Path(root).absolute()
        if self.root.resolve(strict=True) != self.root or not self.root.is_dir():
            raise StoreError("TRUSTED_CANONICAL_DIRECTORY_REQUIRED")
        for name in ("blobs", "records"):
            p = self.root / name
            if p.is_symlink() or not p.is_dir():
                raise StoreError("STORE_LAYOUT:" + name)
        self.fault = fault or (lambda _stage: None)
        # A missing pointer is corruption, NEVER an implicit empty/old world.
        _read(self.root / "CURRENT", 65)
        _read(self.root / "LOCK", 0)

    @classmethod
    def initialize(cls, root: Path | str) -> "SnapshotStore":
        if fcntl is None or os.name != "posix":
            raise StoreError("LINUX_POSIX_STORE_REQUIRED")
        p = Path(root).absolute()
        if p.parent.resolve(strict=True) != p.parent:
            raise StoreError("TRUSTED_CANONICAL_PARENT_REQUIRED")
        p.mkdir(mode=0o700, exist_ok=False)  # Never reset an existing store.
        (p / "blobs").mkdir(mode=0o700)
        (p / "records").mkdir(mode=0o700)
        for name, data in (("LOCK", b""), ("CURRENT", (ZERO + "\n").encode("ascii"))):
            fd = os.open(p / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            try:
                with os.fdopen(fd, "wb", closefd=False) as stream:
                    stream.write(data)
                    stream.flush()
                    os.fsync(fd)
            finally:
                os.close(fd)
        _sync_dir(p / "blobs")
        _sync_dir(p / "records")
        _sync_dir(p)
        _sync_dir(p.parent)
        return cls(p)

    @contextmanager
    def _locked(self) -> Iterator[None]:
        fd = os.open(self.root / "LOCK", os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                raise StoreError("INVALID_LOCK")
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)  # Releases the advisory lock even after exceptions.

    def _load(self) -> tuple[dict, bytes | None, dict[str, dict]]:
        raw = _read(self.root / "CURRENT", 65)
        if len(raw) != 65 or raw[-1:] != b"\n":
            raise StoreError("CURRENT_CORRUPT")
        tip = raw[:-1].decode("ascii", errors="strict")
        if HASH.fullmatch(tip) is None:
            raise StoreError("CURRENT_CORRUPT")
        lineage: dict[str, dict] = {ZERO: genesis_anchor()}
        if tip == ZERO:
            # Orphan immutable objects from a crash before pointer publication are
            # legal. Only the external acknowledged anchor decides whether ZERO is
            # still admissible; never infer acknowledgement from object presence.
            return genesis_anchor(), None, lineage
        cursor = tip
        expected_sequence: int | None = None
        seen: set[str] = set()
        head: dict = {}
        payload: bytes | None = None
        while cursor != ZERO:
            if cursor in seen or len(seen) >= MAX_RECORDS:
                raise StoreError("CHAIN_CYCLE_OR_BUDGET")
            seen.add(cursor)
            encoded = _read(self.root / "records" / (cursor + ".json"), 4096)
            if digest(encoded) != cursor:
                raise StoreError("RECORD_HASH")
            record = json.loads(encoded)
            fields = {"schema", "sequence", "previous", "snapshot_sha256", "snapshot_bytes"}
            if not isinstance(record, dict) or set(record) != fields or _json(record) != encoded:
                raise StoreError("RECORD_ENCODING")
            if record["schema"] != RECORD_SCHEMA or type(record["sequence"]) is not int or not 1 <= record["sequence"] <= MAX_RECORDS:
                raise StoreError("RECORD_SEQUENCE")
            for key in ("previous", "snapshot_sha256"):
                if not isinstance(record[key], str) or HASH.fullmatch(record[key]) is None:
                    raise StoreError("RECORD_REFERENCE")
            if type(record["snapshot_bytes"]) is not int or not 0 < record["snapshot_bytes"] <= MAX_SNAPSHOT_BYTES:
                raise StoreError("RECORD_SIZE")
            if expected_sequence is not None and record["sequence"] != expected_sequence:
                raise StoreError("CHAIN_SEQUENCE")
            blob = _read(self.root / "blobs" / (record["snapshot_sha256"] + ".bin"), MAX_SNAPSHOT_BYTES)
            if digest(blob) != record["snapshot_sha256"] or len(blob) != record["snapshot_bytes"]:
                raise StoreError("SNAPSHOT_HASH_OR_SIZE")
            node = {"tip": cursor, "sequence": record["sequence"], "snapshot_sha256": record["snapshot_sha256"]}
            lineage[cursor] = node
            if not head:
                head = node.duplicate() if hasattr(node, "duplicate") else dict(node)
                payload = blob
            expected_sequence = record["sequence"] - 1
            cursor = record["previous"]
            if (cursor == ZERO) != (expected_sequence == 0):
                raise StoreError("CHAIN_TRUNCATED")
        return head, payload, lineage

    @staticmethod
    def _require_anchor(anchor: dict, head: dict, lineage: dict[str, dict]) -> None:
        exact = validate_anchor(anchor)
        witnessed = lineage.get(exact["tip"])
        if witnessed != exact or exact["sequence"] > head["sequence"]:
            raise StoreError("DURABLE_ANCHOR_ROLLBACK_OR_FORK")

    def load(self, anchor: dict) -> tuple[dict, bytes | None]:
        """Read hash/chain-checked bytes at/after an external durable anchor.

        This proves storage continuity only. The returned bytes still require A8
        semantic admission before use as ecology/executor state.
        """
        exact = validate_anchor(anchor)
        with self._locked():
            head, payload, lineage = self._load()
            self._require_anchor(exact, head, lineage)
            return head, payload

    def _usage(self) -> int:
        total = 0
        count = 0
        for directory in (self.root, self.root / "blobs", self.root / "records"):
            for p in directory.iterdir():
                if p in (self.root / "blobs", self.root / "records"):
                    continue
                info = p.lstat()
                if not stat.S_ISREG(info.st_mode):
                    raise StoreError("UNEXPECTED_STORE_ENTRY")
                total += info.st_size
                count += 1
        if count > 4 * MAX_RECORDS + 32:
            raise StoreError("STORE_FILE_BUDGET")
        return total

    def _temp(self, directory: Path, data: bytes) -> Path:
        fd, name = tempfile.mkstemp(prefix=".pending.", dir=directory)
        p = Path(name)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            return p
        except BaseException:
            p.unlink(missing_ok=True)
            raise

    def _install(self, path: Path, data: bytes, stage: str) -> None:
        temp = self._temp(path.parent, data)
        try:
            self.fault(stage + "_staged")
            try:
                os.link(temp, path, follow_symlinks=False)  # Atomic no-overwrite publication.
            except FileExistsError:
                if _read(path, len(data)) != data:
                    raise StoreError("IMMUTABLE_OBJECT_CONFLICT")
            temp.unlink()
            _sync_dir(path.parent)
            self.fault(stage + "_durable")
        finally:
            temp.unlink(missing_ok=True)

    def commit(self, expected_anchor: dict, data: bytes, admit: Callable[[bytes], bool]) -> dict:
        """Publish one semantically admitted snapshot, or change no durable tip.

        `expected_anchor` is the caller's last durable acknowledgement and must
        exactly equal CURRENT for CAS. An exception after pointer replacement is
        ambiguous acknowledgement: call load(expected_anchor), which accepts a
        valid descendant but rejects rollback/fork below that durable anchor.
        """
        expected = validate_anchor(expected_anchor)
        if type(data) is not bytes or not 0 < len(data) <= MAX_SNAPSHOT_BYTES:
            raise StoreError("SNAPSHOT_BYTE_BUDGET")
        if not callable(admit) or admit(data) is not True:
            raise StoreError("SEMANTIC_ADMISSION_REQUIRED")
        with self._locked():
            current, previous_data, _lineage = self._load()
            if expected != current:
                raise Conflict("STALE_DURABLE_ANCHOR")
            if previous_data == data:
                return current
            if current["sequence"] >= MAX_RECORDS or self._usage() + 2 * len(data) + 8192 > MAX_DISK_BYTES:
                raise StoreError("STORE_CAPACITY_BUDGET")
            blob_hash = digest(data)
            self._install(self.root / "blobs" / (blob_hash + ".bin"), data, "blob")
            record = {"schema": RECORD_SCHEMA, "sequence": current["sequence"] + 1,
                      "previous": current["tip"], "snapshot_sha256": blob_hash, "snapshot_bytes": len(data)}
            encoded = _json(record)
            tip = digest(encoded)
            self._install(self.root / "records" / (tip + ".json"), encoded, "record")
            pointer = self._temp(self.root, (tip + "\n").encode("ascii"))
            try:
                self.fault("pointer_staged")
                os.replace(pointer, self.root / "CURRENT")
                self.fault("pointer_replaced")
                _sync_dir(self.root)
                self.fault("pointer_durable")
            finally:
                pointer.unlink(missing_ok=True)
            return {"tip": tip, "sequence": record["sequence"], "snapshot_sha256": blob_hash}
