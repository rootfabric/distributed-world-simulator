"""WP-ASSET1: safe external asset fetch, immutable raw cache and security gates.

Public surface is intentionally small and typed. Everything here is
fail-closed: unknown input, unverifiable payload or unsafe network target
must produce a typed error, never a silent best-effort result.

Production entrypoint: :func:`obtain_safe` (alias ``prepare_raw_asset``).
It always runs the full gate chain (approved source, DNS/target
validation, redirect policy, DNS-pinned bounded transport, size/hash
verification, content-addressed raw cache) and cannot reach a transport
when a gate fails. The low-level ``pipeline.obtain`` is an explicitly
documented ``unsafe_low_level`` primitive for tests and for code that
has already run the gates itself.
"""

from .contract import (
    DEFAULT_MAX_ASSET_BYTES,
    FetchContract,
    FetchContractError,
    FetchVerificationError,
    VerifiedPayload,
    contract_from_dict,
    fetch_verified,
    verify_payload,
)
from .pipeline import obtain_safe, prepare_raw_asset

__all__ = [
    "DEFAULT_MAX_ASSET_BYTES",
    "FetchContract",
    "FetchContractError",
    "FetchVerificationError",
    "VerifiedPayload",
    "contract_from_dict",
    "fetch_verified",
    "verify_payload",
    "obtain_safe",
    "prepare_raw_asset",
]
