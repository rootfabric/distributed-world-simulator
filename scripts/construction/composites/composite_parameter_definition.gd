extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.composite_parameter_definition.v1"
const VALUE_TYPE_BOOL: String = "BOOL"
const VALUE_TYPE_INT: String = "INT"
const VALUE_TYPE_FLOAT: String = "FLOAT"
const VALUE_TYPE_STRING: String = "STRING"
const VALUE_TYPES: Array[String] = [VALUE_TYPE_BOOL, VALUE_TYPE_INT, VALUE_TYPE_FLOAT, VALUE_TYPE_STRING]
const FIELDS: Array[String] = ["schema", "parameter_id", "value_type", "default_value", "metadata"]


static func create(
	parameter_id: String,
	value_type: String,
	default_value,
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"parameter_id": parameter_id,
		"value_type": value_type,
		"default_value": default_value,
		"metadata": metadata.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_COMPOSITE_PARAMETER_SCHEMA")
	if not _is_path_id(String(value.get("parameter_id", "")), "parameter/"):
		return _failure("INVALID_COMPOSITE_PARAMETER_ID")
	if not VALUE_TYPES.has(String(value.get("value_type", ""))):
		return _failure("INVALID_COMPOSITE_PARAMETER_TYPE")
	var default_validation: Dictionary = validate_value(value, value.get("default_value"))
	if not bool(default_validation.get("success", false)):
		return default_validation
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)):
		return _failure("INVALID_COMPOSITE_PARAMETER_METADATA")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("COMPOSITE_PARAMETER_NOT_JSON_SAFE")
	return _success()


static func validate_value(parameter: Dictionary, raw_value) -> Dictionary:
	match String(parameter.get("value_type", "")):
		VALUE_TYPE_BOOL:
			if typeof(raw_value) != TYPE_BOOL:
				return _failure("COMPOSITE_PARAMETER_BOOL_REQUIRED")
		VALUE_TYPE_INT:
			if not UtilsScript.is_json_integer(raw_value):
				return _failure("COMPOSITE_PARAMETER_INT_REQUIRED")
		VALUE_TYPE_FLOAT:
			if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_value)):
				return _failure("COMPOSITE_PARAMETER_FLOAT_REQUIRED")
		VALUE_TYPE_STRING:
			if typeof(raw_value) != TYPE_STRING:
				return _failure("COMPOSITE_PARAMETER_STRING_REQUIRED")
		_:
			return _failure("INVALID_COMPOSITE_PARAMETER_TYPE")
	if not bool(UtilsScript.canonicalize(raw_value).get("success", false)):
		return _failure("COMPOSITE_PARAMETER_VALUE_NOT_JSON_SAFE")
	return _success()


static func normalize_value(parameter: Dictionary, raw_value):
	match String(parameter.get("value_type", "")):
		VALUE_TYPE_INT:
			return int(raw_value)
		VALUE_TYPE_FLOAT:
			return float(raw_value)
	return raw_value


static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
