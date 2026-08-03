extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.construction_spatial_opening_definition.v1"
const FIELDS: Array[String] = ["schema", "opening_id", "opening_kind", "from_space_id", "to_space_id", "frame_section_id", "closure_part_id", "required_bond_ids", "normally_closed", "properties", "checksum"]
const VALID_KINDS: Array[String] = ["DOOR", "WINDOW", "VENT", "PASSAGE"]

static func create(opening_id: String, opening_kind: String, from_space_id: String, to_space_id: String, frame_section_id: String, closure_part_id: String, required_bond_ids: Array = [], normally_closed: bool = true, properties: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "opening_id": opening_id, "opening_kind": opening_kind, "from_space_id": from_space_id, "to_space_id": to_space_id, "frame_section_id": frame_section_id, "closure_part_id": closure_part_id, "required_bond_ids": _sorted_strings(required_bond_ids), "normally_closed": normally_closed, "properties": properties.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_OPENING_DEFINITION_SCHEMA")
	if not _is_path_id(String(value.get("opening_id", "")), "spatial-opening/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_ID")
	if typeof(value.get("opening_kind")) != TYPE_STRING or not VALID_KINDS.has(String(value["opening_kind"])): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_KIND")
	for field in ["from_space_id", "to_space_id"]:
		if not _is_space_id(String(value.get(field, ""))): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_SPACE")
	if String(value["from_space_id"]) == String(value["to_space_id"]): return _failure("CONSTRUCTION_SPATIAL_OPENING_SELF_CONNECTION")
	if not _is_path_id(String(value.get("frame_section_id", "")), "spatial-section/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_FRAME_SECTION")
	var closure := String(value.get("closure_part_id", ""))
	if String(value["opening_kind"]) != "PASSAGE" and not _is_path_id(closure, "part/"): return _failure("CONSTRUCTION_SPATIAL_OPENING_CLOSURE_REQUIRED")
	if String(value["opening_kind"]) == "PASSAGE" and not closure.is_empty(): return _failure("CONSTRUCTION_SPATIAL_PASSAGE_CLOSURE_FORBIDDEN")
	var bonds := _validate_sorted_paths(value.get("required_bond_ids"), "bond/")
	if not bool(bonds.get("success", false)): return bonds
	if typeof(value.get("normally_closed")) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_NORMALLY_CLOSED")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_SPATIAL_OPENING_DEFINITION_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_SPATIAL_OPENING_DEFINITION_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _validate_sorted_paths(value, prefix: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_BONDS")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_STRING: return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_BOND")
		var identifier := String(raw)
		if not _is_path_id(identifier, prefix) or seen.has(identifier): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_BOND")
		if not previous.is_empty() and identifier < previous: return _failure("CONSTRUCTION_SPATIAL_OPENING_BONDS_NOT_SORTED")
		seen[identifier] = true; previous = identifier
	return _success()
static func _sorted_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result
static func _is_space_id(value: String) -> bool: return value == "space/exterior" or _is_path_id(value, "space/")
static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"): return false
	for segment in value.split("/", true):
		if segment.is_empty(): return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_": return false
	return true
static func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
