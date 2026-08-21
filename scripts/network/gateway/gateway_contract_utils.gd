extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const PROTOCOL_VERSION: int = 1

const CHANNELS: Array[String] = [
	"SESSION_CONTROL",
	"INPUT_MOVEMENT",
	"AUTHORITATIVE_SNAPSHOT",
	"WORLD_OPERATION",
	"WORLD_PROJECTION",
	"RECOVERY_FULL_STATE",
	"TELEMETRY",
]
const DIRECTIONS: Array[String] = ["CLIENT_TO_WORLD", "WORLD_TO_CLIENT"]
const ROUTE_ROLES: Array[String] = ["ACTIVE", "WARM", "PROJECTION", "DRAIN"]
const SESSION_STATES: Array[String] = ["ATTACHING", "ATTACHED", "RESUMING", "DETACHED"]
const GATEWAY_HEALTH_STATES: Array[String] = ["HEALTHY", "DEGRADED", "DRAINING", "UNHEALTHY"]
const MUTATING_CLIENT_CHANNELS: Array[String] = ["INPUT_MOVEMENT", "WORLD_OPERATION"]


static func validate_schema(value: Dictionary, expected_schema: String) -> Dictionary:
	if value.get("schema") != expected_schema:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "schema mismatch")
	if not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) \
			or int(value.get("protocol_version")) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "protocol_version mismatch")
	return NetworkUtilsScript.validation_success()


static func require_id(value: Dictionary, field: String, prefix: String) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(value.get(field), prefix):
		return NetworkUtilsScript.validation_failure(
			"INVALID_ID",
			"%s must be a canonical %s/* id" % [field, prefix],
		)
	return NetworkUtilsScript.validation_success()


static func require_enum(value: Dictionary, field: String, allowed: Array[String]) -> Dictionary:
	if typeof(value.get(field)) != TYPE_STRING or not allowed.has(String(value.get(field))):
		return NetworkUtilsScript.validation_failure(
			"INVALID_ENUM",
			"%s must be one of %s" % [field, allowed],
		)
	return NetworkUtilsScript.validation_success()


static func require_positive_integer(value: Dictionary, field: String) -> Dictionary:
	if not NetworkUtilsScript.is_json_integer(value.get(field)) or int(value.get(field)) < 1:
		return NetworkUtilsScript.validation_failure("INVALID_INTEGER", "%s must be >= 1" % field)
	return NetworkUtilsScript.validation_success()


static func require_nonnegative_integer(value: Dictionary, field: String) -> Dictionary:
	if not NetworkUtilsScript.is_json_integer(value.get(field)) or int(value.get(field)) < 0:
		return NetworkUtilsScript.validation_failure("INVALID_INTEGER", "%s must be >= 0" % field)
	return NetworkUtilsScript.validation_success()


static func require_payload_schema(value: Dictionary, field: String = "payload_schema") -> Dictionary:
	if not BusUtilsScript.is_payload_schema(value.get(field)):
		return NetworkUtilsScript.validation_failure(
			"INVALID_PAYLOAD_SCHEMA",
			"%s must be a versioned planet_simulator.* schema" % field,
		)
	return NetworkUtilsScript.validation_success()


static func validate_payload(payload) -> Dictionary:
	return BusUtilsScript.validate_payload(payload)


static func is_mutating_client_channel(channel: String) -> bool:
	return MUTATING_CLIENT_CHANNELS.has(channel)


static func validate_client_frame_semantics(value: Dictionary) -> Dictionary:
	var channel: String = String(value.get("channel", ""))
	var payload = value.get("payload")
	if typeof(payload) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_TYPE", "payload must be a Dictionary")
	var payload_dict: Dictionary = Dictionary(payload)

	match channel:
		"WORLD_OPERATION":
			if not BusUtilsScript.is_canonical_id(payload_dict.get("operation_id"), "operation"):
				return NetworkUtilsScript.validation_failure(
					"INVALID_OPERATION_ID",
					"WORLD_OPERATION requires canonical operation_id",
				)
		"INPUT_MOVEMENT":
			if not NetworkUtilsScript.is_json_integer(payload_dict.get("input_seq")) \
					or int(payload_dict.get("input_seq")) < 1:
				return NetworkUtilsScript.validation_failure(
					"INVALID_INPUT_SEQUENCE",
					"INPUT_MOVEMENT requires positive input_seq",
				)
		"WORLD_PROJECTION":
			if typeof(payload_dict.get("read_only")) != TYPE_BOOL or not bool(payload_dict.get("read_only")):
				return NetworkUtilsScript.validation_failure(
					"PROJECTION_NOT_READ_ONLY",
					"WORLD_PROJECTION payload must declare read_only=true",
				)
	return NetworkUtilsScript.validation_success()
