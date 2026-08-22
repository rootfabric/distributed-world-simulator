"""ECO.EVO6/R3.1 - deterministic generated-rule outcomes and selection surface.

This adapter keeps the EVO6 rule compiler/generator authoritative for rule
semantics. It materializes two research-only projections from one generated
rule set:
  * visual fates compatible with the existing terrain flyover; and
  * per-cell phenotype fitness surfaces consumed by the Godot P1B mutation
    lineage bridge.

No population truth is introduced here and no accepted P1B/PH kernel is
modified.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))

from evo5_rule_compiler_v1 import apply_rules, compile_rules  # noqa: E402
from evo5_rule_generator_v1 import generate_rules  # noqa: E402

SCHEMA = "distributed_world_simulator.ecology.evo6_r31_generated_outcomes.v1"
VERSION = "1.0.0"
DEFAULT_SEED = "20260823"
DEFAULT_TICKS = 40
DEFAULT_OUTPUT = ROOT / "validation/ecology/evo6_r31_generated_outcomes.v1.json"
TERRAIN_PATH = ROOT / "validation/ecology/evo5_terrain_demo.v1.json"
CELL_SPACING_M = 0.5
CLASS_KEYS = ("terrestrial/low", "terrestrial/tall", "amphibious/low", "amphibious/tall")
PHENOTYPES = (
    ("terrestrial", "low"),
    ("terrestrial", "tall"),
    ("amphibious", "low"),
    ("amphibious", "tall"),
)


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _class_key(root_type: str, form: str) -> str:
    return f"{root_type}/{form}"


def _display_phenotype(cell: dict[str, Any]) -> dict[str, str]:
    zone = str(cell.get("zone", ""))
    features = cell.get("features", {})
    wet = zone == "riverside" or (zone == "ravine_bottom" and "water_dist_m" in features)
    return {
        "root_type": "amphibious" if wet else "terrestrial",
        "form": "tall" if zone == "hill_slopes" else "low",
    }


def _required_neighbour_radius(compiled: list[dict[str, Any]]) -> float | None:
    radii = {
        float(rule["when"]["neighbours"].get("within_r", 0.0))
        for rule in compiled
        if "neighbours" in rule["when"]
    }
    if not radii:
        return None
    if any(radius <= 0.0 for radius in radii):
        raise ValueError("neighbour rule requires positive within_r")
    if len(radii) != 1:
        raise ValueError("mixed neighbour radii require a versioned aggregate contract")
    return next(iter(radii))


def _prepare_cells(cells: list[dict[str, Any]], compiled: list[dict[str, Any]]) -> list[dict[str, Any]]:
    prepared = copy.deepcopy(cells)
    radius_m = _required_neighbour_radius(compiled)
    if radius_m is None:
        return prepared
    for cell in prepared:
        x = int(cell["x"])
        z = int(cell["z"])
        own_height = float(cell["height"])
        count = 0
        taller = 0
        for other in prepared:
            ox = int(other["x"])
            oz = int(other["z"])
            if ox == x and oz == z:
                continue
            distance_m = math.hypot(float(ox - x) * CELL_SPACING_M, float(oz - z) * CELL_SPACING_M)
            if distance_m > radius_m + 1e-12:
                continue
            count += 1
            if float(other["height"]) > own_height:
                taller += 1
        cell.setdefault("features", {})["neighbours"] = {
            "within_r": radius_m,
            "count": count,
            "taller_than_self": taller,
        }
    return prepared


def _site_context(cell: dict[str, Any]) -> dict[str, Any]:
    context = copy.deepcopy(cell.get("context", {}))
    features = copy.deepcopy(cell.get("features", {}))
    context["features"] = features
    effective = context.setdefault("effective_conditions", {})
    height = float(cell.get("height", 1.0))
    effective.setdefault("wind_exposure", round(min(1.0, max(0.0, (height - 1.0) * 0.55)), 3))
    if "snow_cover_frac" in features:
        effective.setdefault("snow_cover_frac", float(features["snow_cover_frac"]))
    return context


def _evaluate_class(
    compiled: list[dict[str, Any]],
    cell: dict[str, Any],
    root_type: str,
    form: str,
    ticks: int,
) -> dict[str, Any]:
    phenotype = {"root_type": root_type, "form": form}
    effects = apply_rules(compiled, _site_context(cell), phenotype)
    vitality_per_tick = float(effects.get("vitality", 0.0))
    death_per_tick = max(0.0, float(effects.get("death_chance", 0.0))) * 10.0
    establishment_per_tick = float(effects.get("seed_establishment", 0.0))
    margin_per_tick = vitality_per_tick - death_per_tick + establishment_per_tick * 0.25
    cumulative_margin = margin_per_tick * float(ticks)
    fitness_weight = min(4.0, max(0.05, 1.0 + margin_per_tick))
    pigment = [round(float(v), 6) for v in effects.get("pigment_shift", [0.0, 0.0, 0.0])]
    return {
        "fitness_weight": round(fitness_weight, 6),
        "score_per_tick": round(margin_per_tick, 6),
        "cumulative_margin": round(cumulative_margin, 6),
        "survived": cumulative_margin > -1.0,
        "pigment": pigment,
        "thorns": int(round(float(effects.get("thorns", 0.0)))),
    }


def _winner_and_spread(class_fitness: dict[str, float]) -> tuple[str, float]:
    ordered = sorted(class_fitness.items(), key=lambda item: (-item[1], item[0]))
    winner = ordered[0][0]
    spread = max(class_fitness.values()) - min(class_fitness.values())
    return winner, round(spread, 6)


def _pick_selection_sites(cells: list[dict[str, Any]], limit: int = 4) -> list[dict[str, Any]]:
    ranked = sorted(cells, key=lambda cell: (-float(cell["fitness_spread"]), str(cell["cell_key"])))
    chosen: list[dict[str, Any]] = []
    winners: set[str] = set()
    for cell in ranked:
        if float(cell["fitness_spread"]) <= 0.0:
            continue
        winner = str(cell["winner_class"])
        if winner in winners:
            continue
        chosen.append(cell)
        winners.add(winner)
        if len(chosen) == limit:
            break
    if len(chosen) < limit:
        used = {str(cell["cell_key"]) for cell in chosen}
        for cell in ranked:
            if float(cell["fitness_spread"]) <= 0.0:
                continue
            if str(cell["cell_key"]) in used:
                continue
            chosen.append(cell)
            used.add(str(cell["cell_key"]))
            if len(chosen) == limit:
                break
    return [
        {
            "site_id": f"site-{index + 1}-{cell['zone']}",
            "cell_key": cell["cell_key"],
            "x": cell["x"],
            "z": cell["z"],
            "zone": cell["zone"],
            "winner_class": cell["winner_class"],
            "fitness_spread": cell["fitness_spread"],
            "class_fitness": cell["class_fitness"],
        }
        for index, cell in enumerate(chosen)
    ]


def selection_surface_digest(sites: list[dict[str, Any]]) -> str:
    tokens: list[str] = [SCHEMA, VERSION, "selection-surface-v1"]
    for site in sorted(sites, key=lambda item: str(item["site_id"])):
        tokens.extend([str(site["site_id"]), str(site["cell_key"])])
        surface = site["class_fitness"]
        for class_key in CLASS_KEYS:
            tokens.append(f"{class_key}={float(surface[class_key]):.6f}")
    return hashlib.sha256("|".join(tokens).encode("utf-8")).hexdigest()


def build_artifact(
    seed: str = DEFAULT_SEED,
    ticks: int = DEFAULT_TICKS,
    terrain: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not isinstance(seed, str) or not seed.strip():
        raise ValueError("seed must be a non-empty string")
    if not isinstance(ticks, int) or ticks <= 0:
        raise ValueError("ticks must be a positive integer")
    if terrain is None:
        terrain = json.loads(TERRAIN_PATH.read_text(encoding="utf-8"))
    cells = terrain.get("cells")
    if not isinstance(cells, list) or not cells:
        raise ValueError("terrain must contain a non-empty cells array")

    raw_rules = generate_rules(seed)
    compiled = compile_rules(raw_rules)
    rule_digest = _digest(raw_rules)
    prepared_cells = _prepare_cells(cells, compiled)
    fates: list[dict[str, Any]] = []
    surfaces: list[dict[str, Any]] = []

    for cell in sorted(prepared_cells, key=lambda item: (int(item.get("z", 0)), int(item.get("x", 0)))):
        x = int(cell["x"])
        z = int(cell["z"])
        class_results: dict[str, dict[str, Any]] = {}
        class_fitness: dict[str, float] = {}
        for root_type, form in PHENOTYPES:
            key = _class_key(root_type, form)
            result = _evaluate_class(compiled, cell, root_type, form, ticks)
            class_results[key] = result
            class_fitness[key] = float(result["fitness_weight"])
        winner, spread = _winner_and_spread(class_fitness)
        cell_key = f"{x}|{z}"
        surfaces.append(
            {
                "cell_key": cell_key,
                "x": x,
                "z": z,
                "zone": str(cell.get("zone", "")),
                "winner_class": winner,
                "fitness_spread": spread,
                "class_fitness": class_fitness,
                "class_results": class_results,
            }
        )

        display = _display_phenotype(cell)
        display_result = class_results[_class_key(display["root_type"], display["form"])]
        fates.append(
            {
                "x": x,
                "z": z,
                "cell_key": cell_key,
                "zone": str(cell.get("zone", "")),
                "phenotype": display,
                "survived": bool(display_result["survived"]),
                "pigment": display_result["pigment"],
                "thorns": int(display_result["thorns"]),
                "fitness_weight": float(display_result["fitness_weight"]),
            }
        )

    selection_sites = _pick_selection_sites(surfaces)
    max_spread = max(float(cell["fitness_spread"]) for cell in surfaces)
    winner_classes = sorted(
        {
            str(cell["winner_class"])
            for cell in surfaces
            if float(cell["fitness_spread"]) > 0.0
        }
    )
    payload: dict[str, Any] = {
        "schema": SCHEMA,
        "version": VERSION,
        "seed": seed,
        "ticks": ticks,
        "terrain_schema": str(terrain.get("schema", "")),
        "rule_digest": rule_digest,
        "rules": raw_rules,
        "fates": fates,
        "selection_sites": selection_sites,
        "selection_surface_digest": selection_surface_digest(selection_sites),
        "metrics": {
            "cell_count": len(fates),
            "neighbour_aggregate_cells": sum(
                1 for cell in prepared_cells if "neighbours" in cell.get("features", {})
            ),
            "snow_context_cells": sum(
                1 for cell in prepared_cells if "snow_cover_frac" in cell.get("features", {})
            ),
            "generated_neighbour_rule_count": sum(
                1 for rule in compiled if "neighbours" in rule["when"]
            ),
            "max_class_fitness_spread": round(max_spread, 6),
            "winner_classes": winner_classes,
            "selection_signal_present": max_spread > 0.0,
        },
    }
    payload["artifact_digest"] = _digest(payload)
    return payload


def write_artifact(
    seed: str = DEFAULT_SEED,
    ticks: int = DEFAULT_TICKS,
    output: Path = DEFAULT_OUTPUT,
) -> dict[str, Any]:
    artifact = build_artifact(seed=seed, ticks=ticks)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(artifact, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return artifact


def main() -> int:
    parser = argparse.ArgumentParser(description="Build EVO6 generated-rule visual/selection artifact")
    parser.add_argument("--seed", default=DEFAULT_SEED)
    parser.add_argument("--ticks", type=int, default=DEFAULT_TICKS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    artifact = write_artifact(args.seed, args.ticks, args.output)
    metrics = artifact["metrics"]
    print(
        "EVO6_R31_GENERATED_OUTCOMES "
        f"seed={artifact['seed']} cells={metrics['cell_count']} "
        f"sites={len(artifact['selection_sites'])} spread={metrics['max_class_fitness_spread']:.6f} "
        f"digest={artifact['artifact_digest']}"
    )
    return 0 if bool(metrics["selection_signal_present"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
