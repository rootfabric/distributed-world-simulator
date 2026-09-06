"""RAW_CONTENT_ADDRESSABLE_CACHE tests: write-once, verify-on-read, immutability."""

from __future__ import annotations

import hashlib
import json
import os

import pytest

from asset_fetch import cache as cache_mod
from asset_fetch import contract as contract_mod

HOSTS = {"downloads.example.com"}


def make_verified(payload: bytes) -> contract_mod.VerifiedPayload:
    contract = contract_mod.contract_from_dict(
        {
            "asset_id": "rock-cc0-01",
            "version": "1.0.0",
            "sha256": hashlib.sha256(payload).hexdigest(),
            "expected_size_bytes": len(payload),
            "url": "https://downloads.example.com/rock.bin",
        },
        approved_hosts=HOSTS,
    )
    return contract_mod.verify_payload(contract, payload)


def test_put_and_get_roundtrip(tmp_path):
    payload_bytes = b"CACHE_FIXTURE_PAYLOAD_123"
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    verified = make_verified(payload_bytes)
    cached = cache.put_verified(verified)
    sha = hashlib.sha256(payload_bytes).hexdigest()

    assert cached.sha256 == sha
    assert cached.blob_path == tmp_path / "blobs" / sha[:2] / sha
    assert cached.blob_path.is_file()

    got = cache.get_verified(sha)
    assert got.data == payload_bytes
    assert got.size_bytes == len(payload_bytes)
    assert got.meta_path is not None
    meta = json.loads(got.meta_path.read_text(encoding="utf-8"))
    assert meta["sha256"] == sha
    assert meta["asset_id"] == "rock-cc0-01"
    assert meta["source_url"].startswith("https://")


def test_idempotent_reput_same_bytes(tmp_path):
    verified = make_verified(b"same-bytes")
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    cache.put_verified(verified)
    cache.put_verified(verified)  # must not raise
    assert cache.has(verified.sha256)


def test_immutability_violation_refused(tmp_path):
    good = make_verified(b"original-content")
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    cache.put_verified(good)

    # Same address (same sha) but different bytes on disk underneath.
    blob = cache.blob_path(good.sha256)
    os.chmod(blob, 0o644)
    blob.write_bytes(b"tampered!!!!!!")

    # Re-putting original bytes now conflicts with tampered disk state.
    with pytest.raises(cache_mod.RawCacheError) as excinfo:
        cache.put_verified(good)
    assert excinfo.value.code == "IMMUTABILITY_VIOLATION"


def test_address_mismatch_refused(tmp_path):
    verified = make_verified(b"content-A")
    forged = contract_mod.VerifiedPayload(
        contract=verified.contract,
        data=b"content-B!!",
        sha256=verified.sha256,  # claimed digest of different bytes
        size_bytes=10,
        temp_path=None,
    )
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    with pytest.raises(cache_mod.RawCacheError) as excinfo:
        cache.put_verified(forged)
    assert excinfo.value.code == "ADDRESS_MISMATCH"


def test_cache_miss_is_typed(tmp_path):
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    with pytest.raises(cache_mod.RawCacheError) as excinfo:
        cache.get_verified("0" * 64)
    assert excinfo.value.code == "CACHE_MISS"


def test_corrupted_blob_detected_on_read(tmp_path):
    verified = make_verified(b"will-be-corrupted")
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    cache.put_verified(verified)

    blob = cache.blob_path(verified.sha256)
    os.chmod(blob, 0o644)
    blob.write_bytes(b"corrupted-bytes!")

    with pytest.raises(cache_mod.RawCacheError) as excinfo:
        cache.get_verified(verified.sha256)
    assert excinfo.value.code == "CACHE_CORRUPT"


def test_uninitialized_cache_is_fail_closed(tmp_path):
    cache = cache_mod.RawContentAddressableCache(tmp_path / "absent")
    verified = make_verified(b"x")
    with pytest.raises(cache_mod.RawCacheError) as excinfo:
        cache.put_verified(verified)
    assert excinfo.value.code == "CACHE_NOT_INITIALIZED"
    with pytest.raises(cache_mod.RawCacheError):
        cache.get_verified("1" * 64)


def test_blob_written_read_only(tmp_path):
    verified = make_verified(b"permissions-check")
    cache = cache_mod.RawContentAddressableCache(tmp_path)
    cache.initialize()
    cache.put_verified(verified)
    mode = cache.blob_path(verified.sha256).stat().st_mode & 0o777
    assert mode == 0o444
