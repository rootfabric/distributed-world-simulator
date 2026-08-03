extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_spatial_section_definition.v1"
const FIELDS: Array[String] = [
	"schema", "section_id", "section_kind", "provider_part_ids", "required_bond_ids",
	"minimum_intact_providers", "properties", "checksum",
]
const VALID_KINDS: Array[String] = ["FOUNDATION", "FLOOR", "WALL", "ROOF", "DOOR_FRAME", "WINDOW_FRAME", "UTILITY_CHASE"]

static func create(section_id: String, section_kind: String, provider_part_ids: Array, required_bond_ids: Array = [], minimum_intact_providers: int = 1, properties: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"section_id": section_id,
		"section_kind": section_kind,
		"provider_part_ids": _sorted_strings(provider_part_ids),
		"required_bond_ids": _sorted_strings(required_bond_ids),
		"minimum_intact_providers": minimum_intact_providers,
		"properties": properties.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_SECTION_DEFINITION_SCHEMA")
	if not _is_path_id(String(value.get("section_id", "")), "spatial-section/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_ID")
	if typeof(value.get("section_kind")) != TYPE_STRING or not VALID_KINDS.has(String(value["section_kind"])): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_KIND")
	var providers := _validate_sorted_paths(value.get("provider_part_ids"), "part/", false)
	if not bool(providers.get("success", false)): return providers
	var bonds := _validate_sorted_paths(value.get("required_bond_ids"), "bond/", true)
	if not bool(bonds.get("success", false)): return bonds
	if not UtilsScript.is_json_integer(value.get("minimum_intact_providers")): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_QUORUM")
	var minimum := int(value["minimum_intact_providers"])
	if minimum < 1 or minimum > Array(value["provider_part_ids"]).size(): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_QUORUM")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_SPATIAL_SECTION_DEFINITION_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_SPATIAL_SECTION_DEFINITION_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func _validate_sorted_paths(value, prefix: String, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (not allow_empty and Array(value).is_empty()): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_REFERENCES")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_STRING: return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_REFERENCE")
		var identifier := String(raw)
		if not _is_path_id(identifier, prefix) or seen.has(identifier): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_REFERENCE")
		if not previous.is_empty() and identifier < previous: return _failure("CONSTRUCTION_SPATIAL_SECTION_REFERENCES_NOT_SORTED")
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
