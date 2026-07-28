extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_handshake_envelope.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "handshake_id", "client_node_id", "runtime_role",
	"checkpoint", "build_id", "instance_id", "space_id", "capabilities",
	"contract_versions", "checksum",
]


static func create(
	handshake_id: String,
	client_node_id: String,
	checkpoint: String,
	build_id: String,
	instance_id: String,
	space_id: String,
	capabilities: Array[String],
	contract_versions: Dictionary,
	protocol_version: int = PROTOCOL_VERSION
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": protocol_version,
		"handshake_id": handshake_id,
		"client_node_id": client_node_id,
		"runtime_role": "bot-client",
		"checkpoint": checkpoint,
		"build_id": build_id,
		"instance_id": instance_id,
		"space_id": space_id,
		"capabilities": capabilities.duplicate(),
		"contract_versions": contract_versions.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "handshake_id", "client_node_id", "runtime_role", "checkpoint", "build_id", "instance_id", "space_id", "checksum"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected handshake schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)):
		return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported handshake protocol version")
	if String(value["runtime_role"]) != "bot-client":
		return UtilsScript.validation_failure("UNSUPPORTED_ROLE", "Handshake requires bot-client role")
	check = _validate_string_array(value.get("capabilities"), "capabilities")
	if not bool(check.get("success", false)):
		return check
	check = _validate_contract_versions(value.get("contract_versions"))
	if not bool(check.get("success", false)):
		return check
	if String(value["checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Handshake checksum mismatch")
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
	var safe: Dictionary = UtilsScript.canonicalize(raw_value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func _is_identifier(value: String) -> bool:
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["_", ".", "-"]):
			return false
	return true
