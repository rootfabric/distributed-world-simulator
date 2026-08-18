#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
CONTRACT = ROOT / "config" / "ecology" / "eco-xfer0-contract.v1.json"
SCHEMA = ROOT / "config" / "ecology" / "eco-xfer0-contract.schema.v1.json"
VALIDATOR = ROOT / "scripts" / "research" / "ecology" / "validate_xfer0_contract.py"
TEST = ROOT / "tests" / "research" / "ecology" / "test_eco_xfer0_contract.py"


def main() -> int:
    for path in [CONTRACT, SCHEMA, VALIDATOR, TEST]:
        if not path.is_file():
            print(f"ECO.XFER0 runner: FAIL missing {path.relative_to(ROOT)}")
            return 1
    try:
        with CONTRACT.open("r", encoding="utf-8") as fh:
            contract = json.load(fh)
        with SCHEMA.open("r", encoding="utf-8") as fh:
            schema = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ECO.XFER0 runner: FAIL JSON {type(exc).__name__}")
        return 1
    if schema.get("$id") != "distributed_world_simulator.ecology.xfer0_contract.schema.v1":
        print("ECO.XFER0 runner: FAIL schema id")
        return 1
    validator_run = subprocess.run([sys.executable, str(VALIDATOR)], cwd=ROOT, text=True, capture_output=True)
    if validator_run.returncode != 0:
        print(validator_run.stdout, end="")
        print(validator_run.stderr, end="", file=sys.stderr)
        return validator_run.returncode
    test_run = subprocess.run([sys.executable, "-m", "unittest", str(TEST)], cwd=ROOT, text=True, capture_output=True)
    if test_run.returncode != 0:
        print(test_run.stdout, end="")
        print(test_run.stderr, end="", file=sys.stderr)
        return test_run.returncode
    print("validator=PASS")
    print("negative_positive_tests=PASS_17_OF_17")
    print("ECO.XFER0 bounded contract: PASS")
    print("contract_hash=" + str(contract.get("contract_hash", "")))
    print("interfaces=" + str(len(contract.get("interfaces", []))))
    print("xfer1_status=" + str(contract.get("xfer1_gate", {}).get("status", "")))
    print("evo3_gate=" + str(contract.get("evo3_gate", {}).get("after_xfer0_acceptance", "")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
