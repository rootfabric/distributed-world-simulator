"""OFFLINE_REUSE_AND_CORRUPTION_RECOVERY tests: cache-first, offline, recovery."""

from __future__ import annotations

import hashlib
import os

import pytest

from asset_fetch import cache as cache_mod
from asset_fetch import contract as contract_mod
from asset_fetch import pipeline as pipeline_mod

HOSTS = {"downloads.example.com"}


def make_contract(payload: bytes) -> contract_mod.FetchContract:
    return contract_mod.contract_from_dict(
        {
            "asset_id": "rock-cc0-01",
            "version": "1.0.0",
            "sha256": hashlib.sha256(payload).hexdigest(),
            "expected_size_bytes": len(payload),
            "url": "https://downloads.example.com/rock.bin",
        },
        approved_hosts=HOSTS,
    )


class CountingTransport:
    def __init__(self, payload: bytes):
        self.payload = payload
        self.calls = 0

    def __call__(self, _contract):
        self.calls += 1
        return self.payload


def seed_cache(tmp_path, payload: bytes) -> cache_mod.RawContentAddressableCache:
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    verified = contract_mod.verify_payload(make_contract(payload), payload)
    cache.put_verified(verified)
    return cache


def test_cache_hit_is_offline_reuse(tmp_path):
    payload = b"cached-asset-bytes"
    contract = make_contract(payload)
    cache = seed_cache(tmp_path, payload)
    transport = CountingTransport(payload)

    result = pipeline_mod.obtain(contract, cache, transport)
    assert result.source == "cache"
    assert result.data == payload
    assert transport.calls == 0  # network never touched on a valid hit


def test_cache_miss_fetches_once_and_stores(tmp_path):
    payload = b"fetched-once-then-cached"
    contract = make_contract(payload)
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    transport = CountingTransport(payload)

    first = pipeline_mod.obtain(contract, cache, transport)
    assert first.source == "network"
    assert transport.calls == 1
    assert cache.has(contract.sha256)

    second = pipeline_mod.obtain(contract, cache, transport)
    assert second.source == "cache"
    assert transport.calls == 1  # no second fetch


def test_corruption_detected_and_recovered(tmp_path):
    payload = b"will-be-corrupted-on-disk"
    contract = make_contract(payload)
    cache = seed_cache(tmp_path, payload)

    blob = cache.blob_path(contract.sha256)
    os.chmod(blob, 0o644)
    blob.write_bytes(b"corrupted-content!!!!")

    transport = CountingTransport(payload)
    result = pipeline_mod.obtain(contract, cache, transport)
    assert result.source == "recovered"
    assert result.data == payload
    assert transport.calls == 1

    # corrupt blob quarantined, not silently deleted
    quarantine = tmp_path / "quarantine" / f"{contract.sha256}.corrupt"
    assert quarantine.is_file()
    assert quarantine.read_bytes() == b"corrupted-content!!!!"

    # subsequent reads hit the repaired cache
    again = pipeline_mod.obtain(contract, cache, transport)
    assert again.source == "cache"
    assert transport.calls == 1


def test_corruption_with_failing_refetch_is_typed_failure(tmp_path):
    payload = b"cannot-recover-this"
    contract = make_contract(payload)
    cache = seed_cache(tmp_path, payload)

    blob = cache.blob_path(contract.sha256)
    os.chmod(blob, 0o644)
    blob.write_bytes(b"corrupted-content!!!!")

    def bad_transport(_contract):
        return b"wrong bytes entirely"

    with pytest.raises(pipeline_mod.PipelineError) as excinfo:
        pipeline_mod.obtain(contract, cache, bad_transport)
    assert excinfo.value.code == "RECOVERY_FAILED"


def test_fetch_failure_is_typed(tmp_path):
    payload = b"never-fetched"
    contract = make_contract(payload)
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()

    def boom(_contract):
        raise OSError("offline")

    with pytest.raises(pipeline_mod.PipelineError) as excinfo:
        pipeline_mod.obtain(contract, cache, boom)
    assert excinfo.value.code == "FETCH_FAILED"


def test_tampered_refetch_is_typed_failure(tmp_path):
    payload = b"original"
    contract = make_contract(payload)
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()

    def tampered(_contract):
        return b"tampered"

    with pytest.raises(pipeline_mod.PipelineError) as excinfo:
        pipeline_mod.obtain(contract, cache, tampered)
    assert excinfo.value.code == "FETCH_FAILED"
