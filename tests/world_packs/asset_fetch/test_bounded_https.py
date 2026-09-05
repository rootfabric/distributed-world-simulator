"""BOUNDED_HTTPS tests: bounded streaming reads against fake openers.

No network access: openers are injected fakes.
"""

from __future__ import annotations

import hashlib

import pytest

from asset_fetch import contract as contract_mod
from asset_fetch import https as https_mod

HOSTS = {"downloads.example.com"}


def make_contract(payload: bytes, *, url_path: str = "asset.bin"):
    return contract_mod.contract_from_dict(
        {
            "asset_id": "rock-cc0-01",
            "version": "1.0.0",
            "sha256": hashlib.sha256(payload).hexdigest(),
            "expected_size_bytes": len(payload),
            "url": f"https://downloads.example.com/{url_path}",
        },
        approved_hosts=HOSTS,
    )


class FakeResponse:
    def __init__(self, data: bytes, *, chunks: int = 3):
        self._chunks = self._split(data, chunks)
        self._index = 0

    @staticmethod
    def _split(data: bytes, parts: int) -> list[bytes]:
        if not data or parts <= 1:
            return [data]
        size = max(1, len(data) // parts)
        return [data[i : i + size] for i in range(0, len(data), size)]

    def read(self, amount: int = -1) -> bytes:
        if self._index >= len(self._chunks):
            return b""
        chunk = self._chunks[self._index]
        if amount >= 0:
            chunk = chunk[:amount]
            if len(chunk) < len(self._chunks[self._index]):
                # partial consume: keep the remainder for the next read
                remainder = self._chunks[self._index][amount:]
                self._chunks[self._index] = chunk
                self._chunks.insert(self._index + 1, remainder)
        self._index += 1
        return chunk

    def close(self) -> None:
        self.closed = True


class FakeOpener:
    def __init__(self, response):
        self.response = response
        self.opened_urls = []
        self.timeout = None

    def open(self, url, timeout=-1):
        self.opened_urls.append(url)
        self.timeout = timeout
        return self.response


class ExplodingOpener:
    def open(self, url, timeout=-1):
        raise OSError("dns failure")


def test_bounded_read_ok_streamed(tmp_path):
    payload = b"x" * 10_000
    contract = make_contract(payload)
    opener = FakeOpener(FakeResponse(payload))
    transport = https_mod.make_bounded_transport(opener, chunk_bytes=1024)
    data = transport(contract)
    assert data == payload
    assert opener.opened_urls == [contract.url]
    assert 0 < opener.timeout <= https_mod.MAX_TIMEOUT_SECONDS


def test_size_exceeded_aborts_transfer():
    contract = make_contract(b"short")  # pins 5 bytes
    opener = FakeOpener(FakeResponse(b"short" + b"EXTRA_BYTES"))
    transport = https_mod.make_bounded_transport(opener)
    with pytest.raises(https_mod.BoundedFetchError) as excinfo:
        transport(contract)
    assert excinfo.value.code == "SIZE_EXCEEDED"


def test_size_short_is_typed_failure():
    contract = make_contract(b"twelve-bytes")
    opener = FakeOpener(FakeResponse(b"short"))
    transport = https_mod.make_bounded_transport(opener)
    with pytest.raises(https_mod.BoundedFetchError) as excinfo:
        transport(contract)
    assert excinfo.value.code == "SIZE_SHORT"


def test_open_failure_is_typed():
    contract = make_contract(b"abc")
    transport = https_mod.make_bounded_transport(ExplodingOpener())
    with pytest.raises(https_mod.BoundedFetchError) as excinfo:
        transport(contract)
    assert excinfo.value.code == "OPEN_FAILED"


def test_read_failure_is_typed():
    class BoomResponse:
        def read(self, amount=-1):
            raise OSError("connection reset")

        def close(self):
            pass

    contract = make_contract(b"abc")
    transport = https_mod.make_bounded_transport(FakeOpener(BoomResponse()))
    with pytest.raises(https_mod.BoundedFetchError) as excinfo:
        transport(contract)
    assert excinfo.value.code == "READ_FAILED"


def test_hard_max_bytes_can_only_tighten():
    payload = b"0123456789"
    contract = make_contract(payload)  # pins 10
    opener = FakeOpener(FakeResponse(payload))
    # hard ceiling below pinned size -> typed SIZE_EXCEEDED
    transport = https_mod.make_bounded_transport(opener, hard_max_bytes=4)
    with pytest.raises(https_mod.BoundedFetchError) as excinfo:
        transport(contract)
    assert excinfo.value.code == "SIZE_EXCEEDED"


def test_invalid_transport_arguments_rejected():
    opener = FakeOpener(FakeResponse(b""))
    with pytest.raises(ValueError):
        https_mod.make_bounded_transport(opener, chunk_bytes=0)
    with pytest.raises(ValueError):
        https_mod.make_bounded_transport(opener, timeout_seconds=0)
    with pytest.raises(ValueError):
        https_mod.make_bounded_transport(opener, timeout_seconds=999)


def test_bounded_transport_composes_with_fetch_verified():
    payload = b"WORLD_PACKS_BOUNDED_HTTPS_FIXTURE"
    contract = make_contract(payload, url_path="rock.bin")
    opener = FakeOpener(FakeResponse(payload))
    transport = https_mod.make_bounded_transport(opener)
    verified = contract_mod.fetch_verified(contract, transport)
    assert verified.sha256 == hashlib.sha256(payload).hexdigest()


def test_default_opener_refuses_redirects():
    import urllib.error
    import urllib.request

    opener = https_mod.default_opener()
    no_redirect = next(
        h
        for h in opener.handlers
        if isinstance(h, urllib.request.HTTPRedirectHandler)
    )

    class _Req:
        pass

    with pytest.raises(urllib.error.HTTPError):
        no_redirect.redirect_request(
            _Req(),
            None,
            302,
            "Found",
            {"location": "https://evil.example.com/x"},
            None,
        )
