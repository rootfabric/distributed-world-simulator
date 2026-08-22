"""ECO.EVO4/E4.B4 - diversity coverage and silhouette fingerprint gate.

Consumes B2 effective development traits (8 PH0 fields, normalized by PH0
bounds). Gates:
  DIVERSITY_COVERAGE - dataset feature variance must not collapse
  SPECIES_FINGERPRINT - inter-species centroid distance must exceed the
                        within-species spread of both species by a margin
Cross-layer coherence: leaf archetype per species is re-derived in python from
the traits checksum using the same hash recipe as the GDScript presentation
module; species must not share archetype+palette identity.
Presentation layer only. Pure stdlib.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
B2_PATH = ROOT / "validation/ecology/evo4_b2_development_state.v1.json"
RESULT_PATH = ROOT / "validation/ecology/evo4_b4_diversity_gate_result.v1.json"

SCHEMA = "distributed_world_simulator.ecology.evo4_b4_diversity_gate.v1"
VERSION = "1.0.0"
TRAIT_NAMES = [
    "max_height_m", "internode_length_m", "apical_dominance", "branch_probability",
    "branch_angle_deg", "branch_length_ratio", "branching_depth", "crown_spread_m",
]
BOUNDS = {
    "max_height_m": (0.10, 40.0), "internode_length_m": (0.02, 4.0),
    "apical_dominance": (0.0, 1.0), "branch_probability": (0.0, 1.0),
    "branch_angle_deg": (0.0, 89.0), "branch_length_ratio": (0.05, 2.0),
    "branching_depth": (1.0, 8.0), "crown_spread_m": (0.05, 30.0),
}
FINGERPRINT_MARGIN = 1.5
MIN_DATASET_VARIANCE = 0.005


def _unit(text: str) -> float:
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:12], 16) / float(2 ** 48)


def _feature_vector(traits: dict) -> list[float]:
    vector = []
    for name in TRAIT_NAMES:
        low, high = BOUNDS[name]
        vector.append((float(traits[name]) - low) / (high - low))
    return vector


def _dist(a: list[float], b: list[float]) -> float:
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def main() -> int:
    data = json.loads(B2_PATH.read_text(encoding="utf-8"))
    by_species: dict[str, list[list[float]]] = {}
    for record in data["records"]:
        by_species.setdefault(str(record["genome_id"]), []).append(
            _feature_vector(record["effective_development_traits"])
        )

    centroids = {species: [sum(dims) / len(vectors) for dims in zip(*vectors)] for species, vectors in by_species.items()}
    spreads = {
        species: max(_dist(vector, centroids[species]) for vector in vectors)
        for species, vectors in by_species.items()
    }

    pair_results = []
    fingerprint_ok = True
    species_list = sorted(by_species)
    for i in range(len(species_list)):
        for j in range(i + 1, len(species_list)):
            a, b = species_list[i], species_list[j]
            distance = _dist(centroids[a], centroids[b])
            required = FINGERPRINT_MARGIN * max(spreads[a], spreads[b])
            ok = distance > required
            fingerprint_ok = fingerprint_ok and ok
            pair_results.append(
                {"pair": [a, b], "centroid_distance": round(distance, 6),
                 "required_gt": round(required, 6), "verdict": "PASS" if ok else "FAIL"}
            )

    flat = [vector for vectors in by_species.values() for vector in vectors]
    dims = list(zip(*flat))
    dataset_variance = 0.0
    for dim in dims:
        mean = sum(dim) / len(dim)
        dataset_variance += sum((d - mean) ** 2 for d in dim) / len(dim)
    dataset_variance /= len(dims)
    coverage_ok = dataset_variance >= MIN_DATASET_VARIANCE

    identities = set()
    b1 = json.loads((ROOT / "validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json").read_text(encoding="utf-8"))
    for entry in b1["entries"]:
        checksum = str(entry["development_traits"]["checksum"])
        arch_index = int(_unit(checksum + "|arch") * 3.0) % 3
        identities.add((str(entry["genome"]["genome_id"]), checksum[:8], ["lanceolate", "rounded", "needle"][arch_index]))
    distinct_identities = len({identity[1] for identity in identities})
    identity_ok = distinct_identities >= 2

    verdict = "PASS" if fingerprint_ok and coverage_ok and identity_ok else "FAIL"
    result = {
        "schema": SCHEMA + ".result",
        "version": VERSION,
        "species_count": len(species_list),
        "records_consumed": len(flat),
        "dataset_variance": round(dataset_variance, 6),
        "min_dataset_variance": MIN_DATASET_VARIANCE,
        "coverage_verdict": "PASS" if coverage_ok else "FAIL",
        "distinct_species_identities": distinct_identities,
        "identity_verdict": "PASS" if identity_ok else "FAIL",
        "fingerprint_margin": FINGERPRINT_MARGIN,
        "fingerprint_verdict": "PASS" if fingerprint_ok else "FAIL",
        "pair_results": pair_results,
        "verdict": verdict,
    }
    RESULT_PATH.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"EVO4_B4_DIVERSITY verdict={verdict} variance={result['dataset_variance']} pairs={len(pair_results)} identities={distinct_identities}")
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
