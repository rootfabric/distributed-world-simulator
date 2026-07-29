extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const DescriptorScript = preload("res://scripts/simulation/aggregates/aggregate_descriptor.gd")

const SCHEMA: String = "planet_simulator.aggregate_snapshot_envelope.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"snapshot_id",
	"descriptor",
	"state",
	"checksum",
]


static func create(snapshot_id: String, descriptor: Dictionary, state: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"snapshot_id": snapshot_id,
		"descriptor": descriptor.duplicate(true),
		"state": state.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_AGGREGATE_SNAPSHOT_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return _failure("UNSUPPORTED_AGGREGATE_SNAPSHOT_PROTOCOL")
	for field in ["snapshot_id", "checksum"]:
		var check: Dictionary = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if typeof(value.get("descriptor")) != TYPE_DICTIONARY or not bool(DescriptorScript.validate(value["descriptor"]).get("success", false)):
		return _failure("INVALID_AGGREGATE_DESCRIPTOR")
	if typeof(value.get("state")) != TYPE_DICTIONARY:
		return _failure("INVALID_AGGREGATE_STATE")
	var safe: Dictionary = UtilsScript.canonicalize(value, "$.aggregate_snapshot")
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_AGGREGATE_SNAPSHOT")
	if not _is_lower_hex_64(String(value["checksum"])):
		return _failure("INVALID_AGGREGATE_SNAPSHOT_CHECKSUM")
	if String(value["checksum"]) != compute_checksum(value):
		return _failure("AGGREGATE_SNAPSHOT_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return Dictionary(round_trip.get("value", {})) if bool(round_trip.get("success", false)) else {}


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func aggregate_id(value: Dictionary) -> String:
	return String(value.get("descriptor", {}).get("identity", {}).get("aggregate_id", ""))


static func authority(value: Dictionary) -> Dictionary:
	return Dictionary(value.get("descriptor", {}).get("authority", {})).duplicate(true)


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true


static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
