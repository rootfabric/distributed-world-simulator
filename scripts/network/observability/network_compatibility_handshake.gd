extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FingerprintScript = preload("res://scripts/network/observability/network_build_fingerprint.gd")

const HELLO_SCHEMA: String = "planet_simulator.network_compatibility_hello.v1"
const ACK_SCHEMA: String = "planet_simulator.network_compatibility_ack.v1"
const REJECTION_SCHEMA: String = "planet_simulator.network_compatibility_rejection.v1"
const HELLO_FIELDS: Array[String] = [
	"schema", "handshake_id", "client_sent_at_ms", "fingerprint", "checksum",
]
const ACK_FIELDS: Array[String] = [
	"schema", "handshake_id", "server_received_at_ms", "server_sent_at_ms",
	"client_fingerprint_checksum", "server_fingerprint", "checksum",
]
const REJECTION_FIELDS: Array[String] = [
	"schema", "handshake_id", "error_code", "server_sent_at_ms", "checksum",
]


static func create_hello(handshake_id: String, fingerprint: Dictionary, client_sent_at_ms: int) -> Dictionary:
	var value: Dictionary = {
		"schema": HELLO_SCHEMA,
		"handshake_id": handshake_id,
		"client_sent_at_ms": client_sent_at_ms,
		"fingerprint": fingerprint.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = _checksum(value)
	return value


static func create_ack(
	handshake_id: String,
	client_fingerprint: Dictionary,
	server_fingerprint: Dictionary,
	server_received_at_ms: int,
	server_sent_at_ms: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": ACK_SCHEMA,
		"handshake_id": handshake_id,
		"server_received_at_ms": server_received_at_ms,
		"server_sent_at_ms": server_sent_at_ms,
		"client_fingerprint_checksum": String(client_fingerprint.get("checksum", "")),
		"server_fingerprint": server_fingerprint.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = _checksum(value)
	return value


static func create_rejection(handshake_id: String, error_code: String, server_sent_at_ms: int) -> Dictionary:
	var value: Dictionary = {
		"schema": REJECTION_SCHEMA,
		"handshake_id": handshake_id,
		"error_code": error_code,
		"server_sent_at_ms": server_sent_at_ms,
		"checksum": "",
	}
	value["checksum"] = _checksum(value)
	return value


static func evaluate_server(expected_fingerprint: Dictionary, hello: Dictionary, received_at_ms: int) -> Dictionary:
	var hello_check: Dictionary = validate_hello(hello)
	if not bool(hello_check.get("success", false)):
		return _failure("FINGERPRINT_REQUIRED" if hello.is_empty() else "INVALID_FINGERPRINT_HELLO", {
			"cause": hello_check,
		})
	var comparison: Dictionary = FingerprintScript.compare(
		expected_fingerprint,
		Dictionary(hello.get("fingerprint", {}))
	)
	if not bool(comparison.get("success", false)):
		return _failure(String(comparison.get("error_code", "FINGERPRINT_MISMATCH")), {
			"comparison": comparison,
		})
	return _success({
		"ack": create_ack(
			String(hello["handshake_id"]),
			Dictionary(hello["fingerprint"]),
			expected_fingerprint,
			received_at_ms,
			received_at_ms
		),
		"client_fingerprint": Dictionary(hello["fingerprint"]).duplicate(true),
	})


static func validate_client_ack(expected_fingerprint: Dictionary, hello: Dictionary, ack: Dictionary) -> Dictionary:
	var hello_check: Dictionary = validate_hello(hello)
	if not bool(hello_check.get("success", false)):
		return _failure("INVALID_LOCAL_HELLO")
	var ack_check: Dictionary = validate_ack(ack)
	if not bool(ack_check.get("success", false)):
		return _failure("INVALID_SERVER_FINGERPRINT_ACK", {"cause": ack_check})
	if String(ack.get("handshake_id", "")) != String(hello.get("handshake_id", "")):
		return _failure("HANDSHAKE_ID_MISMATCH")
	if String(ack.get("client_fingerprint_checksum", "")) != String(
		Dictionary(hello.get("fingerprint", {})).get("checksum", "")
	):
		return _failure("CLIENT_FINGERPRINT_ACK_MISMATCH")
	var comparison: Dictionary = FingerprintScript.compare(
		expected_fingerprint,
		Dictionary(ack.get("server_fingerprint", {}))
	)
	if not bool(comparison.get("success", false)):
		return _failure(String(comparison.get("error_code", "SERVER_FINGERPRINT_MISMATCH")), {
			"comparison": comparison,
		})
	return _success({"compatible": true})


static func validate_hello(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, HELLO_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != HELLO_SCHEMA:
		return _failure("UNSUPPORTED_HELLO_SCHEMA")
	if not _is_handshake_id(String(value.get("handshake_id", ""))):
		return _failure("INVALID_HANDSHAKE_ID")
	if not UtilsScript.is_json_integer(value.get("client_sent_at_ms")) or int(value["client_sent_at_ms"]) < 0:
		return _failure("INVALID_CLIENT_SEND_TIME")
	if not value.get("fingerprint") is Dictionary:
		return _failure("FINGERPRINT_REQUIRED")
	var fingerprint_check: Dictionary = FingerprintScript.validate(Dictionary(value["fingerprint"]))
	if not bool(fingerprint_check.get("success", false)):
		return _failure("INVALID_FINGERPRINT", {"cause": fingerprint_check})
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("HELLO_CHECKSUM_MISMATCH")
	return _success()


static func validate_ack(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, ACK_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != ACK_SCHEMA:
		return _failure("UNSUPPORTED_ACK_SCHEMA")
	if not _is_handshake_id(String(value.get("handshake_id", ""))):
		return _failure("INVALID_HANDSHAKE_ID")
	for field in ["server_received_at_ms", "server_sent_at_ms"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return _failure("INVALID_SERVER_TIME")
	if int(value["server_sent_at_ms"]) < int(value["server_received_at_ms"]):
		return _failure("INVALID_SERVER_TIME_ORDER")
	if not value.get("server_fingerprint") is Dictionary:
		return _failure("SERVER_FINGERPRINT_REQUIRED")
	var fingerprint_check: Dictionary = FingerprintScript.validate(Dictionary(value["server_fingerprint"]))
	if not bool(fingerprint_check.get("success", false)):
		return _failure("INVALID_SERVER_FINGERPRINT", {"cause": fingerprint_check})
	if String(value.get("client_fingerprint_checksum", "")).length() != 64:
		return _failure("INVALID_CLIENT_FINGERPRINT_CHECKSUM")
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("ACK_CHECKSUM_MISMATCH")
	return _success()


static func is_valid_handshake_id(value: String) -> bool:
	return _is_handshake_id(value)


static func validate_rejection(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, REJECTION_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != REJECTION_SCHEMA:
		return _failure("UNSUPPORTED_REJECTION_SCHEMA")
	if not _is_handshake_id(String(value.get("handshake_id", ""))):
		return _failure("INVALID_HANDSHAKE_ID")
	if String(value.get("error_code", "")).is_empty():
		return _failure("REJECTION_ERROR_CODE_REQUIRED")
	if not UtilsScript.is_json_integer(value.get("server_sent_at_ms")) or int(value["server_sent_at_ms"]) < 0:
		return _failure("INVALID_SERVER_SEND_TIME")
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("REJECTION_CHECKSUM_MISMATCH")
	return _success()


static func _checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func _is_handshake_id(value: String) -> bool:
	if not value.begins_with("handshake/") or value.length() > 192 or value != value.to_lower():
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["/", "-", "_", "."]):
			return false
	return not value.contains("//") and not value.ends_with("/")


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
