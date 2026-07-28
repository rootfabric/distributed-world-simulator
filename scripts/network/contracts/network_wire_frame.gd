extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_wire_frame.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "message_id", "message_type", "payload", "payload_hash",
]
const MESSAGE_TYPES: Array[String] = [
	"HANDSHAKE", "HANDSHAKE_RESULT", "SNAPSHOT", "SNAPSHOT_ACK",
	"COMMAND", "COMMAND_RESULT", "DELTA", "RESUME_TICKET",
	"SESSION_RESUME", "SESSION_RESUME_RESULT",
]


static func create(message_id: String, message_type: String, payload: Dictionary) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"message_id": message_id,
		"message_type": message_type,
		"payload": payload.duplicate(true),
		"payload_hash": UtilsScript.payload_hash(payload),
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "message_id", "message_type", "payload_hash"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected network wire frame schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)):
		return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported wire protocol version")
	if not MESSAGE_TYPES.has(String(value["message_type"])):
		return UtilsScript.validation_failure("UNKNOWN_MESSAGE_TYPE", "Unsupported wire message type")
	check = UtilsScript.require_dictionary(value, "payload")
	if not bool(check.get("success", false)):
		return check
	var safe: Dictionary = UtilsScript.canonicalize(value["payload"])
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	var expected_hash: String = UtilsScript.payload_hash(value["payload"])
	if expected_hash.is_empty() or String(value["payload_hash"]) != expected_hash:
		return UtilsScript.validation_failure("PAYLOAD_HASH_MISMATCH", "Wire payload hash mismatch")
	return UtilsScript.validation_success()


static func encode(value: Dictionary) -> Dictionary:
	var check: Dictionary = validate(value)
	if not bool(check.get("success", false)):
		return {"success": false, "error_code": String(check.get("error_code", "INVALID_FRAME")), "packet": PackedByteArray()}
	var encoded: String = UtilsScript.canonical_json(value)
	if encoded.is_empty():
		return {"success": false, "error_code": "SERIALIZATION_FAILED", "packet": PackedByteArray()}
	return {"success": true, "error_code": "", "packet": encoded.to_utf8_buffer()}


static func decode(packet: PackedByteArray, max_packet_bytes: int = 65536) -> Dictionary:
	if packet.is_empty():
		return _decode_failure("EMPTY_PACKET")
	if max_packet_bytes <= 0 or packet.size() > max_packet_bytes:
		return _decode_failure("PACKET_TOO_LARGE")
	var text: String = packet.get_string_from_utf8()
	if text.to_utf8_buffer() != packet:
		return _decode_failure("INVALID_UTF8")
	var json := JSON.new()
	if json.parse(text) != OK:
		return _decode_failure("INVALID_JSON")
	var parsed = json.data
	if not parsed is Dictionary:
		return _decode_failure("INVALID_JSON")
	var check: Dictionary = validate(parsed)
	if not bool(check.get("success", false)):
		return _decode_failure(String(check.get("error_code", "INVALID_FRAME")))
	var canonical: String = UtilsScript.canonical_json(parsed)
	if canonical != text:
		return _decode_failure("NON_CANONICAL_FRAME")
	return {"success": true, "error_code": "", "frame": parsed.duplicate(true)}


static func _decode_failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "frame": {}}
