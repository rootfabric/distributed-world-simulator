extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProfileScript = preload("res://scripts/construction/structural/construction_structural_profile.gd")
const SCHEMA := "planet_simulator.construction_structural_summary.v1"
const FIELDS: Array[String] = ["schema", "construct_id", "load_case_id", "profile_checksum", "structural_state", "maximum_utilization", "part_count", "bond_count", "load_path_count", "critical_part_ids", "critical_bond_ids", "unsupported_part_count", "checksum"]

static func compile(profile: Dictionary) -> Dictionary:
	var checked := ProfileScript.validate(profile)
	if not bool(checked.get("success", false)): return checked
	var critical_parts: Array = profile["overloaded_part_ids"].duplicate(); critical_parts.sort()
	var critical_bonds: Array = profile["overloaded_bond_ids"].duplicate(); critical_bonds.sort()
	var value := {
		"schema": SCHEMA,
		"construct_id": String(profile["construct_id"]),
		"load_case_id": String(profile["load_case_id"]),
		"profile_checksum": String(profile["checksum"]),
		"structural_state": String(profile["structural_state"]),
		"maximum_utilization": float(profile["maximum_utilization"]),
		"part_count": profile["part_states"].size(),
		"bond_count": profile["bond_states"].size(),
		"load_path_count": profile["load_paths"].size(),
		"critical_part_ids": critical_parts,
		"critical_bond_ids": critical_bonds,
		"unsupported_part_count": profile["unsupported_part_ids"].size(),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return {"success": true, "error_code": "", "message": "", "summary": value, "details": {"summary": value}}

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STRUCTURAL_SUMMARY_SCHEMA")
	if not String(value.get("construct_id", "")).begins_with("construct/") or not String(value.get("load_case_id", "")).begins_with("load-case/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SUMMARY_ID")
	if String(value.get("profile_checksum", "")).length() != 64: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SUMMARY_PROFILE_CHECKSUM")
	if typeof(value.get("structural_state")) != TYPE_STRING or not ProfileScript.STATES.has(String(value["structural_state"])): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SUMMARY_STATE")
	if typeof(value.get("maximum_utilization")) not in [TYPE_INT, TYPE_FLOAT] or float(value["maximum_utilization"]) < 0.0: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SUMMARY_UTILIZATION")
	for field in ["part_count", "bond_count", "load_path_count", "unsupported_part_count"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SUMMARY_%s" % field.to_upper())
	for field in ["critical_part_ids", "critical_bond_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SUMMARY_CRITICAL_IDS")
		var sorted := Array(value[field]).duplicate(); sorted.sort(); if sorted != value[field]: return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_SUMMARY_CRITICAL_IDS")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STRUCTURAL_SUMMARY_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _failure(code: String) -> Dictionary: return UtilsScript.validation_failure(code, code)
