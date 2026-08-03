extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const SectionStateScript = preload("res://scripts/construction/spatial/construction_spatial_section_state.gd")
const OpeningStateScript = preload("res://scripts/construction/spatial/construction_spatial_opening_state.gd")
const SpaceStateScript = preload("res://scripts/construction/spatial/construction_spatial_space_state.gd")
const UtilityStateScript = preload("res://scripts/construction/spatial/construction_spatial_utility_state.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")

const SCHEMA := "planet_simulator.construction_spatial_profile.v1"
const COMPILER_ID := "construction-spatial-compiler"
const COMPILER_VERSION := 1
const FIELDS: Array[String] = [
	"schema", "construct_id", "construct_checksum", "construct_revision", "build_state",
	"compiler_id", "compiler_version", "building_state", "activation_level",
	"section_states", "opening_states", "space_states", "utility_states",
	"capabilities", "affordances", "diagnostics", "checksum",
]
const VALID_BUILDING_STATES: Array[String] = ["ACTIVE", "DEGRADED", "INACTIVE"]
const VALID_ACTIVATION_LEVELS: Array[String] = ["DORMANT", "SUMMARY", "FUNCTIONAL"]

static func create(snapshot: Dictionary, building_state: String, activation_level: String, section_states: Array, opening_states: Array, space_states: Array, utility_states: Array, capabilities: Array, affordances: Array, diagnostics: Dictionary = {}) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"construct_id": String(snapshot.get("construct_id", "")),
		"construct_checksum": String(snapshot.get("checksum", "")),
		"construct_revision": int(snapshot.get("state_revision", 0)),
		"build_state": String(snapshot.get("build_state", "")),
		"compiler_id": COMPILER_ID,
		"compiler_version": COMPILER_VERSION,
		"building_state": building_state,
		"activation_level": activation_level,
		"section_states": _sorted_records(section_states, "section_id"),
		"opening_states": _sorted_records(opening_states, "opening_id"),
		"space_states": _sorted_records(space_states, "space_id"),
		"utility_states": _sorted_records(utility_states, "utility_id"),
		"capabilities": _sorted_records(capabilities, "capability_id"),
		"affordances": _sorted_records(affordances, "affordance_id"),
		"diagnostics": diagnostics.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_PROFILE_SCHEMA")
	if not _is_path_id(String(value.get("construct_id", "")), "construct/"):
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_CONSTRUCT_ID")
	if not _is_lower_hex_64(String(value.get("construct_checksum", ""))):
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_CONSTRUCT_CHECKSUM")
	if not UtilsScript.is_json_integer(value.get("construct_revision")) or int(value["construct_revision"]) < 0:
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_CONSTRUCT_REVISION")
	if typeof(value.get("build_state")) != TYPE_STRING or not SnapshotScript.VALID_BUILD_STATES.has(String(value["build_state"])):
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_BUILD_STATE")
	if value.get("compiler_id") != COMPILER_ID or not UtilsScript.is_json_integer(value.get("compiler_version")) or int(value["compiler_version"]) != COMPILER_VERSION:
		return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_PROFILE_COMPILER")
	if typeof(value.get("building_state")) != TYPE_STRING or not VALID_BUILDING_STATES.has(String(value["building_state"])):
		return _failure("INVALID_CONSTRUCTION_SPATIAL_BUILDING_STATE")
	if typeof(value.get("activation_level")) != TYPE_STRING or not VALID_ACTIVATION_LEVELS.has(String(value["activation_level"])):
		return _failure("INVALID_CONSTRUCTION_SPATIAL_ACTIVATION_LEVEL")
	if String(value["building_state"]) == "ACTIVE" and String(value["activation_level"]) != "FUNCTIONAL":
		return _failure("CONSTRUCTION_SPATIAL_ACTIVE_PROFILE_NOT_FUNCTIONAL")
	var section_ids := _validate_records(value.get("section_states"), SectionStateScript, "section_id", "SECTION")
	if not bool(section_ids.get("success", false)):
		return section_ids
	var opening_ids := _validate_records(value.get("opening_states"), OpeningStateScript, "opening_id", "OPENING")
	if not bool(opening_ids.get("success", false)):
		return opening_ids
	var space_ids := _validate_records(value.get("space_states"), SpaceStateScript, "space_id", "SPACE")
	if not bool(space_ids.get("success", false)):
		return space_ids
	var utility_ids := _validate_records(value.get("utility_states"), UtilityStateScript, "utility_id", "UTILITY")
	if not bool(utility_ids.get("success", false)):
		return utility_ids
	if typeof(value.get("capabilities")) != TYPE_ARRAY or typeof(value.get("affordances")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_BEHAVIOR_COLLECTIONS")
	var capabilities_by_id: Dictionary = {}
	var previous_capability_id := ""
	for raw in value["capabilities"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_CAPABILITY")
		var capability: Dictionary = raw
		var checked := CapabilityScript.validate(capability)
		if not bool(checked.get("success", false)):
			return checked
		var capability_id := String(capability["capability_id"])
		if capabilities_by_id.has(capability_id):
			return _failure("DUPLICATE_CONSTRUCTION_SPATIAL_PROFILE_CAPABILITY")
		if not previous_capability_id.is_empty() and capability_id < previous_capability_id:
			return _failure("CONSTRUCTION_SPATIAL_PROFILE_CAPABILITIES_NOT_SORTED")
		capabilities_by_id[capability_id] = capability
		previous_capability_id = capability_id
	var affordance_ids: Dictionary = {}
	var previous_affordance_id := ""
	for raw in value["affordances"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_AFFORDANCE")
		var affordance: Dictionary = raw
		var checked := AffordanceScript.validate(affordance)
		if not bool(checked.get("success", false)):
			return checked
		var affordance_id := String(affordance["affordance_id"])
		if affordance_ids.has(affordance_id):
			return _failure("DUPLICATE_CONSTRUCTION_SPATIAL_PROFILE_AFFORDANCE")
		if not previous_affordance_id.is_empty() and affordance_id < previous_affordance_id:
			return _failure("CONSTRUCTION_SPATIAL_PROFILE_AFFORDANCES_NOT_SORTED")
		var capability_id := String(affordance["capability_id"])
		if not capabilities_by_id.has(capability_id):
			return _failure("CONSTRUCTION_SPATIAL_PROFILE_AFFORDANCE_CAPABILITY_MISSING")
		if not Array(capabilities_by_id[capability_id]["provider_part_ids"]).has(String(affordance["target_part_id"])):
			return _failure("CONSTRUCTION_SPATIAL_PROFILE_AFFORDANCE_PROVIDER_MISMATCH")
		affordance_ids[affordance_id] = true
		previous_affordance_id = affordance_id
	if String(value["building_state"]) == "INACTIVE" and (not value["capabilities"].is_empty() or not value["affordances"].is_empty()):
		return _failure("INACTIVE_CONSTRUCTION_SPATIAL_PROFILE_EXPOSES_BEHAVIOR")
	if typeof(value.get("diagnostics")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["diagnostics"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_DIAGNOSTICS")
	if String(value.get("checksum", "")) != compute_checksum(value):
		return _failure("CONSTRUCTION_SPATIAL_PROFILE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_SPATIAL_PROFILE_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

static func _validate_records(value, script, id_field: String, label: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_%s_STATES" % label)
	var seen: Dictionary = {}
	var previous := ""
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_%s_STATE" % label)
		var checked: Dictionary = script.validate(raw)
		if not bool(checked.get("success", false)):
			return checked
		var identifier := String(raw[id_field])
		if seen.has(identifier):
			return _failure("DUPLICATE_CONSTRUCTION_SPATIAL_PROFILE_%s_STATE" % label)
		if not previous.is_empty() and identifier < previous:
			return _failure("CONSTRUCTION_SPATIAL_PROFILE_%s_STATES_NOT_SORTED" % label)
		seen[identifier] = true
		previous = identifier
	return _success({"ids": seen})

static func _sorted_records(records: Array, id_field: String) -> Array:
	var result := records.duplicate(true)
	result.sort_custom(func(left, right): return String(left.get(id_field, "")) < String(right.get(id_field, "")))
	return result

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
