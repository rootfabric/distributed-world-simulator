extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")


static func require_id(value: Dictionary, field: String, prefix: String) -> Dictionary:
	return GatewayUtilsScript.require_id(value, field, prefix)


static func require_optional_id(value: Dictionary, field: String, prefix: String) -> Dictionary:
	var raw = value.get(field)
	if raw == null:
		return NetworkUtilsScript.validation_success()
	if not BusUtilsScript.is_canonical_id(raw, prefix):
		return NetworkUtilsScript.validation_failure(
			"INVALID_ID",
			"%s must be null or a canonical %s/* id" % [field, prefix],
		)
	return NetworkUtilsScript.validation_success()


static func require_positive_integer(value: Dictionary, field: String) -> Dictionary:
	return GatewayUtilsScript.require_positive_integer(value, field)


static func require_nonnegative_integer(value: Dictionary, field: String) -> Dictionary:
	return GatewayUtilsScript.require_nonnegative_integer(value, field)


static func require_nonnegative_number(value: Dictionary, field: String) -> Dictionary:
	var raw = value.get(field)
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return NetworkUtilsScript.validation_failure("INVALID_NUMBER", "%s must be numeric" % field)
	var number := float(raw)
	if is_nan(number) or is_inf(number) or number < 0.0:
		return NetworkUtilsScript.validation_failure("INVALID_NUMBER", "%s must be finite and >= 0" % field)
	var canonical: Dictionary = NetworkUtilsScript.canonicalize(raw)
	if not bool(canonical.get("success", false)):
		return NetworkUtilsScript.validation_failure("INVALID_NUMBER", String(canonical.get("error", "")))
	return NetworkUtilsScript.validation_success()


static func require_nonempty_string(value: Dictionary, field: String) -> Dictionary:
	return NetworkUtilsScript.require_string(value, field, false)


static func require_optional_string(value: Dictionary, field: String) -> Dictionary:
	var raw = value.get(field)
	if raw == null:
		return NetworkUtilsScript.validation_success()
	if typeof(raw) != TYPE_STRING or String(raw).strip_edges().is_empty():
		return NetworkUtilsScript.validation_failure(
			"INVALID_FIELD_TYPE",
			"%s must be null or a non-empty String" % field,
		)
	return NetworkUtilsScript.validation_success()


static func require_sha256(value: Dictionary, field: String) -> Dictionary:
	var raw = value.get(field)
	if typeof(raw) != TYPE_STRING:
		return NetworkUtilsScript.validation_failure("INVALID_DIGEST", "%s must be a SHA-256 hex String" % field)
	var digest := String(raw)
	if digest.length() != 64 or digest != digest.to_lower():
		return NetworkUtilsScript.validation_failure("INVALID_DIGEST", "%s must contain 64 lowercase hex characters" % field)
	for character in digest:
		if not ((character >= "0" and character <= "9") or (character >= "a" and character <= "f")):
			return NetworkUtilsScript.validation_failure("INVALID_DIGEST", "%s contains non-hex characters" % field)
	return NetworkUtilsScript.validation_success()


static func require_payload(value: Dictionary, field: String) -> Dictionary:
	if typeof(value.get(field)) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must be an Object/Dictionary" % field)
	return GatewayUtilsScript.validate_payload(value.get(field))


static func require_path_range(value: Dictionary, start_field: String = "path_t_start", end_field: String = "path_t_end") -> Dictionary:
	var start_check: Dictionary = require_nonnegative_number(value, start_field)
	if not bool(start_check.get("success", false)):
		return start_check
	var end_check: Dictionary = require_nonnegative_number(value, end_field)
	if not bool(end_check.get("success", false)):
		return end_check
	if float(value.get(end_field)) < float(value.get(start_field)):
		return NetworkUtilsScript.validation_failure("INVALID_PATH_RANGE", "%s must be >= %s" % [end_field, start_field])
	return NetworkUtilsScript.validation_success()
