"""OFFLINE_REUSE_AND_CORRUPTION_RECOVERY for WP-ASSET1.

Cache-first pipeline with exactly one bounded refetch attempt on
detected cache corruption:

    get_verified(contract.sha256)
      ├─ hit   → return cached bytes, transport NEVER invoked (offline)
      ├─ miss  → transport once → verify → put_verified → return
      └─ corrupt → quarantine bad blob → refetch once → verify →
                   replace → return; second corruption or a failing
                   refetch is a typed failure

Everything is offline-testable: transport is injected.
"""

from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from .cache import RawCacheError, RawContentAddressableCache
from .contract import FetchContract, FetchVerificationError, verify_payload


class PipelineError(RuntimeError):
    """Typed cache-first pipeline failure."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


@dataclass(frozen=True)
class PipelineResult:
    data: bytes
    sha256: str
    source: str  # "cache" | "network" | "recovered"
    blob_path: Path


def obtain(
    contract: FetchContract,
    cache: RawContentAddressableCache,
    transport: Callable[[FetchContract], bytes],
) -> PipelineResult:
    """Cache-first obtain with offline reuse and corruption recovery."""

    def fetch_and_store() -> PipelineResult:
        try:
            verified = verify_payload(contract, transport(contract))
        except FetchVerificationError as exc:
            raise PipelineError("FETCH_FAILED", str(exc)) from exc
        except Exception as exc:
            raise PipelineError("FETCH_FAILED", f"transport failed: {exc}") from exc
        try:
            cache.put_verified(verified)
        except RawCacheError as exc:
            raise PipelineError("CACHE_WRITE_FAILED", str(exc)) from exc
        return PipelineResult(
            data=verified.data,
            sha256=verified.sha256,
            source="network",
            blob_path=cache.blob_path(verified.sha256),
        )

    # 1. Pure offline reuse: cache hit must not invoke the transport.
    if cache.has(contract.sha256):
        try:
            cached = cache.get_verified(contract.sha256)
        except RawCacheError as exc:
            if exc.code != "CACHE_CORRUPT":
                raise PipelineError("CACHE_READ_FAILED", str(exc)) from exc
            # 2. Corruption detected: quarantine and refetch exactly once.
            _quarantine(cache, contract.sha256)
            try:
                recovered = fetch_and_store()
            except PipelineError as fail:
                raise PipelineError("RECOVERY_FAILED", str(fail)) from fail
            recovered = PipelineResult(
                data=recovered.data,
                sha256=recovered.sha256,
                source="recovered",
                blob_path=recovered.blob_path,
            )
            return recovered
        return PipelineResult(
            data=cached.data,
            sha256=cached.sha256,
            source="cache",
            blob_path=cached.blob_path,
        )

    # 3. Cache miss: single bounded fetch.
    return fetch_and_store()


def _quarantine(cache: RawContentAddressableCache, sha256: str) -> Path:
    """Move a corrupt blob out of the blobs tree (never delete blindly)."""
    blob = cache.blob_path(sha256)
    if not blob.exists():
        raise PipelineError("QUARANTINE_SOURCE_MISSING", f"cannot quarantine missing {blob}")
    quarantine_dir = cache.root / "quarantine"
    quarantine_dir.mkdir(parents=True, exist_ok=True)
    target = quarantine_dir / f"{sha256}.corrupt"
    try:
        os.chmod(blob, 0o644)  # best-effort clear read-only bit before move
    except OSError:
        pass
    shutil.move(str(blob), str(target))
    return target
