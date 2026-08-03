extends RefCounted
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")
const SCHEMA := "planet_simulator.construction_fabrication_machine_profile.v1"
const FIELDS: Array[String] = ["schema", "construct_id", "construct_revision", "construct_checksum", "machine_definition_id", "machine_definition_checksum", "status", "input_container_id", "output_container_id", "supported_recipe_ids", "provider_states", "utility_states", "capabilities", "affordances", "properties", "checksum"]
const STATUSES := ["ONLINE", "DEGRADED", "OFFLINE"]
static func create(snapshot: Dictionary, definition: Dictionary, status: String, provider_states: Array, utility_states: Array, capabilities: Array, affordances: Array, properties: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "construct_id": String(snapshot.get("construct_id", "")), "construct_revision": int(snapshot.get("state_revision", -1)), "construct_checksum": String(snapshot.get("checksum", "")), "machine_definition_id": String(definition.get("machine_definition_id", "")), "machine_definition_checksum": String(definition.get("checksum", "")), "status": status, "input_container_id": String(definition.get("input_container_id", "")), "output_container_id": String(definition.get("output_container_id", "")), "supported_recipe_ids": Array(definition.get("supported_recipe_ids", [])).duplicate(true), "provider_states": provider_states.duplicate(true), "utility_states": utility_states.duplicate(true), "capabilities": capabilities.duplicate(true), "affordances": affordances.duplicate(true), "properties": properties.duplicate(true), "checksum": ""}; value["checksum"] = compute_checksum(value); return value
static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_FABRICATION_MACHINE_PROFILE_SCHEMA")
	if not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_PROFILE_CONSTRUCT")
	if not UtilsScript.is_json_integer(value.get("construct_revision")) or int(value["construct_revision"]) < 0: return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_PROFILE_REVISION")
	for field in ["construct_checksum", "machine_definition_checksum"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).length() != 64: return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_PROFILE_CHECKSUM_REFERENCE")
	if not String(value.get("machine_definition_id", "")).begins_with("fabrication-machine/") or not STATUSES.has(String(value.get("status", ""))): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_PROFILE_IDENTITY")
	for field in ["input_container_id", "output_container_id"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).is_empty(): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_PROFILE_CONTAINER")
	for field in ["supported_recipe_ids", "provider_states", "utility_states", "capabilities", "affordances"]:
		if typeof(value.get(field)) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_PROFILE_COLLECTION")
	for capability in value["capabilities"]:
		var checked := CapabilityScript.validate(capability); if not bool(checked.get("success", false)): return checked
	for affordance in value["affordances"]:
		var checked := AffordanceScript.validate(affordance); if not bool(checked.get("success", false)): return checked
	if String(value["status"]) == "OFFLINE" and (not Array(value["capabilities"]).is_empty() or not Array(value["affordances"]).is_empty()): return _failure("OFFLINE_CONSTRUCTION_FABRICATION_MACHINE_EXPOSES_BEHAVIOR")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_PROFILE_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_FABRICATION_MACHINE_PROFILE_CHECKSUM_MISMATCH")
	return _success()
static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
