extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.dynamic_type_reference.v1"
const FIELDS: Array[String] = [
	"schema",
	"package_id",
	"package_version",
	"package_hash",
	"state_schema",
]


static func create(
	package_id: String,
	package_version: String,
	package_hash: String,
	state_schema: String
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"package_id": package_id,
		"package_version": package_version,
		"package_hash": package_hash,
		"state_schema": state_schema,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_DYNAMIC_TYPE_SCHEMA")
	for field in ["package_id", "package_version", "package_hash", "state_schema"]:
		var check: Dictionary = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if not _is_package_id(String(value["package_id"])):
		return _failure("INVALID_PACKAGE_ID")
	if not _is_version(String(value["package_version"])):
		return _failure("INVALID_PACKAGE_VERSION")
	if not _is_lower_hex_64(String(value["package_hash"])):
		return _failure("INVALID_PACKAGE_HASH")
	if not _is_schema_id(String(value["state_schema"])):
		return _failure("INVALID_STATE_SCHEMA")
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return Dictionary(round_trip.get("value", {})) if bool(round_trip.get("success", false)) else {}


static func _is_package_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	var parts: PackedStringArray = value.split(":", true)
	if parts.size() != 2:
		return false
	return _is_lower_identifier(parts[0]) and _is_lower_identifier(parts[1])


static func _is_version(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges():
		return false
	var build_parts: PackedStringArray = value.split("+", true, 1)
	if build_parts.size() > 2 or (build_parts.size() == 2 and not _valid_dot_identifiers(build_parts[1], false)):
		return false
	var version_and_pre: String = build_parts[0]
	var pre_parts: PackedStringArray = version_and_pre.split("-", true, 1)
	if pre_parts.size() > 2 or (pre_parts.size() == 2 and not _valid_dot_identifiers(pre_parts[1], true)):
		return false
	var core: PackedStringArray = pre_parts[0].split(".", true)
	if core.size() != 3:
		return false
	for identifier in core:
		if not _is_numeric_identifier(identifier):
			return false
	return true


static func _is_schema_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	var parts: PackedStringArray = value.split(".", true)
	if parts.size() < 2:
		return false
	for part in parts:
		if not _is_lower_identifier(part):
			return false
	return true


static func _valid_dot_identifiers(value: String, reject_numeric_leading_zero: bool) -> bool:
	if value.is_empty():
		return false
	for identifier in value.split(".", true):
		if identifier.is_empty():
			return false
		if reject_numeric_leading_zero and identifier.is_valid_int() and identifier.length() > 1 and identifier.begins_with("0"):
			return false
		for character in identifier:
			var text: String = String(character)
			if not text.to_lower() in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"] and not text in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-"]:
				return false
	return true


static func _is_numeric_identifier(value: String) -> bool:
	if value.is_empty() or (value.length() > 1 and value.begins_with("0")):
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
			return false
	return true


static func _is_lower_identifier(value: String) -> bool:
	if value.is_empty() or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_"]:
			return false
	return true


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true


static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
