extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TransportUtilsScript = preload("res://scripts/network/transports/v2/transport_contract_utils.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")

const SCHEMA: String = "planet_simulator.network_transport_event.v2"
const FIELDS: Array[String] = [
	"schema", "event_id", "event_type", "peer_id", "session_id", "sequence",
	"monotonic_ms", "frame", "error_code", "details",
]
const EVENT_TYPES: Array[String] = [
	"LISTENER_STARTED", "PEER_CONNECTED", "PEER_DISCONNECTED", "MESSAGE_RECEIVED",
	"SEND_FAILED", "TRANSPORT_ERROR", "LISTENER_DRAINING", "LISTENER_STOPPED",
]


static func create(
	event_id: String,
	event_type: String,
	peer_id: String = "",
	session_id: String = "",
	sequence: int = 0,
	frame: Dictionary = {},
	error_code: String = "",
	details: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"event_id": event_id,
		"event_type": event_type,
		"peer_id": peer_id,
		"session_id": session_id,
		"sequence": sequence,
		"monotonic_ms": Time.get_ticks_msec(),
		"frame": frame.duplicate(true),
		"error_code": error_code,
		"details": details.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "event_id", "event_type", "peer_id", "session_id", "error_code"]:
		check = UtilsScript.require_string(value, field, field in ["peer_id", "session_id", "error_code"])
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected transport event schema")
	if not TransportUtilsScript.is_canonical_transport_id(value.get("event_id"), "transport-event"):
		return UtilsScript.validation_failure("INVALID_EVENT_ID", "Invalid event ID")
	if not EVENT_TYPES.has(String(value["event_type"])):
		return UtilsScript.validation_failure("INVALID_EVENT_TYPE", "Unsupported event type")
	if not UtilsScript.is_json_integer(value.get("sequence")) or int(value["sequence"]) < 0:
		return UtilsScript.validation_failure("INVALID_EVENT_SEQUENCE", "Invalid event sequence")
	if not UtilsScript.is_json_integer(value.get("monotonic_ms")) or int(value["monotonic_ms"]) < 0:
		return UtilsScript.validation_failure("INVALID_MONOTONIC_TIME", "Invalid monotonic time")
	check = UtilsScript.require_dictionary(value, "frame")
	if not bool(check.get("success", false)):
		return check
	check = UtilsScript.require_dictionary(value, "details")
	if not bool(check.get("success", false)):
		return check
	var peer_event: bool = String(value["event_type"]) in ["PEER_CONNECTED", "PEER_DISCONNECTED", "MESSAGE_RECEIVED", "SEND_FAILED"]
	if peer_event:
		if not TransportUtilsScript.is_canonical_transport_id(value.get("peer_id"), "peer"):
			return UtilsScript.validation_failure("INVALID_PEER_ID", "Peer event requires peer ID")
		if not TransportUtilsScript.is_canonical_transport_id(value.get("session_id"), "transport-session"):
			return UtilsScript.validation_failure("INVALID_SESSION_ID", "Peer event requires session ID")
	if String(value["event_type"]) == "MESSAGE_RECEIVED":
		check = FrameScript.validate(value["frame"])
		if not bool(check.get("success", false)):
			return UtilsScript.validation_failure("INVALID_EVENT_FRAME", String(check.get("error_code", "INVALID_FRAME")))
		if String(value["frame"].get("session_id", "")) != String(value["session_id"]):
			return UtilsScript.validation_failure("EVENT_SESSION_MISMATCH", "Event and frame sessions differ")
	return UtilsScript.validation_success()
