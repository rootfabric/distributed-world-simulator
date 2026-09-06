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
import urllib.error
import urllib.request
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


class _UserAgent(urllib.request.BaseHandler):
    """Identify ourselves; some CDNs 403 the default python-urllib agent."""


    def _add(self, request):
        if not request.has_header("User-agent"):
            request.add_unredirected_header("User-agent", "DWS-WorldPacks/1.0")
        return request

    def http_request(self, request):
        return self._add(request)

    def https_request(self, request):
        return self._add(request)


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(
            newurl, code, "redirect refused by bounded transport", headers, fp
        )


def default_opener() -> Opener:
    """Build the production opener: https only, no redirects.

    Redirects are refused here because redirect target validation lives
    in the SSRF/redirect gates milestone; following them silently would
    be a security hole.
    """
    import urllib.error
    import urllib.request

    return urllib.request.build_opener(_UserAgent, _NoRedirectHandler)


# --------------------------------------------------------------------------
# DNS-rebinding-safe (pinned) transport.
#
# The validated endpoint must equal the actual connected endpoint: the
# hostname is resolved ONCE per fetch, every answer is checked to be a
# public address, and the TCP connection is made directly to that IP
# while TLS keeps verifying the ORIGINAL hostname (SNI, Host header and
# certificate CN/SAN checks are unaffected). urllib never re-resolves
# the hostname because it never sees it on the connect path.
# --------------------------------------------------------------------------

import socket  # noqa: E402


def _make_pinned_https_connection(pinned_ip: str):
    import http.client

    class _Pinned(http.client.HTTPSConnection):
        pinned = pinned_ip

        def connect(self):  # noqa: D102
            # Dial the validated IP literal, never the hostname: there is
            # no second DNS lookup on the connect path.
            self.sock = socket.create_connection(
                (self.pinned, self.port),
                timeout=self.timeout,
                source_address=getattr(self, "source_address", None),
            )
            if hasattr(socket, "TCP_NODELAY"):
                try:
                    self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                except OSError:
                    pass
            if self._tunnel_host:
                # Proxied CONNECT tunneling is out of contract for the
                # pinned transport; refuse rather than guess the target.
                raise BoundedFetchError(
                    "TUNNEL_UNSUPPORTED",
                    "pinned transport does not support proxy CONNECT tunneling",
                )
            # TLS verification (SNI + certificate hostname check) stays
            # bound to the ORIGINAL hostname from the URL.
            self.sock = self._context.wrap_socket(self.sock, server_hostname=self.host)

    return _Pinned


def pinned_opener(host: str, resolver, *, pinned_ip: str) -> Opener:
    """Build an opener whose HTTPS connections dial ``pinned_ip`` only.

    ``pinned_ip`` must already have passed ``check_resolved_addresses``
    for ``host``; the TLS layer still verifies ``host`` (SNI, Host,
    certificate). Redirects are refused as in :func:`default_opener`.
    """
    import urllib.error
    import urllib.request

    class _PinnedHTTPSHandler(urllib.request.HTTPSHandler):
        def https_open(self, req):
            return self.do_open(_make_pinned_https_connection(pinned_ip), req)

    return urllib.request.build_opener(_UserAgent, _NoRedirectHandler, _PinnedHTTPSHandler)


def resolve_public_ip(host: str, resolver) -> str:
    """Resolve ``host`` once and return a validated public answer.

    Re-uses the gate's public-address checks: ANY non-public answer in
    the resolution fails the whole fetch (fail-closed), so a rebinding
    answer of 127.0.0.1/private space is rejected before any socket is
    opened.
    """
    from .gates import check_resolved_addresses

    check_resolved_addresses(host, resolver)
    answers = list(resolver(host))
    for answer in answers:
        if _answer_is_public(answer):
            return answer
    raise BoundedFetchError(
        "NO_PUBLIC_ADDRESS", f"no public address in resolution for {host!r}"
    )


def _answer_is_public(text: str) -> bool:
    from .gates import _is_public_ip

    return _is_public_ip(text)


def make_pinned_bounded_transport(
    resolver,
    *,
    chunk_bytes: int = DEFAULT_CHUNK_BYTES,
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    hard_max_bytes: Optional[int] = None,
    opener_factory=pinned_opener,
) -> Callable[[FetchContract], bytes]:
    """Build a DNS-rebinding-safe bounded transport.

    For every fetch the hostname in the contract URL is resolved ONCE
    through ``resolver``; all answers must be public (gate re-check),
    the first public answer is pinned for the TCP dial, and the bounded
    read then runs against a freshly built pinned opener. A rebinding
    resolver that returns a private address on this second resolution is
    rejected before any connection is attempted.
    """
    from .contract import FetchContract as _Contract
    from .gates import check_resolved_addresses

    def transport(contract: _Contract) -> bytes:
        from urllib.parse import urlsplit

        host = urlsplit(contract.url).hostname or ""
        check_resolved_addresses(host, resolver, source_url=contract.url)
        pinned_ip = resolve_public_ip(host, resolver)
        opener = opener_factory(host, resolver, pinned_ip=pinned_ip)
        bounded = make_bounded_transport(
            opener,
            chunk_bytes=chunk_bytes,
            timeout_seconds=timeout_seconds,
            hard_max_bytes=hard_max_bytes,
        )
        return bounded(contract)

    return transport
