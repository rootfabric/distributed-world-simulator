extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_handshake_result_envelope.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "handshake_id", "accepted", "session_id",
	"server_node_id", "runtime_role", "checkpoint", "build_id", "authority_owner_id",
	"authority_epoch", "server_tick", "negotiated_capabilities", "contract_versions",
	"error_code", "checksum",
]


static func create(
	handshake_id: String,
	accepted: bool,
	session_id: String,
	server_node_id: String,
	checkpoint: String,
	build_id: String,
	authority_owner_id: String,
	authority_epoch: int,
	server_tick: int,
	negotiated_capabilities: Array[String],
	contract_versions: Dictionary,
	error_code: String = ""
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"handshake_id": handshake_id,
		"accepted": accepted,
		"session_id": session_id,
		"server_node_id": server_node_id,
		"runtime_role": "simulation-server",
		"checkpoint": checkpoint,
		"build_id": build_id,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"server_tick": server_tick,
		"negotiated_capabilities": negotiated_capabilities.duplicate(),
		"contract_versions": contract_versions.duplicate(true),
		"error_code": error_code,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "handshake_id", "session_id", "server_node_id", "runtime_role", "checkpoint", "build_id", "authority_owner_id", "error_code", "checksum"]:
		check = UtilsScript.require_string(value, field, field in ["session_id", "error_code"])
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected handshake result schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)):
		return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported handshake result protocol")
	check = UtilsScript.require_boolean(value, "accepted")
	if not bool(check.get("success", false)):
		return check
	for field in ["authority_epoch", "server_tick"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)) or int(value[field]) < 0:
			return UtilsScript.validation_failure("INVALID_FIELD_VALUE", "%s must be non-negative" % field)
	if String(value["runtime_role"]) != "simulation-server":
		return UtilsScript.validation_failure("UNSUPPORTED_ROLE", "Handshake result requires simulation-server role")
	check = _validate_string_array(value.get("negotiated_capabilities"), "negotiated_capabilities")
	if not bool(check.get("success", false)):
		return check
	check = _validate_contract_versions(value.get("contract_versions"))
	if not bool(check.get("success", false)):
		return check
	var accepted: bool = bool(value["accepted"])
	if accepted and (String(value["session_id"]).is_empty() or not String(value["error_code"]).is_empty()):
		return UtilsScript.validation_failure("INVALID_ACCEPTED_RESULT", "Accepted result requires session_id and empty error_code")
	if not accepted and (not String(value["session_id"]).is_empty() or String(value["error_code"]).is_empty()):
		return UtilsScript.validation_failure("INVALID_REJECTED_RESULT", "Rejected result requires empty session_id and error_code")
	if String(value["checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Handshake result checksum mismatch")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func _validate_string_array(raw_value, field: String) -> Dictionary:
	if not raw_value is Array or raw_value.is_empty():
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must be a non-empty Array" % field)
	var previous: String = ""
	for index in range(raw_value.size()):
		if typeof(raw_value[index]) != TYPE_STRING:
			return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must contain String values" % field)
		var item: String = String(raw_value[index])
		if item.is_empty() or item != item.strip_edges().to_lower() or not _is_identifier(item):
			return UtilsScript.validation_failure("INVALID_FIELD_VALUE", "%s entries must be canonical lowercase identifiers" % field)
		if index > 0 and item <= previous:
			return UtilsScript.validation_failure("NON_CANONICAL_ARRAY", "%s must be sorted and unique" % field)
		previous = item
	return UtilsScript.validation_success()


static func _validate_contract_versions(raw_value) -> Dictionary:
	if not raw_value is Dictionary or raw_value.is_empty():
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "contract_versions must be a non-empty Dictionary")
	for key_value in raw_value.keys():
		if typeof(key_value) != TYPE_STRING:
			return UtilsScript.validation_failure("INVALID_FIELD_NAME", "contract version keys must be String")
		var key: String = String(key_value)
		if key.is_empty() or key != key.strip_edges().to_lower() or not _is_identifier(key):
			return UtilsScript.validation_failure("INVALID_FIELD_NAME", "contract version keys must be canonical lowercase identifiers")
		if not UtilsScript.is_json_integer(raw_value[key_value]) or int(raw_value[key_value]) <= 0:
			return UtilsScript.validation_failure("INVALID_FIELD_VALUE", "contract versions must be positive integers")
	return UtilsScript.validation_success()


static func _is_identifier(value: String) -> bool:
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["_", ".", "-"]):
			return false
	return true
