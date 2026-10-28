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

import dataclasses
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from .cache import RawCacheError, RawContentAddressableCache
from .contract import (
    DEFAULT_MAX_ASSET_BYTES,
    FetchContract,
    FetchVerificationError,
    verify_payload,
)
from .https import DEFAULT_CHUNK_BYTES, DEFAULT_TIMEOUT_SECONDS


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
    """UNSAFE LOW-LEVEL cache-first obtain (arbitrary injected transport).

    This primitive exists for tests and for code that has ALREADY run
    the full gate chain itself. It performs NO approved-source policy,
    NO DNS/target validation, NO redirect policy and NO pinning.
    Production code must use :func:`obtain_safe` (alias
    :func:`prepare_raw_asset`), which cannot reach a transport unless
    every gate passes.
    """

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


def obtain_safe(
    contract,
    cache: RawContentAddressableCache,
    *,
    approved_hosts: set,
    resolver,
    redirector=None,
    max_asset_bytes: int = DEFAULT_MAX_ASSET_BYTES,
    chunk_bytes: int = DEFAULT_CHUNK_BYTES,
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    hard_max_bytes: Optional[int] = None,
    transport_factory=None,
) -> PipelineResult:
    """Single SAFE production entrypoint for raw asset acquisition.

    Always executes the full chain, fail-closed, in this order:

        contract (validated construction or FetchContract instance)
        -> approved-source policy + DNS/target validation + size gates
        -> redirect policy (every hop fully revalidated; bounded hops)
        -> DNS-pinned bounded transport (validated endpoint == connected
           endpoint, TLS hostname verification preserved)
        -> size/hash verification of the payload
        -> immutable content-addressed raw cache

    The transport is built internally via
    ``https.make_pinned_bounded_transport`` (or ``transport_factory`` for
    tests, which still receives the validated contract and cannot be
    reached when a gate fails). Cache reuse (offline path) never invokes
    the transport.
    """
    from .contract import contract_from_dict
    from .gates import resolve_redirect_chain, validate_target

    if not isinstance(contract, FetchContract):
        contract = contract_from_dict(
            contract, approved_hosts=approved_hosts, max_asset_bytes=max_asset_bytes
        )

    # Gate 1..2: approved-source policy + DNS/target validation + size.
    validate_target(
        contract.url,
        approved_hosts=approved_hosts,
        resolver=resolver,
        max_asset_bytes=max_asset_bytes,
        declared_size_bytes=contract.expected_size_bytes,
    )

    # Gate 3: redirect policy (each hop revalidated by resolve_redirect_chain).
    final_url = contract.url
    if redirector is not None:
        chain = resolve_redirect_chain(
            contract.url,
            redirector,
            approved_hosts=approved_hosts,
            resolver=resolver,
        )
        final_url = chain.final_url
        if final_url != contract.url:
            contract = dataclasses.replace(contract, url=final_url)

    # Gate 4: bounded, DNS-pinned transport.
    if transport_factory is None:
        from .https import make_pinned_bounded_transport

        transport = make_pinned_bounded_transport(
            resolver,
            chunk_bytes=chunk_bytes,
            timeout_seconds=timeout_seconds,
            hard_max_bytes=hard_max_bytes,
        )
    else:
        transport = transport_factory

    # Gate 5..6 happen inside obtain/verify_payload/cache.
    return obtain(contract, cache, transport)


# Documented production alias for the same safe entrypoint.
prepare_raw_asset = obtain_safe


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
