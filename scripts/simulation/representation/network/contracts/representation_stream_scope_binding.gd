extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")

const SCHEMA := "planet_simulator.representation_stream_scope_binding.v1"
const FIELDS: Array[String] = ["schema", "lod_level", "scope_id", "checksum"]


static func create(lod_level: int, scope_id: String) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"lod_level": lod_level,
		"scope_id": scope_id,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_STREAM_SCOPE_BINDING_SCHEMA")
	if not Utils.is_json_integer(value.get("lod_level")) or int(value["lod_level"]) < 0 or int(value["lod_level"]) > Utils.MAX_LOD_LEVEL:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_SCOPE_LOD")
	if not Utils.is_canonical_id(value.get("scope_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_SCOPE_ID")
	return Utils.validate_checksum(value)
