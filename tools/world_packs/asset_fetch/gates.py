"""SSRF_REDIRECT_AND_SIZE_GATES for WP-ASSET1.

Fail-closed network-target validation:

1. ``validate_target`` — static URL checks: https only, no userinfo
   (credentials in URL), no fragment tricks, approved host, port
   restrictions, and no literal private/loopback/link-local IP literal.
2. ``check_resolved_addresses`` — DNS-level SSRF check: every address
   the resolver returns for the host must be public. The resolver is
   injectable so tests never perform real DNS.
3. ``validate_redirect`` — a redirect target must itself pass the same
   static + resolved checks; redirect chains are bounded by a hop
   limit and each hop is revalidated.

Size gates live in https.py (bounded reads); this module adds the
DECLARED size cross-check used before any byte is read.
"""

from __future__ import annotations

import ipaddress
from dataclasses import dataclass
from typing import Callable, Optional, Sequence
from urllib.parse import urlsplit

Redirector = Callable[[str], Optional[str]]
Resolver = Callable[[str], Sequence[str]]

DEFAULT_MAX_REDIRECTS = 3
ALLOWED_PORTS = (443,)


class GateError(RuntimeError):
    """Typed SSRF/redirect/size gate failure."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


def _is_public_ip(text: str) -> bool:
    try:
        addr = ipaddress.ip_address(text)
    except ValueError:
        return False
    if (
        addr.is_private
        or addr.is_loopback
        or addr.is_link_local
        or addr.is_reserved
        or addr.is_multicast
        or addr.is_unspecified
    ):
        return False
    # ipv4-mapped ipv6 (::ffff:10.0.0.1) must not bypass the checks.
    if isinstance(addr, ipaddress.IPv6Address) and addr.ipv4_mapped is not None:
        return _is_public_ip(str(addr.ipv4_mapped))
    return True


def check_resolved_addresses(
    host: str, resolver: Resolver, *, source_url: str = ""
) -> None:
    """Refuse hosts whose DNS resolves (fully) to non-public addresses."""
    try:
        answers = list(resolver(host))
    except Exception as exc:
        raise GateError(
            "RESOLUTION_FAILED", f"resolver failed for {host!r}: {exc}"
        ) from exc
    if not answers:
        raise GateError("RESOLUTION_EMPTY", f"resolver returned no addresses for {host!r}")
    for answer in answers:
        if not _is_public_ip(answer):
            raise GateError(
                "PRIVATE_ADDRESS_TARGET",
                f"{host!r} resolves to non-public address {answer}"
                + (f" via {source_url}" if source_url else ""),
            )


def validate_target(
    url: str,
    *,
    approved_hosts: set,
    resolver: Optional[Resolver] = None,
    max_asset_bytes: Optional[int] = None,
    declared_size_bytes: Optional[int] = None,
) -> None:
    """Full pre-flight validation of one fetch/redirect target."""
    parts = urlsplit(url)
    if parts.scheme != "https":
        raise GateError("NON_HTTPS_TARGET", f"scheme must be https, got {parts.scheme!r}")
    if parts.username or parts.password:
        raise GateError("CREDENTIALS_IN_URL", "userinfo in source URL is forbidden")
    if parts.fragment or "@" in (parts.netloc or ""):
        raise GateError("URL_STRUCTURE_SUSPICIOUS", "fragment or '@' in authority is forbidden")
    host = parts.hostname
    if not host:
        raise GateError("NO_HOST", "target has no host")
    if host not in approved_hosts:
        raise GateError("UNAPPROVED_HOST", f"host {host!r} is not approved")
    if parts.port is not None and parts.port not in ALLOWED_PORTS:
        raise GateError("FORBIDDEN_PORT", f"port {parts.port} is not allowed")
    # Literal IP host: must be public (and normally also approved by name).
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        if not _is_public_ip(host):
            raise GateError("PRIVATE_ADDRESS_TARGET", f"host literal {host!r} is not public")
    if resolver is not None:
        check_resolved_addresses(host, resolver, source_url=url)
    if declared_size_bytes is not None and max_asset_bytes is not None:
        if declared_size_bytes > max_asset_bytes:
            raise GateError(
                "DECLARED_SIZE_ABOVE_CEILING",
                f"declared size {declared_size_bytes} exceeds ceiling {max_asset_bytes}",
            )
        if declared_size_bytes <= 0:
            raise GateError("DECLARED_SIZE_INVALID", "declared size must be positive")


@dataclass(frozen=True)
class RedirectChain:
    """Result of following a bounded, fully revalidated redirect chain."""

    final_url: str
    hops: int


def resolve_redirect_chain(
    start_url: str,
    redirector: Redirector,
    *,
    approved_hosts: set,
    resolver: Optional[Resolver] = None,
    max_redirects: int = DEFAULT_MAX_REDIRECTS,
) -> RedirectChain:
    """Follow redirects only while every hop passes all gates.

    ``redirector(url)`` returns the next Location (or None for "no
    redirect"). Each hop: bound the chain, then ``validate_target`` on
    the new URL with the same approved hosts and resolver.
    """
    current = start_url
    # The start URL must itself be valid.
    validate_target(current, approved_hosts=approved_hosts, resolver=resolver)
    hops = 0
    while True:
        nxt = redirector(current)
        if nxt is None:
            return RedirectChain(final_url=current, hops=hops)
        hops += 1
        if hops > max_redirects:
            raise GateError(
                "TOO_MANY_REDIRECTS",
                f"more than {max_redirects} redirects",
            )
        validate_target(nxt, approved_hosts=approved_hosts, resolver=resolver)
        current = nxt
