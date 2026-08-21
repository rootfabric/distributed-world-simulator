"""ECO EVO3 all-stage regression closure.

Runs every accepted EVO3 stage runner (architecture + E3.1..E3.7) in a fresh
subprocess against the exact working-tree HEAD, read-only with respect to
committed artifacts, and requires PASS from each stage.

Policy: config/ecology/eco-evolutionary-ecology-roadmap.v1.json
        roadmap_amendments.regression_closure_policy (ECO-R77)

Exit codes: 0 = all stages PASS, 1 = at least one stage FAIL.
"""
from __future__ import annotations
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent

STAGE_RUNNERS = (
    "RUN_ECO_EVO3_ARCHITECTURE_TESTS.py",
    "RUN_ECO_EVO3_E3_1_TESTS.py",
    "RUN_ECO_EVO3_E3_2_TESTS.py",
    "RUN_ECO_EVO3_E3_3_TESTS.py",
    "RUN_ECO_EVO3_E3_4_TESTS.py",
    "RUN_ECO_EVO3_E3_5_TESTS.py",
    "RUN_ECO_EVO3_E3_6_TESTS.py",
    "RUN_ECO_EVO3_E3_7_TESTS.py",
)


def main() -> int:
    results = []
    print(f"ECO EVO3 REGRESSION CLOSURE @ {ROOT}")
    for name in STAGE_RUNNERS:
        path = ROOT / name
        if not path.is_file():
            print(f"[FAIL] {name}: runner file missing")
            results.append((name, False, 0.0))
            continue
        started = time.monotonic()
        proc = subprocess.run(
            [sys.executable, str(path)],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        elapsed = time.monotonic() - started
        ok = proc.returncode == 0
        results.append((name, ok, elapsed))
        print(f"[{'PASS' if ok else 'FAIL'}] {name} ({elapsed:.1f}s)")
        if not ok:
            tail = "\n".join((proc.stdout + proc.stderr).strip().splitlines()[-15:])
            print(tail)

    passed = sum(1 for _, ok, _ in results if ok)
    verdict = "PASS" if passed == len(results) else "FAIL"
    print(f"\n=== E3 REGRESSION CLOSURE RESULT ===")
    print(f"stages={passed}/{len(results)}")
    print(f"ECO.EVO3 ALL-STAGE REGRESSION CLOSURE: {verdict}")
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
