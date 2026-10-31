#!/usr/bin/env python3
"""Read-only preimplementation R3C3 Earth synchronous-hotpath baseline.

This is SOURCE_ONLY evidence of call structure and theoretical sample/attempt
counts, never proof of elapsed milliseconds, actual sampling, or GUI acceptance.
The --require-baseline-blocking option is a RED baseline oracle; remove it from
post-repair GREEN tests rather than modifying this historical source artifact.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def function_source(text: str, name: str) -> str:
    found = re.search(r"^func " + re.escape(name) + r"\(", text, re.M)
    if found is None:
        raise ValueError("missing expected function: " + name)
    following = re.search(r"^(?:func |static func )", text[found.end():], re.M)
    end = found.end() + following.start() if following else len(text)
    return text[found.start():end]


def checked_nonnegative(value: object, label: str) -> int:
    if type(value) is not int or value < 0:
        raise ValueError("missing/invalid configuration integer: " + label)
    return value


def source_is_blocking(root: Path) -> dict[str, bool]:
    world = (root / "scripts/world/earth/procedural_earth_world.gd").read_text(encoding="utf-8")
    app = (root / "scripts/app/earth_app.gd").read_text(encoding="utf-8")
    explorer = (root / "scripts/actors/earth/earth_explorer.gd").read_text(encoding="utf-8")
    placement = (root / "scripts/world/vegetation/earth_placement_system.gd").read_text(encoding="utf-8")

    def contains(code: str, name: str, fragment: str) -> bool:
        return fragment in function_source(code, name)

    result = {
        "setup_builds_global_synchronously":
            contains(world, "setup", "global_earth.mesh = _build_global_mesh()"),
        "setup_requests_local_synchronously":
            contains(world, "setup", "prepare_surface_region(default_direction, false)"),
        "earth_ready_spawns_at_default":
            contains(app, "_ready", "_spawn_explorer_at_canonical_spawn()"),
        "spawn_activates_explorer":
            contains(app, "_spawn_explorer_at_canonical_spawn", "earth_explorer.activate("),
        "activate_teleports":
            contains(explorer, "activate", "teleport_to_direction(direction, altitude_m)"),
        "teleport_enters_body_surface":
            contains(explorer, "teleport_to_direction", "teleport_to_body_surface("),
        "body_surface_requests_local":
            contains(explorer, "teleport_to_body_surface", "earth_world.prepare_surface_region(direction, false)"),
        "surface_builds_mesh":
            contains(world, "prepare_surface_region", "local_surface.mesh = _build_local_mesh()"),
        "surface_regenerates_vegetation":
            contains(world, "prepare_surface_region", "placement_system.regenerate("),
        "recenter_requests_local_synchronously":
            contains(world, "update_for_view", "prepare_surface_region(target_direction, false)"),
        "placement_clears_old_instances_first":
            contains(placement, "regenerate", "_clear_instances()"),
        "placement_generates_trees":
            contains(placement, "regenerate", "_generate_trees("),
        "placement_generates_grass":
            contains(placement, "regenerate", "_generate_grass("),
        "placement_generates_rocks":
            contains(placement, "regenerate", "_generate_rocks("),
    }
    return result


def audit(root: Path = ROOT) -> dict:
    earth_config = json.loads((root / "config/planets/earth.json").read_text(encoding="utf-8"))
    vegetation = json.loads((root / "config/generation/earth_vegetation.json").read_text(encoding="utf-8"))
    global_cfg = earth_config["global"]
    local_cfg = earth_config["local"]

    global_samples = (
        checked_nonnegative(global_cfg["rings"], "global.rings") + 1
    ) * (
        checked_nonnegative(global_cfg["segments"], "global.segments") + 1
    )
    local_samples = 1 + (
        checked_nonnegative(local_cfg["rings"], "local.rings") *
        checked_nonnegative(local_cfg["segments"], "local.segments")
    )
    trees = 4 * (
        checked_nonnegative(vegetation["max_near_trees"], "max_near_trees") +
        checked_nonnegative(vegetation["max_billboard_trees"], "max_billboard_trees")
    )
    grass = 3 * checked_nonnegative(vegetation["max_grass_instances"], "max_grass_instances")
    rocks = 3 * checked_nonnegative(vegetation["max_rocks"], "max_rocks")
    checks = source_is_blocking(root)
    double_init = all(checks[k] for k in (
        "setup_requests_local_synchronously", "earth_ready_spawns_at_default",
        "spawn_activates_explorer", "activate_teleports", "teleport_enters_body_surface",
        "body_surface_requests_local", "surface_builds_mesh",
    ))
    result = {
        "schema": "dws.net_smooth.r3c3_earth_source_audit.v1",
        "evidence_class": "SOURCE_ONLY_BASELINE",
        "not_runtime_acceptance": True,
        "root": str(root),
        "counts_from_config": {
            "global_mesh_sample_positions": global_samples,
            "local_mesh_sample_positions_per_build": local_samples,
            "placement_tree_attempt_upper_bound": trees,
            "placement_grass_attempt_upper_bound": grass,
            "placement_rock_attempt_upper_bound": rocks,
            "placement_total_attempt_upper_bound": trees + grass + rocks,
        },
        "source_call_graph": checks,
        "two_local_build_requests_during_initial_scene": double_init,
        "actual_attempts_or_sample_duration_measured": False,
        "runtime_or_gui_performance_verified": False,
    }
    try:
        proc = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root,
                              capture_output=True, text=True, check=False, timeout=4)
        result["subject_head"] = proc.stdout.strip() if proc.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        result["subject_head"] = ""
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-baseline-blocking", action="store_true")
    args = parser.parse_args()

    try:
        report = audit(args.root.resolve())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print("R3C3 SOURCE AUDIT INCONCLUSIVE: " + str(exc))
        return 2

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, sort_keys=True, indent=2), encoding="utf-8")
    print(json.dumps(report, sort_keys=True, indent=2))
    if args.require_baseline_blocking:
        if not report["two_local_build_requests_during_initial_scene"]:
            print("R3C3 RED oracle no longer reproduces exact source blocking chain")
            return 1
        if not all(report["source_call_graph"].values()):
            print("R3C3 RED oracle source pathway changed")
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
