"""R2 security repair regression for WP-ASSET1 (adversarial fixtures).

Covers the four required security fixes from the independent R2 review:

1. DNS rebinding / TOCTOU — validated endpoint == connected endpoint.
2. Single safe production entrypoint — gates cannot be bypassed.
3. Malformed URL typing — no raw ValueError from ``urlsplit(...).port``.
4. Archive collision / special-file policy — refusal before extraction.
"""
from __future__ import annotations

import io
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest

from asset_fetch import (
    FetchContractError,
    contract_from_dict,
    obtain_safe,
    prepare_raw_asset,
)
from asset_fetch import pipeline as pipeline_mod
from asset_fetch import https as https_mod
from asset_fetch.archive import (
    ArchiveSafetyError,
    extract_tar_safe,
    extract_zip_safe,
    scan_tar,
    scan_zip,
)
from asset_fetch.cache import RawContentAddressableCache
from asset_fetch.gates import GateError, validate_target
from asset_fetch.https import _make_pinned_https_connection, make_pinned_bounded_transport

APPROVED = {"example.org"}


def contract_dict(url="https://example.org/file.bin", **overrides):
    payload = {
        "asset_id": "test-asset",
        "version": "1.0.0",
        "sha256": "a" * 64,
        "expected_size_bytes": 4,
        "url": url,
    }
    payload.update(overrides)
    return payload


# ------------------------------------------------------------------ FIX 1


class RebindingResolver:
    """First answer public (gate passes), later answers private."""

    def __init__(self, first=("93.184.216.34",), later=("127.0.0.1",)):
        self.first = list(first)
        self.later = list(later)
        self.calls = 0

    def __call__(self, host):
        self.calls += 1
        if self.calls == 1:
            return list(self.first)
        return list(self.later)


def test_rebinding_second_answer_private_never_connects():
    resolver = RebindingResolver()
    opened = []

    def opener_factory(host, resolver, *, pinned_ip):
        opened.append(pinned_ip)

        class _Opener:
            def open(self, url, timeout=...):
                opened.append("OPENED")
                raise AssertionError("must not connect")

        return _Opener()

    transport = make_pinned_bounded_transport(resolver, opener_factory=opener_factory)
    contract = contract_from_dict(contract_dict(), approved_hosts=APPROVED)
    with pytest.raises(GateError, match="PRIVATE_ADDRESS_TARGET"):
        transport(contract)
    assert opened == []  # no opener was ever built, no connection attempted


def test_pinned_connection_dials_validated_ip_with_hostname_tls(monkeypatch):
    dialed = []

    def fake_create_connection(address, timeout=None, source_address=None):
        dialed.append(address)

        class FakeSocket:
            def setsockopt(self, *args, **kwargs):
                pass

        return FakeSocket()

    monkeypatch.setattr(https_mod.socket, "create_connection", fake_create_connection)

    wrapped = {}

    class FakeContext:
        def wrap_socket(self, sock, server_hostname=None):
            wrapped["server_hostname"] = server_hostname
            return sock

    conn_cls = _make_pinned_https_connection("93.184.216.34")
    conn = conn_cls("example.org", 443, timeout=5)
    conn._context = FakeContext()
    conn.connect()
    assert dialed == [("93.184.216.34", 443)]  # dials the pinned IP, not the host
    assert wrapped["server_hostname"] == "example.org"  # TLS keeps original hostname


def test_gate_pass_then_transport_revalidation_rejects_rebind():
    resolver = RebindingResolver()  # gate call would use the public answer
    # Gate itself passes with the first (public) answer...
    validate_target("https://example.org/file.bin", approved_hosts=APPROVED, resolver=resolver)
    assert resolver.calls == 1
    # ...but the pinned transport re-resolves and rejects the private rebind.
    transport = make_pinned_bounded_transport(resolver, opener_factory=lambda *a, **k: pytest.fail("no opener"))
    contract = contract_from_dict(contract_dict(), approved_hosts=APPROVED)
    with pytest.raises(GateError, match="PRIVATE_ADDRESS_TARGET"):
        transport(contract)


# ------------------------------------------------------------------ FIX 2


def spy_transport(calls):
    def transport(contract):
        calls.append(contract.url)
        return b"DATA"

    return transport


def test_obtain_safe_unapproved_host_never_reaches_transport(tmp_path):
    calls = []
    with pytest.raises(FetchContractError, match="UNAPPROVED_SOURCE_HOST"):
        obtain_safe(
            contract_dict(url="https://evil.example/file.bin"),
            RawContentAddressableCache(tmp_path),
            approved_hosts=APPROVED,
            resolver=lambda host: ["93.184.216.34"],
            transport_factory=spy_transport(calls),
        )
    assert calls == []


def test_obtain_safe_private_resolution_never_reaches_transport(tmp_path):
    calls = []
    with pytest.raises(GateError, match="PRIVATE_ADDRESS_TARGET"):
        obtain_safe(
            contract_dict(),
            RawContentAddressableCache(tmp_path),
            approved_hosts=APPROVED,
            resolver=lambda host: ["10.0.0.5"],
            transport_factory=spy_transport(calls),
        )
    assert calls == []


def test_obtain_safe_redirect_to_unapproved_host_never_reaches_transport(tmp_path):
    calls = []
    with pytest.raises(GateError, match="UNAPPROVED_HOST"):
        obtain_safe(
            contract_dict(),
            RawContentAddressableCache(tmp_path),
            approved_hosts=APPROVED,
            resolver=lambda host: ["93.184.216.34"],
            redirector=lambda url: "https://evil.example/file.bin",
            transport_factory=spy_transport(calls),
        )
    assert calls == []


def test_obtain_safe_oversized_declared_size_never_reaches_transport(tmp_path):
    calls = []
    with pytest.raises((GateError, FetchContractError)) as exc:
        obtain_safe(
            contract_dict(expected_size_bytes=1024),
            RawContentAddressableCache(tmp_path),
            approved_hosts=APPROVED,
            resolver=lambda host: ["93.184.216.34"],
            max_asset_bytes=16,
            transport_factory=spy_transport(calls),
        )
    assert "CEILING" in str(exc.value)
    assert calls == []


def test_obtain_safe_happy_path_verifies_and_caches(tmp_path):
    import hashlib

    payload = b"DATA"
    raw = contract_dict(sha256=hashlib.sha256(payload).hexdigest(), expected_size_bytes=4)
    cache = RawContentAddressableCache(tmp_path)
    cache.initialize()
    calls = []

    def verified_transport(contract):
        calls.append(contract.url)
        return payload

    result = obtain_safe(
        raw,
        cache,
        approved_hosts=APPROVED,
        resolver=lambda host: ["93.184.216.34"],
        transport_factory=verified_transport,
    )
    assert result.source == "network"
    assert result.data == payload
    assert cache.has(raw["sha256"])

    # Second call: offline reuse, transport never invoked again.
    calls.clear()
    reused = obtain_safe(
        raw,
        cache,
        approved_hosts=APPROVED,
        resolver=lambda host: ["93.184.216.34"],
        transport_factory=verified_transport,
    )
    assert reused.source == "cache"
    assert calls == []


def test_prepare_raw_asset_is_obtain_safe():
    assert prepare_raw_asset is pipeline_mod.obtain_safe


def test_obtain_documented_unsafe_low_level(tmp_path):
    """The low-level primitive stays injectable but is clearly documented."""
    assert "UNSAFE LOW-LEVEL" in pipeline_mod.obtain.__doc__


# ------------------------------------------------------------------ FIX 3


@pytest.mark.parametrize("url", ["https://example.org:bad/file", "https://example.org:99999/file"])
def test_validate_target_malformed_url_is_typed(url):
    with pytest.raises(GateError):
        validate_target(url, approved_hosts=APPROVED, resolver=lambda host: ["93.184.216.34"])


@pytest.mark.parametrize("url", ["https://example.org:bad/file", "https://example.org:99999/file"])
def test_contract_from_dict_malformed_url_is_typed(url):
    with pytest.raises(FetchContractError):
        contract_from_dict(contract_dict(url=url), approved_hosts=APPROVED)


def test_malformed_port_error_codes_are_specific():
    with pytest.raises(GateError) as bad:
        validate_target(
            "https://example.org:bad/file",
            approved_hosts=APPROVED,
            resolver=lambda host: ["93.184.216.34"],
        )
    assert bad.value.code == "MALFORMED_URL"
    with pytest.raises(GateError) as high:
        validate_target(
            "https://example.org:99999/file",
            approved_hosts=APPROVED,
            resolver=lambda host: ["93.184.216.34"],
        )
    assert high.value.code == "FORBIDDEN_PORT"


# ------------------------------------------------------------------ FIX 4


def make_zip(entries):
    """entries: list of (name, data, external_attr_mode) — mode 0 to omit."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as zf:
        for name, data, mode in entries:
            info = zipfile.ZipInfo(name)
            info.create_system = 3  # unix
            if mode:
                info.external_attr = (mode << 16) | 0o644
            zf.writestr(info, data)
    return buffer.getvalue()


def test_zip_case_insensitive_collision_refused_before_extraction(tmp_path):
    data = make_zip([("A.txt", b"first", 0o100644), ("a.txt", b"second", 0o100644)])
    with pytest.raises(ArchiveSafetyError) as exc:
        scan_zip(data)
    assert exc.value.code in {"CASE_INSENSITIVE_COLLISION", "DUPLICATE_ENTRY_PATH"}
    with pytest.raises(ArchiveSafetyError):
        extract_zip_safe(data, tmp_path)
    assert list(tmp_path.iterdir()) == []  # nothing was written


def test_zip_duplicate_normalized_paths_refused(tmp_path):
    for pair in [(("foo/bar",), ("foo//bar",)), (("foo/bar",), ("foo/./bar",))]:
        entries = [(pair[0][0], b"one", 0o100644), (pair[1][0], b"two", 0o100644)]
        data = make_zip(entries)
        with pytest.raises(ArchiveSafetyError) as exc:
            scan_zip(data)
        assert exc.value.code in {"DUPLICATE_ENTRY_PATH", "CASE_INSENSITIVE_COLLISION"}
        with pytest.raises(ArchiveSafetyError):
            extract_zip_safe(data, tmp_path)
        assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize(
    "mode",
    [
        0o010644,  # FIFO
        0o140644,  # socket
        0o020644,  # character device
        0o060644,  # block device
        0o120644,  # symlink (kept distinct: LINK_ENTRY)
    ],
)
def test_zip_special_file_members_refused(mode, tmp_path):
    data = make_zip([("member", b"x", mode)])
    with pytest.raises(ArchiveSafetyError) as exc:
        scan_zip(data)
    if (mode & 0o170000) == 0o120000:
        assert exc.value.code == "LINK_ENTRY"
    else:
        assert exc.value.code == "NON_REGULAR_ENTRY"
    with pytest.raises(ArchiveSafetyError):
        extract_zip_safe(data, tmp_path)
    assert list(tmp_path.iterdir()) == []


def make_tar(entries):
    """entries: list of (name, data, mode) — data None for non-regular members."""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as tf:
        for name, data, mode in entries:
            info = tarfile.TarInfo(name)
            info.mode = mode
            if name.endswith("/"):
                info.type = tarfile.DIRTYPE
                tf.addfile(info)
            elif data is None:
                info.type = {
                    0o010000: tarfile.FIFOTYPE,
                    0o020000: tarfile.CHRTYPE,
                    0o060000: tarfile.BLKTYPE,
                    0o120000: tarfile.SYMTYPE,
                }.get(mode & 0o170000, tarfile.FIFOTYPE)
                if info.type == tarfile.SYMTYPE:
                    info.linkname = "/etc/passwd"
                tf.addfile(info)
            else:
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
    return buffer.getvalue()


def test_tar_case_collision_and_duplicates_refused(tmp_path):
    data = make_tar([("A.txt", b"first", 0o100644), ("a.txt", b"second", 0o100644)])
    with pytest.raises(ArchiveSafetyError):
        scan_tar(data)
    with pytest.raises(ArchiveSafetyError):
        extract_tar_safe(data, tmp_path)
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("mode", [0o010644, 0o020644, 0o060644])
def test_tar_special_members_refused(mode, tmp_path):
    data = make_tar([("member", None, mode)])
    with pytest.raises(ArchiveSafetyError) as exc:
        scan_tar(data)
    assert exc.value.code == "NON_REGULAR_ENTRY"
    with pytest.raises(ArchiveSafetyError):
        extract_tar_safe(data, tmp_path)
    assert list(tmp_path.iterdir()) == []


def test_tar_symlink_refused(tmp_path):
    data = make_tar([("link", None, 0o120644)])
    with pytest.raises(ArchiveSafetyError) as exc:
        scan_tar(data)
    assert exc.value.code == "LINK_ENTRY"


def test_clean_zip_and_tar_extract(tmp_path):
    data = make_zip([("dir/", b"", 0o040755), ("dir/file.txt", b"ok", 0o100644)])
    report = extract_zip_safe(data, tmp_path / "zip")
    assert report.entry_count == 2
    assert (tmp_path / "zip" / "dir" / "file.txt").read_bytes() == b"ok"

    tdata = make_tar([("dir/", b"", 0o040755), ("dir/file.txt", b"ok", 0o100644)])
    treport = extract_tar_safe(tdata, tmp_path / "tar")
    assert treport.entry_count == 2
    assert (tmp_path / "tar" / "dir" / "file.txt").read_bytes() == b"ok"
