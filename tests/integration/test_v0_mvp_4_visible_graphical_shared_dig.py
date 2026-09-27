#!/usr/bin/env python3
"""Stronger MVP4 gate: real process evidence AND terrain-only visible pixels.

Review 4001519528 split this gate into explicit layers:

1. Construction: every canonical before/after capture is produced with the
   COMPLETE UI hidden (capture evidence must certify `ui.hidden` and record the
   UI region derived from the live UI tree).
2. Analysis: the pixel comparison excludes only that DERIVED UI region - no
   guessed row constant - and requires >= 32 changed terrain pixels in EACH
   client (positive control: real terrain mutation => PASS for A and B).
3. Falsification: a synthesized HUD-only-difference pair (identical terrain,
   differences strictly inside the derived UI region, including rows below 160)
   must be REJECTED by this gate, while the rejected legacy row-160 criterion
   demonstrably accepts it (the exact reported false positive).
"""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests/fixtures/v0_mvp"))
import mvp4_viewport_pixels as pixels

SPEC = importlib.util.spec_from_file_location("mvp4_process", ROOT / "tests/integration/test_v0_mvp_4_graphical_shared_dig.py")
assert SPEC is not None and SPEC.loader is not None
PROCESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROCESS)


def certified_region(capture: dict, actor: str, label: str) -> dict:
    """Validate terrain-only construction evidence and return the derived UI region."""
    entry = capture["captures"][label]
    ui = entry["ui"]
    if ui.get("hidden") is not True or not ui.get("nodes") or ui.get("canvas_items", 0) < 1:
        raise RuntimeError("UI_NOT_HIDDEN_DURING_CAPTURE:%s:%s" % (actor, label))
    region = ui.get("region")
    if not isinstance(region, dict) or min(float(region.get(k, 0)) for k in ("w", "h")) <= 0:
        raise RuntimeError("UI_REGION_NOT_DERIVED:%s:%s" % (actor, label))
    return region


def hud_only_falsification(output: Path, actor: str, before_png: Path, region_a: dict, region_b: dict) -> dict:
    """Negative control: HUD changes + identical terrain => this gate FAILs."""
    width, height, source = pixels.rgba(before_png)
    region = pixels.union_region(region_a, region_b, width, height)
    if region[1] + region[3] <= 160:
        raise RuntimeError("HUD_REGION_PREMISE_UNVERIFIED:%s" % actor)
    first, last = pixels.hud_only_pair(before_png, region, seed=ord(actor) * 7919)
    # Both synthesized images must keep the real captured terrain bit-for-bit
    # outside the derived UI region, and differ only inside it.
    preserved = all(pixels.terrain_change_rgba(width, height, image, source, region)["terrain_changed_pixels"] == 0 for image in (first, last))
    differences_outside = pixels.terrain_change_rgba(width, height, first, last, region)
    if not preserved or differences_outside["terrain_changed_pixels"] != 0:
        raise RuntimeError("HUD_ONLY_PAIR_CONSTRUCTION_INVALID:%s" % actor)
    # Rejected legacy criterion would have accepted this HUD-only pair.
    legacy = pixels.legacy_row160_rgba(width, height, first, last)
    if not legacy["legacy_row160_would_pass"]:
        raise RuntimeError("LEGACY_FALSE_POSITIVE_NOT_REPRODUCED:%s" % actor)
    # The terrain-only gate must reject it: identical terrain, HUD-only change.
    gate = pixels.terrain_change_rgba(width, height, first, last, region)
    if gate["passed"]:
        raise RuntimeError("HUD_ONLY_CHANGE_ACCEPTED:%s" % actor)
    for suffix, image in (("hud-only-1", first), ("hud-only-2", last)):
        pixels.write_rgba_png(output / ("client-%s-%s.png" % (actor, suffix)), width, height, image)
    return {"actor": actor, "ui_region": list(region), "identical_terrain": True,
            "gate_rejected": not gate["passed"], "gate_changed_pixels": gate["terrain_changed_pixels"],
            "legacy_row160_would_pass": True, "legacy_row160_changed_pixels": legacy["legacy_row160_changed_pixels"],
            "hud_only_pair_sha256": [hashlib.sha256(image).hexdigest() for image in (first, last)]}


def main() -> int:
    code = PROCESS.main()
    output = Path(sys.argv[sys.argv.index("--output") + 1]).resolve()
    checks, falsifications, error = {}, [], ""
    try:
        for actor in ("a", "b"):
            before, after = output / f"client-{actor}-before.png", output / f"client-{actor}-after.png"
            capture = json.loads((output / f"capture-{actor}.json").read_text())
            # Layer 1: construction certification for BOTH captures.
            region_before = certified_region(capture, actor, "before")
            region_after = certified_region(capture, actor, "after")
            width, height, _ = pixels.rgba(before)
            region = pixels.union_region(region_before, region_after, width, height)
            # Layer 2: terrain-only comparison outside the derived UI region.
            checks[actor] = pixels.terrain_change(before, after, {"x": region[0], "y": region[1], "w": region[2], "h": region[3]})
            # An identical viewport must fail even if a state/geometry hash
            # elsewhere claims the operation was successful.
            if pixels.terrain_change(before, before, {"x": region[0], "y": region[1], "w": region[2], "h": region[3]})["passed"]:
                raise RuntimeError("IDENTICAL_IMAGE_ACCEPTED")
            snapshots = capture["captures"]
            for player in ("a", "b"):
                if snapshots["before"]["snapshot"]["players"][player]["position"] != snapshots["after"]["snapshot"]["players"][player]["position"]:
                    raise RuntimeError("PLAYER_MOVEMENT_CANNOT_SUBSTITUTE_TERRAIN_CHANGE")
            # Layer 3: explicit HUD-only falsification (negative control).
            falsifications.append(hud_only_falsification(output, actor, before, region_before, region_after))
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        error = type(exc).__name__ + ":" + str(exc)
    positive = {actor: row["passed"] and row["terrain_changed_pixels"] >= pixels.MINIMUM_TERRAIN_PIXELS for actor, row in checks.items()}
    passed = code == 0 and not error and len(checks) == 2 and all(positive.values()) and len(falsifications) == 2
    report = {
        "schema": "distributed_world_simulator.mvp4_visible_terrain_gate.v2",
        "passed": passed,
        "process_exit_code": code,
        "positive_control_actual_terrain_mutation": positive,
        "checks": checks,
        "hud_only_negative_control": {"rejected_all": len(falsifications) == 2 and all(f["gate_rejected"] and f["identical_terrain"] for f in falsifications), "cases": falsifications},
        "error": error,
        "manual_input_executed": False,
        "mvp4_predicate_verified": False,
    }
    (output / "visible-acceptance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
