extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FieldIdScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_id.gd")
const DescriptorScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_descriptor.gd")
const ProvenanceScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_provenance.gd")
const ValueTypeScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_value_type.gd")

const SCHEMA: String = "planet_simulator.semantic_field_sample.v1"
const FIELDS: Array[String] = [
	"schema",
	"field_id",
	"body_id",
	"frame_id",
	"body_fixed_position_m",
	"value",
	"provenance",
	"checksum",
]


static func create(
	field_id: String,
	body_id: String,
	frame_id: String,
	body_fixed_position_m: Array,
	field_value,
	provenance: Dictionary
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"field_id": field_id,
		"body_id": body_id,
		"frame_id": frame_id,
		"body_fixed_position_m": body_fixed_position_m.duplicate(true),
		"value": field_value,
		"provenance": provenance.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_SEMANTIC_FIELD_SAMPLE_SCHEMA")
	var field_validation: Dictionary = FieldIdScript.validate(value.get("field_id"))
	if not bool(field_validation.get("success", false)):
		return field_validation
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SAMPLE_BODY_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SAMPLE_FRAME_ID")
	if not GeoUtilsScript.is_vector3_array(value.get("body_fixed_position_m")):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SAMPLE_POSITION")
	if typeof(value.get("provenance")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_SAMPLE_PROVENANCE")
	var provenance_validation: Dictionary = ProvenanceScript.validate(value["provenance"])
	if not bool(provenance_validation.get("success", false)):
		return provenance_validation
	var safe_value: Dictionary = GeoUtilsScript.validate_json_safe(value.get("value"), "$.semantic_field_sample.value")
	if not bool(safe_value.get("success", false)):
		return safe_value
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.semantic_field_sample")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func validate_against_descriptor(value: Dictionary, descriptor: Dictionary) -> Dictionary:
	var sample_validation: Dictionary = validate(value)
	if not bool(sample_validation.get("success", false)):
		return sample_validation
	var descriptor_validation: Dictionary = DescriptorScript.validate(descriptor)
	if not bool(descriptor_validation.get("success", false)):
		return descriptor_validation
	if String(value["field_id"]) != String(descriptor["field_id"]):
		return GeoUtilsScript.failure("SEMANTIC_FIELD_SAMPLE_DESCRIPTOR_ID_MISMATCH")
	return ValueTypeScript.validate_value(String(descriptor["value_type"]), value["value"])


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
