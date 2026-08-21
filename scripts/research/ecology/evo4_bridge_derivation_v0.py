"""ECO.EVO4/E4.B0 - Morphology Bridge derivation v0 (authorized demo pipe).

Reads the accepted persisted SpeciesCatalog, derives PH0 DevelopmentTraits v0
deterministically from metabolic genome fields (honesty rule B1-v0: derivation
only, no new selection surface), computes the GDScript-compatible trait
checksum bit-exactly, derives a demo IndividualSeed per the PH0 spirit
(hash of genome identity + context, not a heredity event), and emits the
bridge input JSON consumed by the E4.B0 Godot demo lab.

Research layer only: touches no accepted surface, creates no population truth.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CATALOG_PATH = ROOT / "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
OUT_PATH = ROOT / "validation/ecology/evo4_b0_bridge_input.v1.json"

TRAITS_SCHEMA = "distributed_world_simulator.ecology.plant_development_traits.v1"
TRAITS_VERSION = "1.0.0"
RULE_ID = "evo4-b0-derivation-v0"


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def gd_format(value: float) -> str:
    # Mirrors GDScript "%.9f" formatting used by plant_development_traits_v1.compute_checksum.
    return "%.9f" % value


def compute_traits_checksum(traits_id: str, t: dict[str, float | int]) -> str:
    tokens = [
        TRAITS_SCHEMA,
        TRAITS_VERSION,
        traits_id,
        gd_format(float(t["max_height_m"])),
        gd_format(float(t["internode_length_m"])),
        gd_format(float(t["apical_dominance"])),
        gd_format(float(t["branch_probability"])),
        gd_format(float(t["branch_angle_deg"])),
        gd_format(float(t["branch_length_ratio"])),
        str(int(t["branching_depth"])),
        gd_format(float(t["crown_spread_m"])),
    ]
    payload = "|".join(tokens)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def derive_traits(genome_id: str, genome: dict) -> dict:
    """Fixed v0 mapping metabolic -> developmental. Presentation-side only."""
    height = float(genome["height_m"])
    dispersal = float(genome["seed_dispersal_distance_m"])
    shade = float(genome["shade_tolerance"])
    water_pref = float(genome["water_preference"])
    depth = int(2 + round(shade * 2.0))
    t = {
        "max_height_m": clamp(height * 4.0, 0.10, 40.0),
        "internode_length_m": clamp(height * 0.40, 0.02, 4.0),
        "apical_dominance": clamp(1.0 - dispersal / 40.0, 0.0, 1.0),
        "branch_probability": clamp(float(genome["seed_count"]) / 700.0, 0.0, 1.0),
        "branch_angle_deg": clamp(25.0 + shade * 40.0, 0.0, 89.0),
        "branch_length_ratio": clamp(0.60 + water_pref * 0.35, 0.05, 2.0),
        "branching_depth": clamp(depth, 1, 8),
        "crown_spread_m": clamp(dispersal * 0.08, 0.05, 30.0),
    }
    traits_id = "plant-development/" + RULE_ID + "/" + genome_id.replace("genome/", "genome-")
    traits = {
        "schema": TRAITS_SCHEMA,
        "version": TRAITS_VERSION,
        "traits_id": traits_id,
        **t,
    }
    traits["checksum"] = compute_traits_checksum(traits_id, t)
    return traits


def demo_individual_seed(bake_id: str, lineage_id: str, genome_checksum: str, cohort_index: int) -> int:
    digest = hashlib.sha256(
        f"{genome_checksum}|{bake_id}|{lineage_id}|EVO4_B0_DEMO|{cohort_index}".encode("utf-8")
    ).hexdigest()
    return int(digest[:15], 16)


def main() -> int:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    subjects = []
    for index, entry in enumerate(catalog["entries"]):
        genome = entry["genome"]
        traits = derive_traits(str(genome["genome_id"]), genome)
        subjects.append(
            {
                "lineage_id": entry["lineage_id"],
                "genome_id": genome["genome_id"],
                "genome_checksum": genome["checksum"],
                "individual_seed": demo_individual_seed(
                    catalog["bake_id"], entry["lineage_id"], genome["checksum"], index
                ),
                "development_traits": traits,
            }
        )
    document = {
        "schema": "distributed_world_simulator.ecology.evo4_b0_bridge_input.v1",
        "version": "1.0.0",
        "derived_representation": True,
        "source_catalog_schema": catalog["schema"],
        "source_catalog_hash": catalog["catalog_hash"],
        "bake_id": catalog["bake_id"],
        "derivation_rule": RULE_ID,
        "rule_note": (
            "v0 honesty: developmental traits are deterministic derivations of metabolic "
            "genome fields; no independent genes, no ecology coupling, presentation only."
        ),
        "subjects": subjects,
    }
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    blob = hashlib.sha256(OUT_PATH.read_bytes()).hexdigest()
    print(f"EVO4_B0_BRIDGE_INPUT_WRITTEN subjects={len(subjects)} sha256={blob}")
    for s in subjects:
        t = s["development_traits"]
        print(
            f"  {s['genome_id']}: seed={s['individual_seed']} "
            f"h={t['max_height_m']} spread={t['crown_spread_m']} "
            f"apical={t['apical_dominance']} branch_p={t['branch_probability']} "
            f"checksum={t['checksum'][:12]}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
