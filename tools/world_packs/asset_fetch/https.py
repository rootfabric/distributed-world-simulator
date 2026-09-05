"""BOUNDED_HTTPS: bounded streaming HTTPS transport for WP-ASSET1.

Design constraints:

- stdlib only (urllib.request);
- streaming reads with a hard byte ceiling: the connection is aborted as
  soon as the payload exceeds the ceiling, so a hostile server cannot
  exhaust memory or disk;
- explicit connect/read timeout;
- transport is a callable built from an injectable ``opener`` so tests
  never touch the network;
- redirects are NOT followed here (redirect policy belongs to the SSRF
  gates milestone);
- error paths produce typed codes reused by the contract layer.
"""

from __future__ import annotations

import hashlib
from typing import Callable, Optional, Protocol

from .contract import FetchContract, FetchVerificationError

DEFAULT_CHUNK_BYTES = 64 * 1024
DEFAULT_TIMEOUT_SECONDS = 15.0
MAX_TIMEOUT_SECONDS = 120.0


class OpenedResponse(Protocol):
    """Minimal response surface the bounded reader needs."""

    def read(self, amount: int = -1) -> bytes: ...

    def close(self) -> None: ...


class Opener(Protocol):
    """Minimal opener surface (urllib.request.OpenerDirector fits)."""

    def open(self, url: str, timeout: float = ...) -> OpenedResponse: ...


class BoundedFetchError(RuntimeError):
    """Typed bounded-transport failure."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


def make_bounded_transport(
    opener: Opener,
    *,
    chunk_bytes: int = DEFAULT_CHUNK_BYTES,
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    hard_max_bytes: Optional[int] = None,
) -> Callable[[FetchContract], bytes]:
    """Build a transport closure honouring the contract's size bound.

    The transport reads at most ``effective_max`` bytes where

        effective_max = contract.expected_size_bytes

    plus one extra byte probe: if the server sends even one byte more
    than pinned, SIZE_EXCEEDED aborts the transfer. An optional global
    ``hard_max_bytes`` can only tighten, never loosen, that bound.
    """
    if chunk_bytes <= 0:
        raise ValueError("chunk_bytes must be positive")
    if timeout_seconds <= 0 or timeout_seconds > MAX_TIMEOUT_SECONDS:
        raise ValueError(f"timeout_seconds must be in (0, {MAX_TIMEOUT_SECONDS}]")

    def transport(contract: FetchContract) -> bytes:
        limit = contract.expected_size_bytes
        if hard_max_bytes is not None:
            limit = min(limit, hard_max_bytes)
        try:
            response = opener.open(contract.url, timeout=timeout_seconds)
        except Exception as exc:
            raise BoundedFetchError(
                "OPEN_FAILED", f"failed to open {contract.url}: {exc}"
            ) from exc
        try:
            chunks: list[bytes] = []
            total = 0
            while True:
                wanted = min(chunk_bytes, limit + 1 - total)
                if wanted <= 0:
                    # Already read limit+1 probe byte: too big.
                    raise BoundedFetchError(
                        "SIZE_EXCEEDED",
                        f"payload exceeds pinned size {contract.expected_size_bytes}",
                    )
                chunk = response.read(wanted)
                if not chunk:
                    break
                total += len(chunk)
                chunks.append(chunk)
                if total > limit:
                    raise BoundedFetchError(
                        "SIZE_EXCEEDED",
                        f"payload exceeds pinned size {contract.expected_size_bytes}",
                    )
            data = b"".join(chunks)
        except BoundedFetchError:
            raise
        except Exception as exc:
            raise BoundedFetchError("READ_FAILED", f"bounded read failed: {exc}") from exc
        finally:
            try:
                response.close()
            except Exception:
                pass
        if len(data) != contract.expected_size_bytes:
            raise BoundedFetchError(
                "SIZE_SHORT",
                f"payload truncated: expected {contract.expected_size_bytes}, got {len(data)}",
            )
        return data

    return transport


def digest_of(data: bytes) -> str:
    """Convenience sha256 helper (used by cache and evidence layers)."""
    return hashlib.sha256(data).hexdigest()


def default_opener() -> Opener:
    """Build the production opener: https only, no redirects.

    Redirects are refused here because redirect target validation lives
    in the SSRF/redirect gates milestone; following them silently would
    be a security hole.
    """
    import urllib.error
    import urllib.request

    class _NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            raise urllib.error.HTTPError(
                newurl, code, "redirect refused by bounded transport", headers, fp
            )

    return urllib.request.build_opener(_NoRedirect)
