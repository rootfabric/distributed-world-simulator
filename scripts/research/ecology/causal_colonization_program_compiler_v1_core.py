#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import pathlib
from typing import Any

PROGRAM_SCHEMA = "distributed_world_simulator.ecology.evo3_e3_4_causal_colonization_program.v1"
PROGRAM_VERSION = "1.0.0"
CHECKPOINT = "ECO.EVO3/E3.4"
STAGE = "COLONIZATION_PROGRAM"
AUTHORITY = "RESEARCH_DERIVED_NON_AUTHORITATIVE"
HASH_ALGORITHM = "SHA256_CANONICAL_JSON_SORTED_KEYS_V1"
PPM = 1_000_000
UNVERIFIED_INPUT_MARKER = "UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION"


def canonical_bytes(value: Any, *, newline: bool = False) -> bytes:
    text = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return (text + ("\n" if newline else "")).encode("utf-8")


def sha256_canonical(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def load_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("E3_4_JSON_ROOT_NOT_OBJECT")
    return value


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def validate_contract(contract: dict[str, Any]) -> None:
    _require(contract.get("schema") == "distributed_world_simulator.ecology.evo3_e3_4_causal_colonization_contract.v1", "E3_4_CONTRACT_SCHEMA")
    _require(contract.get("version") == "1.0.0", "E3_4_CONTRACT_VERSION")
    _require(contract.get("checkpoint") == CHECKPOINT, "E3_4_CONTRACT_CHECKPOINT")
    _require(contract.get("stage") == STAGE, "E3_4_CONTRACT_STAGE")
    _require(contract.get("authority") == AUTHORITY, "E3_4_CONTRACT_AUTHORITY")
    claimed = str(contract.get("contract_hash", ""))
    body = copy.deepcopy(contract)
    body.pop("contract_hash", None)
    _require(claimed == sha256_canonical(body), "E3_4_CONTRACT_HASH")
    policy = contract.get("input_policy", {})
    _require(policy.get("accepted_e3_3_only") is True, "E3_4_INPUT_POLICY_E3_3")
    _require(policy.get("catalog_prefilter_allowed") is False, "E3_4_CATALOG_PREFILTER_FORBIDDEN")
    _require(policy.get("biome_species_table_allowed") is False, "E3_4_BIOME_TABLE_FORBIDDEN")
    _require(policy.get("target_aware_species_injection_allowed") is False, "E3_4_TARGET_INJECTION_FORBIDDEN")
    _require(policy.get("catalog_rebake_allowed") is False, "E3_4_REBAKE_FORBIDDEN")
    _require(policy.get("catalog_target_tuning_allowed") is False, "E3_4_TARGET_TUNING_FORBIDDEN")
    _require(policy.get("all_catalog_entries_enter_source_port") is True, "E3_4_FULL_CATALOG_REQUIRED")
    output = contract.get("output_policy", {})
    for key in (
        "compiled_suitability_is_population_truth",
        "canonical_binding_resolved",
        "production_binding_authorized",
        "canonical_species_taxonomy",
        "canonical_spatial_domain_creation",
        "production_persistence_authority",
        "world_transaction_authority",
        "network_authority",
    ):
        _require(output.get(key) is False, f"E3_4_OUTPUT_BOUNDARY_{key.upper()}")
    _require(contract.get("successor", {}).get("e3_5_authorized") is False, "E3_4_E3_5_MUST_REMAIN_BLOCKED")
    _require(contract.get("determinism", {}).get("global_rng_allowed") is False, "E3_4_GLOBAL_RNG_FORBIDDEN")


def load_contract(path: pathlib.Path) -> dict[str, Any]:
    contract = load_json(path)
    validate_contract(contract)
    return contract


def validate_accepted_binding(binding: dict[str, Any], contract: dict[str, Any]) -> None:
    accepted = contract["accepted_e3_3"]
    _require(binding.get("schema") == "distributed_world_simulator.ecology.evo3_e3_3_accepted_decomposition_binding.v1", "E3_4_BINDING_SCHEMA")
    _require(binding.get("status") == "ACCEPTED", "E3_4_BINDING_STATUS")
    _require(binding.get("checkpoint") == "ECO.EVO3/E3.3", "E3_4_BINDING_CHECKPOINT")
    checks = {
        "canonical_merge_commit": "canonical_merge_commit",
        "reviewed_head": "reviewed_head",
        "executable_freeze": "executable_freeze",
        "decomposition_artifact_git_blob": "decomposition_artifact_git_blob",
        "decomposition_artifact_sha256": "decomposition_artifact_sha256",
        "decomposition_hash": "decomposition_hash",
        "decomposition_provenance_hash": "decomposition_provenance_hash",
    }
    for binding_key, accepted_key in checks.items():
        _require(binding.get(binding_key) == accepted.get(accepted_key), f"E3_4_BINDING_{binding_key.upper()}")
    _require(binding.get("authority") == AUTHORITY, "E3_4_BINDING_AUTHORITY")
    _require(binding.get("canonical_binding_resolved") is False, "E3_4_BINDING_CANONICAL_PROMOTION")
    _require(binding.get("production_binding_authorized") is False, "E3_4_BINDING_PRODUCTION_PROMOTION")


def load_accepted_decomposition(
    path: pathlib.Path,
    binding_path: pathlib.Path,
    contract: dict[str, Any],
) -> dict[str, Any]:
    binding = load_json(binding_path)
    validate_accepted_binding(binding, contract)
    raw = path.read_bytes()
    accepted = contract["accepted_e3_3"]
    _require(hashlib.sha256(raw).hexdigest() == accepted["decomposition_artifact_sha256"], "E3_4_DECOMPOSITION_ARTIFACT_SHA256")
    value = json.loads(raw.decode("utf-8"))
    _require(isinstance(value, dict), "E3_4_DECOMPOSITION_ROOT")
    _require(value.get("decomposition_hash") == accepted["decomposition_hash"], "E3_4_DECOMPOSITION_HASH")
    _require(value.get("decomposition_provenance_hash") == accepted["decomposition_provenance_hash"], "E3_4_DECOMPOSITION_PROVENANCE")
    _require(value.get("authority") == AUTHORITY, "E3_4_DECOMPOSITION_AUTHORITY")
    _require(value.get("canonical_binding_resolved") is False, "E3_4_DECOMPOSITION_CANONICAL_PROMOTION")
    _require(len(value.get("patches", [])) == int(value.get("summary", {}).get("patch_count", -1)), "E3_4_DECOMPOSITION_PATCH_COUNT")
    _require(len(value.get("edges", [])) == int(value.get("summary", {}).get("edge_count", -1)), "E3_4_DECOMPOSITION_EDGE_COUNT")
    _require(len(value.get("regions", [])) == int(value.get("summary", {}).get("region_count", -1)), "E3_4_DECOMPOSITION_REGION_COUNT")
    return value


def validate_catalog(catalog: dict[str, Any], contract: dict[str, Any]) -> None:
    expected = contract["persisted_evo2_catalog"]
    _require(catalog.get("schema") == "distributed_world_simulator.ecology.evo2_species_catalog.v1", "E3_4_CATALOG_SCHEMA")
    _require(catalog.get("version") == "1.0.0", "E3_4_CATALOG_VERSION")
    _require(catalog.get("catalog_hash") == expected["catalog_hash"], "E3_4_CATALOG_HASH")
    entries = catalog.get("entries")
    _require(isinstance(entries, list), "E3_4_CATALOG_ENTRIES")
    _require(len(entries) == expected["entry_count"], "E3_4_CATALOG_ENTRY_COUNT")
    _require(catalog.get("canonical_species_declared") is False, "E3_4_CATALOG_CANONICAL_PROMOTION")
    seen: set[str] = set()
    for entry in entries:
        _require(isinstance(entry, dict), "E3_4_CATALOG_ENTRY_TYPE")
        species_id = str(entry.get("research_species_id", ""))
        _require(species_id.startswith("eco-research-species/") and species_id not in seen, "E3_4_CATALOG_SPECIES_ID")
        seen.add(species_id)
        _require(entry.get("canonical_species_declared") is False, "E3_4_ENTRY_CANONICAL_PROMOTION")
        _require(entry.get("genome_checksum") == entry.get("genome", {}).get("checksum"), "E3_4_GENOME_CHECKSUM_LINK")
        _require(entry.get("recruitment_traits_checksum") == entry.get("recruitment_traits", {}).get("checksum"), "E3_4_RECRUITMENT_CHECKSUM_LINK")
        for key in ("entry_hash", "genome_checksum", "recruitment_traits_checksum", "source_observation_hash"):
            value = str(entry.get(key, ""))
            _require(len(value) == 64 and all(ch in "0123456789abcdef" for ch in value), f"E3_4_CATALOG_{key.upper()}")


def load_full_persisted_catalog(path: pathlib.Path, contract: dict[str, Any]) -> dict[str, Any]:
    raw = path.read_bytes()
    expected = contract["persisted_evo2_catalog"]
    _require(hashlib.sha256(raw).hexdigest() == expected["semantic_artifact_sha256"], "E3_4_CATALOG_ARTIFACT_SHA256")
    value = json.loads(raw.decode("utf-8"))
    _require(isinstance(value, dict), "E3_4_CATALOG_ROOT")
    validate_catalog(value, contract)
    return value


def _ppm_ratio(value: Any) -> int:
    x = float(value)
    _require(0.0 <= x <= 1.0, "E3_4_TRAIT_RATIO_RANGE")
    return int(round(x * PPM))


def _trait_support_ppm(entry: dict[str, Any]) -> int:
    genome = entry["genome"]
    recruitment = entry["recruitment_traits"]
    root_ppm = int(round(float(genome["root_depth_m"]) / 20.0 * PPM))
    seedbank_ppm = int(round(float(recruitment["seed_bank_half_life_years"]) / 100.0 * PPM))
    values = [
        _ppm_ratio(genome["water_tolerance_width"]),
        _ppm_ratio(genome["shade_tolerance"]),
        max(0, min(PPM, root_ppm)),
        _ppm_ratio(recruitment["dormancy_fraction"]),
        max(0, min(PPM, seedbank_ppm)),
    ]
    return sum(values) // len(values)


def _dispersal_capacity_ppm(entry: dict[str, Any]) -> int:
    genome = entry["genome"]
    distance_milli = int(round(float(genome["seed_dispersal_distance_m"]) * 1000.0))
    return min(PPM, max(0, distance_milli * 10 + int(genome["seed_count"]) * 500))


def _establishment_score_ppm(patch: dict[str, Any], trait_support_ppm: int, dimensions: list[str]) -> int:
    vector = patch["opportunity_vector"]
    base = min(int(vector[name]) for name in dimensions)
    modifier = min(PPM, 500_000 + trait_support_ppm // 2)
    return base * modifier // PPM


def _manifest(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "research_species_id": entry["research_species_id"],
        "lineage_id": entry["lineage_id"],
        "entry_hash": entry["entry_hash"],
        "genome_checksum": entry["genome_checksum"],
        "recruitment_traits_checksum": entry["recruitment_traits_checksum"],
        "source_observation_hash": entry["source_observation_hash"],
    }


def _best_route(
    patch_id: str,
    established: set[str],
    edges: list[dict[str, Any]],
    capacity: int,
) -> tuple[int, str, str] | None:
    candidates: list[tuple[int, str, str]] = []
    for edge in edges:
        a = str(edge["patch_a_id"])
        b = str(edge["patch_b_id"])
        if patch_id == a and b in established:
            origin = b
        elif patch_id == b and a in established:
            origin = a
        else:
            continue
        arrival = capacity * int(edge["continuity_ppm"]) // PPM
        candidates.append((arrival, str(edge["research_edge_id"]), origin))
    if not candidates:
        return None
    candidates.sort(key=lambda item: (-item[0], item[1], item[2]))
    return candidates[0]


def build_colonization_program(
    contract: dict[str, Any],
    decomposition: dict[str, Any],
    catalog: dict[str, Any],
) -> dict[str, Any]:
    """Build the scientific result only; parsed inputs never gain accepted provenance here."""
    validate_contract(contract)
    validate_catalog(catalog, contract)
    _require(decomposition.get("authority") == AUTHORITY, "E3_4_BUILD_DECOMPOSITION_AUTHORITY")
    _require(decomposition.get("canonical_binding_resolved") is False, "E3_4_BUILD_DECOMPOSITION_CANONICAL")
    _require(decomposition.get("decomposition_hash") == contract["accepted_e3_3"]["decomposition_hash"], "E3_4_BUILD_DECOMPOSITION_HASH")
    _require(decomposition.get("decomposition_provenance_hash") == contract["accepted_e3_3"]["decomposition_provenance_hash"], "E3_4_BUILD_DECOMPOSITION_PROVENANCE")

    patches = sorted(decomposition["patches"], key=lambda p: (str(p["stable_spatial_key"]), str(p["research_patch_id"])))
    _require(bool(patches), "E3_4_NO_PATCHES")
    patch_by_id = {str(p["research_patch_id"]): p for p in patches}
    _require(len(patch_by_id) == len(patches), "E3_4_DUPLICATE_PATCH_ID")
    edges = sorted(decomposition.get("edges", []), key=lambda e: str(e["research_edge_id"]))
    for edge in edges:
        _require(edge["patch_a_id"] in patch_by_id and edge["patch_b_id"] in patch_by_id, "E3_4_EDGE_ENDPOINT_UNKNOWN")
        _require(0 <= int(edge["continuity_ppm"]) <= PPM, "E3_4_EDGE_CONTINUITY_RANGE")

    source_patch = patches[0]
    source_patch_id = str(source_patch["research_patch_id"])
    source_key = str(source_patch["stable_spatial_key"])
    entries = list(catalog["entries"])
    manifests = [_manifest(entry) for entry in entries]
    species_ids = [str(entry["research_species_id"]) for entry in entries]
    _require(len(species_ids) == int(contract["persisted_evo2_catalog"]["entry_count"]), "E3_4_BUILD_FULL_CATALOG_COUNT")

    model = contract["causal_model"]
    dimensions = list(model["opportunity_dimensions"])
    min_establishment = int(model["minimum_establishment_ppm"])
    min_arrival = int(model["minimum_edge_arrival_ppm"])
    species_programs: list[dict[str, Any]] = []
    colonized_patch_union: set[str] = set()
    total_establishments = 0

    for entry in entries:
        trait_support = _trait_support_ppm(entry)
        capacity = _dispersal_capacity_ppm(entry)
        scores = {str(p["research_patch_id"]): _establishment_score_ppm(p, trait_support, dimensions) for p in patches}
        evaluations: dict[str, dict[str, Any]] = {}
        for patch in patches:
            pid = str(patch["research_patch_id"])
            evaluations[pid] = {
                "research_patch_id": pid,
                "stable_spatial_key": str(patch["stable_spatial_key"]),
                "establishment_score_ppm": scores[pid],
                "arrival_pressure_ppm": 0,
                "route_edge_id": "",
                "route_origin_patch_id": "",
                "decision": "UNREACHABLE",
            }

        established: set[str] = set()
        source_eval = evaluations[source_patch_id]
        source_eval["arrival_pressure_ppm"] = PPM
        if scores[source_patch_id] >= min_establishment:
            source_eval["decision"] = "ESTABLISHED"
            established.add(source_patch_id)
        else:
            source_eval["decision"] = "ESTABLISHMENT_REJECTED"

        changed = True
        while changed:
            changed = False
            for patch in patches:
                pid = str(patch["research_patch_id"])
                if pid in established or pid == source_patch_id:
                    continue
                route = _best_route(pid, established, edges, capacity)
                if route is None:
                    continue
                arrival, edge_id, origin_id = route
                current = evaluations[pid]
                if arrival < int(current["arrival_pressure_ppm"]):
                    continue
                current["arrival_pressure_ppm"] = arrival
                current["route_edge_id"] = edge_id
                current["route_origin_patch_id"] = origin_id
                if arrival < min_arrival:
                    current["decision"] = "DISPERSAL_REJECTED"
                elif scores[pid] < min_establishment:
                    current["decision"] = "ESTABLISHMENT_REJECTED"
                else:
                    current["decision"] = "ESTABLISHED"
                    established.add(pid)
                    changed = True

        established_ids = [str(p["research_patch_id"]) for p in patches if str(p["research_patch_id"]) in established]
        status = "COLONIZED" if established_ids else "NO_COLONIZATION"
        colonized_patch_union.update(established_ids)
        total_establishments += len(established_ids)
        species_programs.append({
            "research_species_id": entry["research_species_id"],
            "lineage_id": entry["lineage_id"],
            "entry_hash": entry["entry_hash"],
            "source_port_patch_id": source_patch_id,
            "dispersal_capacity_ppm": capacity,
            "establishment_trait_support_ppm": trait_support,
            "patch_evaluations": [evaluations[str(p["research_patch_id"])] for p in patches],
            "established_patch_ids": established_ids,
            "status": status,
        })

    colonized_species = sum(1 for item in species_programs if item["status"] == "COLONIZED")
    filtered_species = len(species_programs) - colonized_species
    overall = "COLONIZATION_PRESENT" if colonized_species else "NO_COLONIZATION"
    provenance = {"input_verification": UNVERIFIED_INPUT_MARKER}
    program: dict[str, Any] = {
        "schema": PROGRAM_SCHEMA,
        "version": PROGRAM_VERSION,
        "checkpoint": CHECKPOINT,
        "compiler_stage": STAGE,
        "authority": AUTHORITY,
        "canonical_binding_resolved": False,
        "production_binding_authorized": False,
        "source_decomposition": {
            "decomposition_hash": decomposition["decomposition_hash"],
            "decomposition_provenance_hash": decomposition["decomposition_provenance_hash"],
            "stable_planet_identity": decomposition["stable_planet_identity"],
            "stable_time_key": decomposition["stable_time_key"],
            "patch_count": len(patches),
            "edge_count": len(edges),
            "region_count": len(decomposition.get("regions", [])),
        },
        "source_catalog": {
            "catalog_hash": catalog["catalog_hash"],
            "bake_id": catalog["bake_id"],
            "source_run_hash": catalog["source_run_hash"],
            "entry_count": len(entries),
        },
        "input_species_manifest": manifests,
        "source_port": {
            "selection": contract["source_port"]["selection"],
            "research_patch_id": source_patch_id,
            "stable_spatial_key": source_key,
            "species_entry_count": len(entries),
            "species_ids": species_ids,
        },
        "causal_thresholds": {
            "minimum_establishment_ppm": min_establishment,
            "minimum_edge_arrival_ppm": min_arrival,
        },
        "species_programs": species_programs,
        "colonization_result": overall,
        "summary": {
            "input_species_count": len(entries),
            "colonized_species_count": colonized_species,
            "filtered_species_count": filtered_species,
            "colonized_patch_count": len(colonized_patch_union),
            "total_species_patch_establishments": total_establishments,
            "no_colonization": overall == "NO_COLONIZATION",
        },
        "provenance": provenance,
        "provenance_hash": sha256_canonical(provenance),
        "colonization_program_hash_algorithm": HASH_ALGORITHM,
    }
    program["colonization_program_hash"] = sha256_canonical(program)
    return program


def validate_program_integrity(program: dict[str, Any]) -> None:
    _require(program.get("schema") == PROGRAM_SCHEMA, "E3_4_PROGRAM_SCHEMA")
    _require(program.get("authority") == AUTHORITY, "E3_4_PROGRAM_AUTHORITY")
    _require(program.get("canonical_binding_resolved") is False, "E3_4_PROGRAM_CANONICAL_PROMOTION")
    _require(program.get("production_binding_authorized") is False, "E3_4_PROGRAM_PRODUCTION_PROMOTION")
    _require(program.get("provenance_hash") == sha256_canonical(program.get("provenance", {})), "E3_4_PROGRAM_PROVENANCE_HASH")
    body = copy.deepcopy(program)
    claimed = str(body.pop("colonization_program_hash", ""))
    _require(claimed == sha256_canonical(body), "E3_4_PROGRAM_HASH")
    manifests = program.get("input_species_manifest", [])
    programs = program.get("species_programs", [])
    _require([x["research_species_id"] for x in manifests] == [x["research_species_id"] for x in programs], "E3_4_PROGRAM_FULL_CATALOG_MANIFEST")
    _require(int(program["source_port"]["species_entry_count"]) == len(manifests), "E3_4_PROGRAM_SOURCE_PORT_COUNT")
    _require(program["source_port"]["species_ids"] == [x["research_species_id"] for x in manifests], "E3_4_PROGRAM_SOURCE_PORT_SPECIES")
    status = program.get("colonization_result")
    _require(status in ("COLONIZATION_PRESENT", "NO_COLONIZATION"), "E3_4_PROGRAM_RESULT")
    _require(bool(program["summary"]["no_colonization"]) == (status == "NO_COLONIZATION"), "E3_4_PROGRAM_NULL_RESULT_SEMANTICS")


def serialize_program(program: dict[str, Any]) -> bytes:
    validate_program_integrity(program)
    return canonical_bytes(program, newline=True)


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="ECO EVO3 E3.4 causal colonization program compiler")
    p.add_argument("--contract", type=pathlib.Path, required=True)
    p.add_argument("--accepted-decomposition", type=pathlib.Path, required=True)
    p.add_argument("--accepted-decomposition-binding", type=pathlib.Path, required=True)
    p.add_argument("--persisted-catalog", type=pathlib.Path, required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    p.add_argument("--quiet", action="store_true")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    contract = load_contract(args.contract)
    decomposition = load_accepted_decomposition(args.accepted_decomposition, args.accepted_decomposition_binding, contract)
    catalog = load_full_persisted_catalog(args.persisted_catalog, contract)
    program = build_colonization_program(contract, decomposition, catalog)
    data = serialize_program(program)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    if not args.quiet:
        print("ECO.EVO3 E3.4 Causal Colonization Program Compiler: PASS")
        print(f"colonization_result={program['colonization_result']}")
        print(f"input_species_count={program['summary']['input_species_count']}")
        print(f"colonized_species_count={program['summary']['colonized_species_count']}")
        print(f"colonized_patch_count={program['summary']['colonized_patch_count']}")
        print(f"colonization_program_hash={program['colonization_program_hash']}")
        print(f"artifact_sha256={hashlib.sha256(data).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
