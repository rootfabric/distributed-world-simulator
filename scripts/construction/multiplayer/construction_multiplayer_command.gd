extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const GrantScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")

const SCHEMA := "planet_simulator.construction_multiplayer_command.v1"
const FIELDS: Array[String] = ["schema", "command_id", "client_id", "session_id", "session_epoch", "sequence", "action", "construct_id", "expected_construct_checksum", "expected_server_generation", "permission_epoch", "payload", "metadata", "checksum"]

static func create(command_id: String, client_id: String, session_id: String, session_epoch: int, sequence: int, action: String, construct_id: String, expected_construct_checksum: String, expected_server_generation: int, permission_epoch: int, payload: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	var result := {"schema": SCHEMA, "command_id": command_id, "client_id": client_id, "session_id": session_id, "session_epoch": session_epoch, "sequence": sequence, "action": action, "construct_id": construct_id, "expected_construct_checksum": expected_construct_checksum, "expected_server_generation": expected_server_generation, "permission_epoch": permission_epoch, "payload": payload.duplicate(true), "metadata": metadata.duplicate(true), "checksum": ""}
	result["checksum"] = compute_checksum(result); return result

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_MULTIPLAYER_COMMAND_SCHEMA")
	if not _id(String(value.get("command_id", "")), "multiplayer-command/") or not _id(String(value.get("client_id", "")), "client/") or not _id(String(value.get("session_id", "")), "session/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_IDENTITY")
	if not _id(String(value.get("construct_id", "")), "construct/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_TARGET")
	if not GrantScript.ACTIONS.has(String(value.get("action", ""))) or String(value.get("action", "")) == GrantScript.ACTION_READ: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_ACTION")
	for field in ["session_epoch", "sequence", "permission_epoch"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_COUNTER")
	if not UtilsScript.is_json_integer(value.get("expected_server_generation")) or int(value["expected_server_generation"]) < -1: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_GENERATION_PRECONDITION")
	var expected_checksum := String(value.get("expected_construct_checksum", ""))
	if not expected_checksum.is_empty() and expected_checksum.length() != 64: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_CHECKSUM_PRECONDITION")
	if typeof(value.get("payload")) != TYPE_DICTIONARY or typeof(value.get("metadata")) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_COMMAND_PAYLOAD")
	if not bool(UtilsScript.canonicalize(value["payload"]).get("success", false)) or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_COMMAND_PAYLOAD")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_COMMAND_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _id(value: String, prefix: String) -> bool: return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()
