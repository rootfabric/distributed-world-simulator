extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TypeReferenceScript = preload("res://scripts/simulation/aggregates/dynamic_type_reference.gd")

const SCHEMA: String = "planet_simulator.aggregate_identity.v1"
const FIELDS: Array[String] = [
	"schema",
	"aggregate_id",
	"aggregate_kind",
	"state_schema",
	"dynamic_type_reference",
]


static func create(
	aggregate_id: String,
	aggregate_kind: String,
	state_schema: String,
	dynamic_type_reference: Dictionary
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"aggregate_id": aggregate_id,
		"aggregate_kind": aggregate_kind,
		"state_schema": state_schema,
		"dynamic_type_reference": dynamic_type_reference.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_AGGREGATE_IDENTITY_SCHEMA")
	for field in ["aggregate_id", "aggregate_kind", "state_schema"]:
		var check: Dictionary = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if not _is_aggregate_id(String(value["aggregate_id"])):
		return _failure("INVALID_AGGREGATE_ID")
	if not _is_kind(String(value["aggregate_kind"])):
		return _failure("INVALID_AGGREGATE_KIND")
	if not _is_schema_id(String(value["state_schema"])):
		return _failure("INVALID_AGGREGATE_STATE_SCHEMA")
	if typeof(value.get("dynamic_type_reference")) != TYPE_DICTIONARY:
		return _failure("INVALID_DYNAMIC_TYPE_REFERENCE")
	var type_validation: Dictionary = TypeReferenceScript.validate(value["dynamic_type_reference"])
	if not bool(type_validation.get("success", false)):
		return _failure("INVALID_DYNAMIC_TYPE_REFERENCE")
	if String(value["dynamic_type_reference"]["state_schema"]) != String(value["state_schema"]):
		return _failure("DYNAMIC_TYPE_STATE_SCHEMA_MISMATCH")
	return UtilsScript.validation_success()


static func _is_aggregate_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	var parts: PackedStringArray = value.split("/", true)
	if parts.size() < 2:
		return false
	for part in parts:
		if not _is_lower_identifier(part, true):
			return false
	return true


static func _is_kind(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_upper():
		return false
	for character in value:
		if not String(character) in ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "_"]:
			return false
	return true


static func _is_schema_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	var parts: PackedStringArray = value.split(".", true)
	if parts.size() < 2:
		return false
	for part in parts:
		if not _is_lower_identifier(part, false):
			return false
	return true


static func _is_lower_identifier(value: String, allow_colon: bool) -> bool:
	if value.is_empty() or value != value.to_lower():
		return false
	var allowed: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_"]
	if allow_colon:
		allowed.append(":")
	for character in value:
		if not String(character) in allowed:
			return false
	return true


static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
