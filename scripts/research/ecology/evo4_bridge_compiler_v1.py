"""ECO.EVO4/E4.B2 - bridge compiler: catalog entry x conditions x seed x age
-> DevelopmentState + effective PH0-shaped DevelopmentTraits.

Contract: docs/plans/ECO_EVO4_B2_UNIT_MAPPING_CONTRACT_RU.md (rule evo4-b2-plasticity-v0).
Presentation-side only: no ecology truth claims, no retuning of accepted E3.x cores.
Pure stdlib; deterministic across fresh processes.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
B1_ARTIFACT_PATH = ROOT / "validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json"
SNAPSHOT_PATH = ROOT / (
    "config/ecology/accepted_inputs/e3_final/"
    "e3_final_unseen_planet_field_snapshot.arid-basin-02.v1.json"
)
OUTPUT_PATH = ROOT / "validation/ecology/evo4_b2_development_state.v1.json"

DOC_SCHEMA = "distributed_world_simulator.ecology.evo4_b2_development_state.v1"
VERSION = "1.0.0"
RULE_ID = "evo4-b2-plasticity-v0"

PPM_SCALE = 1_000_000.0
BASE_AGE_YEARS = 2.0
COHORT_STEP_YEARS = 1.5

# Independent copy of PH0 bounds (plant_development_traits_v1.gd).
BOUNDS = {
    "max_height_m": (0.10, 40.0),
    "internode_length_m": (0.02, 4.0),
    "apical_dominance": (0.0, 1.0),
    "branch_probability": (0.0, 1.0),
    "branch_angle_deg": (0.0, 89.0),
    "branch_length_ratio": (0.05, 2.0),
    "branching_depth": (1, 8),
    "crown_spread_m": (0.05, 30.0),
}


def _load_module_by_path(name: str, relative: tuple[str, ...]):
    module_path = ROOT.joinpath(*relative)
    spec = importlib.util.spec_from_file_location(name, module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {name} from {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def synthesize_cohort_age(lifespan_years: float, cohort_index: int) -> float:
    return float(min(lifespan_years, BASE_AGE_YEARS + cohort_index * COHORT_STEP_YEARS))


def compile_one(entry: dict, conditions: dict, cohort_age_years: float) -> dict:
    """Contract formulas: scales -> stunting -> clamp -> PH0-exact effective traits."""
    derivation = _load_module_by_path(
        "evo4_bridge_derivation_v0",
        ("scripts/research/ecology/evo4_bridge_derivation_v0.py",),
    )
    base = entry["development_traits"]
    a_light = float(conditions["light_availability_ppm"]) / PPM_SCALE
    a_soil = float(conditions["soil_moisture_ppm"]) / PPM_SCALE
    a_nutrient = float(conditions["nutrient_availability_ppm"]) / PPM_SCALE
    a_disturbance = float(conditions["disturbance_pressure_ppm"]) / PPM_SCALE
    temperature_milli_c = float(conditions["temperature_milli_c"])

    height_scale = _clamp(0.70 + 0.60 * a_light, 0.70, 1.30)
    crown_scale = _clamp(0.70 + 0.60 * a_soil, 0.70, 1.30)
    branch_prob_scale = _clamp(0.80 + 0.40 * a_nutrient, 0.80, 1.20)
    stress_index = _clamp(a_disturbance, 0.0, 1.0)

    effective = dict(base)
    effective["max_height_m"] = _clamp(
        float(base["max_height_m"]) * height_scale * (1.0 - 0.35 * stress_index), *BOUNDS["max_height_m"]
    )
    effective["crown_spread_m"] = _clamp(
        float(base["crown_spread_m"]) * crown_scale, *BOUNDS["crown_spread_m"]
    )
    effective["branch_probability"] = _clamp(
        float(base["branch_probability"]) * branch_prob_scale, *BOUNDS["branch_probability"]
    )
    effective["internode_length_m"] = _clamp(
        float(base["internode_length_m"]) * (1.0 - 0.25 * stress_index), *BOUNDS["internode_length_m"]
    )
    effective["traits_id"] = str(base["traits_id"]) + "+evo4-b2"
    effective["checksum"] = derivation.compute_traits_checksum(effective["traits_id"], effective)

    dormancy_state = "DORMANT_COLD" if temperature_milli_c < 0 else "ACTIVE"
    return {
        "development_state": {
            "age_years": float(cohort_age_years),
            "dormancy_state": dormancy_state,
            "stress_index": stress_index,
            "plasticity_scales": {
                "height_scale": height_scale,
                "crown_scale": crown_scale,
                "branch_prob_scale": branch_prob_scale,
            },
        },
        "effective_development_traits": effective,
    }


def main() -> int:
    point_sampling = _load_module_by_path(
        "evo4_point_sampling_v1", ("scripts/research/ecology/evo4_point_sampling_v1.py",)
    )
    b1_bytes = B1_ARTIFACT_PATH.read_bytes()
    snapshot_bytes = SNAPSHOT_PATH.read_bytes()
    b1 = json.loads(b1_bytes.decode("utf-8"))
    snapshot = json.loads(snapshot_bytes.decode("utf-8"))
    index = point_sampling.build_sample_index(snapshot["samples"])

    records = []
    for entry in b1["entries"]:
        lifespan_years = float(entry["genome"]["lifespan_years"])
        seed = int(entry["evo4_bridge"]["individual_seed_demo"])
        age = synthesize_cohort_age(lifespan_years, cohort_index=0)
        for sample_item in snapshot["samples"]:
            sampled = point_sampling.sample(
                index, sample_item["latitude_microdeg"], sample_item["longitude_microdeg"]
            )
            if not bool(sampled.get("ok", False)):
                raise ValueError(f"sampling failed: {sampled}")
            compiled = compile_one(entry, sampled["conditions"], age)
            records.append(
                {
                    "lineage_id": entry["lineage_id"],
                    "genome_id": entry["genome"]["genome_id"],
                    "stable_spatial_key": sampled["stable_spatial_key"],
                    "sample_id": sampled["sample_id"],
                    "individual_seed_demo": seed,
                    "cohort_age_years": compiled["development_state"]["age_years"],
                    "development_state": compiled["development_state"],
                    "effective_development_traits": compiled["effective_development_traits"],
                }
            )
    document = {
        "schema": DOC_SCHEMA,
        "version": VERSION,
        "derived_representation": True,
        "rule_id": RULE_ID,
        "provenance": {
            "generator": "evo4_bridge_compiler_v1.py",
            "generator_version": VERSION,
            "inputs": {
                "b1_artifact_sha256": hashlib.sha256(b1_bytes).hexdigest(),
                "snapshot_sha256": hashlib.sha256(snapshot_bytes).hexdigest(),
            },
        },
        "records": records,
    }
    payload = json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(payload, encoding="utf-8", newline="\n")
    digest = hashlib.sha256(OUTPUT_PATH.read_bytes()).hexdigest()
    print(f"EVO4_B2_DEVELOPMENT_STATE_WRITTEN records={len(records)} sha256={digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
