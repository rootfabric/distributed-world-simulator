extends RefCounted

const MAX_SAFE_JSON_INTEGER: int = 9007199254740991


static func canonicalize(value, path: String = "$") -> Dictionary:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return {"success": true, "value": value, "error": ""}
		TYPE_INT:
			var integer_value: int = int(value)
			if integer_value < -MAX_SAFE_JSON_INTEGER or integer_value > MAX_SAFE_JSON_INTEGER:
				return _failure(path, "Integer exceeds the safe JSON range")
			return {"success": true, "value": integer_value, "error": ""}
		TYPE_FLOAT:
			var number: float = float(value)
			if is_nan(number) or is_inf(number):
				return _failure(path, "Non-finite floating-point value")
			if number == floor(number):
				if absf(number) > float(MAX_SAFE_JSON_INTEGER):
					return _failure(path, "Integer-valued number exceeds the safe JSON range")
				return {"success": true, "value": int(number), "error": ""}
			return {"success": true, "value": number, "error": ""}
		TYPE_ARRAY:
			var output: Array = []
			for index in range(value.size()):
				var child: Dictionary = canonicalize(value[index], "%s[%d]" % [path, index])
				if not bool(child.get("success", false)):
					return child
				output.append(child.get("value"))
			return {"success": true, "value": output, "error": ""}
		TYPE_DICTIONARY:
			var output: Dictionary = {}
			for key_value in value.keys():
				if typeof(key_value) != TYPE_STRING:
					return _failure(path, "Dictionary keys must be String")
				var key: String = String(key_value)
				var child: Dictionary = canonicalize(value[key_value], "%s.%s" % [path, key])
				if not bool(child.get("success", false)):
					return child
				output[key] = child.get("value")
			return {"success": true, "value": output, "error": ""}
		_:
			return _failure(path, "Godot runtime value is forbidden in network DTO: %s" % type_string(typeof(value)))


static func canonical_json(value) -> String:
	var normalized: Dictionary = canonicalize(value)
	if not bool(normalized.get("success", false)):
		return ""
	return JSON.stringify(normalized.get("value"), "", true, true)


static func payload_hash(value) -> String:
	var encoded: String = canonical_json(value)
	return encoded.sha256_text() if not encoded.is_empty() else ""


static func finalize_json_checksum(value: Dictionary) -> Dictionary:
	var candidate: Dictionary = value.duplicate(true)
	candidate["checksum"] = ""
	var round_trip: Dictionary = json_round_trip(candidate)
	if not bool(round_trip.get("success", false)) or not round_trip.get("value") is Dictionary:
		return {}
	candidate = Dictionary(round_trip.get("value", {})).duplicate(true)
	var payload := candidate.duplicate(true)
	payload.erase("checksum")
	candidate["checksum"] = payload_hash(payload)
	return candidate


static func json_round_trip(value) -> Dictionary:
	var encoded: String = canonical_json(value)
	if encoded.is_empty():
		return {"success": false, "value": {}, "error": "Value is not JSON-safe"}
	var decoded = JSON.parse_string(encoded)
	if decoded == null:
		return {"success": false, "value": {}, "error": "Canonical JSON could not be decoded"}
	return {"success": true, "value": decoded, "error": ""}


static func validate_exact_fields(value: Dictionary, required_fields: Array[String]) -> Dictionary:
	for field in required_fields:
		if not value.has(field):
			return validation_failure("MISSING_FIELD", "Required field is missing: %s" % field)
	for raw_key in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return validation_failure("INVALID_FIELD_NAME", "Envelope field names must be String")
		var key: String = String(raw_key)
		if not required_fields.has(key):
			return validation_failure("UNEXPECTED_FIELD", "Unexpected envelope field: %s" % key)
	return validation_success()


static func is_json_integer(value) -> bool:
	var value_type: int = typeof(value)
	if value_type == TYPE_INT:
		var integer_value: int = int(value)
		return integer_value >= -MAX_SAFE_JSON_INTEGER and integer_value <= MAX_SAFE_JSON_INTEGER
	if value_type != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return not is_nan(number) \
		and not is_inf(number) \
		and absf(number) <= float(MAX_SAFE_JSON_INTEGER) \
		and number == floor(number)


static func require_string(value: Dictionary, field: String, allow_empty: bool = false) -> Dictionary:
	if typeof(value.get(field)) != TYPE_STRING:
		return validation_failure("INVALID_FIELD_TYPE", "%s must be a String" % field)
	if not allow_empty and String(value[field]).strip_edges().is_empty():
		return validation_failure("EMPTY_FIELD", "%s cannot be empty" % field)
	return validation_success()


static func require_dictionary(value: Dictionary, field: String) -> Dictionary:
	if typeof(value.get(field)) != TYPE_DICTIONARY:
		return validation_failure("INVALID_FIELD_TYPE", "%s must be an Object/Dictionary" % field)
	return validation_success()


static func require_boolean(value: Dictionary, field: String) -> Dictionary:
	if typeof(value.get(field)) != TYPE_BOOL:
		return validation_failure("INVALID_FIELD_TYPE", "%s must be a Boolean" % field)
	return validation_success()


static func require_json_integer(value: Dictionary, field: String) -> Dictionary:
	if not is_json_integer(value.get(field)):
		return validation_failure("INVALID_FIELD_TYPE", "%s must be an integer-valued JSON number" % field)
	return validation_success()


static func validation_success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


static func validation_failure(error_code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "message": message}


static func _failure(path: String, message: String) -> Dictionary:
	return {
		"success": false,
		"value": null,
		"error": "%s: %s" % [path, message],
	}
