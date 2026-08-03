extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProfileScript = preload("res://scripts/construction/structural/construction_structural_profile.gd")
const DamageRequestScript = preload("res://scripts/construction/damage/construction_damage_request.gd")

const SCHEMA := "planet_simulator.construction_structural_cascade_plan.v1"
const FIELDS: Array[String] = ["schema", "cascade_id", "construct_id", "source_snapshot_checksum", "load_case_checksum", "step_profiles", "failed_bond_ids", "part_conditions", "damage_request", "stable", "checksum"]

static func create(cascade_id: String, construct_id: String, source_checksum: String, load_case_checksum: String, profiles: Array, failed_bonds: Array, part_conditions: Dictionary, damage_request: Dictionary, stable: bool) -> Dictionary:
	var bonds := failed_bonds.duplicate(); bonds.sort()
	var conditions := {}; var keys := part_conditions.keys(); keys.sort(); for key in keys: conditions[key] = part_conditions[key]
	var value := {"schema": SCHEMA, "cascade_id": cascade_id, "construct_id": construct_id, "source_snapshot_checksum": source_checksum, "load_case_checksum": load_case_checksum, "step_profiles": profiles.duplicate(true), "failed_bond_ids": bonds, "part_conditions": conditions, "damage_request": damage_request.duplicate(true), "stable": stable, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STRUCTURAL_CASCADE_PLAN_SCHEMA")
	if not String(value.get("cascade_id", "")).begins_with("cascade/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_ID")
	if not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_CONSTRUCT")
	if not _hex64(String(value.get("source_snapshot_checksum", ""))) or not _hex64(String(value.get("load_case_checksum", ""))): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_SOURCE_CHECKSUM")
	if typeof(value.get("step_profiles")) != TYPE_ARRAY or Array(value["step_profiles"]).is_empty(): return _failure("CONSTRUCTION_STRUCTURAL_CASCADE_PROFILES_REQUIRED")
	for profile in value["step_profiles"]:
		if typeof(profile) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_PROFILE")
		var checked := ProfileScript.validate(profile); if not bool(checked.get("success", false)): return checked
		if String(profile["construct_id"]) != String(value["construct_id"]): return _failure("CONSTRUCTION_STRUCTURAL_CASCADE_PROFILE_CONSTRUCT_MISMATCH")
	if typeof(value.get("failed_bond_ids")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_BONDS")
	var sorted := Array(value["failed_bond_ids"]).duplicate(); sorted.sort(); if sorted != value["failed_bond_ids"]: return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_CASCADE_BONDS")
	var seen := {}; for bond_id in value["failed_bond_ids"]:
		if typeof(bond_id) != TYPE_STRING or not String(bond_id).begins_with("bond/") or seen.has(bond_id): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_BOND")
		seen[bond_id] = true
	if typeof(value.get("part_conditions")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_PART_CONDITIONS")
	var condition_keys: Array = value["part_conditions"].keys(); var sorted_keys: Array = condition_keys.duplicate(); sorted_keys.sort(); if condition_keys != sorted_keys: return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_CASCADE_PART_CONDITIONS")
	for part_id in condition_keys:
		if typeof(part_id) != TYPE_STRING or not String(part_id).begins_with("part/") or String(value["part_conditions"][part_id]) not in ["DEGRADED", "DESTROYED"]: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_PART_CONDITION")
	if typeof(value.get("damage_request")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_DAMAGE_REQUEST")
	if Dictionary(value["damage_request"]).is_empty():
		if not Array(value["failed_bond_ids"]).is_empty() or not Dictionary(value["part_conditions"]).is_empty(): return _failure("CONSTRUCTION_STRUCTURAL_CASCADE_DAMAGE_REQUEST_MISSING")
	else:
		var checked := DamageRequestScript.validate(value["damage_request"]); if not bool(checked.get("success", false)): return checked
		if String(value["damage_request"]["construct_id"]) != String(value["construct_id"]) or String(value["damage_request"]["source_snapshot_checksum"]) != String(value["source_snapshot_checksum"]): return _failure("CONSTRUCTION_STRUCTURAL_CASCADE_DAMAGE_REQUEST_MISMATCH")
		if value["damage_request"]["broken_bond_ids"] != value["failed_bond_ids"] or value["damage_request"]["part_conditions"] != value["part_conditions"]: return _failure("CONSTRUCTION_STRUCTURAL_CASCADE_DAMAGE_PAYLOAD_MISMATCH")
	if typeof(value.get("stable")) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_STABLE")
	if bool(value["stable"]) != (Array(value["failed_bond_ids"]).is_empty() and Dictionary(value["part_conditions"]).is_empty() and String(value["step_profiles"][-1]["structural_state"]) == "STABLE"):
		return _failure("CONSTRUCTION_STRUCTURAL_CASCADE_STABLE_MISMATCH")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STRUCTURAL_CASCADE_PLAN_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _hex64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower(): return false
	for character in value:
		if not String(character) in "0123456789abcdef": return false
	return true
static func _failure(code: String) -> Dictionary: return UtilsScript.validation_failure(code, code)
