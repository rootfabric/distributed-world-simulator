extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_spatial_space_state.v1"
const FIELDS: Array[String] = ["schema", "space_id", "status", "section_ids", "opening_ids", "required_utility_ids", "boundary_failure_section_ids", "open_exterior_opening_ids", "available_utility_ids", "properties", "diagnostics", "checksum"]
const VALID_STATUSES: Array[String] = ["HABITABLE", "DEGRADED", "EXPOSED", "INACTIVE"]

static func create(definition: Dictionary, status: String, boundary_failures: Array, open_exterior_openings: Array, available_utilities: Array, properties: Dictionary, diagnostics: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "space_id": String(definition.get("space_id", "")), "status": status, "section_ids": Array(definition.get("section_ids", [])).duplicate(true), "opening_ids": Array(definition.get("opening_ids", [])).duplicate(true), "required_utility_ids": Array(definition.get("required_utility_ids", [])).duplicate(true), "boundary_failure_section_ids": _sorted_strings(boundary_failures), "open_exterior_opening_ids": _sorted_strings(open_exterior_openings), "available_utility_ids": _sorted_strings(available_utilities), "properties": properties.duplicate(true), "diagnostics": diagnostics.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_SPACE_STATE_SCHEMA")
	if not _is_path_id(String(value.get("space_id", "")), "space/") or String(value["space_id"]) == "space/exterior": return _failure("INVALID_CONSTRUCTION_SPATIAL_SPACE_STATE_ID")
	if typeof(value.get("status")) != TYPE_STRING or not VALID_STATUSES.has(String(value["status"])): return _failure("INVALID_CONSTRUCTION_SPATIAL_SPACE_STATUS")
	for spec in [["section_ids", "spatial-section/"], ["opening_ids", "spatial-opening/"], ["required_utility_ids", "spatial-utility/"], ["boundary_failure_section_ids", "spatial-section/"], ["open_exterior_opening_ids", "spatial-opening/"], ["available_utility_ids", "spatial-utility/"]]:
		var checked := _validate_sorted_paths(value.get(String(spec[0])), String(spec[1])); if not bool(checked.get("success", false)): return checked
	var sections := {}
	for raw in value["section_ids"]:
		sections[String(raw)] = true
	for raw in value["boundary_failure_section_ids"]:
		if not sections.has(String(raw)): return _failure("CONSTRUCTION_SPATIAL_SPACE_BOUNDARY_FAILURE_MISMATCH")
	var openings := {}
	for raw in value["opening_ids"]:
		openings[String(raw)] = true
	for raw in value["open_exterior_opening_ids"]:
		if not openings.has(String(raw)): return _failure("CONSTRUCTION_SPATIAL_SPACE_OPENING_STATE_MISMATCH")
	var utilities := {}
	for raw in value["required_utility_ids"]:
		utilities[String(raw)] = true
	for raw in value["available_utility_ids"]:
		if not utilities.has(String(raw)): return _failure("CONSTRUCTION_SPATIAL_SPACE_UTILITY_STATE_MISMATCH")
	for field in ["properties", "diagnostics"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value[field]).get("success", false)): return _failure("INVALID_CONSTRUCTION_SPATIAL_SPACE_STATE_%s" % field.to_upper())
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_SPATIAL_SPACE_STATE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_SPATIAL_SPACE_STATE_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _validate_sorted_paths(value, prefix: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_SPATIAL_SPACE_STATE_COLLECTION")
	var previous := ""; var seen := {}
	for raw in value:
		var identifier := String(raw)
		if typeof(raw) != TYPE_STRING or not _is_path_id(identifier, prefix) or seen.has(identifier): return _failure("INVALID_CONSTRUCTION_SPATIAL_SPACE_STATE_REFERENCE")
		if not previous.is_empty() and identifier < previous: return _failure("CONSTRUCTION_SPATIAL_SPACE_STATE_REFERENCES_NOT_SORTED")
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
