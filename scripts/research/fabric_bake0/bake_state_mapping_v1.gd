extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_state_mapping.v1"
const FIELDS: Array[String] = [
	"schema", "mapping_id", "full_state_schema_hash", "reduced_state_schema_hash",
	"projection_hash", "reconstruction_descriptor_hash", "checksum",
]

static func create(
	mapping_id: String, full_state_schema_hash: String, reduced_state_schema_hash: String,
	projection_hash: String, reconstruction_descriptor_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"mapping_id": mapping_id,
		"full_state_schema_hash": full_state_schema_hash,
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"projection_hash": projection_hash,
		"reconstruction_descriptor_hash": reconstruction_descriptor_hash,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BAKE_STATE_MAPPING_SCHEMA")
	if not Utils.is_canonical_id(value.get("mapping_id"), 2):
		return Utils.failure("INVALID_BAKE_STATE_MAPPING_ID")
	for field in [
		"full_state_schema_hash", "reduced_state_schema_hash",
		"projection_hash", "reconstruction_descriptor_hash",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_BAKE_STATE_MAPPING_HASH", {"field": field})
	return Utils.validate_checksum(value)
