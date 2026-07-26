extends RefCounted

const SCHEMA: String = "planet_simulator.item_operation_payload.v1"
const SCHEMA_VERSION: int = 1


static func build(
	command_type: String,
	aggregate_id: String,
	expected_revision: int,
	payload: Dictionary
) -> Dictionary:
	var envelope: Dictionary = {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"command_type": command_type,
		"aggregate_id": aggregate_id,
		"expected_revision": expected_revision,
		"payload": payload.duplicate(true),
	}
	var canonical_value = canonicalize(envelope)
	if not canonical_value is Dictionary:
		return {
			"success": false,
			"error_code": "PAYLOAD_CANONICALIZATION_FAILED",
		}
	var canonical_envelope: Dictionary = Dictionary(canonical_value)
	var encoded: String = JSON.stringify(
		canonical_envelope,
		"",
		true,
		true
	)
	if encoded.is_empty():
		return {
			"success": false,
			"error_code": "PAYLOAD_ENCODING_FAILED",
		}
	return {
		"success": true,
		"payload_hash": encoded.sha256_text(),
		"canonical_payload": canonical_envelope,
		"encoded_payload": encoded,
	}


static func canonicalize(value):
	var encoded: String = JSON.stringify(value, "", true, true)
	if encoded.is_empty():
		return null
	return JSON.parse_string(encoded)


static func is_sha256_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code: int = value.unicode_at(index)
		var is_digit: bool = code >= 48 and code <= 57
		var is_lower_hex: bool = code >= 97 and code <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true
