extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.matter_body_definition.v1"
const BODY_KINDS: Array[String] = ["ASTEROID", "MOON", "PLANET", "COMET", "ARTIFICIAL_BODY"]
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"body_kind",
	"body_frame_id",
	"generator_id",
	"generator_version",
	"generator_seed",
	"reference_radius_m",
	"default_material_id",
	"material_catalog_id",
	"material_catalog_hash",
	"metadata",
	"checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"body_kind": String(data.get("body_kind", "")).strip_edges().to_upper(),
		"body_frame_id": String(data.get("body_frame_id", "")).strip_edges().to_lower(),
		"generator_id": String(data.get("generator_id", "")).strip_edges().to_lower(),
		"generator_version": String(data.get("generator_version", "")).strip_edges(),
		"generator_seed": int(data.get("generator_seed", 0)),
		"reference_radius_m": float(data.get("reference_radius_m", 0.0)),
		"default_material_id": String(data.get("default_material_id", "")).strip_edges().to_lower(),
		"material_catalog_id": String(data.get("material_catalog_id", "")).strip_edges().to_lower(),
		"material_catalog_hash": String(data.get("material_catalog_hash", "")).strip_edges().to_lower(),
		"metadata": Dictionary(data.get("metadata", {})).duplicate(true),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_BODY_SCHEMA")
	for field in ["body_id", "body_frame_id", "generator_id", "default_material_id", "material_catalog_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_BODY_ID", {"field": field})
	if typeof(value.get("body_kind")) != TYPE_STRING or not String(value["body_kind"]) in BODY_KINDS:
		return MatterUtilsScript.failure("INVALID_MATTER_BODY_KIND")
	if not MatterUtilsScript.is_semantic_version(value.get("generator_version")):
		return MatterUtilsScript.failure("INVALID_MATTER_GENERATOR_VERSION")
	if not MatterUtilsScript.is_json_integer(value.get("generator_seed")):
		return MatterUtilsScript.failure("INVALID_MATTER_GENERATOR_SEED")
	if not MatterUtilsScript.is_positive_number(value.get("reference_radius_m")):
		return MatterUtilsScript.failure("INVALID_MATTER_REFERENCE_RADIUS")
	if not MatterUtilsScript.is_lower_hex_64(value.get("material_catalog_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_CATALOG_HASH")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY:
		return MatterUtilsScript.failure("INVALID_MATTER_BODY_METADATA")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_body")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)
