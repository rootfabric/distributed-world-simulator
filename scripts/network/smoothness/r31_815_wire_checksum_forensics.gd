extends RefCounted

# R31 / #815 — bounded, opt-in, read-only SEND/RECV exact packet fingerprints.
# Emits metadata ONLY (never raw payload or identity/token). It cannot
# validate, mutate, bypass, decrypt or alter a transport frame.
# All times in Trace are local per-process; join across actors by packet hash
# or frame_id, not process-local timestamps.
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "dws.net_smooth.r31_815.wire_checksum_fingerprint.v1"
const OPT_IN_ENV: String = "DWS_NET_R31_815_WIRE_FORENSICS"
const MAX_EVENTS_PER_PROCESS: int = 16000


static func enabled() -> bool:
	return OS.get_environment(OPT_IN_ENV) == "1"


static func inspect_packet(
	phase: String,
	peer_id: String,
	packet: PackedByteArray,
	sender_frame: Dictionary = {},
	error_code: String = ""
) -> Dictionary:
	# Pure instrumentation: only parse a private copy of existing wire bytes.
	var packet_text: String = packet.get_string_from_utf8()
	var payload_source = JSON.parse_string(packet_text)
	var frame: Dictionary = (
		Dictionary(payload_source)
		if payload_source is Dictionary else {}
	)
	var body_value = frame.get("payload", {})
	var body: Dictionary = (
		Dictionary(body_value) if body_value is Dictionary else {}
	)
	var advertised_checksum: String = String(frame.get("payload_checksum", ""))
	var parsed_checksum: String = (
		NetworkUtilsScript.payload_hash(body) if body_value is Dictionary else ""
	)
	var sender_hash: String = ""
	if sender_frame.has("payload") and sender_frame["payload"] is Dictionary:
		sender_hash = NetworkUtilsScript.payload_hash(
			Dictionary(sender_frame["payload"]))
	var parsed_canonical: String = NetworkUtilsScript.canonical_json(frame)
	return {
		"schema": SCHEMA,
		"phase": phase,
		"error_code": error_code,
		"frame_id": String(frame.get("frame_id", "")),
		"sequence": int(frame.get("sequence", 0)),
		"channel": String(frame.get("channel", "")),
		"delivery_mode": String(frame.get("delivery_mode", "")),
		"message_type": String(body.get("type", "")),
		"payload_field_count": body.size(),
		"packet_bytes": packet.size(),
		"packet_sha256": packet_text.sha256_text(),
		"peer_id_sha256": peer_id.sha256_text() if not peer_id.is_empty() else "",
		"session_id_sha256": String(frame.get("session_id", "")).sha256_text(),
		"advertised_payload_sha256": advertised_checksum,
		"postparse_payload_sha256": parsed_checksum,
		"postparse_checksum_matches": (
			advertised_checksum != "" and parsed_checksum == advertised_checksum),
		"sender_dictionary_payload_sha256": sender_hash,
		"sender_checksum_matches": (
			sender_hash == advertised_checksum if not sender_hash.is_empty() else null),
		"packet_canonical_after_parse": (
			parsed_canonical == packet_text if not parsed_canonical.is_empty() else false),
		"parsed_dictionary": payload_source is Dictionary,
		"raw_payload_redacted": true,
	}


static func numeric_roundtrip_drift(source_payload: Dictionary) -> Dictionary:
	# Native diagnostic of the exact old Frame.create->encode->decode pattern.
	# Does NOT modify or normalize the source payload.
	var first_text: String = NetworkUtilsScript.canonical_json(source_payload)
	var first_value = JSON.parse_string(first_text)
	var second_text: String = (
		NetworkUtilsScript.canonical_json(first_value)
		if first_value is Dictionary else ""
	)
	var second_value = (
		JSON.parse_string(second_text) if not second_text.is_empty() else null
	)
	var third_text: String = (
		NetworkUtilsScript.canonical_json(second_value)
		if second_value is Dictionary else ""
	)
	return {
		"first_sha256": first_text.sha256_text(),
		"second_sha256": second_text.sha256_text(),
		"third_sha256": third_text.sha256_text(),
		"first_equals_second": first_text == second_text,
		"second_equals_third": second_text == third_text,
	}
