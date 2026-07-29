extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const MAX_TEXT_LENGTH := 192
const FORBIDDEN_ADAPTER_FIELDS: Array[String] = [
	"nats_subject",
	"jetstream_stream",
	"jetstream_consumer",
	"broker_id",
	"broker_message_id",
	"enet_channel",
	"transport_session_id",
	"transport_route_id",
]


static func is_canonical_id(value, prefix: String) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text != text.strip_edges() or text != text.to_lower() or not text.begins_with(prefix + "/"):
		return false
	if text.length() < prefix.length() + 2 or text.length() > MAX_TEXT_LENGTH:
		return false
	if text.contains("//") or text.ends_with("/"):
		return false
	for character in text:
		if not _is_identifier_character(character, true):
			return false
	return true


static func is_semantic_name(value, allow_slash: bool = false) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.is_empty() or text.length() > MAX_TEXT_LENGTH or text != text.strip_edges() or text != text.to_lower():
		return false
	if text.begins_with(".") or text.ends_with(".") or text.contains(".."):
		return false
	if text.begins_with("/") or text.ends_with("/") or text.contains("//"):
		return false
	for character in text:
		if not _is_identifier_character(character, allow_slash):
			return false
	return true


static func is_payload_schema(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text != text.strip_edges() or text != text.to_lower():
		return false
	if not text.begins_with("planet_simulator.") or text.length() > MAX_TEXT_LENGTH:
		return false
	var version_index: int = text.rfind(".v")
	if version_index <= "planet_simulator".length() or version_index >= text.length() - 2:
		return false
	var version_text: String = text.substr(version_index + 2)
	if version_text.is_empty():
		return false
	for character in version_text:
		if character < "0" or character > "9":
			return false
	return is_semantic_name(text, false)


static func validate_payload(payload) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_TYPE", "payload must be an Object/Dictionary")
	var canonical: Dictionary = NetworkUtilsScript.canonicalize(payload)
	if not bool(canonical.get("success", false)):
		return NetworkUtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(canonical.get("error", "payload is not JSON-safe")))
	var forbidden: String = _find_forbidden_field(payload, "$")
	if not forbidden.is_empty():
		return NetworkUtilsScript.validation_failure("ADAPTER_METADATA_FORBIDDEN", forbidden)
	return NetworkUtilsScript.validation_success()


static func deep_copy_json(value) -> Dictionary:
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
	if not bool(round_trip.get("success", false)):
		return {"success": false, "error_code": "NON_CANONICAL_VALUE", "value": null}
	return {"success": true, "error_code": "", "value": round_trip.get("value")}


static func content_hash_from_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


static func _find_forbidden_field(value, path: String) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			for raw_key in value.keys():
				if typeof(raw_key) != TYPE_STRING:
					return "%s contains a non-String key" % path
				var key: String = String(raw_key)
				if FORBIDDEN_ADAPTER_FIELDS.has(key):
					return "%s.%s is adapter-specific transport metadata" % [path, key]
				var nested: String = _find_forbidden_field(value[raw_key], "%s.%s" % [path, key])
				if not nested.is_empty():
					return nested
		TYPE_ARRAY:
			for index in range(value.size()):
				var nested: String = _find_forbidden_field(value[index], "%s[%d]" % [path, index])
				if not nested.is_empty():
					return nested
	return ""


static func _is_identifier_character(character: String, allow_slash: bool) -> bool:
	return (character >= "a" and character <= "z") \
		or (character >= "0" and character <= "9") \
		or character in (["/", "-", "_", "."] if allow_slash else ["-", "_", "."])
