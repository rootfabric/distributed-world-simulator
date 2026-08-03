extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const DefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_section_definition.gd")
const SCHEMA := "planet_simulator.construction_spatial_section_state.v1"
const FIELDS: Array[String] = ["schema", "section_id", "section_kind", "status", "provider_part_ids", "online_provider_part_ids", "degraded_provider_part_ids", "offline_provider_part_ids", "properties", "diagnostics", "checksum"]
const VALID_STATUSES: Array[String] = ["ONLINE", "DEGRADED", "OFFLINE"]

static func create(definition: Dictionary, status: String, online_parts: Array, degraded_parts: Array, offline_parts: Array, properties: Dictionary, diagnostics: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "section_id": String(definition.get("section_id", "")), "section_kind": String(definition.get("section_kind", "")), "status": status, "provider_part_ids": Array(definition.get("provider_part_ids", [])).duplicate(true), "online_provider_part_ids": _sorted_strings(online_parts), "degraded_provider_part_ids": _sorted_strings(degraded_parts), "offline_provider_part_ids": _sorted_strings(offline_parts), "properties": properties.duplicate(true), "diagnostics": diagnostics.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_SECTION_STATE_SCHEMA")
	if not _is_path_id(String(value.get("section_id", "")), "spatial-section/"): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_STATE_ID")
	if typeof(value.get("section_kind")) != TYPE_STRING or not DefinitionScript.VALID_KINDS.has(String(value["section_kind"])): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_STATE_KIND")
	if typeof(value.get("status")) != TYPE_STRING or not VALID_STATUSES.has(String(value["status"])): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_STATUS")
	var providers := _partition(value)
	if not bool(providers.get("success", false)): return providers
	for field in ["properties", "diagnostics"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value[field]).get("success", false)): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_STATE_%s" % field.to_upper())
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_SPATIAL_SECTION_STATE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_SPATIAL_SECTION_STATE_NOT_JSON_SAFE")
	return _success()

static func _partition(value: Dictionary) -> Dictionary:
	for field in ["provider_part_ids", "online_provider_part_ids", "degraded_provider_part_ids", "offline_provider_part_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_PROVIDER_COLLECTION")
		var previous := ""; var seen_local := {}
		for raw in value[field]:
			var identifier := String(raw)
			if typeof(raw) != TYPE_STRING or not _is_path_id(identifier, "part/") or seen_local.has(identifier): return _failure("INVALID_CONSTRUCTION_SPATIAL_SECTION_PROVIDER")
			if not previous.is_empty() and identifier < previous: return _failure("CONSTRUCTION_SPATIAL_SECTION_PROVIDERS_NOT_SORTED")
			seen_local[identifier] = true; previous = identifier
	var providers := {}
	for raw in value["provider_part_ids"]:
		providers[String(raw)] = true
	var classified := {}
	for field in ["online_provider_part_ids", "degraded_provider_part_ids", "offline_provider_part_ids"]:
		for raw in value[field]:
			var identifier := String(raw)
			if not providers.has(identifier) or classified.has(identifier): return _failure("CONSTRUCTION_SPATIAL_SECTION_PROVIDER_PARTITION_MISMATCH")
			classified[identifier] = true
	if classified.size() != providers.size(): return _failure("CONSTRUCTION_SPATIAL_SECTION_PROVIDER_PARTITION_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
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
