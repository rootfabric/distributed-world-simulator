#!/usr/bin/env python3
"""Stronger MVP4 gate: real process evidence AND visible terrain pixel change."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests/fixtures/v0_mvp"))
from mvp4_viewport_pixels import terrain_change

SPEC = importlib.util.spec_from_file_location("mvp4_process", ROOT / "tests/integration/test_v0_mvp_4_graphical_shared_dig.py")
assert SPEC is not None and SPEC.loader is not None
PROCESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROCESS)


def main() -> int:
    code = PROCESS.main()
    output = Path(sys.argv[sys.argv.index("--output") + 1]).resolve()
    checks, error = {}, ""
    try:
        for actor in ("a", "b"):
            before, after = output / f"client-{actor}-before.png", output / f"client-{actor}-after.png"
            checks[actor] = terrain_change(before, after)
            # An identical viewport must fail even if a state/geometry hash
            # elsewhere claims the operation was successful.
            if terrain_change(before, before)["passed"]: raise RuntimeError("IDENTICAL_IMAGE_ACCEPTED")
            capture = json.loads((output / f"capture-{actor}.json").read_text())
            snapshots = capture["captures"]
            for player in ("a", "b"):
                if snapshots["before"]["snapshot"]["players"][player]["position"] != snapshots["after"]["snapshot"]["players"][player]["position"]:
                    raise RuntimeError("PLAYER_MOVEMENT_CANNOT_SUBSTITUTE_TERRAIN_CHANGE")
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        error = type(exc).__name__ + ":" + str(exc)
    passed = code == 0 and not error and len(checks) == 2 and all(row["passed"] for row in checks.values())
    report = {"schema": "distributed_world_simulator.mvp4_visible_terrain_gate.v1", "passed": passed, "process_exit_code": code, "checks": checks, "error": error, "manual_input_executed": False, "mvp4_predicate_verified": False}
    (output / "visible-acceptance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if passed else 1

if __name__ == "__main__":
    raise SystemExit(main())
