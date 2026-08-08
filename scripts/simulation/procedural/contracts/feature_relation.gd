extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureIdScript = preload("res://scripts/simulation/procedural/contracts/feature_id.gd")

const SCHEMA: String = "planet_simulator.feature_relation.v1"
const TYPE_PREFIX: String = "feature-relation/"
const FIELDS: Array[String] = [
	"schema",
	"relation_type",
	"target_feature_id",
	"attributes",
	"checksum",
]


static func create(relation_type: String, target_feature_id: String, attributes: Dictionary = {}) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"relation_type": relation_type,
		"target_feature_id": target_feature_id,
		"attributes": attributes.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_FEATURE_RELATION_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("relation_type"), 2) or not String(value["relation_type"]).begins_with(TYPE_PREFIX):
		return GeoUtilsScript.failure("INVALID_FEATURE_RELATION_TYPE")
	var target_validation: Dictionary = FeatureIdScript.validate(value.get("target_feature_id"))
	if not bool(target_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_FEATURE_RELATION_TARGET")
	if typeof(value.get("attributes")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_FEATURE_RELATION_ATTRIBUTES")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.feature_relation")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func identity_token(value: Dictionary) -> String:
	return "%s#%s" % [String(value.get("relation_type", "")), String(value.get("target_feature_id", ""))]
