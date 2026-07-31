extends RefCounted
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_fabrication_machine_definition.v1"
const FIELDS: Array[String] = ["schema", "machine_definition_id", "provider_part_ids", "required_bond_ids", "input_container_id", "output_container_id", "supported_recipe_ids", "required_behavior_capability_kinds", "required_utility_ids", "minimum_intact_providers", "properties", "checksum"]
static func create(machine_definition_id: String, provider_part_ids: Array, required_bond_ids: Array, input_container_id: String, output_container_id: String, supported_recipe_ids: Array, required_behavior_capability_kinds: Array, required_utility_ids: Array, minimum_intact_providers: int, properties: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "machine_definition_id": machine_definition_id, "provider_part_ids": _sorted(provider_part_ids), "required_bond_ids": _sorted(required_bond_ids), "input_container_id": input_container_id, "output_container_id": output_container_id, "supported_recipe_ids": _sorted(supported_recipe_ids), "required_behavior_capability_kinds": _sorted(required_behavior_capability_kinds), "required_utility_ids": _sorted(required_utility_ids), "minimum_intact_providers": minimum_intact_providers, "properties": properties.duplicate(true), "checksum": ""}; value["checksum"] = compute_checksum(value); return value
static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_FABRICATION_MACHINE_DEFINITION_SCHEMA")
	if not _path(String(value.get("machine_definition_id", "")), "fabrication-machine/"): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_DEFINITION_ID")
	for spec in [["provider_part_ids", "part/", false], ["required_bond_ids", "bond/", true], ["supported_recipe_ids", "fabrication-recipe/", false], ["required_utility_ids", "spatial-utility/", true]]:
		var checked := _validate_paths(value.get(String(spec[0])), String(spec[1]), bool(spec[2])); if not bool(checked.get("success", false)): return checked
	if typeof(value.get("required_behavior_capability_kinds")) != TYPE_ARRAY or Array(value["required_behavior_capability_kinds"]).is_empty(): return _failure("CONSTRUCTION_FABRICATION_MACHINE_CAPABILITIES_REQUIRED")
	var previous := ""
	for raw in value["required_behavior_capability_kinds"]:
		var text := String(raw); if typeof(raw) != TYPE_STRING or text != text.to_upper() or (not previous.is_empty() and text < previous): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_CAPABILITY"); previous = text
	for field in ["input_container_id", "output_container_id"]:
		if not _token(String(value.get(field, ""))): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_CONTAINER")
	if String(value["input_container_id"]) == String(value["output_container_id"]): return _failure("CONSTRUCTION_FABRICATION_MACHINE_CONTAINERS_MUST_DIFFER")
	if not UtilsScript.is_json_integer(value.get("minimum_intact_providers")) or int(value["minimum_intact_providers"]) < 1 or int(value["minimum_intact_providers"]) > Array(value["provider_part_ids"]).size(): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_QUORUM")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_FABRICATION_MACHINE_DEFINITION_CHECKSUM_MISMATCH")
	return _success()
static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _validate_paths(value, prefix: String, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (not allow_empty and Array(value).is_empty()): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_REFERENCES")
	var previous := ""
	var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_STRING: return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_REFERENCE")
		var text := String(raw); if not _path(text, prefix) or seen.has(text) or (not previous.is_empty() and text < previous): return _failure("INVALID_CONSTRUCTION_FABRICATION_MACHINE_REFERENCE")
		seen[text] = true; previous = text
	return _success()
static func _sorted(values: Array) -> Array:
	var result: Array = []
	for raw in values:
		result.append(String(raw))
	result.sort()
	return result
static func _path(value: String, prefix: String) -> bool: return value.begins_with(prefix) and value.length() > prefix.length() and _token(value)
static func _token(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges(): return false
	for c in value:
		if not String(c) in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:": return false
	return true
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
