extends RefCounted

const H0Contract = preload("res://scripts/runtime/seamless/mrpf/mrpf_h0_projection_contract.gd")

const SCHEMA := "distributed_world_simulator.mrpf_h1_projection_datagram.v1"
const ALLOWED_KEYS := [
	"schema",
	"source_route_id",
	"source_session_id",
	"sequence",
	"payload_hash",
	"payload",
]

static func encode(
	source_route_id: String,
	source_session_id: String,
	sequence: int,
	representation: Dictionary
) -> Dictionary:
	var route_id := source_route_id.strip_edges()
	var session_id := source_session_id.strip_edges()
	if route_id.is_empty():
		return _failure("MRPF_H1_ROUTE_ID_REQUIRED")
	if session_id.is_empty():
		return _failure("MRPF_H1_SESSION_ID_REQUIRED")
	if sequence < 1:
		return _failure("MRPF_H1_SEQUENCE_INVALID")
	var validated := H0Contract.validate(representation)
	if not bool(validated.get("success", false)):
		return _failure("MRPF_H1_PAYLOAD_INVALID", {"cause": validated})
	var datagram := {
		"schema": SCHEMA,
		"source_route_id": route_id,
		"source_session_id": session_id,
		"sequence": sequence,
		"payload_hash": String(representation.get("checksum", "")),
		"payload": representation.duplicate(true),
	}
	return _success({"packet": JSON.stringify(datagram).to_utf8_buffer()})

static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.is_empty():
		return _failure("MRPF_H1_DATAGRAM_EMPTY")
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("MRPF_H1_DATAGRAM_JSON_INVALID")
	var datagram: Dictionary = Dictionary(parsed)
	for raw_key in datagram.keys():
		if typeof(raw_key) != TYPE_STRING:
			return _failure("MRPF_H1_DATAGRAM_FIELD_UNKNOWN", {"field": str(raw_key)})
		if not ALLOWED_KEYS.has(String(raw_key)):
			return _failure("MRPF_H1_DATAGRAM_FIELD_UNKNOWN", {"field": String(raw_key)})
	for key in ALLOWED_KEYS:
		if not datagram.has(key):
			return _failure("MRPF_H1_DATAGRAM_FIELD_REQUIRED", {"field": key})
	if typeof(datagram["schema"]) != TYPE_STRING or String(datagram["schema"]) != SCHEMA:
		return _failure("MRPF_H1_DATAGRAM_SCHEMA_INVALID")
	for key in ["source_route_id", "source_session_id", "payload_hash"]:
		if typeof(datagram[key]) != TYPE_STRING or String(datagram[key]).strip_edges().is_empty():
			return _failure("MRPF_H1_DATAGRAM_FIELD_TYPE_INVALID", {"field": key})
	var sequence_result := _decode_wire_int(datagram["sequence"], 1, "sequence")
	if not bool(sequence_result.get("success", false)):
		return sequence_result
	if typeof(datagram["payload"]) != TYPE_DICTIONARY:
		return _failure("MRPF_H1_DATAGRAM_FIELD_TYPE_INVALID", {"field": "payload"})
	var payload_result := _normalize_representation(Dictionary(datagram["payload"]))
	if not bool(payload_result.get("success", false)):
		return payload_result
	var payload: Dictionary = Dictionary(payload_result["details"]["payload"])
	var validated := H0Contract.validate(payload)
	if not bool(validated.get("success", false)):
		return _failure("MRPF_H1_PAYLOAD_INVALID", {"cause": validated})
	if String(datagram["payload_hash"]) != String(payload.get("checksum", "")):
		return _failure("MRPF_H1_PAYLOAD_HASH_MISMATCH")
	return _success({
		"source_route_id": String(datagram["source_route_id"]),
		"source_session_id": String(datagram["source_session_id"]),
		"sequence": int(sequence_result["details"]["value"]),
		"payload": payload,
	})

static func _normalize_representation(payload: Dictionary) -> Dictionary:
	var normalized := payload.duplicate(true)
	for key in ["source_revision", "lod_level", "valid_from_revision"]:
		if not normalized.has(key):
			return _failure("MRPF_H1_PAYLOAD_INVALID", {
				"cause": {"success": false, "error_code": "MRPF_H0_FIELD_REQUIRED", "details": {"field": key}}
			})
		var minimum := 1 if key == "source_revision" else 0
		var wire_int := _decode_wire_int(normalized[key], minimum, key)
		if not bool(wire_int.get("success", false)):
			return _failure("MRPF_H1_PAYLOAD_WIRE_INT_INVALID", {"field": key})
		normalized[key] = int(wire_int["details"]["value"])
	return _success({"payload": normalized})

static func _decode_wire_int(raw: Variant, minimum: int, field: String) -> Dictionary:
	if typeof(raw) == TYPE_INT:
		var direct := int(raw)
		if direct < minimum:
			return _failure("MRPF_H1_DATAGRAM_INTEGER_INVALID", {"field": field})
		return _success({"value": direct})
	if typeof(raw) != TYPE_FLOAT:
		return _failure("MRPF_H1_DATAGRAM_FIELD_TYPE_INVALID", {"field": field})
	var as_float := float(raw)
	if is_nan(as_float) or is_inf(as_float):
		return _failure("MRPF_H1_DATAGRAM_INTEGER_INVALID", {"field": field})
	var converted := int(as_float)
	if float(converted) != as_float or converted < minimum:
		return _failure("MRPF_H1_DATAGRAM_INTEGER_INVALID", {"field": field})
	return _success({"value": converted})

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}

static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
