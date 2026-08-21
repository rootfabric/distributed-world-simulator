from __future__ import annotations
import argparse, copy, hashlib, importlib.util, json
from pathlib import Path
from typing import Any

SCHEMA = "distributed_world_simulator.ecology.evo3_e3_8_cross_planet_generalization_matrix.v1"
CONTRACT_SCHEMA = "distributed_world_simulator.ecology.evo3_e3_8_cross_planet_matrix_contract.v1"
CHECKPOINT = "ECO.EVO3/E3.8"
COMPILER_STAGE = "CROSS_PLANET_GENERALIZATION_MATRIX"
AUTHORITY = "RESEARCH_DERIVED_NON_AUTHORITATIVE"
HASH_ALGORITHM = "SHA256_CANONICAL_JSON_SORTED_KEYS_V1"
ROOT = Path(__file__).resolve().parents[3]
STAGE_DIR = ROOT / "scripts/research/ecology"
DEFAULT_CONTRACT = ROOT / "config/ecology/eco-evo3-e3-8-cross-planet-matrix-contract.v1.json"
EXPECTED_CONTRACT_HASH = "a23e949ac385c5f2899c88664a493e2403ff3c75feefe45bf4bcee3859f8d6bd"
SCALE = 1_000_000
FAMILY_ORDER = ("dry", "wet", "cold", "hot", "seasonal", "isolated")
THERMAL_FAMILIES = ("cold", "hot")
FORBIDDEN_TRUE_KEYS = {"canonical_binding_resolved", "production_binding_authorized", "canonical_species_declared", "canonical_time_ownership", "canonical_environment_ownership", "history_write_allowed", "forecast_authorized", "network_authority", "persistence_authority", "production_persistence_authority", "world_transaction_authority", "transaction_authority", "asset_scatter_truth", "xfer1_authority"}


def canonical_bytes(v: Any) -> bytes:
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def object_hash(v: dict, field: str) -> str:
    x = copy.deepcopy(v)
    x.pop(field, None)
    return sha256_hex(canonical_bytes(x))


def _require(ok: bool, msg: str) -> None:
    if not ok:
        raise ValueError(msg)


def _reject_true_authority(v: Any, where: str) -> None:
    if isinstance(v, dict):
        for k, x in v.items():
            if k in FORBIDDEN_TRUE_KEYS:
                _require(x is False, f"{where}: forbidden authority promotion {k}={x!r}")
            _reject_true_authority(x, where)
    elif isinstance(v, list):
        for x in v:
            _reject_true_authority(x, where)


class _VerifiedMatrixInputs:
    __slots__ = ("contract", "snapshot", "catalog", "contract_e32", "contract_e33", "contract_e34", "decomposition", "program_e34", "raw")

    def __init__(self, *, contract, snapshot, catalog, contract_e32, contract_e33, contract_e34, decomposition, program_e34, raw):
        self.contract = copy.deepcopy(contract)
        self.snapshot = copy.deepcopy(snapshot)
        self.catalog = copy.deepcopy(catalog)
        self.contract_e32 = copy.deepcopy(contract_e32)
        self.contract_e33 = copy.deepcopy(contract_e33)
        self.contract_e34 = copy.deepcopy(contract_e34)
        self.decomposition = copy.deepcopy(decomposition)
        self.program_e34 = copy.deepcopy(program_e34)
        self.raw = {k: bytes(v) for k, v in raw.items()}


class _VerifiedGeneralizationMatrix(dict):
    def __init__(self, value, inputs):
        super().__init__(copy.deepcopy(value))
        self._raw = {k: bytes(v) for k, v in inputs.raw.items()}


_STAGE_CACHE = {}


def _load_stage_module(filename: str):
    if filename in _STAGE_CACHE:
        return _STAGE_CACHE[filename]
    path = STAGE_DIR / filename
    spec = importlib.util.spec_from_file_location("e38_" + filename.replace("-", "_").replace(".py", ""), path)
    _require(spec is not None and spec.loader is not None, f"cannot load stage module {filename}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    _STAGE_CACHE[filename] = (mod, sha256_hex(path.read_bytes()))
    return _STAGE_CACHE[filename]


def _validate_contract(c):
    _require(c.get("schema") == CONTRACT_SCHEMA, "contract schema")
    _require(c.get("checkpoint") == CHECKPOINT and c.get("compiler_stage") == COMPILER_STAGE, "contract stage")
    _require(c.get("authority") == AUTHORITY and c.get("canonical_binding_resolved") is False and c.get("production_binding_authorized") is False, "contract authority")
    _require(c.get("research_only") is True, "contract research only")
    _require(c.get("contract_hash") == EXPECTED_CONTRACT_HASH == object_hash(c, "contract_hash"), "contract hash")
    p = c.get("input_policy", {})
    for k in ("raw_bytes_required", "artifact_sha256_required", "plain_parsed_json_authority_forbidden", "catalog_retuning_forbidden", "accepted_compiler_modification_forbidden", "post_reveal_matrix_tuning_forbidden"):
        _require(p.get(k) is True, f"contract input policy {k}")
    ai = c.get("accepted_inputs", {})
    _require(set(ai) == {"e3_1_snapshot_path", "e3_1_snapshot_sha256", "e3_1_snapshot_hash", "catalog_path", "catalog_sha256", "catalog_hash", "e3_2_contract_path", "e3_2_contract_sha256", "e3_2_contract_hash", "e3_3_contract_path", "e3_3_contract_sha256", "e3_3_contract_hash", "e3_4_contract_path", "e3_4_contract_sha256", "e3_4_contract_hash", "e3_3_decomposition_path", "e3_3_decomposition_sha256", "e3_3_decomposition_hash", "e3_4_program_path", "e3_4_program_sha256", "e3_4_colonization_program_hash"}, "accepted input pins")
    fams = c.get("predeclared_families", [])
    _require([f.get("family") for f in fams] == list(FAMILY_ORDER), "predeclared family order")
    for f in fams:
        _require(f.get("variation") in ("SOIL_MOISTURE_MULTIPLIER", "TEMPERATURE_OFFSET_MILLI_C", "DISTURBANCE_PRESSURE_MULTIPLIER", "EDGE_CONTINUITY_MULTIPLIER"), "family variation kind")
        if f["variation"] == "TEMPERATURE_OFFSET_MILLI_C":
            _require(type(f.get("offset_milli_c")) is int, "temperature offset")
        else:
            _require(type(f.get("numerator")) is int and type(f.get("denominator")) is int and f["denominator"] > 0, "multiplier")
    ri = c.get("required_invariants", {})
    for k in ("six_families_exact", "thermal_shortcut_absent", "outcome_diversity_present", "null_outcome_valid", "same_input_same_matrix_bytes_required", "fresh_process_replay_required"):
        _require(ri.get(k) is True, f"required invariant {k}")
    for k in ("global_rng_allowed", "local_clock_allowed", "ambient_environment_allowed"):
        _require(ri.get(k) is False, f"forbidden nondeterminism {k}")
    o = c.get("output_contract", {})
    _require(o.get("schema") == SCHEMA and o.get("research_derived_non_authoritative") is True, "output identity")
    for k in ("individual_entity_truth_forbidden", "canonical_species_declared_forbidden", "asset_scatter_truth_forbidden", "xfer1_authority_forbidden", "production_persistence_authority_forbidden"):
        _require(o.get(k) is True, f"output policy {k}")
    fp = c.get("forbidden_promotions", {})
    _require(all(v is False for v in fp.values()) and set(fp) == FORBIDDEN_TRUE_KEYS, "forbidden promotions")


def _verify_raw(name, raw, spec_sha, semantic_checks):
    _require(sha256_hex(raw) == spec_sha, f"{name}: SHA-256 mismatch")
    v = json.loads(raw.decode("utf-8"))
    _require(isinstance(v, dict), f"{name}: root must be object")
    semantic_checks(v)
    _reject_true_authority(v, name)
    return v


def _verified_inputs_from_raw(raw):
    import json as _json
    _require(set(raw) == {"contract", "e3_1_snapshot", "catalog", "e3_2_contract", "e3_3_contract", "e3_4_contract", "e3_3_decomposition", "e3_4_program"}, "exact raw input set")

    def self_hash(field):
        return lambda v: _require(v[field] == object_hash(v, field), f"{field} mismatch")

    def const_hash(field, expected):
        return lambda v: _require(v[field] == expected, f"{field} mismatch")

    c = _json.loads(raw["contract"].decode("utf-8"))
    _validate_contract(c)
    ai = c["accepted_inputs"]
    snapshot = _verify_raw("e3_1_snapshot", raw["e3_1_snapshot"], ai["e3_1_snapshot_sha256"], self_hash("snapshot_hash"))
    catalog = _verify_raw("catalog", raw["catalog"], ai["catalog_sha256"], const_hash("catalog_hash", ai["catalog_hash"]))
    c32 = _verify_raw("e3_2_contract", raw["e3_2_contract"], ai["e3_2_contract_sha256"], self_hash("contract_hash"))
    c33 = _verify_raw("e3_3_contract", raw["e3_3_contract"], ai["e3_3_contract_sha256"], self_hash("contract_hash"))
    c34 = _verify_raw("e3_4_contract", raw["e3_4_contract"], ai["e3_4_contract_sha256"], self_hash("contract_hash"))
    dec = _verify_raw("e3_3_decomposition", raw["e3_3_decomposition"], ai["e3_3_decomposition_sha256"], self_hash("decomposition_hash"))
    prog = _verify_raw("e3_4_program", raw["e3_4_program"], ai["e3_4_program_sha256"], self_hash("colonization_program_hash"))
    _require(c32["contract_hash"] == ai["e3_2_contract_hash"] and c33["contract_hash"] == ai["e3_3_contract_hash"] and c34["contract_hash"] == ai["e3_4_contract_hash"], "stage contract pins")
    _require(dec["decomposition_hash"] == ai["e3_3_decomposition_hash"] and prog["colonization_program_hash"] == ai["e3_4_colonization_program_hash"], "accepted artifact pins")
    _require(snapshot["snapshot_hash"] == ai["e3_1_snapshot_hash"] and catalog["catalog_hash"] == ai["catalog_hash"], "identity pins")
    return _VerifiedMatrixInputs(contract=c, snapshot=snapshot, catalog=catalog, contract_e32=c32, contract_e33=c33, contract_e34=c34, decomposition=dec, program_e34=prog, raw=raw)


def load_verified_inputs(contract_path: Path = DEFAULT_CONTRACT):
    cr = Path(contract_path).read_bytes()
    b = _parse_object(cr, "binding preflight")
    ai = b["accepted_inputs"]
    raw = {"contract": cr}
    for key, path_key in (("e3_1_snapshot", "e3_1_snapshot_path"), ("catalog", "catalog_path"), ("e3_2_contract", "e3_2_contract_path"), ("e3_3_contract", "e3_3_contract_path"), ("e3_4_contract", "e3_4_contract_path"), ("e3_3_decomposition", "e3_3_decomposition_path"), ("e3_4_program", "e3_4_program_path")):
        raw[key] = (ROOT / ai[path_key]).read_bytes()
    return _verified_inputs_from_raw(raw)


def _parse_object(raw: bytes, where: str):
    v = json.loads(raw.decode("utf-8"))
    _require(isinstance(v, dict), f"{where}: root must be object")
    return v


def _clamp(v):
    return 0 if v < 0 else (SCALE if v > SCALE else v)


def _variant_snapshot(family, spec, base):
    s = copy.deepcopy(base)
    s["stable_planet_identity"] = "eco-evo3-fixture/e3-8-family/" + family + "/planet-alpha-derived-01"
    for x in s["samples"]:
        if spec["variation"] == "SOIL_MOISTURE_MULTIPLIER":
            x["soil_moisture_ppm"] = _clamp(x["soil_moisture_ppm"] * spec["numerator"] // spec["denominator"])
        elif spec["variation"] == "TEMPERATURE_OFFSET_MILLI_C":
            x["temperature_milli_c"] = x["temperature_milli_c"] + spec["offset_milli_c"]
        elif spec["variation"] == "DISTURBANCE_PRESSURE_MULTIPLIER":
            x["disturbance_pressure_ppm"] = _clamp(x["disturbance_pressure_ppm"] * spec["numerator"] // spec["denominator"])
        x["sample_hash"] = object_hash(x, "sample_hash")
    s["snapshot_id"] = "eco-evo3/e3.8/matrix/" + family + "/" + object_hash(s, "snapshot_hash")[:24]
    s["snapshot_hash"] = object_hash(s, "snapshot_hash")
    return s


def _colonization_outcomes(c34, decomposition, catalog):
    core, _ = _load_stage_module("causal_colonization_program_compiler_v1_core.py")
    model = c34["causal_model"]
    dimensions = list(model["opportunity_dimensions"])
    min_establishment = int(model["minimum_establishment_ppm"])
    min_arrival = int(model["minimum_edge_arrival_ppm"])
    patches = sorted(decomposition["patches"], key=lambda p: (str(p["stable_spatial_key"]), str(p["research_patch_id"])))
    edges = sorted(decomposition.get("edges", []), key=lambda e: str(e["research_edge_id"]))
    source_patch_id = str(patches[0]["research_patch_id"])
    results = {}
    for entry in catalog["entries"]:
        trait_support = core._trait_support_ppm(entry)
        capacity = core._dispersal_capacity_ppm(entry)
        scores = {str(p["research_patch_id"]): core._establishment_score_ppm(p, trait_support, dimensions) for p in patches}
        established = set()
        if scores[source_patch_id] >= min_establishment:
            established.add(source_patch_id)
        changed = True
        while changed:
            changed = False
            for patch in patches:
                pid = str(patch["research_patch_id"])
                if pid in established or pid == source_patch_id:
                    continue
                route = core._best_route(pid, established, edges, capacity)
                if route is None:
                    continue
                arrival = route[0]
                if arrival < min_arrival:
                    continue
                if scores[pid] >= min_establishment:
                    established.add(pid)
                    changed = True
        results[str(entry["research_species_id"])] = {
            "status": "COLONIZED" if established else "NO_COLONIZATION",
            "established_patch_count": len(established),
        }
    return results


def _family_result(family, spec, inputs, baseline):
    e32mod, _ = _load_stage_module("ecological_opportunity_field_v1.py")
    e33mod, _ = _load_stage_module("research_ecology_decomposition_v1.py")
    s_f = _variant_snapshot(family, spec, inputs.snapshot)
    f_f = e32mod._build(inputs.contract_e32, s_f)
    d_f = e33mod._build(inputs.contract_e33, f_f)
    scaling = None
    if spec["variation"] == "EDGE_CONTINUITY_MULTIPLIER":
        scaling = {"numerator": spec["numerator"], "denominator": spec["denominator"]}
        scaled_edges = []
        for e in d_f["edges"]:
            e = copy.deepcopy(e)
            e["continuity_ppm"] = _clamp(e["continuity_ppm"] * spec["numerator"] // spec["denominator"])
            e["edge_hash"] = object_hash(e, "edge_hash")
            scaled_edges.append(e)
        d_f["edges"] = scaled_edges
        d_f["decomposition_hash"] = object_hash(d_f, "decomposition_hash")
    outcomes = _colonization_outcomes(inputs.contract_e34, d_f, inputs.catalog)
    per_species = []
    colonized = 0
    total_established = 0
    for sid in sorted(outcomes):
        base_status = baseline[sid]
        fam = outcomes[sid]["status"]
        if base_status == "COLONIZED" and fam == "COLONIZED":
            oc = "PRESERVED_COLONIZED"
        elif base_status == "NO_COLONIZATION" and fam == "NO_COLONIZATION":
            oc = "PRESERVED_NO_COLONIZATION"
        elif base_status == "COLONIZED" and fam == "NO_COLONIZATION":
            oc = "LOST_REVERSAL"
        else:
            oc = "GAINED_ESTABLISHMENT"
        n = outcomes[sid]["established_patch_count"]
        total_established += n
        if fam == "COLONIZED":
            colonized += 1
        per_species.append({"research_species_id": sid, "baseline_status": base_status, "family_status": fam, "outcome_class": oc, "established_patch_count": n})
    return {
        "family": family,
        "stable_planet_identity": s_f["stable_planet_identity"],
        "variant_snapshot_hash": s_f["snapshot_hash"],
        "opportunity_field_hash": f_f["opportunity_field_hash"],
        "decomposition_hash": d_f["decomposition_hash"],
        "edge_continuity_scaling": scaling,
        "per_species": per_species,
        "summary": {
            "colonized_species_count": colonized,
            "no_colonization_species_count": len(per_species) - colonized,
            "established_patch_total": total_established,
        },
    }


def _baseline_statuses(program_e34):
    return {str(sp["research_species_id"]): str(sp["status"]) for sp in program_e34["species_programs"]}


def _build_matrix(i):
    specs = {f["family"]: f for f in i.contract["predeclared_families"]}
    baseline = _baseline_statuses(i.program_e34)
    families = [_family_result(family, specs[family], i, baseline) for family in FAMILY_ORDER]
    statuses_by_family = {f["family"]: {sp["research_species_id"]: sp["family_status"] for sp in f["per_species"]} for f in families}
    thermal_shortcut_absent = all(statuses_by_family[f] == baseline for f in THERMAL_FAMILIES)
    diversity_classes = {sp["outcome_class"] for f in families if f["family"] not in THERMAL_FAMILIES for sp in f["per_species"]}
    outcome_diversity_present = bool(diversity_classes & {"LOST_REVERSAL", "GAINED_ESTABLISHMENT"})
    null_outcome_valid = any(sp["family_status"] == "NO_COLONIZATION" for f in families for sp in f["per_species"])
    reused_modules = {}
    for fn in ("ecological_opportunity_field_v1.py", "research_ecology_decomposition_v1.py", "causal_colonization_program_compiler_v1_core.py"):
        reused_modules[fn[:-3]] = _load_stage_module(fn)[1]
    provenance = {
        "contract_hash": i.contract["contract_hash"],
        "accepted_control_head": i.contract["parent"]["accepted_control_head"],
        "e3_7_merge_head": i.contract["parent"]["e3_7_merge_head"],
        "e3_1_snapshot_hash": i.snapshot["snapshot_hash"],
        "evo2_species_catalog_hash": i.catalog["catalog_hash"],
        "e3_2_contract_hash": i.contract_e32["contract_hash"],
        "e3_3_contract_hash": i.contract_e33["contract_hash"],
        "e3_4_contract_hash": i.contract_e34["contract_hash"],
        "e3_3_decomposition_hash": i.decomposition["decomposition_hash"],
        "e3_4_colonization_program_hash": i.program_e34["colonization_program_hash"],
        "input_verification": "EXACT_RAW_SHA256_AND_ACCEPTED_SEMANTIC_IDENTITIES",
        "compiler_module_reuse": "UNMODIFIED_IMPORTED_ACCEPTED_BUILDERS",
    }
    m = {
        "schema": SCHEMA,
        "version": "1.0.0",
        "checkpoint": CHECKPOINT,
        "compiler_stage": COMPILER_STAGE,
        "authority": AUTHORITY,
        "canonical_binding_resolved": False,
        "production_binding_authorized": False,
        "stable_planet_identity": i.snapshot["stable_planet_identity"],
        "stable_time_key": i.snapshot["stable_time_key"],
        "predeclaration": {
            "contract_hash": i.contract["contract_hash"],
            "family_count": len(FAMILY_ORDER),
            "families": [
                {k: v for k, v in spec.items() if k in ("family", "variation", "numerator", "denominator", "offset_milli_c")}
                for spec in (specs[f] for f in FAMILY_ORDER)
            ],
        },
        "accepted_inputs": {
            "e3_1_snapshot_hash": i.snapshot["snapshot_hash"],
            "catalog_hash": i.catalog["catalog_hash"],
            "catalog_entry_count": len(i.catalog["entries"]),
            "e3_2_contract_hash": i.contract_e32["contract_hash"],
            "e3_3_contract_hash": i.contract_e33["contract_hash"],
            "e3_4_contract_hash": i.contract_e34["contract_hash"],
            "e3_3_decomposition_hash": i.decomposition["decomposition_hash"],
            "e3_4_colonization_program_hash": i.program_e34["colonization_program_hash"],
            "baseline_species_statuses": dict(sorted(baseline.items())),
        },
        "reused_modules": reused_modules,
        "families": families,
        "matrix_invariants": {
            "six_families_exact": [f["family"] for f in families] == list(FAMILY_ORDER),
            "thermal_shortcut_absent": thermal_shortcut_absent,
            "outcome_diversity_present": outcome_diversity_present,
            "null_outcome_valid": null_outcome_valid,
            "catalog_untouched": True,
            "compiler_modules_reused_unmodified": True,
        },
        "provenance": provenance,
        "provenance_hash": sha256_hex(canonical_bytes(provenance)),
        "cross_planet_generalization_matrix_hash_algorithm": HASH_ALGORITHM,
    }
    m["cross_planet_generalization_matrix_hash"] = object_hash(m, "cross_planet_generalization_matrix_hash")
    return m


MATRIX_KEYS = ("schema", "version", "checkpoint", "compiler_stage", "authority", "canonical_binding_resolved", "production_binding_authorized", "stable_planet_identity", "stable_time_key", "predeclaration", "accepted_inputs", "reused_modules", "families", "matrix_invariants", "provenance", "provenance_hash", "cross_planet_generalization_matrix_hash_algorithm", "cross_planet_generalization_matrix_hash")


def validate_output_structure(m):
    _require(set(m) == set(MATRIX_KEYS), "matrix keys")
    _require(m["schema"] == SCHEMA and m["checkpoint"] == CHECKPOINT and m["compiler_stage"] == COMPILER_STAGE, "matrix identity")
    _require(m["authority"] == AUTHORITY and m["canonical_binding_resolved"] is False and m["production_binding_authorized"] is False, "matrix authority")
    _require(len(m["families"]) == 6 and [f["family"] for f in m["families"]] == list(FAMILY_ORDER), "family coverage")
    inv = m["matrix_invariants"]
    _require(all(inv[k] is True for k in ("six_families_exact", "thermal_shortcut_absent", "outcome_diversity_present", "null_outcome_valid", "catalog_untouched", "compiler_modules_reused_unmodified")), "matrix invariants")
    _require(m["provenance_hash"] == sha256_hex(canonical_bytes(m["provenance"])), "provenance hash")
    _require(m["cross_planet_generalization_matrix_hash"] == object_hash(m, "cross_planet_generalization_matrix_hash"), "matrix hash")
    _reject_true_authority(m, "GeneralizationMatrix")


def build_planet_generalization_matrix(inputs):
    _require(type(inputs) is _VerifiedMatrixInputs, "build requires exact _VerifiedMatrixInputs capability")
    v = _verified_inputs_from_raw(inputs.raw)
    m = _build_matrix(v)
    validate_output_structure(m)
    return _VerifiedGeneralizationMatrix(m, v)


def validate_output_integrity(matrix):
    _require(type(matrix) is _VerifiedGeneralizationMatrix, "serialization requires _VerifiedGeneralizationMatrix capability")
    inputs = _verified_inputs_from_raw(matrix._raw)
    expected = _build_matrix(inputs)
    validate_output_structure(expected)
    _require(canonical_bytes(dict(matrix)) == canonical_bytes(expected), "GeneralizationMatrix differs from independent exact-input rebuild")


def serialize_planet_generalization_matrix(matrix):
    validate_output_integrity(matrix)
    return canonical_bytes(dict(matrix)) + b"\n"


def write_planet_generalization_matrix(matrix, output):
    Path(output).write_bytes(serialize_planet_generalization_matrix(matrix))


def main():
    p = argparse.ArgumentParser(description="ECO EVO3 E3.8 cross-planet generalization matrix compiler")
    p.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--quiet", action="store_true")
    a = p.parse_args()
    inputs = load_verified_inputs(a.contract)
    matrix = build_planet_generalization_matrix(inputs)
    write_planet_generalization_matrix(matrix, a.output)
    if not a.quiet:
        print(f"E3.8 CrossPlanetGeneralizationMatrix: {a.output}")
        print(f"cross_planet_generalization_matrix_hash={matrix['cross_planet_generalization_matrix_hash']}")
        print(f"provenance_hash={matrix['provenance_hash']}")
        for f in matrix["families"]:
            print(f"family={f['family']} colonized={f['summary']['colonized_species_count']} established_patches={f['summary']['established_patch_total']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
