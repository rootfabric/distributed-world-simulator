"""FETCH_CONTRACT: bounded fetch contract for WP-ASSET1.

A :class:`FetchContract` pins the exact expected identity of one asset:

- non-empty asset id and version,
- exact sha256 (lowercase hex, 64 chars),
- exact expected size in bytes,
- one approved source URL (https scheme, explicitly approved host).

``verify_payload`` / ``fetch_verified`` turn raw bytes into a
:class:`VerifiedPayload` only when every pinned expectation matches.
Any deviation raises a typed error with a machine-readable ``code``.

No network access happens in this module: the transport is injected, so
all behaviour is testable offline with negative fixtures.
"""

from __future__ import annotations

import hashlib
import os
import re
import tempfile
from dataclasses import dataclass
from typing import Callable, Mapping, Optional
from urllib.parse import urlsplit

# Hard global ceiling for a single asset payload. Contracts may declare a
# smaller expected size but never a larger one.
DEFAULT_MAX_ASSET_BYTES = 64 * 1024 * 1024

_ASSET_ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,127}$")
_VERSION_RE = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$")
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class FetchContractError(ValueError):
    """Typed contract construction/validation failure.

    ``code`` is a stable machine-readable identifier (see tests for the
    exact list). Fail-closed: nothing is fetched when this is raised.
    """

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


class FetchVerificationError(RuntimeError):
    """Typed payload verification failure (hash/size mismatch etc.)."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


@dataclass(frozen=True)
class FetchContract:
    """Immutable, fully pinned description of one fetchable asset."""

    asset_id: str
    version: str
    sha256: str
    expected_size_bytes: int
    url: str
    approved_hosts: frozenset

    def source_host(self) -> str:
        return urlsplit(self.url).hostname or ""


@dataclass(frozen=True)
class VerifiedPayload:
    """Bytes that satisfied every pinned expectation of their contract."""

    contract: FetchContract
    data: bytes
    sha256: str
    size_bytes: int
    temp_path: Optional[str]

    def dispose(self) -> None:
        if self.temp_path is not None:
            try:
                os.unlink(self.temp_path)
            except FileNotFoundError:
                pass


def contract_from_dict(
    raw: Mapping,
    *,
    approved_hosts: Optional[set] = None,
    max_asset_bytes: int = DEFAULT_MAX_ASSET_BYTES,
) -> FetchContract:
    """Validate and build a contract from plain data.

    Raises :class:`FetchContractError` with a specific code on any
    invalid or unpinned field. Fail-closed: an unknown or partially
    specified asset can never produce a contract.
    """
    if not isinstance(raw, Mapping):
        raise FetchContractError("CONTRACT_NOT_MAPPING", "contract payload must be a mapping")

    approved = frozenset(approved_hosts or ())

    asset_id = raw.get("asset_id")
    if not isinstance(asset_id, str) or not _ASSET_ID_RE.match(asset_id):
        raise FetchContractError(
            "INVALID_ASSET_ID",
            "asset_id must match " + _ASSET_ID_RE.pattern,
        )

    version = raw.get("version")
    if not isinstance(version, str) or not _VERSION_RE.match(version):
        raise FetchContractError(
            "INVALID_VERSION",
            "version must match " + _VERSION_RE.pattern,
        )

    sha256 = raw.get("sha256")
    if not isinstance(sha256, str):
        raise FetchContractError("INVALID_SHA256", "sha256 must be a lowercase hex string")
    normalized = sha256.strip().lower()
    if not _SHA256_RE.match(normalized):
        raise FetchContractError(
            "INVALID_SHA256",
            "sha256 must be exactly 64 lowercase hex characters",
        )

    size = raw.get("expected_size_bytes")
    if not isinstance(size, int) or isinstance(size, bool):
        raise FetchContractError(
            "INVALID_EXPECTED_SIZE",
            "expected_size_bytes must be an integer",
        )
    if size <= 0:
        raise FetchContractError("INVALID_EXPECTED_SIZE", "expected_size_bytes must be positive")
    if size > max_asset_bytes:
        raise FetchContractError(
            "EXPECTED_SIZE_ABOVE_CEILING",
            f"expected_size_bytes {size} exceeds ceiling {max_asset_bytes}",
        )

    url = raw.get("url")
    if not isinstance(url, str) or not url:
        raise FetchContractError("INVALID_SOURCE_URL", "url must be a non-empty string")
    parts = urlsplit(url)
    if parts.scheme != "https":
        raise FetchContractError(
            "NON_HTTPS_SOURCE",
            f"source scheme must be https, got {parts.scheme!r}",
        )
    host = parts.hostname
    if not host:
        raise FetchContractError("INVALID_SOURCE_URL", "source url has no host")
    if not approved:
        raise FetchContractError(
            "NO_APPROVED_HOSTS",
            "approved_hosts must be a non-empty set; implicit approval is forbidden",
        )
    if host not in approved:
        raise FetchContractError(
            "UNAPPROVED_SOURCE_HOST",
            f"source host {host!r} is not in the approved host set",
        )

    return FetchContract(
        asset_id=asset_id,
        version=version,
        sha256=normalized,
        expected_size_bytes=size,
        url=url,
        approved_hosts=approved,
    )


def verify_payload(
    contract: FetchContract, data: bytes, *, keep_temp_file: bool = False
) -> VerifiedPayload:
    """Verify raw bytes against a contract.

    Returns a :class:`VerifiedPayload` (optionally backed by a temp file)
    or raises :class:`FetchVerificationError` with a typed code.
    """
    if not isinstance(data, (bytes, bytearray)):
        raise FetchVerificationError("PAYLOAD_NOT_BYTES", "payload must be bytes")

    size = len(data)
    if size != contract.expected_size_bytes:
        raise FetchVerificationError(
            "SIZE_MISMATCH",
            f"expected {contract.expected_size_bytes} bytes, got {size}",
        )

    digest = hashlib.sha256(data).hexdigest()
    if digest != contract.sha256:
        raise FetchVerificationError(
            "HASH_MISMATCH",
            f"expected sha256 {contract.sha256}, got {digest}",
        )

    temp_path: Optional[str] = None
    if keep_temp_file:
        fd, temp_path = tempfile.mkstemp(
            prefix=f"wp-asset-{contract.asset_id}-", suffix=".verified"
        )
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)

    return VerifiedPayload(
        contract=contract,
        data=bytes(data),
        sha256=digest,
        size_bytes=size,
        temp_path=temp_path,
    )


def fetch_verified(
    contract: FetchContract,
    transport: Callable[[FetchContract], bytes],
    *,
    keep_temp_file: bool = False,
) -> VerifiedPayload:
    """Fetch via an injected transport and verify the result.

    The transport receives the contract and must return the raw payload
    bytes (bounded reading is the transport's responsibility, see the
    https module). Verification is always performed afterwards here.
    """
    try:
        data = transport(contract)
    except FetchVerificationError:
        raise
    except Exception as exc:  # transport failures are surfaced as-is
        raise FetchVerificationError(
            "TRANSPORT_ERROR", f"transport failed: {exc}"
        ) from exc
    return verify_payload(contract, data, keep_temp_file=keep_temp_file)
