extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const StateScript = preload("res://scripts/construction/mobile/construction_mobile_subsystem_state.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")

const SCHEMA: String = "planet_simulator.construction_mobile_profile.v1"
const COMPILER_ID: String = "construction-mobile-compiler"
const COMPILER_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema",
	"construct_id",
	"construct_checksum",
	"construct_revision",
	"build_state",
	"compiler_id",
	"compiler_version",
	"mobility_state",
	"subsystem_states",
	"capabilities",
	"affordances",
	"diagnostics",
	"checksum",
]
const VALID_MOBILITY_STATES: Array[String] = ["MOBILE", "DEGRADED", "IMMOBILE"]


static func create(
	construct_snapshot: Dictionary,
	mobility_state: String,
	subsystem_states: Array,
	capabilities: Array,
	affordances: Array,
	diagnostics: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"construct_id": String(construct_snapshot.get("construct_id", "")),
		"construct_checksum": String(construct_snapshot.get("checksum", "")),
		"construct_revision": int(construct_snapshot.get("state_revision", 0)),
		"build_state": String(construct_snapshot.get("build_state", "")),
		"compiler_id": COMPILER_ID,
		"compiler_version": COMPILER_VERSION,
		"mobility_state": mobility_state,
		"subsystem_states": _sorted_records(subsystem_states, "subsystem_id"),
		"capabilities": _sorted_records(capabilities, "capability_id"),
		"affordances": _sorted_records(affordances, "affordance_id"),
		"diagnostics": diagnostics.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_MOBILE_PROFILE_SCHEMA")
	if not _is_path_id(String(value.get("construct_id", "")), "construct/"):
		return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_CONSTRUCT_ID")
	if not _is_lower_hex_64(String(value.get("construct_checksum", ""))):
		return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_CONSTRUCT_CHECKSUM")
	if not UtilsScript.is_json_integer(value.get("construct_revision")) or int(value["construct_revision"]) < 0:
		return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_CONSTRUCT_REVISION")
	if typeof(value.get("build_state")) != TYPE_STRING or not SnapshotScript.VALID_BUILD_STATES.has(String(value["build_state"])):
		return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_BUILD_STATE")
	if value.get("compiler_id") != COMPILER_ID or not UtilsScript.is_json_integer(value.get("compiler_version")) or int(value["compiler_version"]) != COMPILER_VERSION:
		return _failure("UNSUPPORTED_CONSTRUCTION_MOBILE_PROFILE_COMPILER")
	if typeof(value.get("mobility_state")) != TYPE_STRING or not VALID_MOBILITY_STATES.has(String(value["mobility_state"])):
		return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_MOBILITY_STATE")
	if typeof(value.get("subsystem_states")) != TYPE_ARRAY or typeof(value.get("capabilities")) != TYPE_ARRAY or typeof(value.get("affordances")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_COLLECTIONS")
	var subsystem_ids: Dictionary = {}
	var previous_subsystem_id: String = ""
	for raw in value["subsystem_states"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_SUBSYSTEM_STATE")
		var state: Dictionary = raw
		var validation: Dictionary = StateScript.validate(state)
		if not bool(validation.get("success", false)):
			return validation
		var subsystem_id: String = String(state["subsystem_id"])
		if subsystem_ids.has(subsystem_id):
			return _failure("DUPLICATE_CONSTRUCTION_MOBILE_PROFILE_SUBSYSTEM_STATE")
		if not previous_subsystem_id.is_empty() and subsystem_id < previous_subsystem_id:
			return _failure("CONSTRUCTION_MOBILE_PROFILE_SUBSYSTEMS_NOT_SORTED")
		subsystem_ids[subsystem_id] = true
		previous_subsystem_id = subsystem_id
	var capability_ids: Dictionary = {}
	var previous_capability_id: String = ""
	for raw in value["capabilities"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_CAPABILITY")
		var capability: Dictionary = raw
		var validation: Dictionary = CapabilityScript.validate(capability)
		if not bool(validation.get("success", false)):
			return validation
		var capability_id: String = String(capability["capability_id"])
		if capability_ids.has(capability_id):
			return _failure("DUPLICATE_CONSTRUCTION_MOBILE_PROFILE_CAPABILITY")
		if not previous_capability_id.is_empty() and capability_id < previous_capability_id:
			return _failure("CONSTRUCTION_MOBILE_PROFILE_CAPABILITIES_NOT_SORTED")
		capability_ids[capability_id] = capability
		previous_capability_id = capability_id
	var affordance_ids: Dictionary = {}
	var previous_affordance_id: String = ""
	for raw in value["affordances"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_AFFORDANCE")
		var affordance: Dictionary = raw
		var validation: Dictionary = AffordanceScript.validate(affordance)
		if not bool(validation.get("success", false)):
			return validation
		var affordance_id: String = String(affordance["affordance_id"])
		if affordance_ids.has(affordance_id):
			return _failure("DUPLICATE_CONSTRUCTION_MOBILE_PROFILE_AFFORDANCE")
		if not previous_affordance_id.is_empty() and affordance_id < previous_affordance_id:
			return _failure("CONSTRUCTION_MOBILE_PROFILE_AFFORDANCES_NOT_SORTED")
		var capability_id: String = String(affordance["capability_id"])
		if not capability_ids.has(capability_id):
			return _failure("CONSTRUCTION_MOBILE_PROFILE_AFFORDANCE_CAPABILITY_MISSING")
		var capability: Dictionary = capability_ids[capability_id]
		if not Array(capability["provider_part_ids"]).has(String(affordance["target_part_id"])):
			return _failure("CONSTRUCTION_MOBILE_PROFILE_AFFORDANCE_PROVIDER_MISMATCH")
		affordance_ids[affordance_id] = true
		previous_affordance_id = affordance_id
	if String(value["mobility_state"]) == "IMMOBILE":
		for capability in value["capabilities"]:
			if ["LOCOMOTION_GROUND", "STEERING"].has(String(capability["capability_kind"])):
				return _failure("IMMOBILE_CONSTRUCTION_MOBILE_PROFILE_HAS_MOTION_CAPABILITY")
	if typeof(value.get("diagnostics")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["diagnostics"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_MOBILE_PROFILE_DIAGNOSTICS")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_MOBILE_PROFILE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_MOBILE_PROFILE_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _sorted_records(records: Array, id_field: String) -> Array:
	var output: Array = records.duplicate(true)
	output.sort_custom(func(left, right): return String(left.get(id_field, "")) < String(right.get(id_field, "")))
	return output


static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "0123456789abcdef":
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
