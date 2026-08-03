extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TransportUtilsScript = preload("res://scripts/network/transports/v2/transport_contract_utils.gd")
const ChannelPolicyScript = preload("res://scripts/network/realtime/realtime_channel_policy.gd")

const SCHEMA: String = "planet_simulator.protocol_frame.v2"
const PROTOCOL_VERSION: int = 2
const FIELDS: Array[String] = [
	"schema", "protocol_version", "frame_id", "session_id", "sequence", "channel",
	"delivery_mode", "payload_schema", "payload", "payload_checksum",
]
const CHANNELS: Array[String] = ChannelPolicyScript.ALL_CHANNELS
const DELIVERY_MODES: Array[String] = ["RELIABLE_ORDERED", "RELIABLE_UNORDERED", "UNRELIABLE_SEQUENCED"]


static func create(
	frame_id: String,
	session_id: String,
	sequence: int,
	channel: String,
	delivery_mode: String,
	payload_schema: String,
	payload: Dictionary
) -> Dictionary:
	var canonical_payload := payload.duplicate(true)
	var round_trip := UtilsScript.json_round_trip(canonical_payload)
	if bool(round_trip.get("success", false)) and round_trip.get("value") is Dictionary:
		canonical_payload = Dictionary(round_trip.get("value", {}))
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"frame_id": frame_id,
		"session_id": session_id,
		"sequence": sequence,
		"channel": channel,
		"delivery_mode": delivery_mode,
		"payload_schema": payload_schema,
		"payload": canonical_payload,
		"payload_checksum": UtilsScript.payload_hash(canonical_payload),
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "frame_id", "session_id", "channel", "delivery_mode", "payload_schema", "payload_checksum"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected protocol frame schema")
	if not UtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol frame version")
	if not TransportUtilsScript.is_canonical_transport_id(value.get("frame_id"), "frame"):
		return UtilsScript.validation_failure("INVALID_FRAME_ID", "Invalid frame ID")
	if not TransportUtilsScript.is_canonical_transport_id(value.get("session_id"), "transport-session"):
		return UtilsScript.validation_failure("INVALID_SESSION_ID", "Invalid transport session ID")
	if not UtilsScript.is_json_integer(value.get("sequence")) or int(value["sequence"]) < 1:
		return UtilsScript.validation_failure("INVALID_SEQUENCE", "Frame sequence must be positive")
	if not CHANNELS.has(String(value["channel"])):
		return UtilsScript.validation_failure("INVALID_CHANNEL", "Unsupported protocol channel")
	if not DELIVERY_MODES.has(String(value["delivery_mode"])):
		return UtilsScript.validation_failure("INVALID_DELIVERY_MODE", "Unsupported delivery mode")
	var delivery_check: Dictionary = ChannelPolicyScript.validate_delivery(
		String(value["channel"]), String(value["delivery_mode"])
	)
	if not bool(delivery_check.get("success", false)):
		return UtilsScript.validation_failure(
			String(delivery_check.get("error_code", "CHANNEL_DELIVERY_MISMATCH")),
			"Channel delivery policy mismatch"
		)
	if not String(value["payload_schema"]).begins_with("planet_simulator."):
		return UtilsScript.validation_failure("INVALID_PAYLOAD_SCHEMA", "Payload schema must be namespaced")
	check = UtilsScript.require_dictionary(value, "payload")
	if not bool(check.get("success", false)):
		return check
	var canonical: Dictionary = UtilsScript.canonicalize(value["payload"])
	if not bool(canonical.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(canonical.get("error", "")))
	var expected_checksum: String = UtilsScript.payload_hash(value["payload"])
	if expected_checksum.is_empty() or expected_checksum != String(value["payload_checksum"]):
		return UtilsScript.validation_failure("PAYLOAD_CHECKSUM_MISMATCH", "Payload checksum mismatch")
	return UtilsScript.validation_success()


static func encode(value: Dictionary, max_packet_bytes: int = 1048576) -> Dictionary:
	var check: Dictionary = validate(value)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_FRAME")))
	var encoded: String = UtilsScript.canonical_json(value)
	if encoded.is_empty():
		return TransportUtilsScript.failure("SERIALIZATION_FAILED")
	var packet: PackedByteArray = encoded.to_utf8_buffer()
	if max_packet_bytes <= 0 or packet.size() > max_packet_bytes:
		return TransportUtilsScript.failure("PACKET_TOO_LARGE", {"packet_bytes": packet.size()})
	return TransportUtilsScript.success({"packet": packet, "packet_bytes": packet.size()})


static func decode(packet: PackedByteArray, max_packet_bytes: int = 1048576) -> Dictionary:
	if packet.is_empty():
		return TransportUtilsScript.failure("EMPTY_PACKET")
	if max_packet_bytes <= 0 or packet.size() > max_packet_bytes:
		return TransportUtilsScript.failure("PACKET_TOO_LARGE")
	var text: String = packet.get_string_from_utf8()
	if text.to_utf8_buffer() != packet:
		return TransportUtilsScript.failure("INVALID_UTF8")
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return TransportUtilsScript.failure("INVALID_JSON")
	var check: Dictionary = validate(parsed)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_FRAME")))
	if UtilsScript.canonical_json(parsed) != text:
		return TransportUtilsScript.failure("NON_CANONICAL_FRAME")
	return TransportUtilsScript.success({"frame": parsed.duplicate(true)})
