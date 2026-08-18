from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any, Dict, Iterable

CONTRACT_SCHEMA = "distributed_world_simulator.ecology.evo3_planet_field_snapshot_contract.v1"
FIXTURE_SCHEMA = "distributed_world_simulator.ecology.evo3_planet_field_semantic_fixture.v1"
SNAPSHOT_SCHEMA = "distributed_world_simulator.ecology.evo3_planet_field_snapshot.v1"
VERSION = "1.0.0"
EXPECTED_FOUNDATIONS = ["G", "ENV", "MAT", "WQ", "SD", "TF"]
EXPECTED_PARENT = {
    "e3_0_durable_head": "f1820949fcb89156429e5c150e530ac7da1267b7",
    "e3_0_code_under_test_head": "250cf503c72440972bc8cdfaf4cea95398686ae0",
    "e3_0_architecture_hash": "cbf50695b6db79d543c26168bcfa1bb9ac2e29b052f0eabeafb028ab618a3ac6",
    "e3_0_roadmap_hash": "1b153d5974ab2f922dfe557ce5a9d3eed5a83f904b5c50265d7a28fb6faba178",
    "xfer0_code_under_test_head": "bb80beac95d838b56cccbe5d98f7e1bcbfd80376",
    "xfer0_contract_hash": "06024c88fba045ba98e74594e55dce717d2c8dcd26f3d6a559a789bb5e39d309",
    "xfer0_aggregate_hash": "1adf3d0fa733ed74e3a28bfe1d0632f5d45c62ca5df932bce3e55693a18e9044",
}
SAMPLE_VALUE_FIELDS = ["latitude_microdeg","longitude_microdeg","temperature_milli_c","soil_moisture_ppm","light_availability_ppm","nutrient_availability_ppm","disturbance_pressure_ppm"]
SAMPLE_KEYS = ["sample_id", "stable_spatial_key", *SAMPLE_VALUE_FIELDS, "sample_hash"]
SNAPSHOT_SAMPLE_KEYS = SAMPLE_KEYS + ["field_provenance_hash"]
FORBIDDEN_TOKENS = ("biome", "species", "population", "authority_route", "production_api")


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def sha256_hex(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def object_hash(value: Dict[str, Any], hash_field: str) -> str:
    payload = copy.deepcopy(value)
    payload.pop(hash_field, None)
    return sha256_hex(canonical_bytes(payload))


def load_json(path: Path | str) -> Dict[str, Any]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("root must be object")
    return data


def _exact_keys(obj: Dict[str, Any], expected: Iterable[str], where: str) -> None:
    actual, expected_set = set(obj), set(expected)
    if actual != expected_set:
        raise ValueError(f"{where} keys mismatch")


def _assert_no_forbidden_keys(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            lower = str(key).lower()
            if any(token in lower for token in FORBIDDEN_TOKENS):
                raise ValueError(f"forbidden semantic key {key!r}")
            _assert_no_forbidden_keys(child)
    elif isinstance(value, list):
        for child in value:
            _assert_no_forbidden_keys(child)


def validate_contract(contract: Dict[str, Any]) -> None:
    required = {"schema","version","revision","branch","checkpoint","name","status","research_only","parent","binding","snapshot_semantics","fixture_policy","output_contract","forbidden_promotions","next_gate","contract_hash_algorithm","contract_hash"}
    _exact_keys(contract, required, "contract")
    if contract["schema"] != CONTRACT_SCHEMA or contract["version"] != VERSION or contract["checkpoint"] != "ECO.EVO3/E3.1" or contract["research_only"] is not True:
        raise ValueError("contract identity/scope")
    if contract["parent"] != EXPECTED_PARENT:
        raise ValueError("parent identity mismatch")
    binding = contract["binding"]
    if binding.get("mode") != "RESEARCH_FIXTURE_SEMANTIC_ADAPTER_NO_PRODUCTION_API_BINDING" or binding.get("canonical_bindings_resolved") is not False or binding.get("required_foundations") != EXPECTED_FOUNDATIONS:
        raise ValueError("binding contract")
    if binding.get("owner_references_are_opaque") is not True or binding.get("compiler_may_write_owner_state") is not False or binding.get("production_api_binding_authorized") is not False or binding.get("xfer1_required_for_production_binding") is not True:
        raise ValueError("authority boundary")
    sem = contract["snapshot_semantics"]
    if sem.get("numeric_encoding") != "INTEGER_FIXED_UNITS_V1" or list(sem.get("units", {})) != SAMPLE_VALUE_FIELDS or set(sem.get("bounds", {})) != set(SAMPLE_VALUE_FIELDS):
        raise ValueError("numeric contract")
    policy = contract["fixture_policy"]
    if policy.get("provider_mode") != "RESEARCH_FIXTURE_SEMANTIC_ADAPTER" or policy.get("sample_count") != 12:
        raise ValueError("fixture policy")
    for name in ("all_foundations_required_per_snapshot","unique_sample_ids_required","unique_spatial_keys_required","global_rng_consumption_forbidden","species_fields_forbidden","biome_fields_forbidden","population_fields_forbidden"):
        if policy.get(name) is not True:
            raise ValueError(name)
    output = contract["output_contract"]
    if output.get("schema") != SNAPSHOT_SCHEMA or output.get("authority") != "RESEARCH_DERIVED_NON_AUTHORITATIVE" or output.get("canonical_binding_resolved") is not False:
        raise ValueError("output authority")
    if contract["contract_hash_algorithm"] != "SHA256_CANONICAL_JSON_SORTED_KEYS_V1" or contract["contract_hash"] != object_hash(contract, "contract_hash"):
        raise ValueError("contract hash")


def validate_fixture(fixture: Dict[str, Any], contract: Dict[str, Any]) -> None:
    validate_contract(contract)
    required = {"schema","version","revision","fixture_id","provider_mode","canonical_binding_resolved","stable_planet_identity","stable_time_key","reference_frame_identity","foundation_references","samples","fixture_hash_algorithm","fixture_hash"}
    _exact_keys(fixture, required, "fixture")
    policy = contract["fixture_policy"]
    if fixture["schema"] != FIXTURE_SCHEMA or fixture["version"] != VERSION or fixture["fixture_id"] != policy["fixture_id"] or fixture["provider_mode"] != policy["provider_mode"] or fixture["canonical_binding_resolved"] is not False:
        raise ValueError("fixture identity/binding")
    refs = fixture["foundation_references"]
    if list(refs) != EXPECTED_FOUNDATIONS:
        raise ValueError("foundation refs")
    for fid in EXPECTED_FOUNDATIONS:
        _exact_keys(refs[fid], {"semantic_reference","canonical_binding_resolved"}, fid)
        if not refs[fid]["semantic_reference"] or refs[fid]["canonical_binding_resolved"] is not False:
            raise ValueError("foundation binding")
    samples = fixture["samples"]
    if len(samples) != 12:
        raise ValueError("sample count")
    ids, spatial, bounds = set(), set(), contract["snapshot_semantics"]["bounds"]
    for sample in samples:
        _exact_keys(sample, SAMPLE_KEYS, "sample")
        if sample["sample_id"] in ids or sample["stable_spatial_key"] in spatial:
            raise ValueError("duplicate sample identity")
        ids.add(sample["sample_id"]); spatial.add(sample["stable_spatial_key"])
        for field in SAMPLE_VALUE_FIELDS:
            value = sample[field]
            if type(value) is not int:
                raise ValueError("non-integer field")
            lo, hi = bounds[field]
            if not lo <= value <= hi:
                raise ValueError("field out of bounds")
        if sample["sample_hash"] != object_hash(sample, "sample_hash"):
            raise ValueError("sample hash")
    if fixture["fixture_hash_algorithm"] != "SHA256_CANONICAL_JSON_SORTED_KEYS_V1" or fixture["fixture_hash"] != object_hash(fixture, "fixture_hash"):
        raise ValueError("fixture hash")
    _assert_no_forbidden_keys(fixture)


def _sample_provenance(sample: Dict[str, Any], fixture: Dict[str, Any]) -> str:
    material = {"stable_planet_identity":fixture["stable_planet_identity"],"stable_time_key":fixture["stable_time_key"],"reference_frame_identity":fixture["reference_frame_identity"],"foundation_references":fixture["foundation_references"],"sample":{k:sample[k] for k in SAMPLE_KEYS}}
    return sha256_hex(canonical_bytes(material))


def _build(contract: Dict[str, Any], fixture: Dict[str, Any]) -> Dict[str, Any]:
    samples = []
    for source in sorted(fixture["samples"], key=lambda x: x["stable_spatial_key"]):
        out = copy.deepcopy(source); out["field_provenance_hash"] = _sample_provenance(source, fixture); samples.append(out)
    foundations = copy.deepcopy(fixture["foundation_references"])
    provenance = {"contract_hash":contract["contract_hash"],"source_fixture_hash":fixture["fixture_hash"],"stable_planet_identity":fixture["stable_planet_identity"],"stable_time_key":fixture["stable_time_key"],"reference_frame_identity":fixture["reference_frame_identity"],"foundation_manifest":foundations,"sample_provenance_hashes":[s["field_provenance_hash"] for s in samples]}
    ph = sha256_hex(canonical_bytes(provenance))
    snapshot = {"schema":SNAPSHOT_SCHEMA,"version":VERSION,"snapshot_id":"eco-evo3/e3.1/snapshot/"+ph[:24],"authority":"RESEARCH_DERIVED_NON_AUTHORITATIVE","canonical_binding_resolved":False,"stable_planet_identity":fixture["stable_planet_identity"],"stable_time_key":fixture["stable_time_key"],"reference_frame_identity":fixture["reference_frame_identity"],"foundation_manifest":foundations,"samples":samples,"source_fixture_hash":fixture["fixture_hash"],"field_provenance_hash":ph,"snapshot_hash_algorithm":"SHA256_CANONICAL_JSON_SORTED_KEYS_V1"}
    snapshot["snapshot_hash"] = object_hash(snapshot, "snapshot_hash")
    return snapshot


def build_snapshot(contract: Dict[str, Any], fixture: Dict[str, Any]) -> Dict[str, Any]:
    validate_fixture(fixture, contract)
    snapshot = _build(contract, fixture)
    validate_snapshot(snapshot, contract, fixture)
    return snapshot


def validate_snapshot(snapshot: Dict[str, Any], contract: Dict[str, Any], fixture: Dict[str, Any] | None = None) -> None:
    validate_contract(contract)
    required = {"schema","version","snapshot_id","authority","canonical_binding_resolved","stable_planet_identity","stable_time_key","reference_frame_identity","foundation_manifest","samples","source_fixture_hash","field_provenance_hash","snapshot_hash_algorithm","snapshot_hash"}
    _exact_keys(snapshot, required, "snapshot")
    if snapshot["schema"] != SNAPSHOT_SCHEMA or snapshot["version"] != VERSION or snapshot["authority"] != "RESEARCH_DERIVED_NON_AUTHORITATIVE" or snapshot["canonical_binding_resolved"] is not False:
        raise ValueError("snapshot authority")
    if list(snapshot["foundation_manifest"]) != EXPECTED_FOUNDATIONS:
        raise ValueError("snapshot foundations")
    for ref in snapshot["foundation_manifest"].values():
        _exact_keys(ref, {"semantic_reference","canonical_binding_resolved"}, "snapshot foundation")
        if ref["canonical_binding_resolved"] is not False:
            raise ValueError("canonical foundation")
    keys = [s["stable_spatial_key"] for s in snapshot["samples"]]
    if keys != sorted(keys) or len(keys) != len(set(keys)):
        raise ValueError("snapshot ordering")
    bounds = contract["snapshot_semantics"]["bounds"]
    for sample in snapshot["samples"]:
        _exact_keys(sample, SNAPSHOT_SAMPLE_KEYS, "snapshot sample")
        for field in SAMPLE_VALUE_FIELDS:
            if type(sample[field]) is not int or not bounds[field][0] <= sample[field] <= bounds[field][1]:
                raise ValueError("snapshot field")
        source_shape = {k:sample[k] for k in SAMPLE_KEYS}
        if sample["sample_hash"] != object_hash(source_shape, "sample_hash"):
            raise ValueError("snapshot sample hash")
    if snapshot["snapshot_hash_algorithm"] != "SHA256_CANONICAL_JSON_SORTED_KEYS_V1" or snapshot["snapshot_hash"] != object_hash(snapshot, "snapshot_hash"):
        raise ValueError("snapshot hash")
    _assert_no_forbidden_keys(snapshot)
    if fixture is not None:
        validate_fixture(fixture, contract)
        if snapshot != _build(contract, fixture):
            raise ValueError("snapshot source mismatch")


def write_snapshot(path: Path | str, snapshot: Dict[str, Any]) -> None:
    Path(path).write_bytes(canonical_bytes(snapshot) + b"\n")


def main() -> int:
    p = argparse.ArgumentParser(); p.add_argument("--contract", required=True); p.add_argument("--fixture", required=True); p.add_argument("--output"); p.add_argument("--quiet", action="store_true"); a = p.parse_args()
    contract, fixture = load_json(a.contract), load_json(a.fixture)
    snapshot = build_snapshot(contract, fixture)
    if a.output: write_snapshot(a.output, snapshot)
    if not a.quiet:
        print("ECO.EVO3 E3.1 Planet Field Snapshot: PASS")
        print(f"samples={len(snapshot['samples'])}")
        print(f"contract_hash={contract['contract_hash']}")
        print(f"fixture_hash={fixture['fixture_hash']}")
        print(f"field_provenance_hash={snapshot['field_provenance_hash']}")
        print(f"snapshot_hash={snapshot['snapshot_hash']}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
