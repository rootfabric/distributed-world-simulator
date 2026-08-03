extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_build_fingerprint.v1"
const SESSION_ID_PREFIX: String = "session-id/"
const SESSION_DIGEST_PREFIX: String = "sha256/"
const FIELDS: Array[String] = [
	"schema", "build_id", "git_commit", "protocol_hash", "world_id",
	"session_token", "checksum",
]


static func create(
	build_id: String,
	git_commit: String,
	protocol_hash: String,
	world_id: String,
	session_token: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"build_id": build_id,
		"git_commit": git_commit,
		"protocol_hash": protocol_hash,
		"world_id": world_id,
		"session_token": session_token,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "build_id", "git_commit", "protocol_hash", "world_id", "session_token", "checksum"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected build fingerprint schema")
	if not _is_identifier(String(value["build_id"]), false):
		return UtilsScript.validation_failure("INVALID_BUILD_ID", "build_id must be a canonical identifier")
	if not _is_hex(String(value["git_commit"]), 7, 64):
		return UtilsScript.validation_failure("INVALID_GIT_COMMIT", "git_commit must be a lowercase hexadecimal commit ID")
	if not _is_hex(String(value["protocol_hash"]), 64, 64):
		return UtilsScript.validation_failure("INVALID_PROTOCOL_HASH", "protocol_hash must be a SHA-256 value")
	if not _is_identifier(String(value["world_id"]), true):
		return UtilsScript.validation_failure("INVALID_WORLD_ID", "world_id must be a canonical identifier")
	if not _is_safe_session_token(String(value["session_token"])):
		return UtilsScript.validation_failure(
			"INVALID_SESSION_TOKEN",
			"session_token must use session-id/<public-id> or sha256/<64-lowercase-hex>"
		)
	if String(value["checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Build fingerprint checksum mismatch")
	return UtilsScript.validation_success()


static func compare(expected: Dictionary, actual: Dictionary) -> Dictionary:
	var expected_check: Dictionary = validate(expected)
	if not bool(expected_check.get("success", false)):
		return _failure("INVALID_EXPECTED_FINGERPRINT")
	var actual_check: Dictionary = validate(actual)
	if not bool(actual_check.get("success", false)):
		return _failure("INVALID_ACTUAL_FINGERPRINT")
	for pair in [
		["build_id", "BUILD_ID_MISMATCH"],
		["git_commit", "GIT_COMMIT_MISMATCH"],
		["protocol_hash", "PROTOCOL_HASH_MISMATCH"],
		["world_id", "WORLD_ID_MISMATCH"],
		["session_token", "SESSION_TOKEN_MISMATCH"],
	]:
		var field: String = String(pair[0])
		if String(expected[field]) != String(actual[field]):
			return _failure(String(pair[1]), {
				"field": field,
				"expected": String(expected[field]),
				"actual": String(actual[field]),
			})
	return _success({"compatible": true})


static func compute_protocol_hash(contract_versions: Dictionary, channel_policy: Dictionary) -> String:
	return UtilsScript.payload_hash({
		"contract_versions": contract_versions,
		"channel_policy": channel_policy,
	})


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func _is_safe_session_token(value: String) -> bool:
	if value.begins_with(SESSION_ID_PREFIX):
		var public_id: String = value.substr(SESSION_ID_PREFIX.length())
		return _is_identifier(public_id, true)
	if value.begins_with(SESSION_DIGEST_PREFIX):
		var digest: String = value.substr(SESSION_DIGEST_PREFIX.length())
		return _is_hex(digest, 64, 64)
	return false


static func _is_hex(value: String, min_length: int, max_length: int) -> bool:
	if value.length() < min_length or value.length() > max_length or value != value.to_lower():
		return false
	for character in value:
		if not ((character >= "0" and character <= "9") or (character >= "a" and character <= "f")):
			return false
	return true


static func _is_identifier(value: String, allow_slash: bool) -> bool:
	if value.is_empty() or value != value.strip_edges() or value != value.to_lower() or value.length() > 192:
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["-", "_", "."] or (allow_slash and character == "/")):
			return false
	return not value.contains("//") and not value.ends_with("/") and not value.begins_with("/")


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
