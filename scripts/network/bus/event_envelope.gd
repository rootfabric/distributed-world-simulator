extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const SCHEMA := "planet_simulator.event_envelope.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = ["schema", "protocol_version", "event_id", "stream_id", "event_type", "sequence", "producer_id", "payload_schema", "payload"]


static func create(event_id: String, stream_id: String, event_type: String, sequence: int, producer_id: String, payload_schema: String, payload: Dictionary) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"event_id": event_id,
		"stream_id": stream_id,
		"event_type": event_type,
		"sequence": sequence,
		"producer_id": producer_id,
		"payload_schema": payload_schema,
		"payload": payload.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Event schema/version mismatch")
	if not BusUtilsScript.is_canonical_id(value.get("event_id"), "event") or not BusUtilsScript.is_canonical_id(value.get("stream_id"), "stream"):
		return NetworkUtilsScript.validation_failure("INVALID_EVENT_IDENTITY", "event_id/stream_id is not canonical")
	if not BusUtilsScript.is_semantic_name(value.get("event_type"), true):
		return NetworkUtilsScript.validation_failure("INVALID_EVENT_TYPE", "event_type is not canonical")
	if not NetworkUtilsScript.is_json_integer(value.get("sequence")) or int(value["sequence"]) < 1:
		return NetworkUtilsScript.validation_failure("INVALID_SEQUENCE", "sequence must be positive")
	if not BusUtilsScript.is_canonical_id(value.get("producer_id"), "producer"):
		return NetworkUtilsScript.validation_failure("INVALID_PRODUCER_ID", "producer_id is not canonical")
	if not BusUtilsScript.is_payload_schema(value.get("payload_schema")):
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_SCHEMA", "payload_schema is not canonical")
	return BusUtilsScript.validate_payload(value.get("payload"))
