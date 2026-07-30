extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const SCHEMA := "planet_simulator.player_join_command.v1"
const FIELDS: Array[String] = ["schema", "message_id", "operation_id", "logical_player_id", "transport_session_id", "authority_epoch"]

static func create(message_id: String, operation_id: String, logical_player_id: String, transport_session_id: String, authority_epoch: int) -> Dictionary:
	return Wire.create(SCHEMA, {"message_id": message_id, "operation_id": operation_id, "logical_player_id": logical_player_id.strip_edges().to_lower(), "transport_session_id": transport_session_id.strip_edges(), "authority_epoch": authority_epoch})

static func validate(value: Dictionary) -> Dictionary:
	var check := Wire.validate(value, SCHEMA, FIELDS)
	if not bool(check.get("success", false)): return _map(check, "INVALID_PLAYER_JOIN_COMMAND")
	for pair in [["message_id", "message"], ["operation_id", "operation"], ["transport_session_id", "transport-session"]]:
		check = Wire.require_id(value, pair[0], pair[1])
		if not bool(check.get("success", false)): return _map(check, "INVALID_PLAYER_JOIN_COMMAND")
	if String(value.get("logical_player_id", "")).strip_edges().is_empty() or String(value.get("logical_player_id", "")) != String(value.get("logical_player_id", "")).to_lower(): return Wire.failure("INVALID_PLAYER_JOIN_COMMAND")
	check = Wire.require_positive_integer(value, "authority_epoch")
	return Wire.success() if bool(check.get("success", false)) else Wire.failure("INVALID_PLAYER_JOIN_COMMAND")

static func _map(_check: Dictionary, code: String) -> Dictionary: return Wire.failure(code)
