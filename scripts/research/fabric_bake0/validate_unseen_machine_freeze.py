#!/usr/bin/env python3
"""Fail closed if post-freeze challenge commits modify frozen solver/compiler bytes."""
from __future__ import annotations
import argparse
import subprocess
import sys

FROZEN_PREFIXES = (
    "scripts/research/fabric0/",
    "scripts/research/fabric_bake0/",
    "scripts/simulation/representation/",
)
ALLOWED_POST_FREEZE = {
    "RUN_FABRIC_B0_7_TESTS.sh",
    "tests/research/fabric_bake0/unseen_machine_challenge_fixture_v1.gd",
    "tests/research/fabric_bake0/fabric_bake_b0_7_unseen_machine_acceptance.gd",
    "validation/fabric_b0_7/kernel-freeze.v1.json",
}
ALLOWED_PREFIXES = (
    "docs/research/",
    "validation/fabric_b0_7/",
    "validation/FABRIC_B0_7_",
)

def changed_paths(base: str, head: str) -> list[str]:
    out = subprocess.check_output(["git", "diff", "--name-only", f"{base}..{head}"], text=True)
    return [line.strip() for line in out.splitlines() if line.strip()]

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("freeze_head")
    parser.add_argument("challenge_head")
    args = parser.parse_args()
    changed = changed_paths(args.freeze_head, args.challenge_head)
    forbidden = []
    for path in changed:
        if path in ALLOWED_POST_FREEZE or path.startswith(ALLOWED_PREFIXES):
            continue
        if path.startswith(FROZEN_PREFIXES):
            forbidden.append(path)
            continue
        forbidden.append(path)
    if forbidden:
        print("B0.7 UNSEEN FREEZE: FAIL")
        for path in forbidden:
            print(f"FORBIDDEN_POST_FREEZE_CHANGE={path}")
        return 1
    print(f"B0.7 UNSEEN FREEZE: PASS changed={len(changed)}")
    for path in changed:
        print(f"ALLOWED_POST_FREEZE_CHANGE={path}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
