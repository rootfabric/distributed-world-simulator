extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const DefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_opening_definition.gd")
const SCHEMA := "planet_simulator.construction_spatial_opening_state.v1"
const FIELDS: Array[String] = ["schema", "opening_id", "opening_kind", "from_space_id", "to_space_id", "frame_section_id", "closure_part_id", "status", "properties", "diagnostics", "checksum"]
const VALID_STATUSES: Array[String] = ["SEALED", "CLOSED", "OPEN", "BREACHED", "INACTIVE"]

static func create(definition: Dictionary, status: String, properties: Dictionary, diagnostics: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "opening_id": String(definition.get("opening_id", "")), "opening_kind": String(definition.get("opening_kind", "")), "from_space_id": String(definition.get("from_space_id", "")), "to_space_id": String(definition.get("to_space_id", "")), "frame_section_id": String(definition.get("frame_section_id", "")), "closure_part_id": String(definition.get("closure_part_id", "")), "status": status, "properties": properties.duplicate(true), "diagnostics": diagnostics.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_OPENING_STATE_SCHEMA")
	if not _is_path_id(String(value.get("opening_id", "")), "spatial-opening/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_STATE_ID")
	if typeof(value.get("opening_kind")) != TYPE_STRING or not DefinitionScript.VALID_KINDS.has(String(value["opening_kind"])): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_STATE_KIND")
	for field in ["from_space_id", "to_space_id"]:
		var space_id := String(value.get(field, "")); if space_id != "space/exterior" and not _is_path_id(space_id, "space/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_STATE_SPACE")
	if not _is_path_id(String(value.get("frame_section_id", "")), "spatial-section/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_STATE_FRAME")
	var closure := String(value.get("closure_part_id", "")); if not closure.is_empty() and not _is_path_id(closure, "part/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_STATE_CLOSURE")
	if typeof(value.get("status")) != TYPE_STRING or not VALID_STATUSES.has(String(value["status"])): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_STATUS")
	for field in ["properties", "diagnostics"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value[field]).get("success", false)): return _failure("INVALID_CONSTRUCTION_SPATIAL_OPENING_STATE_%s" % field.to_upper())
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_SPATIAL_OPENING_STATE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_SPATIAL_OPENING_STATE_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"): return false
	for segment in value.split("/", true):
		if segment.is_empty(): return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_": return false
	return true
static func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
