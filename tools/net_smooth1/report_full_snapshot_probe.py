#!/usr/bin/env python3
"""R4.2 full-snapshot SHA forensic report; never an acceptance-gate substitute.

Read role-local SmoothTrace JSONL and correlate snapshots by declared SHA-256,
not by timestamps from different processes. This never exports raw snapshots.
Exit 0: probe integrity good (not product PASS); 1: checksum mismatch detected;
2: incomplete trace/missing evidence (INCONCLUSIVE). Input paths stay local.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

SHA = re.compile(r"^[0-9a-f]{64}$")
KIND = "full_snapshot_wire_probe"
SERVER = {"SERVER_JOIN_ACK_BEFORE_FRAME", "SERVER_GAMEPLAY_SNAPSHOT_BEFORE_FRAME"}
CLIENT = {"CLIENT_JOIN_ACK_AFTER_FRAME", "CLIENT_FULL_SNAPSHOT_REJECTED_AFTER_FRAME"}
STAGES = SERVER | CLIENT


def read_role(run: Path, role: str) -> tuple[list[dict], list[str]]:
    source = run / role / "trace.jsonl"
    errors: list[str] = []
    records: list[dict] = []
    if not source.is_file():
        return records, [f"{role}:TRACE_MISSING"]
    end = None
    try:
        with source.open("r", encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                record = json.loads(line)
                if not isinstance(record, dict):
                    errors.append(f"{role}:TRACE_RECORD_TYPE:{line_number}")
                    continue
                if record.get("kind") == "end":
                    end = record.get("data", {})
                elif record.get("kind") == KIND:
                    data = record.get("data", {})
                    if not isinstance(data, dict):
                        errors.append(f"{role}:PROBE_RECORD_TYPE:{line_number}")
                    else:
                        records.append(data)
    except (ValueError, OSError) as ex:
        errors.append(f"{role}:TRACE_UNREADABLE:{type(ex).__name__}")
    if not isinstance(end, dict):
        errors.append(f"{role}:TRACE_END_MISSING")
    elif end.get("dropped", 0) != 0 or end.get("io_errors", 0) != 0:
        errors.append(f"{role}:TRACE_LOSS_OR_IO")
    return records, errors


def evaluate(run: Path) -> tuple[dict, int]:
    events: list[dict] = []
    errors: list[str] = []
    mismatches: list[dict] = []
    for role in ("server", "a", "b"):
        records, role_errors = read_role(run, role)
        errors.extend(role_errors)
        for data in records:
            stage = data.get("stage")
            if stage not in STAGES:
                errors.append(f"{role}:UNKNOWN_PROBE_STAGE")
                continue
            if (role == "server") != (stage in SERVER):
                errors.append(f"{role}:WRONG_ROLE_STAGE")
                continue
            hashes = {key: data.get(key) for key in (
                "declared_sha256", "source_sha256", "after_json_sha256"
            )}
            if any(not isinstance(v, str) or not SHA.fullmatch(v) for v in hashes.values()):
                errors.append(f"{role}:PROBE_HASH_INVALID")
                continue
            row = {"role": role, "stage": stage, **hashes,
                   "revision": data.get("revision"), "server_tick": data.get("server_tick"),
                   "source_valid": data.get("source_valid"),
                   "after_json_valid": data.get("after_json_valid"),
                   "source_error": data.get("source_error", ""),
                   "after_json_error": data.get("after_json_error", "")}
            events.append(row)
            if (hashes["declared_sha256"] != hashes["source_sha256"]
                    or hashes["declared_sha256"] != hashes["after_json_sha256"]
                    or row["source_valid"] is not True or row["after_json_valid"] is not True):
                mismatches.append(row)
    join_server = {d["declared_sha256"] for d in events
                   if d["stage"] == "SERVER_JOIN_ACK_BEFORE_FRAME"}
    join_client = [d for d in events if d["stage"] == "CLIENT_JOIN_ACK_AFTER_FRAME"]
    if not join_server:
        errors.append("SERVER_JOIN_PROBE_MISSING")
    if not join_client:
        errors.append("CLIENT_JOIN_PROBE_MISSING")
    unpaired = [d["declared_sha256"] for d in join_client
                if d["declared_sha256"] not in join_server]
    if unpaired:
        errors.append(f"UNPAIRED_CLIENT_JOIN_PROBES:{len(unpaired)}")
    # The error code in every mismatch is evidence, not a license to waive it.
    # Keep sample SHA only; never reproduce player/session/payload fields.
    code = 1 if mismatches else 2 if errors else 0
    return {
        "schema": "dws.net_smooth.full_snapshot_wire_forensics.v1",
        "run_directory": str(run),
        "probe_events": len(events),
        "server_join_probe_count": len(join_server),
        "client_join_probe_count": len(join_client),
        "checksum_mismatch_count": len(mismatches),
        "mismatch_records": mismatches[:20],
        "unpaired_client_join_count": len(unpaired),
        "evidence_errors": errors,
        "verdict": "CHECKSUM_MISMATCH" if code == 1 else
                   "INCONCLUSIVE" if code == 2 else "PROBE_HASHES_MATCH_NOT_PRODUCT_PASS",
    }, code


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result, code = evaluate(args.run.resolve())
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                            encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items()
                      if key not in ("mismatch_records", "run_directory")},
                     sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
