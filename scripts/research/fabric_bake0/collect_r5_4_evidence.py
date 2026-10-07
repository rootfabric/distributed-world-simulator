#!/usr/bin/env python3
"""Strict R5.4 R3 evidence: causal work, non-causal control and rollback."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

PREFIX = "FABRIC_R5_4_RESULT="
HASH_PREFIX = "FABRIC_R5_4_DETERMINISTIC_HASH="
PASS = "FABRIC R5.4 MIXED COMPLEXITY 100K MACHINE: PASS ("
SCHEMA = "fabric.r5_4.mixed_complexity_100k.result.v2"
FATAL = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:", re.I)
LINUX_GODOT_SHA256 = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
WINDOWS_GODOT_SHA256 = "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"
CANONICAL_ENGINE_IDENTITY_LINES = {
    "GODOT_SHA256=" + LINUX_GODOT_SHA256,
    "GODOT_SHA256=" + WINDOWS_GODOT_SHA256,
}
EXPECTED = {
    "checks": 1048, "machine_parts": 100000, "recursive_levels": 4, "recursive_nodes": 15,
    "baseline_recursive_physical_components": 1812, "final_recursive_physical_components": 1852,
    "recursive_compiled_input_components": 24, "recursive_executable_equations": 4,
    "local_full_peak": 20, "local_reconstructed_parts": 20, "local_metadata_parts_scanned": 0,
    "local_range_query_count": 4, "local_range_query_prefix_reads": 80,
    "local_recursive_changed": 4, "local_recursive_reused": 11,
    "global_structural_parts_scanned": 0, "global_recursive_changed": 15, "global_recursive_reused": 0,
    "explicit_global_control_parts_scanned": 100000,
    "global_structural_state_unchanged": True, "explicit_global_control_state_unchanged": True,
    "rollback_rejected_events": 11, "rollback_state_unchanged_events": 11,
    "uninitialized_rejections": 3, "steady_calls": 320,
}


def req(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def strict(text: str) -> Any:
    def bad(value: str) -> None:
        raise ValueError("nonfinite " + value)

    def finite(value: str) -> float:
        number = float(value)
        req(math.isfinite(number), "nonfinite " + value)
        return number

    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            req(key not in result, "duplicate JSON key " + key)
            result[key] = value
        return result

    return json.loads(text, parse_constant=bad, parse_float=finite, object_pairs_hook=unique)


def digest(value: dict[str, Any]) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return hashlib.sha256(encoded).hexdigest()


def sample(path: Path) -> tuple[str, dict[str, Any]]:
    text = path.read_text(encoding="utf-8-sig")
    req(not FATAL.search(text), "sample fatal " + path.name)
    lines = text.splitlines()
    rows = [line[len(PREFIX):] for line in lines if line.startswith(PREFIX)]
    req(len(rows) == 1, "result marker count")
    result = strict(rows[0])
    req(type(result) is dict, "result object")
    req(result.get("schema") == SCHEMA, "schema")
    req(set(result) == set(EXPECTED) | {"schema", "failures", "final_machine_hash"}, "result fields")
    req(type(result.get("failures")) is list and result["failures"] == [], "failures")
    for key, value in EXPECTED.items():
        req(type(result.get(key)) is type(value) and result[key] == value, "mismatch " + key)
    req(type(result["final_machine_hash"]) is str and
        re.fullmatch(r"[0-9a-f]{64}", result["final_machine_hash"]) is not None, "machine hash")
    passes = [line for line in lines if line.startswith(PASS)]
    req(passes == [PASS + str(EXPECTED["checks"]) + " assertions)"], "PASS assertion count")
    hashes = [line[len(HASH_PREFIX):] for line in lines if line.startswith(HASH_PREFIX)]
    req(hashes == [digest(result)], "declared deterministic hash")
    return rows[0], result


def validate_identity(before: list[str], after: list[str]) -> None:
    req(before == after, "identity moved")
    req(len(before) == 4, "identity shape")
    req(re.fullmatch(r"HEAD=[0-9a-f]{40}", before[0]) is not None, "head identity")
    req(re.fullmatch(r"TREE=[0-9a-f]{40}", before[1]) is not None, "tree identity")
    req(before[2] == "GODOT_VERSION=4.7.1.stable.double.custom_build.a13da4feb", "engine version")
    req(before[3] in CANONICAL_ENGINE_IDENTITY_LINES, "engine sha")


def collect(root: Path, *, expected_head: str | None = None,
            expected_tree: str | None = None, expected_hash: str | None = None) -> dict[str, Any]:
    before = (root / "identity-before.txt").read_text(encoding="utf-8-sig").splitlines()
    after = (root / "identity-after.txt").read_text(encoding="utf-8-sig").splitlines()
    validate_identity(before, after)
    if expected_head is not None:
        req(before[0] == "HEAD=" + expected_head, "expected head")
    if expected_tree is not None:
        req(before[1] == "TREE=" + expected_tree, "expected tree")
    rows = [sample(root / f"sample-{i}.log") for i in (1, 2, 3)]
    req(rows[0][0] == rows[1][0] == rows[2][0], "payload mismatch")
    for name, marker in (
        ("r53", "FABRIC R5.3 RECURSIVE HIERARCHICAL EXECUTION: PASS (1231 assertions)"),
        ("r51", "FABRIC R5.1 QUANTITATIVE SCALE: PASS (93 assertions) count=100000"),
    ):
        text = (root / f"{name}-regression.log").read_text(encoding="utf-8-sig")
        req(text.splitlines().count(marker) == 1 and not FATAL.search(text), "regression " + name)
    for name in ("import", "parse"):
        req(not FATAL.search((root / f"{name}.log").read_text(encoding="utf-8-sig")), name + " fatal")
    python_log = (root / "python-tests.log").read_text(encoding="utf-8-sig")
    req(re.search(r"^Ran [1-9][0-9]* tests? in ", python_log, re.M) is not None and
        python_log.splitlines().count("OK") == 1 and
        not re.search(r"^FAILED|^ERROR:|^FAIL:|Traceback \(", python_log, re.M), "python contract")
    hashed = digest(rows[0][1])
    if expected_hash is not None:
        req(hashed == expected_hash, "expected hash")
    return {
        "schema": "fabric.r5_4.exact_evidence.v2", "status": "IMPLEMENTER_EXACT_PASS",
        "identity": before, "deterministic_hash": hashed, "result": rows[0][1],
        "logs": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.glob("*.log"))},
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--expected-head")
    parser.add_argument("--expected-tree")
    parser.add_argument("--expected-hash")
    args = parser.parse_args()
    evidence = collect(args.root, expected_head=args.expected_head,
                       expected_tree=args.expected_tree, expected_hash=args.expected_hash)
    (args.root / "evidence.json").write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n")
    print(HASH_PREFIX + evidence["deterministic_hash"])
    print("FABRIC_R5_4_EVIDENCE=PASS")


if __name__ == "__main__":
    main()
