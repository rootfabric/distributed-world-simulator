"""Tests for EVO6/R4 generator. Run directly."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts/research/ecology"))
from evo5_rule_generator_v1 import generate_rules  # noqa: E402
from evo5_rule_compiler_v1 import compile_rules  # noqa: E402


def _eq(label, ok):
    if not ok:
        raise SystemExit(f"FAIL {label}")
    print(f"ok {label}")


def main() -> int:
    a = generate_rules("seedA", 12)
    b = generate_rules("seedA", 12)
    c = generate_rules("seedB", 12)
    _eq("deterministic same seed", a == b)
    _eq("different seeds differ", a != c)
    _eq("count bounds (12 + wetland stabilizer)", len(a) == 13 and len(c) == 13)
    _eq("all generated compile fail-closed", bool(compile_rules(a)) and bool(compile_rules(c)))
    ids = [r["id"] for r in a]
    _eq("unique sorted ids", ids == sorted(ids) and len(set(ids)) == len(ids))
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
