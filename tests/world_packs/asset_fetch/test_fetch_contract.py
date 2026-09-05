"""FETCH_CONTRACT negative fixtures and positive contract tests (offline).

No network access: all transports are injected fakes.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from asset_fetch import contract as contract_mod

HOSTS = {"downloads.example.com"}

PAYLOAD = b"WORLD_PACKS_FIXTURE_PAYLOAD_V1"
SHA = hashlib.sha256(PAYLOAD).hexdigest()


def make_raw(**overrides):
    raw = {
        "asset_id": "rock-cc0-01",
        "version": "1.0.0",
        "sha256": SHA,
        "expected_size_bytes": len(PAYLOAD),
        "url": "https://downloads.example.com/rock-cc0-01-1.0.0.bin",
    }
    raw.update(overrides)
    return raw


# ---------------------------------------------------------------------------
# Negative contract fixtures: invalid input must never produce a contract.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("overrides", "code"),
    [
        ({"asset_id": ""}, "INVALID_ASSET_ID"),
        ({"asset_id": "Bad Id"}, "INVALID_ASSET_ID"),
        ({"asset_id": None}, "INVALID_ASSET_ID"),
        ({"version": ""}, "INVALID_VERSION"),
        ({"version": 1}, "INVALID_VERSION"),
        ({"sha256": "abc"}, "INVALID_SHA256"),
        ({"sha256": "Z" * 64}, "INVALID_SHA256"),
        ({"sha256": None}, "INVALID_SHA256"),
        ({"expected_size_bytes": 0}, "INVALID_EXPECTED_SIZE"),
        ({"expected_size_bytes": -5}, "INVALID_EXPECTED_SIZE"),
        ({"expected_size_bytes": "10"}, "INVALID_EXPECTED_SIZE"),
        ({"expected_size_bytes": 10**9}, "EXPECTED_SIZE_ABOVE_CEILING"),
        ({"url": "http://downloads.example.com/x.bin"}, "NON_HTTPS_SOURCE"),
        ({"url": "ftp://downloads.example.com/x.bin"}, "NON_HTTPS_SOURCE"),
        ({"url": ""}, "INVALID_SOURCE_URL"),
        ({"url": "https://other.example.com/x.bin"}, "UNAPPROVED_SOURCE_HOST"),
        ({"url": "https:///nohost.bin"}, "INVALID_SOURCE_URL"),
    ],
)
def test_invalid_contract_fields_are_typed_failures(overrides, code):
    with pytest.raises(contract_mod.FetchContractError) as excinfo:
        contract_mod.contract_from_dict(make_raw(**overrides), approved_hosts=HOSTS)
    assert excinfo.value.code == code


def test_missing_keys_are_typed_failures():
    for key in ("asset_id", "version", "sha256", "expected_size_bytes", "url"):
        raw = make_raw()
        del raw[key]
        with pytest.raises(contract_mod.FetchContractError):
            contract_mod.contract_from_dict(raw, approved_hosts=HOSTS)


def test_empty_approved_host_set_is_fail_closed():
    with pytest.raises(contract_mod.FetchContractError) as excinfo:
        contract_mod.contract_from_dict(make_raw(), approved_hosts=set())
    assert excinfo.value.code == "NO_APPROVED_HOSTS"


def test_non_mapping_contract_rejected():
    with pytest.raises(contract_mod.FetchContractError) as excinfo:
        contract_mod.contract_from_dict([make_raw()], approved_hosts=HOSTS)
    assert excinfo.value.code == "CONTRACT_NOT_MAPPING"


# ---------------------------------------------------------------------------
# Positive contract fixture.
# ---------------------------------------------------------------------------


def test_valid_contract_is_built_and_normalizes_hash():
    contract = contract_mod.contract_from_dict(make_raw(), approved_hosts=HOSTS)
    assert contract.asset_id == "rock-cc0-01"
    assert contract.sha256 == SHA
    assert contract.expected_size_bytes == len(PAYLOAD)
    assert contract.source_host() == "downloads.example.com"


def test_uppercase_hash_is_normalized_before_validation():
    contract = contract_mod.contract_from_dict(
        make_raw(sha256=SHA.upper()), approved_hosts=HOSTS
    )
    assert contract.sha256 == SHA


# ---------------------------------------------------------------------------
# Payload verification: positive + negative fixtures, offline.
# ---------------------------------------------------------------------------


def test_verify_payload_ok_and_temp_file_roundtrip(tmp_path):
    contract = contract_mod.contract_from_dict(make_raw(), approved_hosts=HOSTS)
    payload = contract_mod.verify_payload(contract, PAYLOAD, keep_temp_file=True)
    assert payload.sha256 == SHA
    assert payload.size_bytes == len(PAYLOAD)
    assert payload.data == PAYLOAD
    assert payload.temp_path is not None
    stored = Path(payload.temp_path).read_bytes()
    assert stored == PAYLOAD
    payload.dispose()
    assert not Path(payload.temp_path).exists()


def test_verify_payload_size_mismatch():
    contract = contract_mod.contract_from_dict(make_raw(), approved_hosts=HOSTS)
    with pytest.raises(contract_mod.FetchVerificationError) as excinfo:
        contract_mod.verify_payload(contract, PAYLOAD + b"X")
    assert excinfo.value.code == "SIZE_MISMATCH"


def test_verify_payload_hash_mismatch():
    contract = contract_mod.contract_from_dict(make_raw(), approved_hosts=HOSTS)
    tampered = bytearray(PAYLOAD)
    tampered[0] ^= 0xFF
    with pytest.raises(contract_mod.FetchVerificationError) as excinfo:
        contract_mod.verify_payload(contract, bytes(tampered))
    assert excinfo.value.code == "HASH_MISMATCH"


def test_verify_payload_rejects_non_bytes():
    contract = contract_mod.contract_from_dict(make_raw(), approved_hosts=HOSTS)
    with pytest.raises(contract_mod.FetchVerificationError) as excinfo:
        contract_mod.verify_payload(contract, "text")
    assert excinfo.value.code == "PAYLOAD_NOT_BYTES"


def test_fetch_verified_ok_with_injected_transport():
    contract = contract_mod.contract_from_dict(make_raw(), approved_hosts=HOSTS)
    payload = contract_mod.fetch_verified(contract, lambda c: PAYLOAD)
    assert payload.data == PAYLOAD


def test_fetch_verified_transport_error_is_typed():
    contract = contract_mod.contract_from_dict(make_raw(), approved_hosts=HOSTS)

    def boom(_contract):
        raise OSError("connection reset")

    with pytest.raises(contract_mod.FetchVerificationError) as excinfo:
        contract_mod.fetch_verified(contract, boom)
    assert excinfo.value.code == "TRANSPORT_ERROR"


def test_fetch_verified_tampered_transport_is_hash_mismatch():
    contract = contract_mod.contract_from_dict(make_raw(), approved_hosts=HOSTS)

    def tamper(_contract):
        out = bytearray(PAYLOAD)
        out[-1] ^= 0x01
        return bytes(out)

    with pytest.raises(contract_mod.FetchVerificationError) as excinfo:
        contract_mod.fetch_verified(contract, tamper)
    assert excinfo.value.code == "HASH_MISMATCH"
