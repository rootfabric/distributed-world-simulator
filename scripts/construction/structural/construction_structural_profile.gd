extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const PartStateScript = preload("res://scripts/construction/structural/construction_structural_part_state.gd")
const BondStateScript = preload("res://scripts/construction/structural/construction_structural_bond_state.gd")
const LoadPathScript = preload("res://scripts/construction/structural/construction_structural_load_path.gd")

const SCHEMA := "planet_simulator.construction_structural_profile.v1"
const FIELDS: Array[String] = [
	"schema", "construct_id", "construct_checksum", "construct_revision", "load_case_id", "load_case_checksum",
	"structural_state", "part_states", "bond_states", "load_paths", "overloaded_part_ids", "overloaded_bond_ids",
	"unsupported_part_ids", "maximum_utilization", "total_applied_load_n", "total_support_reaction_n", "diagnostics", "checksum",
]
const STATES: Array[String] = ["STABLE", "OVERLOADED", "UNSUPPORTED", "FAILED"]

static func create(snapshot: Dictionary, load_case: Dictionary, state: String, part_states: Array, bond_states: Array, load_paths: Array, diagnostics: Dictionary = {}) -> Dictionary:
	var overloaded_parts: Array = []
	var overloaded_bonds: Array = []
	var unsupported_parts: Array = []
	var max_utilization := 0.0
	var total_applied := 0.0
	var total_reaction := 0.0
	for part in part_states:
		total_applied += float(part.get("self_weight_n", 0.0)) + float(part.get("external_load_n", 0.0))
		total_reaction += float(part.get("reaction_n", 0.0))
		max_utilization = maxf(max_utilization, float(part.get("utilization", 0.0)))
		match String(part.get("state", "")):
			"OVERLOADED": overloaded_parts.append(String(part["part_id"]))
			"UNSUPPORTED": unsupported_parts.append(String(part["part_id"]))
	for bond in bond_states:
		max_utilization = maxf(max_utilization, float(bond.get("utilization", 0.0)))
		if String(bond.get("state", "")) == "OVERLOADED": overloaded_bonds.append(String(bond["bond_id"]))
	for values in [overloaded_parts, overloaded_bonds, unsupported_parts]: values.sort()
	var value := {
		"schema": SCHEMA,
		"construct_id": String(snapshot.get("construct_id", "")),
		"construct_checksum": String(snapshot.get("checksum", "")),
		"construct_revision": int(snapshot.get("state_revision", 0)),
		"load_case_id": String(load_case.get("load_case_id", "")),
		"load_case_checksum": String(load_case.get("checksum", "")),
		"structural_state": state,
		"part_states": _sorted(part_states, "part_id"),
		"bond_states": _sorted(bond_states, "bond_id"),
		"load_paths": _sorted(load_paths, "load_path_id"),
		"overloaded_part_ids": overloaded_parts,
		"overloaded_bond_ids": overloaded_bonds,
		"unsupported_part_ids": unsupported_parts,
		"maximum_utilization": _rounded(max_utilization),
		"total_applied_load_n": _rounded(total_applied),
		"total_support_reaction_n": _rounded(total_reaction),
		"diagnostics": diagnostics.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STRUCTURAL_PROFILE_SCHEMA")
	if not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_CONSTRUCT")
	if not _hex64(String(value.get("construct_checksum", ""))) or not _hex64(String(value.get("load_case_checksum", ""))): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_SOURCE_CHECKSUM")
	if not UtilsScript.is_json_integer(value.get("construct_revision")) or int(value["construct_revision"]) < 0: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_REVISION")
	if not String(value.get("load_case_id", "")).begins_with("load-case/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_LOAD_CASE")
	if typeof(value.get("structural_state")) != TYPE_STRING or not STATES.has(String(value["structural_state"])): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_STATE")
	var part_ids := {}; var previous := ""
	if typeof(value.get("part_states")) != TYPE_ARRAY or Array(value["part_states"]).is_empty(): return _failure("CONSTRUCTION_STRUCTURAL_PROFILE_PARTS_REQUIRED")
	for part in value["part_states"]:
		if typeof(part) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_PART")
		var checked := PartStateScript.validate(part); if not bool(checked.get("success", false)): return checked
		var part_id := String(part["part_id"]); if part_ids.has(part_id) or (not previous.is_empty() and part_id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_PROFILE_PARTS")
		part_ids[part_id] = part; previous = part_id
	var bond_ids := {}; previous = ""
	if typeof(value.get("bond_states")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_BONDS")
	for bond in value["bond_states"]:
		if typeof(bond) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_BOND")
		var checked := BondStateScript.validate(bond); if not bool(checked.get("success", false)): return checked
		var bond_id := String(bond["bond_id"]); if bond_ids.has(bond_id) or (not previous.is_empty() and bond_id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_PROFILE_BONDS")
		bond_ids[bond_id] = bond; previous = bond_id
	var path_ids := {}; previous = ""
	if typeof(value.get("load_paths")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_LOAD_PATHS")
	for path in value["load_paths"]:
		if typeof(path) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_LOAD_PATH")
		var checked := LoadPathScript.validate(path); if not bool(checked.get("success", false)): return checked
		var path_id := String(path["load_path_id"]); if path_ids.has(path_id) or (not previous.is_empty() and path_id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_PROFILE_LOAD_PATHS")
		for part_id in path["part_ids"]:
			if not part_ids.has(String(part_id)): return _failure("CONSTRUCTION_STRUCTURAL_LOAD_PATH_UNKNOWN_PART")
		for bond_id in path["bond_ids"]:
			if not bond_ids.has(String(bond_id)): return _failure("CONSTRUCTION_STRUCTURAL_LOAD_PATH_UNKNOWN_BOND")
		path_ids[path_id] = path; previous = path_id
	for field in ["overloaded_part_ids", "overloaded_bond_ids", "unsupported_part_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_SUMMARY")
		var sorted := Array(value[field]).duplicate(); sorted.sort(); if sorted != value[field]: return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_PROFILE_SUMMARY")
		var seen := {}; for member in value[field]:
			if typeof(member) != TYPE_STRING or seen.has(member): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_SUMMARY_MEMBER")
			seen[member] = true
	for field in ["maximum_utilization", "total_applied_load_n", "total_support_reaction_n"]:
		if not _non_negative(value.get(field)): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_%s" % field.to_upper())
	var computed_max := 0.0
	var computed_applied := 0.0
	var computed_reaction := 0.0
	var computed_overloaded_parts: Array = []
	var computed_unsupported_parts: Array = []
	for part in value["part_states"]:
		computed_max = maxf(computed_max, float(part["utilization"]))
		computed_applied += float(part["self_weight_n"]) + float(part["external_load_n"])
		computed_reaction += float(part["reaction_n"])
		if String(part["state"]) == "OVERLOADED": computed_overloaded_parts.append(String(part["part_id"]))
		if String(part["state"]) == "UNSUPPORTED": computed_unsupported_parts.append(String(part["part_id"]))
	var computed_overloaded_bonds: Array = []
	for bond in value["bond_states"]:
		computed_max = maxf(computed_max, float(bond["utilization"]))
		if String(bond["state"]) == "OVERLOADED": computed_overloaded_bonds.append(String(bond["bond_id"]))
	for ids in [computed_overloaded_parts, computed_overloaded_bonds, computed_unsupported_parts]: ids.sort()
	if computed_overloaded_parts != value["overloaded_part_ids"] or computed_overloaded_bonds != value["overloaded_bond_ids"] or computed_unsupported_parts != value["unsupported_part_ids"]:
		return _failure("CONSTRUCTION_STRUCTURAL_PROFILE_SUMMARY_MISMATCH")
	if absf(_rounded(computed_max) - float(value["maximum_utilization"])) > 0.000000001 or absf(_rounded(computed_applied) - float(value["total_applied_load_n"])) > 0.000000001 or absf(_rounded(computed_reaction) - float(value["total_support_reaction_n"])) > 0.000000001:
		return _failure("CONSTRUCTION_STRUCTURAL_PROFILE_NUMERIC_SUMMARY_MISMATCH")
	var expected_state := "STABLE"
	if not Array(value["unsupported_part_ids"]).is_empty(): expected_state = "UNSUPPORTED"
	elif not Array(value["overloaded_part_ids"]).is_empty() or not Array(value["overloaded_bond_ids"]).is_empty(): expected_state = "OVERLOADED"
	if String(value["structural_state"]) == "FAILED": expected_state = "FAILED"
	elif String(value["structural_state"]) != expected_state: return _failure("CONSTRUCTION_STRUCTURAL_PROFILE_STATE_SUMMARY_MISMATCH")
	if typeof(value.get("diagnostics")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["diagnostics"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_PROFILE_DIAGNOSTICS")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STRUCTURAL_PROFILE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_STRUCTURAL_PROFILE_NOT_JSON_SAFE")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted(values: Array, field: String) -> Array:
	var output := values.duplicate(true); output.sort_custom(func(a, b): return String(a.get(field, "")) < String(b.get(field, ""))); return output
static func _rounded(value: float) -> float: return snappedf(value, 0.000000001)
static func _non_negative(value) -> bool: return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) >= 0.0
static func _hex64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower(): return false
	for character in value:
		if not String(character) in "0123456789abcdef": return false
	return true
static func _failure(code: String) -> Dictionary: return UtilsScript.validation_failure(code, code)
