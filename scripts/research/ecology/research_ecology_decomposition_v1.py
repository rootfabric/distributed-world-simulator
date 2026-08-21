from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any

CONTRACT_SCHEMA = "distributed_world_simulator.ecology.evo3_research_ecology_decomposition_contract.v1"
SOURCE_SCHEMA = "distributed_world_simulator.ecology.evo3_ecological_opportunity_field.v1"
OUTPUT_SCHEMA = "distributed_world_simulator.ecology.evo3_research_ecology_decomposition.v1"
VERSION = "1.0.0"
SCALE = 1_000_000
LONGITUDE_PERIOD_MICRODEG = 360_000_000
NEIGHBOR_COUNT = 2
CONTINUITY_KEYS = (
    "water_opportunity_ppm",
    "light_opportunity_ppm",
    "nutrient_opportunity_ppm",
    "persistence_opportunity_ppm",
    "limiting_resource_opportunity_ppm",
    "establishment_opportunity_ppm",
)

EXPECTED_PARENT = {
    "e3_2_acceptance_revision": "ECO-EVO3-E3.2-2026-08-19-R2-ACCEPTED",
    "e3_2_reviewed_head": "578981af36c2fe101925db024e6b7747c99806ab",
    "e3_2_merge_commit": "83f35d7abe2ebdea3e5afe175833817ad631c5e6",
    "e3_2_code_under_test_head": "f276a5b29a39a00ae15c866a310b20f3ad9fe9c8",
    "e3_2_aggregate_hash": "ef0ed137bf8d2862f4c9cfacee0792dba8079e539daa4bfb7322d7d5da8afc9c",
    "e3_2_contract_hash": "bbb2e4f29ac88da42102ee6c08d239f8e0a72760ab8d1371fdea2cda258ed47d",
    "e3_2_field_provenance_hash": "9be81517eaf0c28503291c5595c0790232b8f88c7ffa9ced2e886ec1f8597aa4",
    "e3_2_opportunity_field_hash": "acba61638f8128b667880f2bd391ab73f6175d0899656bba92657d578d48203c",
    "e3_2_field_artifact_sha256": "59a0af5e40cae5c8a91e487da158edadfd4e127a0390ebe856f78f2365a066ff",
    "e3_2_acceptance_path": "validation/ecology/eco-evo3-e3-2-acceptance.json",
    "e3_0_architecture_hash": "cbf50695b6db79d543c26168bcfa1bb9ac2e29b052f0eabeafb028ab618a3ac6",
}
EXPECTED_INPUT = {
    "mode": "EXACT_ACCEPTED_E3_2_OPPORTUNITY_FIELD_ONLY",
    "materialized_field_path": "config/ecology/accepted_inputs/e3_2_accepted_ecological_opportunity_field.v1.json",
    "e3_1_snapshot_direct_input_forbidden": True,
    "raw_fixture_input_forbidden": True,
    "candidate_alias_input_forbidden": True,
    "artifact_sha256_must_match_parent": True,
    "opportunity_field_hash_must_match_parent": True,
    "field_provenance_must_match_parent": True,
    "canonical_binding_must_remain_unresolved": True,
    "owner_state_write_forbidden": True,
}
EXPECTED_DECOMPOSITION = {
    "patch_model": "ONE_RESEARCH_PATCH_PER_ACCEPTED_E3_2_SAMPLE",
    "patch_order": "LEXICOGRAPHIC_STABLE_SPATIAL_KEY",
    "spatial_metric": "WRAPPED_LAT_LON_MICRODEG_SQUARED_V1",
    "longitude_period_microdeg": LONGITUDE_PERIOD_MICRODEG,
    "neighbor_selection": "TWO_NEAREST_BY_DISTANCE_THEN_STABLE_SPATIAL_KEY",
    "neighbor_count": NEIGHBOR_COUNT,
    "edge_rule": "UNDIRECTED_EDGE_ONLY_IF_NEIGHBOR_SELECTION_IS_MUTUAL",
    "edge_order": "LEXICOGRAPHIC_ENDPOINT_STABLE_SPATIAL_KEYS",
    "continuity_dimensions": list(CONTINUITY_KEYS),
    "opportunity_delta_mean_ppm": "floor(sum(abs(endpoint_dimension_delta))/6)",
    "continuity_ppm": "1000000-opportunity_delta_mean_ppm",
    "region_rule": "CONNECTED_COMPONENTS_OF_MUTUAL_NEAREST_NEIGHBOR_PATCH_GRAPH",
    "region_order": "LEXICOGRAPHIC_MINIMUM_PATCH_STABLE_SPATIAL_KEY",
    "species_identity_partition_key_forbidden": True,
    "biome_label_partition_key_forbidden": True,
    "global_rng_consumption_forbidden": True,
}
EXPECTED_OUTPUT = {
    "schema": OUTPUT_SCHEMA,
    "version": VERSION,
    "authority": "RESEARCH_DERIVED_NON_AUTHORITATIVE",
    "canonical_binding_resolved": False,
    "expected_patch_count": 12,
    "research_patch_ids_namespaced": True,
    "research_region_ids_namespaced": True,
    "research_ids_are_not_canonical_sd_ids": True,
    "source_provenance_retained": True,
    "population_truth_forbidden": True,
    "species_assignment_forbidden": True,
    "biome_label_forbidden": True,
    "canonical_sd_creation_forbidden": True,
    "production_authority_claim_forbidden": True,
}
EXPECTED_NEXT = {
    "on_accept": "AUTHORIZE_E3_4_CAUSAL_COLONIZATION_PROGRAM_COMPILER",
    "e3_4_must_consume_accepted_e3_3_decomposition": True,
    "e3_4_must_consume_full_portable_species_catalog": True,
    "e3_4_null_no_colonization_must_remain_valid": True,
    "production_binding_remains_blocked_on_xfer1": True,
}
SOURCE_SAMPLE_KEYS = {
    "opportunity_id", "stable_spatial_key", "latitude_microdeg", "longitude_microdeg",
    "thermal_context_milli_c", "water_opportunity_ppm", "light_opportunity_ppm",
    "nutrient_opportunity_ppm", "persistence_opportunity_ppm",
    "limiting_resource_opportunity_ppm", "establishment_opportunity_ppm",
    "source_sample_hash", "source_field_provenance_hash", "opportunity_sample_hash",
}
SOURCE_KEYS = {
    "schema", "version", "field_id", "authority", "canonical_binding_resolved",
    "stable_planet_identity", "stable_time_key", "reference_frame_identity",
    "source_snapshot_hash", "source_field_provenance_hash", "derivation_contract_hash",
    "samples", "summary", "field_provenance_hash", "opportunity_field_hash_algorithm",
    "opportunity_field_hash",
}
VECTOR_KEYS = set(CONTINUITY_KEYS)
PATCH_KEYS = {
    "research_patch_id", "stable_spatial_key", "latitude_microdeg", "longitude_microdeg",
    "source_opportunity_id", "source_opportunity_sample_hash", "opportunity_vector",
    "patch_hash",
}
EDGE_KEYS = {
    "research_edge_id", "patch_a_id", "patch_b_id", "endpoint_spatial_keys",
    "spatial_distance_sq_microdeg2", "opportunity_delta_mean_ppm", "continuity_ppm",
    "edge_hash",
}
REGION_KEYS = {
    "research_region_id", "patch_ids", "stable_spatial_keys", "internal_edge_ids",
    "internal_edge_count", "mean_internal_continuity_ppm", "mean_opportunity_ppm",
    "source_opportunity_field_hash", "region_hash",
}
MEAN_KEYS = set(CONTINUITY_KEYS)
FORBIDDEN_OUTPUT_TOKENS = (
    "species", "biome", "population", "canonical_sd", "production_api",
    "authority_route", "world_transaction",
)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    ).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def object_hash(value: dict, field: str) -> str:
    payload = copy.deepcopy(value)
    payload.pop(field, None)
    return sha256_hex(canonical_bytes(payload))


def load_json(path: str | Path) -> dict:
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("root")
    return value


def _keys(value: dict, expected: set[str], where: str) -> None:
    if set(value) != expected:
        raise ValueError(where + " keys")


def _forbidden(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if any(token in str(key).lower() for token in FORBIDDEN_OUTPUT_TOKENS):
                raise ValueError("forbidden key")
            _forbidden(child)
    elif isinstance(value, list):
        for child in value:
            _forbidden(child)
    elif isinstance(value, str):
        if any(token in value.lower() for token in FORBIDDEN_OUTPUT_TOKENS):
            raise ValueError("forbidden string")


def validate_contract(contract: dict) -> None:
    _keys(
        contract,
        {
            "schema", "version", "revision", "branch", "checkpoint", "name", "status",
            "research_only", "parent", "input_policy", "decomposition_semantics",
            "output_contract", "acceptance_gates", "forbidden_promotions", "next_gate",
            "contract_hash_algorithm", "contract_hash",
        },
        "contract",
    )
    if (
        contract["schema"] != CONTRACT_SCHEMA
        or contract["version"] != VERSION
        or contract["checkpoint"] != "ECO.EVO3/E3.3"
        or contract["research_only"] is not True
    ):
        raise ValueError("contract identity")
    if contract["parent"] != EXPECTED_PARENT:
        raise ValueError("parent")
    if contract["input_policy"] != EXPECTED_INPUT:
        raise ValueError("input policy")
    if contract["decomposition_semantics"] != EXPECTED_DECOMPOSITION:
        raise ValueError("decomposition semantics")
    if contract["output_contract"] != EXPECTED_OUTPUT:
        raise ValueError("output contract")
    gates = contract["acceptance_gates"]
    if gates.get("fresh_process_replay_count") != 2:
        raise ValueError("fresh process count")
    for key in (
        "exact_accepted_e3_2_artifact_required",
        "same_input_same_bytes_required",
        "fresh_process_bytes_must_match",
        "all_12_patches_retained",
        "mutual_neighbor_graph_recomputed",
        "component_partition_recomputed",
        "semantic_tamper_after_rehash_must_fail",
        "direct_e3_1_or_raw_fixture_input_must_fail",
        "canonical_sd_or_species_partition_injection_must_fail",
        "production_authority_claim_forbidden",
    ):
        if gates.get(key) is not True:
            raise ValueError(key)
    if contract["next_gate"] != EXPECTED_NEXT:
        raise ValueError("next gate")
    if contract["contract_hash_algorithm"] != "SHA256_CANONICAL_JSON_SORTED_KEYS_V1":
        raise ValueError("contract hash algorithm")
    if contract["contract_hash"] != object_hash(contract, "contract_hash"):
        raise ValueError("contract hash")


def validate_source_field(field: dict, contract: dict) -> None:
    validate_contract(contract)
    _keys(field, SOURCE_KEYS, "source field")
    if (
        field["schema"] != SOURCE_SCHEMA
        or field["version"] != VERSION
        or field["authority"] != "RESEARCH_DERIVED_NON_AUTHORITATIVE"
        or field["canonical_binding_resolved"] is not False
    ):
        raise ValueError("source identity")
    parent = contract["parent"]
    if field["derivation_contract_hash"] != parent["e3_2_contract_hash"]:
        raise ValueError("source contract")
    if field["field_provenance_hash"] != parent["e3_2_field_provenance_hash"]:
        raise ValueError("source provenance")
    if field["opportunity_field_hash"] != parent["e3_2_opportunity_field_hash"]:
        raise ValueError("source field hash")
    if field["opportunity_field_hash_algorithm"] != "SHA256_CANONICAL_JSON_SORTED_KEYS_V1":
        raise ValueError("source hash algorithm")
    if field["opportunity_field_hash"] != object_hash(field, "opportunity_field_hash"):
        raise ValueError("source semantic hash")
    if len(field["samples"]) != 12:
        raise ValueError("source sample count")
    spatial_keys = [sample.get("stable_spatial_key") for sample in field["samples"]]
    if spatial_keys != sorted(spatial_keys) or len(set(spatial_keys)) != 12:
        raise ValueError("source sample order")
    sample_hashes = []
    for sample in field["samples"]:
        _keys(sample, SOURCE_SAMPLE_KEYS, "source sample")
        if not sample["stable_spatial_key"]:
            raise ValueError("source spatial key")
        for key in CONTINUITY_KEYS:
            if type(sample[key]) is not int or not 0 <= sample[key] <= SCALE:
                raise ValueError("source opportunity range")
        if type(sample["latitude_microdeg"]) is not int or not -90_000_000 <= sample["latitude_microdeg"] <= 90_000_000:
            raise ValueError("source latitude")
        if type(sample["longitude_microdeg"]) is not int or not -180_000_000 <= sample["longitude_microdeg"] <= 180_000_000:
            raise ValueError("source longitude")
        if sample["opportunity_sample_hash"] != object_hash(sample, "opportunity_sample_hash"):
            raise ValueError("source sample hash")
        sample_hashes.append(sample["opportunity_sample_hash"])
    if len(set(sample_hashes)) != 12:
        raise ValueError("source duplicate sample hash")
    _forbidden(field)


def load_accepted_opportunity_field(path: str | Path, contract: dict) -> dict:
    validate_contract(contract)
    normalized = Path(path).as_posix()
    if not normalized.endswith(contract["input_policy"]["materialized_field_path"]):
        raise ValueError("accepted field path")
    raw = Path(path).read_bytes()
    if sha256_hex(raw) != contract["parent"]["e3_2_field_artifact_sha256"]:
        raise ValueError("accepted field artifact sha")
    field = json.loads(raw.decode("utf-8"))
    if raw != canonical_bytes(field) + b"\n":
        raise ValueError("accepted field canonical bytes")
    validate_source_field(field, contract)
    return field


def _wrapped_longitude_delta(a: int, b: int) -> int:
    delta = abs(a - b)
    return min(delta, LONGITUDE_PERIOD_MICRODEG - delta)


def spatial_distance_sq(a: dict, b: dict) -> int:
    dlat = a["latitude_microdeg"] - b["latitude_microdeg"]
    dlon = _wrapped_longitude_delta(a["longitude_microdeg"], b["longitude_microdeg"])
    return dlat * dlat + dlon * dlon


def _neighbor_map(source_samples: list[dict]) -> dict[str, list[str]]:
    by_key = {sample["stable_spatial_key"]: sample for sample in source_samples}
    result: dict[str, list[str]] = {}
    for key in sorted(by_key):
        ranked = sorted(
            (
                spatial_distance_sq(by_key[key], other),
                other_key,
            )
            for other_key, other in by_key.items()
            if other_key != key
        )
        result[key] = [other_key for _, other_key in ranked[:NEIGHBOR_COUNT]]
    return result


def _patch_id(contract: dict, field: dict, sample: dict) -> str:
    identity = sha256_hex(
        canonical_bytes(
            {
                "source_opportunity_field_hash": field["opportunity_field_hash"],
                "stable_spatial_key": sample["stable_spatial_key"],
                "source_opportunity_sample_hash": sample["opportunity_sample_hash"],
                "derivation_contract_hash": contract["contract_hash"],
            }
        )
    )
    return "eco-evo3/e3.3/patch/" + identity[:24]


def _edge_id(contract: dict, field: dict, key_a: str, key_b: str) -> str:
    identity = sha256_hex(
        canonical_bytes(
            {
                "source_opportunity_field_hash": field["opportunity_field_hash"],
                "endpoint_spatial_keys": [key_a, key_b],
                "derivation_contract_hash": contract["contract_hash"],
            }
        )
    )
    return "eco-evo3/e3.3/edge/" + identity[:24]


def _region_id(contract: dict, field: dict, stable_keys: list[str]) -> str:
    identity = sha256_hex(
        canonical_bytes(
            {
                "source_opportunity_field_hash": field["opportunity_field_hash"],
                "stable_spatial_keys": stable_keys,
                "derivation_contract_hash": contract["contract_hash"],
            }
        )
    )
    return "eco-evo3/e3.3/region/" + identity[:24]


def _build(contract: dict, field: dict) -> dict:
    source_samples = field["samples"]
    by_key = {sample["stable_spatial_key"]: sample for sample in source_samples}
    neighbors = _neighbor_map(source_samples)

    patches = []
    patch_by_key: dict[str, dict] = {}
    for sample in source_samples:
        patch = {
            "research_patch_id": _patch_id(contract, field, sample),
            "stable_spatial_key": sample["stable_spatial_key"],
            "latitude_microdeg": sample["latitude_microdeg"],
            "longitude_microdeg": sample["longitude_microdeg"],
            "source_opportunity_id": sample["opportunity_id"],
            "source_opportunity_sample_hash": sample["opportunity_sample_hash"],
            "opportunity_vector": {key: sample[key] for key in CONTINUITY_KEYS},
        }
        patch["patch_hash"] = object_hash(patch, "patch_hash")
        patches.append(patch)
        patch_by_key[sample["stable_spatial_key"]] = patch

    edge_key_pairs = []
    for key_a in sorted(neighbors):
        for key_b in neighbors[key_a]:
            if key_a < key_b and key_a in neighbors[key_b]:
                edge_key_pairs.append((key_a, key_b))
    edge_key_pairs.sort()

    edges = []
    for key_a, key_b in edge_key_pairs:
        a = by_key[key_a]
        b = by_key[key_b]
        delta_sum = sum(abs(a[key] - b[key]) for key in CONTINUITY_KEYS)
        delta_mean = delta_sum // len(CONTINUITY_KEYS)
        edge = {
            "research_edge_id": _edge_id(contract, field, key_a, key_b),
            "patch_a_id": patch_by_key[key_a]["research_patch_id"],
            "patch_b_id": patch_by_key[key_b]["research_patch_id"],
            "endpoint_spatial_keys": [key_a, key_b],
            "spatial_distance_sq_microdeg2": spatial_distance_sq(a, b),
            "opportunity_delta_mean_ppm": delta_mean,
            "continuity_ppm": SCALE - delta_mean,
        }
        edge["edge_hash"] = object_hash(edge, "edge_hash")
        edges.append(edge)

    graph = {key: set() for key in sorted(by_key)}
    edge_by_pair = {}
    for edge in edges:
        key_a, key_b = edge["endpoint_spatial_keys"]
        graph[key_a].add(key_b)
        graph[key_b].add(key_a)
        edge_by_pair[(key_a, key_b)] = edge

    components = []
    visited: set[str] = set()
    for start in sorted(graph):
        if start in visited:
            continue
        stack = [start]
        visited.add(start)
        component = []
        while stack:
            node = stack.pop()
            component.append(node)
            for other in sorted(graph[node], reverse=True):
                if other not in visited:
                    visited.add(other)
                    stack.append(other)
        components.append(sorted(component))
    components.sort(key=lambda component: component[0])

    regions = []
    for component in components:
        component_set = set(component)
        internal_edges = [
            edge for edge in edges
            if set(edge["endpoint_spatial_keys"]).issubset(component_set)
        ]
        internal_edges.sort(key=lambda edge: tuple(edge["endpoint_spatial_keys"]))
        means = {
            key: sum(by_key[spatial_key][key] for spatial_key in component) // len(component)
            for key in CONTINUITY_KEYS
        }
        region = {
            "research_region_id": _region_id(contract, field, component),
            "patch_ids": [patch_by_key[key]["research_patch_id"] for key in component],
            "stable_spatial_keys": component,
            "internal_edge_ids": [edge["research_edge_id"] for edge in internal_edges],
            "internal_edge_count": len(internal_edges),
            "mean_internal_continuity_ppm": (
                sum(edge["continuity_ppm"] for edge in internal_edges) // len(internal_edges)
                if internal_edges
                else None
            ),
            "mean_opportunity_ppm": means,
            "source_opportunity_field_hash": field["opportunity_field_hash"],
        }
        region["region_hash"] = object_hash(region, "region_hash")
        regions.append(region)

    summary = {
        "patch_count": len(patches),
        "edge_count": len(edges),
        "region_count": len(regions),
        "singleton_region_count": sum(1 for region in regions if len(region["patch_ids"]) == 1),
        "largest_region_patch_count": max(len(region["patch_ids"]) for region in regions),
    }

    provenance = sha256_hex(
        canonical_bytes(
            {
                "source_opportunity_field_hash": field["opportunity_field_hash"],
                "source_field_provenance_hash": field["field_provenance_hash"],
                "derivation_contract_hash": contract["contract_hash"],
                "patch_hashes": [patch["patch_hash"] for patch in patches],
                "edge_hashes": [edge["edge_hash"] for edge in edges],
                "region_hashes": [region["region_hash"] for region in regions],
            }
        )
    )
    output = {
        "schema": OUTPUT_SCHEMA,
        "version": VERSION,
        "decomposition_id": "eco-evo3/e3.3/decomposition/" + provenance[:24],
        "authority": "RESEARCH_DERIVED_NON_AUTHORITATIVE",
        "canonical_binding_resolved": False,
        "stable_planet_identity": field["stable_planet_identity"],
        "stable_time_key": field["stable_time_key"],
        "reference_frame_identity": field["reference_frame_identity"],
        "source_opportunity_field_hash": field["opportunity_field_hash"],
        "source_field_provenance_hash": field["field_provenance_hash"],
        "derivation_contract_hash": contract["contract_hash"],
        "adjacency_model": {
            "spatial_metric": EXPECTED_DECOMPOSITION["spatial_metric"],
            "neighbor_selection": EXPECTED_DECOMPOSITION["neighbor_selection"],
            "neighbor_count": NEIGHBOR_COUNT,
            "edge_rule": EXPECTED_DECOMPOSITION["edge_rule"],
            "continuity_dimensions": list(CONTINUITY_KEYS),
        },
        "patches": patches,
        "edges": edges,
        "regions": regions,
        "summary": summary,
        "decomposition_provenance_hash": provenance,
        "decomposition_hash_algorithm": "SHA256_CANONICAL_JSON_SORTED_KEYS_V1",
    }
    output["decomposition_hash"] = object_hash(output, "decomposition_hash")
    return output


def build_decomposition(contract: dict, field: dict) -> dict:
    validate_source_field(field, contract)
    output = _build(contract, field)
    validate_decomposition(output, contract, field)
    return output


def validate_decomposition(output: dict, contract: dict, field: dict) -> None:
    validate_source_field(field, contract)
    _keys(
        output,
        {
            "schema", "version", "decomposition_id", "authority",
            "canonical_binding_resolved", "stable_planet_identity", "stable_time_key",
            "reference_frame_identity", "source_opportunity_field_hash",
            "source_field_provenance_hash", "derivation_contract_hash",
            "adjacency_model", "patches", "edges", "regions", "summary",
            "decomposition_provenance_hash", "decomposition_hash_algorithm",
            "decomposition_hash",
        },
        "decomposition",
    )
    if (
        output["schema"] != OUTPUT_SCHEMA
        or output["version"] != VERSION
        or output["authority"] != "RESEARCH_DERIVED_NON_AUTHORITATIVE"
        or output["canonical_binding_resolved"] is not False
    ):
        raise ValueError("decomposition identity")
    if (
        output["source_opportunity_field_hash"] != field["opportunity_field_hash"]
        or output["source_field_provenance_hash"] != field["field_provenance_hash"]
        or output["derivation_contract_hash"] != contract["contract_hash"]
    ):
        raise ValueError("decomposition source")
    if output["adjacency_model"] != {
        "spatial_metric": EXPECTED_DECOMPOSITION["spatial_metric"],
        "neighbor_selection": EXPECTED_DECOMPOSITION["neighbor_selection"],
        "neighbor_count": NEIGHBOR_COUNT,
        "edge_rule": EXPECTED_DECOMPOSITION["edge_rule"],
        "continuity_dimensions": list(CONTINUITY_KEYS),
    }:
        raise ValueError("adjacency model")
    if len(output["patches"]) != 12:
        raise ValueError("patch count")
    expected_spatial_keys = [sample["stable_spatial_key"] for sample in field["samples"]]
    if [patch.get("stable_spatial_key") for patch in output["patches"]] != expected_spatial_keys:
        raise ValueError("patch order")
    patch_ids = []
    patch_hashes = []
    for patch in output["patches"]:
        _keys(patch, PATCH_KEYS, "patch")
        _keys(patch["opportunity_vector"], VECTOR_KEYS, "patch opportunity vector")
        if not str(patch["research_patch_id"]).startswith("eco-evo3/e3.3/patch/"):
            raise ValueError("patch namespace")
        if patch["patch_hash"] != object_hash(patch, "patch_hash"):
            raise ValueError("patch hash")
        patch_ids.append(patch["research_patch_id"])
        patch_hashes.append(patch["patch_hash"])
    if len(set(patch_ids)) != 12 or len(set(patch_hashes)) != 12:
        raise ValueError("patch uniqueness")

    edge_pairs = []
    edge_ids = []
    for edge in output["edges"]:
        _keys(edge, EDGE_KEYS, "edge")
        if not str(edge["research_edge_id"]).startswith("eco-evo3/e3.3/edge/"):
            raise ValueError("edge namespace")
        key_a, key_b = edge["endpoint_spatial_keys"]
        if key_a >= key_b:
            raise ValueError("edge endpoint order")
        if edge["continuity_ppm"] != SCALE - edge["opportunity_delta_mean_ppm"]:
            raise ValueError("edge continuity")
        if not 0 <= edge["continuity_ppm"] <= SCALE:
            raise ValueError("edge continuity range")
        if edge["edge_hash"] != object_hash(edge, "edge_hash"):
            raise ValueError("edge hash")
        edge_pairs.append((key_a, key_b))
        edge_ids.append(edge["research_edge_id"])
    if edge_pairs != sorted(edge_pairs) or len(set(edge_pairs)) != len(edge_pairs):
        raise ValueError("edge order")
    if len(set(edge_ids)) != len(edge_ids):
        raise ValueError("edge uniqueness")

    seen_patch_ids = []
    region_ids = []
    region_first_keys = []
    for region in output["regions"]:
        _keys(region, REGION_KEYS, "region")
        _keys(region["mean_opportunity_ppm"], MEAN_KEYS, "region mean opportunity")
        if not str(region["research_region_id"]).startswith("eco-evo3/e3.3/region/"):
            raise ValueError("region namespace")
        if not region["stable_spatial_keys"]:
            raise ValueError("empty region")
        if region["stable_spatial_keys"] != sorted(region["stable_spatial_keys"]):
            raise ValueError("region key order")
        if len(region["patch_ids"]) != len(region["stable_spatial_keys"]):
            raise ValueError("region patch alignment")
        if region["internal_edge_count"] != len(region["internal_edge_ids"]):
            raise ValueError("region edge count")
        if region["source_opportunity_field_hash"] != field["opportunity_field_hash"]:
            raise ValueError("region source")
        if region["region_hash"] != object_hash(region, "region_hash"):
            raise ValueError("region hash")
        seen_patch_ids.extend(region["patch_ids"])
        region_ids.append(region["research_region_id"])
        region_first_keys.append(region["stable_spatial_keys"][0])
    if sorted(seen_patch_ids) != sorted(patch_ids) or len(seen_patch_ids) != len(set(seen_patch_ids)):
        raise ValueError("region partition")
    if len(set(region_ids)) != len(region_ids):
        raise ValueError("region uniqueness")
    if region_first_keys != sorted(region_first_keys):
        raise ValueError("region order")

    summary = output["summary"]
    if set(summary) != {
        "patch_count", "edge_count", "region_count",
        "singleton_region_count", "largest_region_patch_count",
    }:
        raise ValueError("summary keys")
    if (
        summary["patch_count"] != len(output["patches"])
        or summary["edge_count"] != len(output["edges"])
        or summary["region_count"] != len(output["regions"])
        or summary["singleton_region_count"] != sum(
            1 for region in output["regions"] if len(region["patch_ids"]) == 1
        )
        or summary["largest_region_patch_count"] != max(
            len(region["patch_ids"]) for region in output["regions"]
        )
    ):
        raise ValueError("summary")
    if output["decomposition_hash_algorithm"] != "SHA256_CANONICAL_JSON_SORTED_KEYS_V1":
        raise ValueError("decomposition hash algorithm")
    if output["decomposition_hash"] != object_hash(output, "decomposition_hash"):
        raise ValueError("decomposition hash")
    _forbidden(output)
    if output != _build(contract, field):
        raise ValueError("semantic decomposition")


def write_decomposition(path: str | Path, output: dict) -> None:
    Path(path).write_bytes(canonical_bytes(output) + b"\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--accepted-field", required=True)
    parser.add_argument("--output")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    contract = load_json(args.contract)
    field = load_accepted_opportunity_field(args.accepted_field, contract)
    output = build_decomposition(contract, field)
    if args.output:
        write_decomposition(args.output, output)
    if not args.quiet:
        print("ECO.EVO3 E3.3 Research Ecology Decomposition: PASS")
        print(f"patches={output['summary']['patch_count']}")
        print(f"edges={output['summary']['edge_count']}")
        print(f"regions={output['summary']['region_count']}")
        print(f"contract_hash={contract['contract_hash']}")
        print(f"source_opportunity_field_hash={output['source_opportunity_field_hash']}")
        print(f"decomposition_provenance_hash={output['decomposition_provenance_hash']}")
        print(f"decomposition_hash={output['decomposition_hash']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
