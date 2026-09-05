"""WP-ASSET1: safe external asset fetch, immutable raw cache and security gates.

Public surface is intentionally small and typed. Everything here is
fail-closed: unknown input, unverifiable payload or unsafe network target
must produce a typed error, never a silent best-effort result.
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

__all__ = [
    "DEFAULT_MAX_ASSET_BYTES",
    "FetchContract",
    "FetchContractError",
    "FetchVerificationError",
    "VerifiedPayload",
    "contract_from_dict",
    "fetch_verified",
    "verify_payload",
]
