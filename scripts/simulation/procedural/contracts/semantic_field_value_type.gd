extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const PREFIX: String = "semantic-field-value/"
const SCALAR_FLOAT: String = "semantic-field-value/scalar-float"
const SCALAR_INT: String = "semantic-field-value/scalar-int"
const BOOLEAN: String = "semantic-field-value/boolean"
const CANONICAL_ID: String = "semantic-field-value/canonical-id"
const VECTOR3_FLOAT: String = "semantic-field-value/vector3-float"
const SUPPORTED: Array[String] = [SCALAR_FLOAT, SCALAR_INT, BOOLEAN, CANONICAL_ID, VECTOR3_FLOAT]


static func validate(value) -> Dictionary:
	if typeof(value) != TYPE_STRING or String(value) not in SUPPORTED:
		return GeoUtilsScript.failure("UNSUPPORTED_SEMANTIC_FIELD_VALUE_TYPE")
	return GeoUtilsScript.success()


static func validate_value(value_type: String, value) -> Dictionary:
	var type_validation: Dictionary = validate(value_type)
	if not bool(type_validation.get("success", false)):
		return type_validation
	match value_type:
		SCALAR_FLOAT:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_FLOAT_VALUE")
		SCALAR_INT:
			if not GeoUtilsScript.is_json_integer(value):
				return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_INT_VALUE")
		BOOLEAN:
			if typeof(value) != TYPE_BOOL:
				return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_BOOL_VALUE")
		CANONICAL_ID:
			if not GeoUtilsScript.is_canonical_id(value, 2):
				return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_CANONICAL_ID_VALUE")
		VECTOR3_FLOAT:
			if not GeoUtilsScript.is_vector3_array(value):
				return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_VECTOR3_VALUE")
	return GeoUtilsScript.success()
