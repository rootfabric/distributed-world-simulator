extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_spatial_utility_definition.v1"
const FIELDS: Array[String] = ["schema", "utility_id", "utility_kind", "provider_part_ids", "required_bond_ids", "dependency_utility_ids", "minimum_online_providers", "properties", "checksum"]
const VALID_KINDS: Array[String] = ["POWER", "WATER", "AIR", "DATA", "HEAT"]

static func create(utility_id: String, utility_kind: String, provider_part_ids: Array, required_bond_ids: Array = [], dependency_utility_ids: Array = [], minimum_online_providers: int = 1, properties: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "utility_id": utility_id, "utility_kind": utility_kind, "provider_part_ids": _sorted_strings(provider_part_ids), "required_bond_ids": _sorted_strings(required_bond_ids), "dependency_utility_ids": _sorted_strings(dependency_utility_ids), "minimum_online_providers": minimum_online_providers, "properties": properties.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_UTILITY_DEFINITION_SCHEMA")
	if not _is_path_id(String(value.get("utility_id", "")), "spatial-utility/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_UTILITY_ID")
	if typeof(value.get("utility_kind")) != TYPE_STRING or not VALID_KINDS.has(String(value["utility_kind"])): return _failure("INVALID_CONSTRUCTION_SPATIAL_UTILITY_KIND")
	for spec in [["provider_part_ids", "part/", false], ["required_bond_ids", "bond/", true], ["dependency_utility_ids", "spatial-utility/", true]]:
		var checked := _validate_sorted_paths(value.get(String(spec[0])), String(spec[1]), bool(spec[2]))
		if not bool(checked.get("success", false)): return checked
	if Array(value["dependency_utility_ids"]).has(String(value["utility_id"])): return _failure("CONSTRUCTION_SPATIAL_UTILITY_SELF_DEPENDENCY")
	if not UtilsScript.is_json_integer(value.get("minimum_online_providers")): return _failure("INVALID_CONSTRUCTION_SPATIAL_UTILITY_QUORUM")
	var minimum := int(value["minimum_online_providers"])
	if minimum < 1 or minimum > Array(value["provider_part_ids"]).size(): return _failure("INVALID_CONSTRUCTION_SPATIAL_UTILITY_QUORUM")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_SPATIAL_UTILITY_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_SPATIAL_UTILITY_DEFINITION_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_SPATIAL_UTILITY_DEFINITION_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _validate_sorted_paths(value, prefix: String, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (not allow_empty and Array(value).is_empty()): return _failure("INVALID_CONSTRUCTION_SPATIAL_UTILITY_REFERENCES")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_STRING: return _failure("INVALID_CONSTRUCTION_SPATIAL_UTILITY_REFERENCE")
		var identifier := String(raw)
		if not _is_path_id(identifier, prefix) or seen.has(identifier): return _failure("INVALID_CONSTRUCTION_SPATIAL_UTILITY_REFERENCE")
		if not previous.is_empty() and identifier < previous: return _failure("CONSTRUCTION_SPATIAL_UTILITY_REFERENCES_NOT_SORTED")
		seen[identifier] = true; previous = identifier
	return _success()
static func _sorted_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result
static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"): return false
	for segment in value.split("/", true):
		if segment.is_empty(): return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_": return false
	return true
static func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
