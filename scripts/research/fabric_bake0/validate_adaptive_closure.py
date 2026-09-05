#!/usr/bin/env python3
"""Bind real closure outputs to an exact checkout; exclude hardware timing from replay."""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    folder = Path(sys.argv[1])
    runners = sys.argv[2:]
    timings = dict(line.split("\t") for line in (folder / "timings.tsv").read_text().splitlines())
    required = ["B06A_SAFETY_HASH", "B06A_ENVELOPE_CHECKSUM", "B06B_SELECTION_HASH",
                "B06C_TRANSITION_HASH", "B06D_RECOVERY_HASH", "B06D_DISK_RECOVERY_HASH",
                "B06E_FINAL_STATE_HASH", "B06E_TRANSITION_HASH", "B06E_WORK_HASH"]
    hashes: dict[str, str] = {}
    scales: dict[str, dict] = {}
    suites: list[dict] = []
    for runner in runners:
        path = folder / (Path(runner).stem + ".log")
        raw = path.read_bytes()
        text = raw.decode("utf-8")
        if re.search(r"SCRIPT ERROR|Parse Error|Invalid call|^ERROR:|Segmentation fault", text, re.M):
            raise ValueError(f"Runtime failure in {runner}")
        for key, value in re.findall(r"^(B06[A-E]_[A-Z_]+)=([0-9a-f]{64})$", text, re.M):
            if key in hashes and hashes[key] != value:
                raise ValueError(f"Conflicting deterministic hash: {key}")
            hashes[key] = value
        for count, payload in re.findall(r"^B06E_SCALE_(500|1000|2000)=(.+)$", text, re.M):
            scales[count] = json.loads(payload)
        counts = [int(n) for n in re.findall(r"PASS \((\d+) assertions\)", text)]
        suites.append({"runner": runner, "exit_code": 0, "assertion_counts": counts,
                       "log_sha256": sha256(raw), "wall_seconds": float(timings[runner])})
    if set(required) - hashes.keys() or set(scales) != {"500", "1000", "2000"}:
        raise ValueError("Incomplete B0.6 exact replay evidence")
    for count, result in scales.items():
        if result["subjects"] != int(count):
            raise ValueError("Scale subject count mismatch")
        counters = result["work_counters"]
        for field in ["unsafe_selection_count", "duplicate_ownership_count", "global_rebuilds", "failed_closed"]:
            if counters[field] != 0:
                raise ValueError(f"Nonzero safety counter {field} at {count}")
    deterministic = {"hashes": hashes, "scales": scales,
                     "suites": [{k: s[k] for k in ["runner", "exit_code", "assertion_counts"]} for s in suites]}
    closure_hash = sha256(json.dumps(deterministic, sort_keys=True, separators=(",", ":")).encode())
    git = lambda *args: subprocess.check_output(["git", *args], text=True).strip()
    binary = Path(os.environ["GODOT_BIN"])
    manifest = {"schema": "dws.fabric.b0_6.exact_evidence.v1", "head": git("rev-parse", "HEAD"),
                "tree": git("rev-parse", "HEAD^{tree}"), "branch": git("branch", "--show-current"),
                "godot_version": subprocess.check_output([str(binary), "--version"], text=True).strip(),
                "godot_sha256": sha256(binary.read_bytes()), "exit_code": 0, "hashes": hashes,
                "scales": scales, "suites": suites, "closure_hash": closure_hash}
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("B06_CLOSURE_HASH=" + closure_hash)


if __name__ == "__main__":
    main()
