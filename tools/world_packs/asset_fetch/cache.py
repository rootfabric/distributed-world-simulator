"""RAW_CONTENT_ADDRESSABLE_CACHE: immutable sha256-addressed raw cache.

Layout under a caller-provided cache root (never inside Git):

    <root>/blobs/<sha[:2]>/<sha256>      immutable raw payload (write-once)
    <root>/meta/<sha[:2]>/<sha256>.json  provenance sidecar

Invariants:

- a blob file is written at most once; rewriting a different byte
  stream under an existing address is REFUSED (IMMUTABILITY_VIOLATION);
- ``put`` recomputes sha256 of the bytes it stores and never trusts a
  caller-provided digest for addressing without verification;
- ``get`` re-verifies the stored blob before returning it; corruption
  on disk yields a typed CACHE_CORRUPT error, never silent bad data;
- sidecar metadata records asset_id/version/url for offline audit.
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .contract import FetchContract, VerifiedPayload


class RawCacheError(RuntimeError):
    """Typed raw-cache failure."""

    def __init__(self, code: str, message: str, *, sha256: str = "") -> None:
        super().__init__(f"{code}: {message}")
        self.code = code
        self.sha256 = sha256


@dataclass(frozen=True)
class CachedRaw:
    sha256: str
    size_bytes: int
    blob_path: Path
    meta_path: Optional[Path]
    data: bytes


def _sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class RawContentAddressableCache:
    def __init__(self, root: Path) -> None:
        self.root = Path(root)
        self.blobs_dir = self.root / "blobs"
        self.meta_dir = self.root / "meta"
        self._initialized = False

    def initialize(self) -> None:
        self.blobs_dir.mkdir(parents=True, exist_ok=True)
        self.meta_dir.mkdir(parents=True, exist_ok=True)
        self._initialized = True

    def _require_initialized(self) -> None:
        if not self._initialized and not (self.blobs_dir.is_dir() and self.meta_dir.is_dir()):
            raise RawCacheError("CACHE_NOT_INITIALIZED", f"cache root not initialized: {self.root}")

    def blob_path(self, sha256: str) -> Path:
        return self.blobs_dir / sha256[:2] / sha256

    def meta_path(self, sha256: str) -> Path:
        return self.meta_dir / sha256[:2] / f"{sha256}.json"

    def has(self, sha256: str) -> bool:
        return self.blob_path(sha256).is_file()

    def put_verified(self, payload: VerifiedPayload, *, metadata: Optional[dict] = None) -> CachedRaw:
        """Store a verified payload immutably (write-once)."""
        self._require_initialized()
        digest = _sha256_of(payload.data)
        if digest != payload.sha256 or digest != payload.contract.sha256:
            raise RawCacheError(
                "ADDRESS_MISMATCH",
                f"payload digest {digest} does not match verified digest {payload.sha256}",
                sha256=digest,
            )

        blob = self.blob_path(digest)
        blob.parent.mkdir(parents=True, exist_ok=True)
        if blob.exists():
            existing = blob.read_bytes()
            if existing == payload.data:
                # Idempotent re-put of identical bytes is allowed.
                self._write_meta(digest, payload.contract, metadata, overwrite=False)
                return CachedRaw(
                    sha256=digest,
                    size_bytes=len(payload.data),
                    blob_path=blob,
                    meta_path=self.meta_path(digest),
                    data=payload.data,
                )
            raise RawCacheError(
                "IMMUTABILITY_VIOLATION",
                f"blob {digest} already exists with different content",
                sha256=digest,
            )

        # Write-once via exclusive create, then flush to disk.
        fd = os.open(blob, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(payload.data)
                handle.flush()
                os.fsync(handle.fileno())
        except FileExistsError:
            raise RawCacheError(
                "IMMUTABILITY_VIOLATION",
                f"blob {digest} appeared concurrently with different content",
                sha256=digest,
            )
        self._write_meta(digest, payload.contract, metadata, overwrite=False)
        return CachedRaw(
            sha256=digest,
            size_bytes=len(payload.data),
            blob_path=blob,
            meta_path=self.meta_path(digest),
            data=payload.data,
        )

    def _write_meta(
        self, digest: str, contract: FetchContract, metadata: Optional[dict], *, overwrite: bool
    ) -> None:
        meta = self.meta_path(digest)
        if meta.exists() and not overwrite:
            return
        meta.parent.mkdir(parents=True, exist_ok=True)
        record = {
            "schema": "dws.world_packs.raw_cache_meta.v1",
            "sha256": digest,
            "asset_id": contract.asset_id,
            "version": contract.version,
            "source_url": contract.url,
            "size_bytes": contract.expected_size_bytes,
            "extra": metadata or {},
        }
        tmp = meta.with_suffix(".tmp")
        tmp.write_text(json.dumps(record, indent=2, sort_keys=True), encoding="utf-8")
        os.replace(tmp, meta)

    def get_verified(self, sha256: str) -> CachedRaw:
        """Read a blob, re-verifying its digest on every read."""
        self._require_initialized()
        blob = self.blob_path(sha256)
        if not blob.is_file():
            raise RawCacheError("CACHE_MISS", f"no blob for {sha256}", sha256=sha256)
        data = blob.read_bytes()
        actual = _sha256_of(data)
        if actual != sha256:
            raise RawCacheError(
                "CACHE_CORRUPT",
                f"blob {sha256} hashes to {actual}",
                sha256=sha256,
            )
        return CachedRaw(
            sha256=sha256,
            size_bytes=len(data),
            blob_path=blob,
            meta_path=self.meta_path(sha256) if self.meta_path(sha256).is_file() else None,
            data=data,
        )
