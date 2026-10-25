#!/usr/bin/env python3
"""Verify actual native real-chain proof; never convert synthetic PASS to #815 closure.

No report is modified. Verify original Git blobs, exact first-bit witness,
checksum ordering, complete corpus counts and absence of live activation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

EXPECTED_BLOBS = {
    "scripts/network/contracts/network_contract_utils.gd": "58b97f82ab09c699ae3c48060c6e0747579aa676",
    "scripts/network/transports/v2/transport_contract_utils.gd": "ce6b25973a3fb55c64f4a451e11a786f63187be6",
    "scripts/network/realtime/realtime_channel_policy.gd": "2b14b325620695451bcedc242e2fb798bac15482",
    "scripts/network/transports/v2/protocol_frame_v2.gd": "ed3ebff3f30d55668248cc78b15c18f1fc5fb8cb",
    "scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd": "dae68d7ef6812e91381052baaaa3e32bf4404423",
    "scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd": "f09c5d156d8cd31704aa6790f0ee824c832df2ba",
    "scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd": "d3e8bf3aa4ace9ce6b1a08224262ce4c14a8dcf8",
}


def require(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError(code)


def check_source(root: Path) -> None:
    for name, expected in EXPECTED_BLOBS.items():
        raw = (root / name).read_bytes()
        got = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        require(got == expected, "ORIGINAL_CODEC_SOURCE_CHANGED:" + name)


def validate(report: dict[str, Any]) -> dict[str, Any]:
    require(report.get("schema") == "dws.net_smooth.815.real_snapshot_chain.v1", "BAD_SCHEMA")
    require(report.get("fixture_kind") == "DETERMINISTIC_EARTH_LOCAL_DTO_NOT_LIVE_INCIDENT", "FIXTURE_SCOPE_UNATTESTED")
    require(report.get("historical_incident_proven") is False, "CANNOT_CLAIM_LIVE_ROOT_CAUSE")
    require(report.get("live_network_activation") is False, "LIVE_ACTIVATION_FORBIDDEN")
    require(report.get("ready_for_merge") is False, "MERGE_NOT_AUTHORIZED")
    require(report.get("failures") == [], "NATIVE_ASSERTION_FAILURES")
    cases, legacy = report.get("cases"), report.get("legacy_failures")
    require(type(cases) is int and cases == 2048, "INCOMPLETE_NATIVE_CORPUS")
    require(type(legacy) is int and 1 <= legacy <= cases, "LEGACY_RED_NOT_REPRODUCED")
    require(report.get("v2_failures") == 0, "V2_NOT_GREEN")
    require(type(report.get("assertions")) is int and report["assertions"] > 20000, "ASSERTION_COVERAGE_INCOMPLETE")
    stages = report.get("first_failure_stages", {})
    require(isinstance(stages, dict) and all(type(n) is int and n >= 0 for n in stages.values()), "MALFORMED_STAGE_COUNTS")
    require(sum(stages.values()) == cases and stages.get("NONE", 0) + legacy == cases, "COUNTS_DO_NOT_PARTITION_CORPUS")
    original = report.get("original_sources", [])
    require(isinstance(original, list) and len(original) == len(EXPECTED_BLOBS), "SOURCE_FINGERPRINTS_MISSING")
    require({x.get("path"): x.get("git_blob_sha1") for x in original} == EXPECTED_BLOBS, "WRONG_PRODUCTION_CONTRACTS")
    witnesses = report.get("witnesses", [])
    require(isinstance(witnesses, list) and witnesses, "NO_DETERMINISTIC_WITNESS")
    fixed = witnesses[0]
    require(fixed.get("case") == 84, "FIXED_WITNESS_MISSING")
    require(fixed.get("first_broken_stage") == "FRAME_CREATE_JSON" and fixed.get("first_broken_checksums") == ["h", "c"], "INCORRECT_FIRST_CHECKSUM_LAYER")
    require(fixed.get("receiver_error") == "PAYLOAD_CHECKSUM_MISMATCH", "ORIGINAL_ERROR_CODE_NOT_PRESERVED")
    diff = fixed.get("first_frame_create_numeric_change", {})
    require(diff.get("path") == "$.payload.snapshot.p[0].v[1]", "INCORRECT_CHANGED_FIELD")
    require(diff.get("before_f64le") == "381e0df76695bebc" and diff.get("after_f64le") == "391e0df76695bebc", "EXACT_FLOAT_BITS_NOT_REPRODUCED")
    require(fixed.get("outer_after_frame_create") == fixed.get("outer_stored") and fixed.get("outer_after_receive_parse") != fixed.get("outer_stored"), "OUTER_CHECKSUM_CAUSAL_CHAIN_INCOMPLETE")
    for key in ("compact_created", "frame_created", "receiver_parsed"):
        layer = fixed.get(key, {})
        require(type(layer.get("h_valid")) is bool and type(layer.get("c_valid")) is bool, "MISSING_INNER_CHECKSUM_PROOF")
    require(fixed["compact_created"]["h_valid"] and fixed["compact_created"]["c_valid"], "COMPACT_NOT_ORIGINALLY_VALID")
    require(not fixed["frame_created"]["h_valid"] and not fixed["frame_created"]["c_valid"], "INNER_FAILURE_NOT_ISOLATED")
    require(fixed["receiver_parsed"]["h_valid"] and fixed["receiver_parsed"]["c_valid"], "TWO_CYCLE_NOT_REPRODUCED")
    old_size, new_size = report.get("v1_packet_bytes_total_corpus"), report.get("v2_packet_bytes_total_corpus")
    require(type(old_size) is int and type(new_size) is int and old_size > 0 and new_size > 0, "PACKET_SIZE_EVIDENCE_MISSING")
    return {
        "verdict": "NATIVE_REAL_CONTRACT_RED_GREEN_ONLY",
        "cases": cases, "legacy_red_cases": legacy, "v2_green_cases": cases,
        "first_stage": fixed["first_broken_stage"], "first_checksums": fixed["first_broken_checksums"],
        "numeric_field": diff["path"], "bit_before": diff["before_f64le"], "bit_after": diff["after_f64le"],
        "v2_vs_v1_packet_bytes_percent": 100 * (new_size / old_size - 1),
        "historical_incident_proven": False, "live_network_activation": False, "ready_for_merge": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--source-root", type=Path)
    args = parser.parse_args()
    try:
        if args.source_root:
            check_source(args.source_root)
        raw = args.report.read_bytes()
        result = validate(json.loads(raw))
        result["report_sha256"] = hashlib.sha256(raw).hexdigest()
    except (ValueError, TypeError, KeyError, OSError) as err:
        print("NS1_815_CHAIN_EVIDENCE_INVALID:" + str(err))
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
