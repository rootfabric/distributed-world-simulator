#!/usr/bin/env python3
"""Strict bounded FABRIC R5.6.1 R1 exact evidence from unmodified runners."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path

SCHEMA = "fabric.r5_6_1.canonical_delta.result.v1"
FATAL = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:", re.I)
ENGINE = {
    "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7",
    "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
}

def req(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)

def load_unique(raw: str) -> dict:
    def pairs(value):
        out = {}
        for k, v in value:
            req(k not in out, "duplicate JSON key " + k)
            out[k] = v
        return out
    def bad(v):
        raise ValueError("nonfinite JSON " + v)
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad)

def sample(path: Path):
    text = path.read_text(encoding="utf-8-sig")
    req(not FATAL.search(text), "Godot fatal " + path.name)
    rows = [s[len("FABRIC_R5_6_1_RESULT="):] for s in text.splitlines() if s.startswith("FABRIC_R5_6_1_RESULT=")]
    hashes = [s[len("FABRIC_R5_6_1_RESULT_HASH="):] for s in text.splitlines() if s.startswith("FABRIC_R5_6_1_RESULT_HASH=")]
    req(len(rows) == len(hashes) == 1, "duplicate/missing result " + path.name)
    obj = load_unique(rows[0]); req(type(obj) is dict, "result object")
    req(set(obj) == {"schema", "checks", "failures", "independent_variants", "sequence_events", "scenario_a_final_hash", "scenario_b_final_hash"}, "fields")
    req(obj.get("schema") == SCHEMA and obj.get("failures") == [], "schema/failures")
    req(type(obj["checks"]) is int and obj["checks"] >= 180, "assertion count")
    req(type(obj["independent_variants"]) is int and obj["independent_variants"] == 2, "variants")
    req(type(obj["sequence_events"]) is int and obj["sequence_events"] == 3, "events")
    for k in ("scenario_a_final_hash", "scenario_b_final_hash"):
        req(type(obj[k]) is str and re.fullmatch(r"[0-9a-f]{64}", obj[k]) is not None, "hash format")
    req(obj["scenario_a_final_hash"] != obj["scenario_b_final_hash"], "different graph identity")
    canonical = hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()).hexdigest()
    req(hashes == [canonical], "result hash mismatch")
    return rows[0], obj, canonical

def collect(root: Path, expected_head: str = "", expected_tree: str = "") -> dict:
    before = (root / "identity-before.txt").read_text().splitlines()
    after = (root / "identity-after.txt").read_text().splitlines()
    req(before == after and len(before) == 4, "identity mismatch")
    req(re.fullmatch("HEAD=[0-9a-f]{40}", before[0]) is not None, "HEAD format")
    req(re.fullmatch("TREE=[0-9a-f]{40}", before[1]) is not None, "TREE format")
    req(before[2] == "GODOT_VERSION=4.7.1.stable.double.custom_build.a13da4feb", "Godot version")
    req(before[3].startswith("GODOT_SHA256=") and before[3].split("=", 1)[1] in ENGINE, "Godot SHA")
    if expected_head: req(before[0] == "HEAD=" + expected_head, "expected HEAD")
    if expected_tree: req(before[1] == "TREE=" + expected_tree, "expected TREE")
    rows = [sample(root / f"sample-{i}.log") for i in (1,2,3)]
    req(rows[0][0] == rows[1][0] == rows[2][0], "deterministic payload mismatch")
    for name in ("import", "parse", "bridge4-regression"):
        content = (root / (name + ".log")).read_text(encoding="utf-8-sig")
        req(not FATAL.search(content), "fatal " + name)
        if name == "bridge4-regression":
            req(re.search(r"FABRIC BRIDGE-4 Canonical World: PASS \(\d+ assertions\)", content) is not None, "Bridge-4 regression missing")
    result = {
        "schema": "fabric.r5_6_1.exact_evidence.v1",
        "status": "IMPLEMENTER_EXACT_PASS",
        "identity": before,
        "deterministic_hash": rows[0][2],
        "result": rows[0][1],
        "logs": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.glob("*.log"))},
    }
    (root / "evidence.json").write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    return result

def main() -> None:
    ap=argparse.ArgumentParser();ap.add_argument("--root",type=Path,required=True);ap.add_argument("--expected-head",default="");ap.add_argument("--expected-tree",default="")
    ns=ap.parse_args()
    r=collect(ns.root,ns.expected_head,ns.expected_tree)
    print("FABRIC_R5_6_1_HASH=" + r["deterministic_hash"])
    print("FABRIC_R5_6_1_EVIDENCE=PASS")
if __name__=="__main__":main()
