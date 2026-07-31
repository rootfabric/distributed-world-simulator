extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")

const SCHEMA: String = "planet_simulator.construction_behavior_profile.v1"
const COMPILER_ID: String = "construction-behavior-compiler"
const COMPILER_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema",
	"construct_id",
	"construct_checksum",
	"construct_revision",
	"build_state",
	"operational",
	"compiler_id",
	"compiler_version",
	"composite_definition_id",
	"composite_definition_version",
	"capabilities",
	"affordances",
	"diagnostics",
	"checksum",
]


static func create(
	construct_snapshot: Dictionary,
	operational: bool,
	capabilities: Array,
	affordances: Array,
	diagnostics: Dictionary = {}
) -> Dictionary:
	var facets: Dictionary = Dictionary(construct_snapshot.get("compiled_facets", {}))
	var value: Dictionary = {
		"schema": SCHEMA,
		"construct_id": String(construct_snapshot.get("construct_id", "")),
		"construct_checksum": String(construct_snapshot.get("checksum", "")),
		"construct_revision": int(construct_snapshot.get("state_revision", 0)),
		"build_state": String(construct_snapshot.get("build_state", "")),
		"operational": operational,
		"compiler_id": COMPILER_ID,
		"compiler_version": COMPILER_VERSION,
		"composite_definition_id": String(facets.get("composite_definition_id", "")),
		"composite_definition_version": int(facets.get("composite_definition_version", 0)),
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
		return _failure("UNSUPPORTED_CONSTRUCTION_BEHAVIOR_PROFILE_SCHEMA")
	if not _is_path_id(String(value.get("construct_id", "")), "construct/"):
		return _failure("INVALID_CONSTRUCTION_BEHAVIOR_CONSTRUCT_ID")
	if not _is_lower_hex_64(String(value.get("construct_checksum", ""))):
		return _failure("INVALID_CONSTRUCTION_BEHAVIOR_CONSTRUCT_CHECKSUM")
	if not UtilsScript.is_json_integer(value.get("construct_revision")) or int(value["construct_revision"]) < 0:
		return _failure("INVALID_CONSTRUCTION_BEHAVIOR_CONSTRUCT_REVISION")
	if typeof(value.get("build_state")) != TYPE_STRING or not SnapshotScript.VALID_BUILD_STATES.has(String(value["build_state"])):
		return _failure("INVALID_CONSTRUCTION_BEHAVIOR_BUILD_STATE")
	if typeof(value.get("operational")) != TYPE_BOOL:
		return _failure("INVALID_CONSTRUCTION_BEHAVIOR_OPERATIONAL_FLAG")
	if bool(value["operational"]) != (String(value["build_state"]) == "OPERATIONAL"):
		return _failure("CONSTRUCTION_BEHAVIOR_OPERATIONAL_STATE_MISMATCH")
	if value.get("compiler_id") != COMPILER_ID or not UtilsScript.is_json_integer(value.get("compiler_version")) or int(value["compiler_version"]) != COMPILER_VERSION:
		return _failure("UNSUPPORTED_CONSTRUCTION_BEHAVIOR_COMPILER")
	var definition_id: String = String(value.get("composite_definition_id", ""))
	var definition_version: int = int(value.get("composite_definition_version", 0))
	if definition_id.is_empty():
		if definition_version != 0:
			return _failure("CONSTRUCTION_BEHAVIOR_DEFINITION_VERSION_WITHOUT_ID")
	elif not _is_path_id(definition_id, "composite-definition/") or definition_version < 1:
		return _failure("INVALID_CONSTRUCTION_BEHAVIOR_DEFINITION_PROVENANCE")
	if typeof(value.get("capabilities")) != TYPE_ARRAY or typeof(value.get("affordances")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_BEHAVIOR_COLLECTIONS")
	var capability_ids: Dictionary = {}
	var capability_kinds: Dictionary = {}
	var previous_capability_id: String = ""
	for raw in value["capabilities"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_BEHAVIOR_CAPABILITY")
		var capability: Dictionary = raw
		var validation: Dictionary = CapabilityScript.validate(capability)
		if not bool(validation.get("success", false)):
			return validation
		var capability_id: String = String(capability["capability_id"])
		if capability_ids.has(capability_id):
			return _failure("DUPLICATE_CONSTRUCTION_BEHAVIOR_CAPABILITY")
		if not previous_capability_id.is_empty() and capability_id < previous_capability_id:
			return _failure("CONSTRUCTION_BEHAVIOR_CAPABILITIES_NOT_SORTED")
		capability_ids[capability_id] = capability
		capability_kinds[String(capability["capability_kind"])] = true
		previous_capability_id = capability_id
	var affordance_ids: Dictionary = {}
	var previous_affordance_id: String = ""
	for raw in value["affordances"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_BEHAVIOR_AFFORDANCE")
		var affordance: Dictionary = raw
		var validation: Dictionary = AffordanceScript.validate(affordance)
		if not bool(validation.get("success", false)):
			return validation
		var affordance_id: String = String(affordance["affordance_id"])
		if affordance_ids.has(affordance_id):
			return _failure("DUPLICATE_CONSTRUCTION_BEHAVIOR_AFFORDANCE")
		if not previous_affordance_id.is_empty() and affordance_id < previous_affordance_id:
			return _failure("CONSTRUCTION_BEHAVIOR_AFFORDANCES_NOT_SORTED")
		var referenced_capability_id: String = String(affordance["capability_id"])
		if not capability_ids.has(referenced_capability_id):
			return _failure("CONSTRUCTION_BEHAVIOR_AFFORDANCE_CAPABILITY_MISSING")
		var referenced_capability: Dictionary = capability_ids[referenced_capability_id]
		if not Array(referenced_capability["provider_part_ids"]).has(String(affordance["target_part_id"])):
			return _failure("CONSTRUCTION_BEHAVIOR_AFFORDANCE_PROVIDER_MISMATCH")
		var target_port_id: String = String(affordance["target_port_id"])
		if not target_port_id.is_empty() and not Array(referenced_capability["source_port_ids"]).has(target_port_id):
			return _failure("CONSTRUCTION_BEHAVIOR_AFFORDANCE_PORT_MISMATCH")
		affordance_ids[affordance_id] = true
		previous_affordance_id = affordance_id
	if not bool(value["operational"]) and (not value["capabilities"].is_empty() or not value["affordances"].is_empty()):
		return _failure("NON_OPERATIONAL_CONSTRUCT_EXPOSES_BEHAVIOR")
	if typeof(value.get("diagnostics")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["diagnostics"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_BEHAVIOR_DIAGNOSTICS")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_BEHAVIOR_PROFILE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_BEHAVIOR_PROFILE_NOT_JSON_SAFE")
	return _success({"capability_kinds": capability_kinds.keys()})


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func capability_kinds(value: Dictionary) -> Array:
	var result: Array = []
	for capability in value.get("capabilities", []):
		result.append(String(capability.get("capability_kind", "")))
	result.sort()
	return result


static func _sorted_records(records: Array, id_field: String) -> Array:
	var result: Array = records.duplicate(true)
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
