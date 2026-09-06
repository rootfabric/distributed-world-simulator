"""SSRF_REDIRECT_AND_SIZE_GATES tests: offline, injected resolvers/redirectors."""

from __future__ import annotations

import pytest

from asset_fetch import gates as gates_mod

HOSTS = {"downloads.example.com"}
PUBLIC = ["93.184.216.34"]  # TEST-NET-3 is documentation, but not private


def dns(host):
    return {"downloads.example.com": PUBLIC}.get(host, [])


def test_valid_target_passes():
    gates_mod.validate_target(
        "https://downloads.example.com/a.bin",
        approved_hosts=HOSTS,
        resolver=dns,
    )


@pytest.mark.parametrize(
    ("url", "code"),
    [
        ("http://downloads.example.com/a.bin", "NON_HTTPS_TARGET"),
        ("ftp://downloads.example.com/a.bin", "NON_HTTPS_TARGET"),
        ("https://user:pw@downloads.example.com/a.bin", "CREDENTIALS_IN_URL"),
        ("https://downloads.example.com/a.bin#frag", "URL_STRUCTURE_SUSPICIOUS"),
        ("https:///a.bin", "NO_HOST"),
        ("https://evil.example.com/a.bin", "UNAPPROVED_HOST"),
        ("https://downloads.example.com:8443/a.bin", "FORBIDDEN_PORT"),
        ("https://127.0.0.1/a.bin", "UNAPPROVED_HOST"),
    ],
)
def test_static_target_rejections(url, code):
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.validate_target(url, approved_hosts=HOSTS, resolver=dns)
    assert excinfo.value.code == code


def test_private_ip_literal_is_rejected_even_if_approved():
    hosts = {"169.254.169.254"}  # cloud metadata endpoint
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.validate_target(
            "https://169.254.169.254/latest/meta-data",
            approved_hosts=hosts,
        )
    assert excinfo.value.code == "PRIVATE_ADDRESS_TARGET"


@pytest.mark.parametrize(
    "addr",
    [
        "10.1.2.3",
        "192.168.0.10",
        "172.16.5.4",
        "127.0.0.1",
        "169.254.169.254",
        "0.0.0.0",
        "fd00::1",
        "fe80::1",
        "::ffff:10.0.0.1",  # ipv4-mapped bypass attempt
    ],
)
def test_dns_rebinding_to_private_space_rejected(addr):
    def resolver(_host):
        return [addr]

    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.check_resolved_addresses("downloads.example.com", resolver)
    assert excinfo.value.code == "PRIVATE_ADDRESS_TARGET"


def test_mixed_public_and_private_answers_rejected():
    def resolver(_host):
        return ["93.184.216.34", "10.0.0.8"]

    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.check_resolved_addresses("downloads.example.com", resolver)
    assert excinfo.value.code == "PRIVATE_ADDRESS_TARGET"


def test_empty_and_failing_resolvers_are_typed_errors():
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.check_resolved_addresses("x", lambda _h: [])
    assert excinfo.value.code == "RESOLUTION_EMPTY"

    def boom(_h):
        raise OSError("dns down")

    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.check_resolved_addresses("x", boom)
    assert excinfo.value.code == "RESOLUTION_FAILED"


def test_declared_size_gate():
    base = dict(approved_hosts=HOSTS)
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.validate_target(
            "https://downloads.example.com/a.bin",
            declared_size_bytes=10**9,
            max_asset_bytes=1024,
            **base,
        )
    assert excinfo.value.code == "DECLARED_SIZE_ABOVE_CEILING"
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.validate_target(
            "https://downloads.example.com/a.bin",
            declared_size_bytes=0,
            max_asset_bytes=1024,
            **base,
        )
    assert excinfo.value.code == "DECLARED_SIZE_INVALID"
    # valid declared size passes
    gates_mod.validate_target(
        "https://downloads.example.com/a.bin",
        declared_size_bytes=512,
        max_asset_bytes=1024,
        **base,
    )


def test_redirect_chain_ok_same_host():
    hops = {
        "https://downloads.example.com/a.bin": "https://downloads.example.com/a-2.bin",
        "https://downloads.example.com/a-2.bin": None,
    }
    chain = gates_mod.resolve_redirect_chain(
        "https://downloads.example.com/a.bin",
        lambda url: hops.get(url),
        approved_hosts=HOSTS,
        resolver=dns,
    )
    assert chain.final_url == "https://downloads.example.com/a-2.bin"
    assert chain.hops == 1


def test_redirect_to_other_approved_host_ok():
    hosts = {"downloads.example.com", "mirror.example.org"}
    resolver = lambda h: {"downloads.example.com": ["93.184.216.34"], "mirror.example.org": ["93.184.216.35"]}.get(h, [])  # noqa: E731
    chain = gates_mod.resolve_redirect_chain(
        "https://downloads.example.com/a.bin",
        lambda url: "https://mirror.example.org/a.bin" if "example.com" in url else None,
        approved_hosts=hosts,
        resolver=resolver,
    )
    assert chain.final_url == "https://mirror.example.org/a.bin"


def test_redirect_to_unapproved_host_rejected():
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.resolve_redirect_chain(
            "https://downloads.example.com/a.bin",
            lambda url: "https://evil.example.net/a.bin",
            approved_hosts=HOSTS,
            resolver=dns,
        )
    assert excinfo.value.code == "UNAPPROVED_HOST"


def test_redirect_to_http_rejected():
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.resolve_redirect_chain(
            "https://downloads.example.com/a.bin",
            lambda url: "http://downloads.example.com/a.bin",
            approved_hosts=HOSTS,
            resolver=dns,
        )
    assert excinfo.value.code == "NON_HTTPS_TARGET"


def test_redirect_to_private_ip_rejected():
    hosts = {"downloads.example.com", "metadata.internal"}
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.resolve_redirect_chain(
            "https://downloads.example.com/a.bin",
            lambda url: "https://metadata.internal/x" if url.endswith("a.bin") else None,
            approved_hosts=hosts,
            resolver=lambda h: ["10.0.0.5"],
        )
    assert excinfo.value.code == "PRIVATE_ADDRESS_TARGET"


def test_redirect_loop_bounded():
    def loop(url):
        return "https://downloads.example.com/next.bin"

    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.resolve_redirect_chain(
            "https://downloads.example.com/a.bin",
            loop,
            approved_hosts=HOSTS,
            resolver=dns,
        )
    assert excinfo.value.code == "TOO_MANY_REDIRECTS"


def test_redirect_with_credentials_rejected():
    with pytest.raises(gates_mod.GateError) as excinfo:
        gates_mod.resolve_redirect_chain(
            "https://downloads.example.com/a.bin",
            lambda url: "https://user:pw@downloads.example.com/a.bin",
            approved_hosts=HOSTS,
            resolver=dns,
        )
    assert excinfo.value.code == "CREDENTIALS_IN_URL"
