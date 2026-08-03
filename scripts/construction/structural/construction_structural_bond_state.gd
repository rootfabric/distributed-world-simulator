extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_structural_bond_state.v1"
const FIELDS: Array[String] = ["schema", "bond_id", "bond_state", "load_n", "effective_capacity_n", "utilization", "state", "load_path_ids", "checksum"]
const STATES: Array[String] = ["OK", "OVERLOADED", "BROKEN"]

static func create(bond_id: String, bond_state: String, load_n: float, effective_capacity_n: float, utilization: float, state: String, load_path_ids: Array) -> Dictionary:
	var paths := load_path_ids.duplicate(); paths.sort()
	var value := {"schema": SCHEMA, "bond_id": bond_id, "bond_state": bond_state, "load_n": load_n, "effective_capacity_n": effective_capacity_n, "utilization": utilization, "state": state, "load_path_ids": paths, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STRUCTURAL_BOND_STATE_SCHEMA")
	if not String(value.get("bond_id", "")).begins_with("bond/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_BOND_STATE_ID")
	if typeof(value.get("bond_state")) != TYPE_STRING or String(value["bond_state"]) not in ["INTACT", "DEGRADED", "BROKEN"]: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SOURCE_BOND_STATE")
	for field in ["load_n", "effective_capacity_n", "utilization"]:
		if not _non_negative(value.get(field)): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_BOND_%s" % field.to_upper())
	if typeof(value.get("state")) != TYPE_STRING or not STATES.has(String(value["state"])): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_BOND_STATE")
	if String(value["bond_state"]) == "BROKEN" and String(value["state"]) != "BROKEN": return _failure("CONSTRUCTION_STRUCTURAL_BROKEN_BOND_STATE_MISMATCH")
	if typeof(value.get("load_path_ids")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_BOND_LOAD_PATHS")
	var sorted := Array(value["load_path_ids"]).duplicate(); sorted.sort(); if sorted != value["load_path_ids"]: return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_BOND_LOAD_PATHS")
	var seen := {}; for path_id in value["load_path_ids"]:
		if typeof(path_id) != TYPE_STRING or not String(path_id).begins_with("load-path/") or seen.has(path_id): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_BOND_LOAD_PATH")
		seen[path_id] = true
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STRUCTURAL_BOND_STATE_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _non_negative(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) >= 0.0
static func _failure(code: String) -> Dictionary: return UtilsScript.validation_failure(code, code)
