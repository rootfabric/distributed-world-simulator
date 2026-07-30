extends RefCounted

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")


static func create(schema: String, payload: Dictionary) -> Dictionary:
	var value: Dictionary = payload.duplicate(true)
	value["schema"] = schema
	value.erase("checksum")
	value["checksum"] = NetworkUtils.payload_hash(value)
	return value


static func validate(value: Dictionary, schema: String, fields_without_checksum: Array[String]) -> Dictionary:
	var fields: Array[String] = fields_without_checksum.duplicate()
	fields.append("checksum")
	var exact: Dictionary = NetworkUtils.validate_exact_fields(value, fields)
	if not bool(exact.get("success", false)):
		return failure("INVALID_WIRE_FIELDS", {"schema": schema})
	if String(value.get("schema", "")) != schema:
		return failure("INVALID_WIRE_SCHEMA", {"expected": schema})
	var copy: Dictionary = value.duplicate(true)
	var checksum: String = String(copy.get("checksum", ""))
	copy.erase("checksum")
	if checksum.length() != 64 or checksum != NetworkUtils.payload_hash(copy):
		return failure("WIRE_CHECKSUM_MISMATCH", {"schema": schema})
	var canonical: Dictionary = NetworkUtils.canonicalize(value)
	if not bool(canonical.get("success", false)):
		return failure("WIRE_NOT_JSON_SAFE", {"schema": schema})
	return success()


static func require_id(value: Dictionary, field: String, prefix: String = "") -> Dictionary:
	var check: Dictionary = NetworkUtils.require_string(value, field)
	if not bool(check.get("success", false)):
		return failure("INVALID_WIRE_ID", {"field": field})
	if not prefix.is_empty() and not String(value.get(field, "")).begins_with(prefix + "/"):
		return failure("INVALID_WIRE_ID", {"field": field, "prefix": prefix})
	return success()


static func require_positive_integer(value: Dictionary, field: String, allow_zero: bool = false) -> Dictionary:
	if not NetworkUtils.is_json_integer(value.get(field)):
		return failure("INVALID_WIRE_INTEGER", {"field": field})
	var integer_value: int = int(value.get(field, 0))
	if integer_value < (0 if allow_zero else 1):
		return failure("INVALID_WIRE_INTEGER", {"field": field})
	return success()


static func validate_vector3(value, field: String) -> Dictionary:
	if not value is Dictionary:
		return failure("INVALID_WIRE_VECTOR", {"field": field})
	var exact: Dictionary = NetworkUtils.validate_exact_fields(value, ["x", "y", "z"])
	if not bool(exact.get("success", false)):
		return failure("INVALID_WIRE_VECTOR", {"field": field})
	for component in ["x", "y", "z"]:
		if typeof(value.get(component)) not in [TYPE_INT, TYPE_FLOAT]:
			return failure("INVALID_WIRE_VECTOR", {"field": field, "component": component})
		var number: float = float(value.get(component))
		if is_nan(number) or is_inf(number):
			return failure("INVALID_WIRE_VECTOR", {"field": field, "component": component})
	return success()


static func stringify_dictionary_keys(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var output: Dictionary = {}
			for key in value.keys():
				output[String(key)] = stringify_dictionary_keys(value[key])
			return output
		TYPE_ARRAY:
			var output: Array = []
			for child in value:
				output.append(stringify_dictionary_keys(child))
			return output
		_:
			return value


static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
