extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FieldIdScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_id.gd")
const ValueTypeScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_value_type.gd")
const DomainScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_domain.gd")

const SCHEMA: String = "planet_simulator.semantic_field_descriptor.v1"
const FIELDS: Array[String] = [
	"schema",
	"field_id",
	"value_type",
	"domain",
	"unit",
	"semantic_version",
	"metadata",
	"checksum",
]


static func create(
	field_id: String,
	value_type: String,
	domain: String,
	unit: String,
	semantic_version: String = "1.0.0",
	metadata: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"field_id": field_id,
		"value_type": value_type,
		"domain": domain,
		"unit": unit,
		"semantic_version": semantic_version,
		"metadata": metadata.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_SEMANTIC_FIELD_DESCRIPTOR_SCHEMA")
	var field_validation: Dictionary = FieldIdScript.validate(value.get("field_id"))
	if not bool(field_validation.get("success", false)):
		return field_validation
	var type_validation: Dictionary = ValueTypeScript.validate(value.get("value_type"))
	if not bool(type_validation.get("success", false)):
		return type_validation
	var domain_validation: Dictionary = DomainScript.validate(value.get("domain"))
	if not bool(domain_validation.get("success", false)):
		return domain_validation
	if typeof(value.get("unit")) != TYPE_STRING or String(value["unit"]).strip_edges().is_empty():
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_UNIT")
	if not GeoUtilsScript.is_semantic_version(value.get("semantic_version")):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_VERSION")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_METADATA")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.semantic_field_descriptor")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
