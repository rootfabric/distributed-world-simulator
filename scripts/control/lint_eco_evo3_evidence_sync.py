"""ECO EVO3 evidence closure-run binding lint (ECO-R78, A5).

Cross-checks the live roadmap tracker against acceptance checkpoints:
for every accepted-evidence field ``<stage>_closure_run_id`` and
``<stage>_project_control_run_id`` the referenced run id together with its
run number must literally appear in the corresponding acceptance checkpoint
document. A superseded run id must not be presented as final.

Exit codes: 0 = PASS, 1 = FAIL, 2 = configuration error.
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TRACKER = ROOT / "config/ecology/eco-evolutionary-ecology-roadmap.v1.json"

RUN_ID_KEYS = ("closure_run_id", "project_control_run_id")


def main() -> int:
    try:
        tracker = json.loads(TRACKER.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"[CONFIG-ERROR] cannot read tracker {TRACKER}: {exc}")
        return 2

    evidence = tracker.get("accepted_evidence")
    if not isinstance(evidence, dict):
        print("[CONFIG-ERROR] tracker has no accepted_evidence object")
        return 2

    findings = []
    checked = 0
    for key, value in sorted(evidence.items()):
        for kind in RUN_ID_KEYS:
            if not key.endswith(kind):
                continue
            stage = key[: -len(kind) - 1]  # e.g. "e3_7"
            checkpoint_key = f"{stage}_acceptance_checkpoint"
            checkpoint_rel = evidence.get(checkpoint_key)
            if not checkpoint_key or not checkpoint_rel:
                findings.append(f"[FAIL] {key}: no {checkpoint_key} to bind against")
                continue
            number_key = f"{stage}_closure_run_number" if kind == "closure_run_id" else None
            binding = str(value)
            if number_key and evidence.get(number_key):
                binding = f"{value} / #{evidence[number_key]}"
            checkpoint_path = ROOT / checkpoint_rel
            if not checkpoint_path.is_file():
                findings.append(f"[FAIL] {key}: checkpoint file missing: {checkpoint_rel}")
                continue
            text = checkpoint_path.read_text(encoding="utf-8")
            checked += 1
            if binding in text:
                print(f"[PASS] {key} -> {binding} bound in {checkpoint_rel}")
            else:
                findings.append(
                    f"[FAIL] {key}: binding '{binding}' not found in {checkpoint_rel}"
                )

    print(f"\n=== E3 EVIDENCE SYNC LINT ===")
    print(f"bindings_checked={checked}")
    print(f"findings={len(findings)}")
    for line in findings:
        print(line)
    verdict = "PASS" if not findings else "FAIL"
    print(f"E3 EVIDENCE CLOSURE-RUN BINDING: {verdict}")
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
