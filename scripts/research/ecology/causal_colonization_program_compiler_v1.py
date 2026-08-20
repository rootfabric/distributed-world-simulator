#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import subprocess
from typing import Any

_CORE_PATH = pathlib.Path(__file__).with_name("causal_colonization_program_compiler_v1_core.py")
_REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]
_E2_8_VALIDATION_PATH = _REPO_ROOT / "validation/ecology/eco-evo2-e2-8-catalog-persistence-validation.json"
_E2_FINAL_VALIDATION_PATH = _REPO_ROOT / "validation/ecology/eco-evo2-final-unseen-world-validation.json"
_SPEC = importlib.util.spec_from_file_location("e34_causal_core", _CORE_PATH)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("E3_4_CORE_IMPORT_FAILED")
_core = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_core)

# Preserve the scientific surface while overriding every authority-sensitive
# loader/build boundary below. The retained core is intentionally incapable of
# emitting accepted-input provenance on its own.
for _name in dir(_core):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_core, _name)

CONTRACT_GIT_BLOB = "de38fbc06a2a733cfac52df5b0345f900f42f117"
BINDING_GIT_BLOB = "84660f5c60da2e7b9dcb9ace0d287321f303a94e"
DECOMPOSITION_GIT_BLOB = "9915bc13b0e81533fdc99ffe5707d0d60ba58eda"
CATALOG_GIT_BLOB = "397ace0c6c7b204793b7663e7a89417d44ba3484"
E2_8_VALIDATION_GIT_BLOB = "47d55332591ef59fcf324701fece19df10781d44"
E2_FINAL_VALIDATION_GIT_BLOB = "bd7999a7bbaba4048844333f509994b2668ed227"

GENOME_SCHEMA = "distributed_world_simulator.ecology.plant_genome.v1"
RECRUITMENT_SCHEMA = "distributed_world_simulator.ecology.evo1_recruitment_traits.v1"
CATALOG_SCHEMA = "distributed_world_simulator.ecology.evo2_species_catalog.v1"
CATALOG_ENTRY_SCHEMA = CATALOG_SCHEMA + ".entry"
CATALOG_VERSION = "1.0.0"
SPECIES_CONCEPT = "ECO_RESEARCH_LINEAGE_HYPOTHESIS_V1"
PARENT_P2_7_ACCEPTED_AGGREGATE = "7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe"


class _VerifiedInput(dict[str, Any]):
    def __init__(self, value: dict[str, Any], *, kind: str, raw: bytes, binding_raw: bytes | None = None) -> None:
        super().__init__(value)
        self.kind = kind
        self.raw = bytes(raw)
        self.binding_raw = None if binding_raw is None else bytes(binding_raw)


def _git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def _verify_blob(raw: bytes, expected: str, code: str) -> None:
    _require(_git_blob_sha1(raw) == expected, code)


def _parse_object(raw: bytes, root_code: str) -> dict[str, Any]:
    value = json.loads(raw.decode("utf-8"))
    _require(isinstance(value, dict), root_code)
    return value


def _sha256_text(tokens: list[str], separator: str) -> str:
    return hashlib.sha256(separator.join(tokens).encode("utf-8")).hexdigest()


def _genome_checksum(genome: dict[str, Any]) -> str:
    return _sha256_text([
        GENOME_SCHEMA,
        CATALOG_VERSION,
        str(genome.get("genome_id", "")),
        f"{float(genome.get('height_m', 0.0)):.9f}",
        f"{float(genome.get('growth_rate', 0.0)):.9f}",
        f"{float(genome.get('root_depth_m', 0.0)):.9f}",
        f"{float(genome.get('water_preference', 0.0)):.9f}",
        f"{float(genome.get('water_tolerance_width', 0.0)):.9f}",
        f"{float(genome.get('shade_tolerance', 0.0)):.9f}",
        str(int(genome.get("seed_count", 0))),
        f"{float(genome.get('seed_dispersal_distance_m', 0.0)):.9f}",
        f"{float(genome.get('lifespan_years', 0.0)):.9f}",
    ], "|")


def _recruitment_checksum(traits: dict[str, Any]) -> str:
    return _sha256_text([
        RECRUITMENT_SCHEMA,
        CATALOG_VERSION,
        str(traits.get("trait_id", "")),
        f"{float(traits.get('dormancy_fraction', 0.0)):.12f}",
        f"{float(traits.get('seed_bank_half_life_years', 0.0)):.12f}",
    ], "|")


def _entry_hash(entry: dict[str, Any]) -> str:
    tokens = [
        CATALOG_ENTRY_SCHEMA,
        CATALOG_VERSION,
        str(entry.get("research_species_id", "")),
        str(entry.get("lineage_id", "")),
        str(entry.get("parent_lineage_id", "")),
        str(int(entry.get("split_year", -1))),
        str(entry.get("genome_checksum", "")),
        str(entry.get("recruitment_traits_checksum", "")),
        str(entry.get("source_observation_hash", "")),
        "canonical_species_declared=false",
    ]
    tokens.extend(f"ancestor={value}" for value in entry.get("ancestry_path", []))
    tokens.extend(f"patch={value}" for value in entry.get("observed_patch_ids", []))
    return _sha256_text(tokens, "\n")


def _catalog_hash(catalog: dict[str, Any]) -> str:
    tokens = [
        CATALOG_SCHEMA,
        CATALOG_VERSION,
        SPECIES_CONCEPT,
        PARENT_P2_7_ACCEPTED_AGGREGATE,
        str(catalog.get("bake_id", "")),
        str(catalog.get("source_run_hash", "")),
        "canonical_species_declared=false",
    ]
    tokens.extend(str(entry.get("entry_hash", "")) if isinstance(entry, dict) else "invalid-entry" for entry in catalog.get("entries", []))
    return _sha256_text(tokens, "\n")


def validate_catalog(catalog: dict[str, Any], contract: dict[str, Any]) -> str:
    expected = contract["persisted_evo2_catalog"]
    _require(catalog.get("schema") == CATALOG_SCHEMA, "E3_4_CATALOG_SCHEMA")
    _require(catalog.get("version") == CATALOG_VERSION, "E3_4_CATALOG_VERSION")
    _require(catalog.get("species_concept") == SPECIES_CONCEPT, "E3_4_CATALOG_SPECIES_CONCEPT")
    _require(catalog.get("parent_p2_7_accepted_aggregate") == PARENT_P2_7_ACCEPTED_AGGREGATE, "E3_4_CATALOG_PARENT_AGGREGATE")
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
        _require(entry.get("schema") == CATALOG_ENTRY_SCHEMA and entry.get("version") == CATALOG_VERSION, "E3_4_CATALOG_ENTRY_SCHEMA")
        _require(entry.get("canonical_species_declared") is False, "E3_4_ENTRY_CANONICAL_PROMOTION")

        genome = entry.get("genome")
        traits = entry.get("recruitment_traits")
        _require(isinstance(genome, dict), "E3_4_GENOME_TYPE")
        _require(isinstance(traits, dict), "E3_4_RECRUITMENT_TYPE")
        _require(genome.get("schema") == GENOME_SCHEMA and genome.get("version") == CATALOG_VERSION, "E3_4_GENOME_SCHEMA")
        _require(traits.get("schema") == RECRUITMENT_SCHEMA and traits.get("version") == CATALOG_VERSION, "E3_4_RECRUITMENT_SCHEMA")

        genome_checksum = _genome_checksum(genome)
        recruitment_checksum = _recruitment_checksum(traits)
        _require(genome.get("checksum") == genome_checksum, "E3_4_GENOME_CHECKSUM_CONTENT")
        _require(entry.get("genome_checksum") == genome_checksum, "E3_4_GENOME_CHECKSUM_LINK")
        _require(traits.get("checksum") == recruitment_checksum, "E3_4_RECRUITMENT_CHECKSUM_CONTENT")
        _require(entry.get("recruitment_traits_checksum") == recruitment_checksum, "E3_4_RECRUITMENT_CHECKSUM_LINK")
        _require(entry.get("entry_hash") == _entry_hash(entry), "E3_4_CATALOG_ENTRY_HASH_CONTENT")

    computed = _catalog_hash(catalog)
    _require(catalog.get("catalog_hash") == computed, "E3_4_CATALOG_HASH_CONTENT")
    _require(computed == expected["catalog_hash"], "E3_4_CATALOG_HASH")
    return computed


def load_contract(path: pathlib.Path) -> _VerifiedInput:
    raw = path.read_bytes()
    _verify_blob(raw, CONTRACT_GIT_BLOB, "E3_4_CONTRACT_ARTIFACT_GIT_BLOB")
    contract = _parse_object(raw, "E3_4_CONTRACT_ROOT")
    validate_contract(contract)
    return _VerifiedInput(contract, kind="contract", raw=raw)


def load_accepted_decomposition(path: pathlib.Path, binding_path: pathlib.Path, contract: dict[str, Any]) -> _VerifiedInput:
    _require(isinstance(contract, _VerifiedInput) and contract.kind == "contract", "E3_4_EXACT_RAW_CONTRACT_REQUIRED")
    binding_raw = binding_path.read_bytes()
    raw = path.read_bytes()
    _verify_blob(binding_raw, BINDING_GIT_BLOB, "E3_4_BINDING_ARTIFACT_GIT_BLOB")
    _verify_blob(raw, DECOMPOSITION_GIT_BLOB, "E3_4_DECOMPOSITION_ARTIFACT_GIT_BLOB")
    binding = _parse_object(binding_raw, "E3_4_BINDING_ROOT")
    validate_accepted_binding(binding, contract)
    _require(hashlib.sha256(raw).hexdigest() == contract["accepted_e3_3"]["decomposition_artifact_sha256"], "E3_4_DECOMPOSITION_ARTIFACT_SHA256")
    value = _parse_object(raw, "E3_4_DECOMPOSITION_ROOT")
    _validate_accepted_decomposition(value, contract)
    return _VerifiedInput(value, kind="decomposition", raw=raw, binding_raw=binding_raw)


def _validate_accepted_decomposition(value: dict[str, Any], contract: dict[str, Any]) -> None:
    accepted = contract["accepted_e3_3"]
    _require(value.get("decomposition_hash") == accepted["decomposition_hash"], "E3_4_DECOMPOSITION_HASH")
    _require(value.get("decomposition_provenance_hash") == accepted["decomposition_provenance_hash"], "E3_4_DECOMPOSITION_PROVENANCE")
    _require(value.get("authority") == AUTHORITY, "E3_4_DECOMPOSITION_AUTHORITY")
    _require(value.get("canonical_binding_resolved") is False, "E3_4_DECOMPOSITION_CANONICAL_PROMOTION")
    _require(len(value.get("patches", [])) == int(value.get("summary", {}).get("patch_count", -1)), "E3_4_DECOMPOSITION_PATCH_COUNT")
    _require(len(value.get("edges", [])) == int(value.get("summary", {}).get("edge_count", -1)), "E3_4_DECOMPOSITION_EDGE_COUNT")
    _require(len(value.get("regions", [])) == int(value.get("summary", {}).get("region_count", -1)), "E3_4_DECOMPOSITION_REGION_COUNT")


def load_full_persisted_catalog(path: pathlib.Path, contract: dict[str, Any]) -> _VerifiedInput:
    _require(isinstance(contract, _VerifiedInput) and contract.kind == "contract", "E3_4_EXACT_RAW_CONTRACT_REQUIRED")
    raw = path.read_bytes()
    _verify_blob(raw, CATALOG_GIT_BLOB, "E3_4_CATALOG_ARTIFACT_GIT_BLOB")
    _require(hashlib.sha256(raw).hexdigest() == contract["persisted_evo2_catalog"]["semantic_artifact_sha256"], "E3_4_CATALOG_ARTIFACT_SHA256")
    catalog = _parse_object(raw, "E3_4_CATALOG_ROOT")
    validate_catalog(catalog, contract)
    return _VerifiedInput(catalog, kind="catalog", raw=raw)


def _git_is_ancestor(ancestor: str, descendant: str) -> bool:
    completed = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=_REPO_ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return completed.returncode == 0


def _verify_historical_lineage(
    contract: dict[str, Any],
    catalog_hash: str,
    *,
    e2_8_path: pathlib.Path = _E2_8_VALIDATION_PATH,
    e2_final_path: pathlib.Path = _E2_FINAL_VALIDATION_PATH,
) -> dict[str, Any]:
    expected = contract["persisted_evo2_catalog"]

    e2_8_raw = e2_8_path.read_bytes()
    _verify_blob(e2_8_raw, E2_8_VALIDATION_GIT_BLOB, "E3_4_E2_8_EVIDENCE_GIT_BLOB")
    e2_8 = _parse_object(e2_8_raw, "E3_4_E2_8_EVIDENCE_ROOT")
    _require(e2_8.get("schema") == "distributed_world_simulator.ecology.evo2_checkpoint_validation.v1", "E3_4_E2_8_EVIDENCE_SCHEMA")
    _require(e2_8.get("checkpoint") == "ECO.EVO2/E2.8", "E3_4_E2_8_EVIDENCE_CHECKPOINT")
    _require(e2_8.get("status") == "ACCEPTED_EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_VERIFICATION", "E3_4_E2_8_EVIDENCE_STATUS")
    _require(e2_8.get("decision") == "ACCEPT_E2_8_AND_AUTHORIZE_EVO2_FINAL", "E3_4_E2_8_EVIDENCE_DECISION")
    e2_8_acceptance = e2_8.get("acceptance", {})
    _require(e2_8_acceptance.get("catalog_hash") == catalog_hash, "E3_4_E2_8_CATALOG_HASH")
    _require(e2_8_acceptance.get("catalog_hash") == expected["catalog_hash"], "E3_4_E2_8_CONTRACT_CATALOG_HASH")
    _require(e2_8_acceptance.get("transport_sha256") == expected["e2_8_transport_sha256"], "E3_4_E2_8_TRANSPORT_SHA256")
    _require(int(e2_8_acceptance.get("artifact_bytes", -1)) == int(expected["e2_8_transport_bytes"]), "E3_4_E2_8_TRANSPORT_BYTES")
    _require(e2_8.get("persisted_semantic_identity", {}).get("catalog_entry_count") == expected["entry_count"], "E3_4_E2_8_ENTRY_COUNT")
    _require(e2_8.get("verification", {}).get("fresh_restore_semantic_identity_exact") is True, "E3_4_E2_8_FRESH_RESTORE_IDENTITY")

    e2_final_raw = e2_final_path.read_bytes()
    _verify_blob(e2_final_raw, E2_FINAL_VALIDATION_GIT_BLOB, "E3_4_E2_FINAL_EVIDENCE_GIT_BLOB")
    e2_final = _parse_object(e2_final_raw, "E3_4_E2_FINAL_EVIDENCE_ROOT")
    _require(e2_final.get("schema") == "distributed_world_simulator.ecology.evo2_checkpoint_validation.v1", "E3_4_E2_FINAL_EVIDENCE_SCHEMA")
    _require(e2_final.get("checkpoint") == "ECO.EVO2/E2.FINAL", "E3_4_E2_FINAL_EVIDENCE_CHECKPOINT")
    _require(e2_final.get("status") == "ACCEPTED_EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_VERIFICATION", "E3_4_E2_FINAL_EVIDENCE_STATUS")
    _require(e2_final.get("decision") == "ACCEPT_EVO2_FINAL_AND_CLOSE_EVO2_RESEARCH_ROUTE", "E3_4_E2_FINAL_EVIDENCE_DECISION")
    e2_final_acceptance = e2_final.get("acceptance", {})
    _require(e2_final_acceptance.get("parent_e2_8_aggregate") == e2_8_acceptance.get("aggregate_hash"), "E3_4_E2_FINAL_PARENT_E2_8")
    _require(e2_final_acceptance.get("input_transport_sha256") == e2_8_acceptance.get("transport_sha256"), "E3_4_E2_FINAL_TRANSPORT_LINK")
    _require(e2_final_acceptance.get("catalog_hash") == catalog_hash, "E3_4_E2_FINAL_CATALOG_HASH")
    _require(e2_final_acceptance.get("aggregate_hash") == expected["e2_final_aggregate_hash"], "E3_4_E2_FINAL_AGGREGATE")
    route = e2_final.get("causal_route", {})
    _require(route.get("direct_catalog_reconstruction_bypass") is False, "E3_4_E2_FINAL_RECONSTRUCTION_BYPASS")
    _require(route.get("rebake") is False, "E3_4_E2_FINAL_REBAKE")
    _require(route.get("all_restored_catalog_entries_enter_source_port") is True, "E3_4_E2_FINAL_FULL_SOURCE_PORT")

    anchor = str(expected["historical_eco_anchor"])
    _require(len(anchor) == 40 and all(ch in "0123456789abcdef" for ch in anchor), "E3_4_HISTORICAL_ECO_ANCHOR_FORMAT")
    _require(_git_is_ancestor(anchor, str(e2_8_acceptance.get("code_under_test_head", ""))), "E3_4_HISTORICAL_ECO_ANCHOR_E2_8_LINEAGE")
    _require(_git_is_ancestor(anchor, str(e2_final_acceptance.get("code_under_test_head", ""))), "E3_4_HISTORICAL_ECO_ANCHOR_E2_FINAL_LINEAGE")

    return {
        "persisted_evo2_transport_sha256": e2_8_acceptance["transport_sha256"],
        "persisted_evo2_transport_bytes": int(e2_8_acceptance["artifact_bytes"]),
        "e2_final_aggregate_hash": e2_final_acceptance["aggregate_hash"],
        "historical_eco_anchor": anchor,
        "e2_8_validation_git_blob": E2_8_VALIDATION_GIT_BLOB,
        "e2_final_validation_git_blob": E2_FINAL_VALIDATION_GIT_BLOB,
    }


def _unverified_build(contract: dict[str, Any], decomposition: dict[str, Any], catalog: dict[str, Any]) -> dict[str, Any]:
    return _core.build_colonization_program(contract, decomposition, catalog)


def _reparse_verified_inputs(
    contract_input: _VerifiedInput,
    decomposition_input: _VerifiedInput,
    catalog_input: _VerifiedInput,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    _require(contract_input.kind == "contract", "E3_4_EXACT_RAW_CONTRACT_REQUIRED")
    _require(decomposition_input.kind == "decomposition", "E3_4_EXACT_RAW_DECOMPOSITION_REQUIRED")
    _require(catalog_input.kind == "catalog", "E3_4_EXACT_RAW_CATALOG_REQUIRED")
    _require(decomposition_input.binding_raw is not None, "E3_4_EXACT_RAW_BINDING_REQUIRED")

    contract_raw = contract_input.raw
    binding_raw = decomposition_input.binding_raw
    decomposition_raw = decomposition_input.raw
    catalog_raw = catalog_input.raw
    _verify_blob(contract_raw, CONTRACT_GIT_BLOB, "E3_4_CONTRACT_ARTIFACT_GIT_BLOB")
    _verify_blob(binding_raw, BINDING_GIT_BLOB, "E3_4_BINDING_ARTIFACT_GIT_BLOB")
    _verify_blob(decomposition_raw, DECOMPOSITION_GIT_BLOB, "E3_4_DECOMPOSITION_ARTIFACT_GIT_BLOB")
    _verify_blob(catalog_raw, CATALOG_GIT_BLOB, "E3_4_CATALOG_ARTIFACT_GIT_BLOB")

    contract = _parse_object(contract_raw, "E3_4_CONTRACT_ROOT")
    validate_contract(contract)
    binding = _parse_object(binding_raw, "E3_4_BINDING_ROOT")
    validate_accepted_binding(binding, contract)
    _require(hashlib.sha256(decomposition_raw).hexdigest() == contract["accepted_e3_3"]["decomposition_artifact_sha256"], "E3_4_DECOMPOSITION_ARTIFACT_SHA256")
    decomposition = _parse_object(decomposition_raw, "E3_4_DECOMPOSITION_ROOT")
    _validate_accepted_decomposition(decomposition, contract)
    catalog_sha256 = hashlib.sha256(catalog_raw).hexdigest()
    _require(catalog_sha256 == contract["persisted_evo2_catalog"]["semantic_artifact_sha256"], "E3_4_CATALOG_ARTIFACT_SHA256")
    catalog = _parse_object(catalog_raw, "E3_4_CATALOG_ROOT")
    catalog_hash = validate_catalog(catalog, contract)
    historical = _verify_historical_lineage(contract, catalog_hash)

    provenance = {
        "contract_hash": contract["contract_hash"],
        "accepted_e3_3_merge_commit": binding["canonical_merge_commit"],
        "accepted_e3_3_decomposition_hash": decomposition["decomposition_hash"],
        "accepted_e3_3_decomposition_provenance_hash": decomposition["decomposition_provenance_hash"],
        "persisted_evo2_catalog_hash": catalog_hash,
        "persisted_evo2_catalog_semantic_artifact_sha256": catalog_sha256,
        "persisted_evo2_transport_sha256": historical["persisted_evo2_transport_sha256"],
        "e2_final_aggregate_hash": historical["e2_final_aggregate_hash"],
        "historical_eco_anchor": historical["historical_eco_anchor"],
    }
    return contract, decomposition, catalog, provenance, historical


def build_colonization_program(contract: dict[str, Any], decomposition: dict[str, Any], catalog: dict[str, Any]) -> dict[str, Any]:
    verified = all(isinstance(value, _VerifiedInput) for value in (contract, decomposition, catalog))
    if not verified:
        return _unverified_build(contract, decomposition, catalog)

    contract_value, decomposition_value, catalog_value, provenance, historical = _reparse_verified_inputs(
        contract,
        decomposition,
        catalog,
    )
    program = _core.build_colonization_program(contract_value, decomposition_value, catalog_value)

    transport_sha256 = historical["persisted_evo2_transport_sha256"]
    transport_bytes = int(historical["persisted_evo2_transport_bytes"])
    _require(transport_bytes > 0, "E3_4_VERIFIED_TRANSPORT_BYTES")
    program["source_catalog"]["transport_sha256"] = transport_sha256
    program["source_catalog"]["transport_bytes"] = transport_bytes
    program["provenance"] = provenance
    program["provenance_hash"] = sha256_canonical(provenance)
    program.pop("colonization_program_hash", None)
    program["colonization_program_hash"] = sha256_canonical(program)
    return program


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
