"""ECO.EVO4/E4.B6 - region materialization manifest exporter.

Consumes the ACCEPTED E3.FINAL unseen-world program and the B1 extended
catalog, selects one combination (polar-plateau-04 / extended_r1), and emits a
deterministic instance manifest for the Godot materialization lab:
every ESTABLISHED patch evaluation of every COLONIZED species becomes a patch
population; instance seeds/positions/yaws are keyed by
(genome_checksum | stable_spatial_key | instance_index).
Presentation layer only; zero chain-hash impact. Pure stdlib.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROGRAM_PATH = ROOT / "validation/ecology/eco-evo3-e3-final-unseen-world-program.generated.json"
B1_PATH = ROOT / "validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json"
EXTENDED_CATALOG_PATH = ROOT / (
    "config/ecology/accepted_inputs/e3_final/evo2_persisted_species_catalog.e3_final_extended_r1.v1.json"
)
OUT_PATH = ROOT / "validation/ecology/evo4_b6_region_manifest.v1.json"

SCHEMA = "distributed_world_simulator.ecology.evo4_b6_region_manifest.v1"
VERSION = "1.0.0"
TARGET_INSTANCES_PER_PATCH = 10


def _unit(text: str) -> float:
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:12], 16) / float(2 ** 48)


def _patch_center(stable_key: str) -> tuple[float, float]:
    digits = "".join(ch for ch in stable_key if ch.isdigit())[-2:]
    index = int(digits) if digits else 0
    cols, rows = 4, 3
    gx, gy = index % cols, (index // cols) % rows
    return (gx - (cols - 1) / 2.0) * 7.0, (gy - (rows - 1) / 2.0) * 6.0


def _load_derivation():
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "evo4_bridge_derivation_v0", ROOT / "scripts/research/ecology/evo4_bridge_derivation_v0.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["evo4_bridge_derivation_v0"] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    derivation = _load_derivation()
    program = json.loads(PROGRAM_PATH.read_text(encoding="utf-8"))
    b1 = json.loads(B1_PATH.read_bytes().decode("utf-8"))
    by_lineage: dict[str, dict] = {}
    for entry in b1["entries"]:
        by_lineage[entry["lineage_id"]] = {
            "development_traits": entry["development_traits"],
            "genome": entry["genome"],
            "seed": int(entry["evo4_bridge"]["individual_seed_demo"]),
            "dormancy": 0.25,
        }
    extended = json.loads(EXTENDED_CATALOG_PATH.read_bytes().decode("utf-8"))
    for index, entry in enumerate(extended["entries"]):
        lineage_id = entry["lineage_id"]
        if lineage_id in by_lineage:
            continue
        genome = entry["genome"]
        traits = derivation.derive_traits(str(genome["genome_id"]), genome)
        by_lineage[lineage_id] = {
            "development_traits": traits,
            "genome": genome,
            "seed": derivation.demo_individual_seed(
                str(extended["bake_id"]), lineage_id, str(genome["checksum"]), index
            ),
            "dormancy": float(entry.get("recruitment_traits", {}).get("dormancy_fraction", 0.25)),
        }

    combos = [
        c for c in program["combinations"]
        if c["catalog"]["variant"] == "extended_r1" and "polar" in str(c["stable_planet_identity"])
    ]
    if len(combos) != 1:
        raise SystemExit(f"expected exactly one polar/extended_r1 combo, got {len(combos)}")
    combo = combos[0]

    instances = []
    for species_program in combo["colonization_program"]["species_programs"]:
        if species_program["status"] != "COLONIZED":
            continue
        lineage_id = species_program["lineage_id"]
        entry = by_lineage.get(lineage_id)
        if entry is None:
            continue
        genome_checksum = entry["development_traits"]["checksum"]
        base_seed = int(entry["seed"])
        lifespan_years = float(entry["genome"]["lifespan_years"])
        evaluations = [
            pe for pe in species_program["patch_evaluations"] if pe["decision"] == "ESTABLISHED"
        ]
        evaluations.sort(key=lambda pe: pe["research_patch_id"])  # deterministic order
        for rank, evaluation in enumerate(evaluations):
            key = evaluation["stable_spatial_key"]
            cx, cz = _patch_center(key)
            cohort_age = round(min(lifespan_years, 1.0 + float(evaluation["establishment_score_ppm"]) / 100000.0), 2)
            for i in range(TARGET_INSTANCES_PER_PATCH):
                seed_material = f"{genome_checksum}|{key}|{i}"
                digest = hashlib.sha256(seed_material.encode("utf-8")).hexdigest()
                angle = 2.0 * math.pi * _unit(digest[:24] + "/a")
                radius = 2.6 * math.sqrt(_unit(digest[:24] + "/r"))
                instances.append(
                    {
                        "genome_id": entry["genome"]["genome_id"],
                        "lineage_id": lineage_id,
                        "individual_seed": int(digest[:15], 16),
                        "variant_index": (base_seed + i * 131) % 8,
                        "stable_spatial_key": key,
                        "patch_rank": rank,
                        "cohort_age_years": cohort_age,
                        "position": [round(cx + radius * math.cos(angle), 3), round(radius * math.sin(angle), 3)],
                        "yaw_rad": round(2.0 * math.pi * _unit(digest[:24] + "/y"), 4),
                        "scale": round(0.80 + 0.45 * _unit(digest[:24] + "/s"), 3),
                    }
                )

    document = {
        "schema": SCHEMA,
        "version": VERSION,
        "derived_representation": True,
        "source_program_sha256": hashlib.sha256(PROGRAM_PATH.read_bytes()).hexdigest(),
        "source_combination": {
            "stable_planet_identity": combo["stable_planet_identity"],
            "catalog_variant": combo["catalog"]["variant"],
            "planet_snapshot_sha256": combo["planet_snapshot"]["sha256"],
        },
        "instances_per_patch": TARGET_INSTANCES_PER_PATCH,
        "species_traits": {
            entry["genome"]["genome_id"]: {
                "development_traits": entry["development_traits"],
                "water_preference": float(entry["genome"].get("water_preference", 0.5)),
                "shade_tolerance": float(entry["genome"].get("shade_tolerance", 0.3)),
                "dormancy_fraction": float(entry.get("dormancy", 0.25)),
                "variant_base_seed": int(entry["seed"]),
            }
            for entry in by_lineage.values()
        },
        "instances": instances,
    }
    OUT_PATH.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    digest = hashlib.sha256(OUT_PATH.read_bytes()).hexdigest()
    species_count = len({i["genome_id"] for i in instances})
    print(f"EVO4_B6_MANIFEST_WRITTEN instances={len(instances)} species={species_count} sha256={digest[:16]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
