extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_structural_part_state.v1"
const FIELDS: Array[String] = ["schema", "part_id", "support", "condition", "self_weight_n", "external_load_n", "transmitted_load_n", "reaction_n", "effective_capacity_n", "utilization", "state", "load_path_ids", "checksum"]
const STATES: Array[String] = ["SUPPORT", "OK", "OVERLOADED", "UNSUPPORTED", "DESTROYED"]
const CONDITIONS: Array[String] = ["INTACT", "DEGRADED", "DESTROYED"]

static func create(part_id: String, support: bool, condition: String, self_weight_n: float, external_load_n: float, transmitted_load_n: float, reaction_n: float, effective_capacity_n: float, utilization: float, state: String, load_path_ids: Array) -> Dictionary:
	var paths := load_path_ids.duplicate(); paths.sort()
	var value := {"schema": SCHEMA, "part_id": part_id, "support": support, "condition": condition, "self_weight_n": self_weight_n, "external_load_n": external_load_n, "transmitted_load_n": transmitted_load_n, "reaction_n": reaction_n, "effective_capacity_n": effective_capacity_n, "utilization": utilization, "state": state, "load_path_ids": paths, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STRUCTURAL_PART_STATE_SCHEMA")
	if not String(value.get("part_id", "")).begins_with("part/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PART_STATE_ID")
	if typeof(value.get("support")) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PART_SUPPORT")
	if typeof(value.get("condition")) != TYPE_STRING or not CONDITIONS.has(String(value["condition"])): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PART_CONDITION")
	for field in ["self_weight_n", "external_load_n", "transmitted_load_n", "reaction_n", "effective_capacity_n", "utilization"]:
		if not _non_negative(value.get(field)): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PART_%s" % field.to_upper())
	if typeof(value.get("state")) != TYPE_STRING or not STATES.has(String(value["state"])): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PART_STATE")
	if bool(value["support"]) and String(value["state"]) not in ["SUPPORT", "OVERLOADED", "DESTROYED"]: return _failure("CONSTRUCTION_STRUCTURAL_SUPPORT_STATE_MISMATCH")
	if String(value["condition"]) == "DESTROYED" and String(value["state"]) != "DESTROYED": return _failure("CONSTRUCTION_STRUCTURAL_DESTROYED_PART_STATE_MISMATCH")
	if typeof(value.get("load_path_ids")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PART_LOAD_PATHS")
	var sorted := Array(value["load_path_ids"]).duplicate(); sorted.sort(); if sorted != value["load_path_ids"]: return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_PART_LOAD_PATHS")
	var seen := {}; for path_id in value["load_path_ids"]:
		if typeof(path_id) != TYPE_STRING or not String(path_id).begins_with("load-path/") or seen.has(path_id): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PART_LOAD_PATH")
		seen[path_id] = true
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STRUCTURAL_PART_STATE_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _non_negative(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) >= 0.0
static func _failure(code: String) -> Dictionary: return UtilsScript.validation_failure(code, code)
