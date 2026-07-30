extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const SCHEMA := "planet_simulator.player_leave_command.v1"
const FIELDS: Array[String] = ["schema", "message_id", "operation_id", "logical_player_id", "transport_session_id", "authority_epoch", "ownership_epoch"]

static func create(message_id: String, operation_id: String, logical_player_id: String, transport_session_id: String, authority_epoch: int, ownership_epoch: int) -> Dictionary:
	return Wire.create(SCHEMA, {"message_id": message_id, "operation_id": operation_id, "logical_player_id": logical_player_id.strip_edges().to_lower(), "transport_session_id": transport_session_id.strip_edges(), "authority_epoch": authority_epoch, "ownership_epoch": ownership_epoch})

static func validate(value: Dictionary) -> Dictionary:
	var check := Wire.validate(value, SCHEMA, FIELDS)
	if not bool(check.get("success", false)): return Wire.failure("INVALID_PLAYER_LEAVE_COMMAND")
	for pair in [["message_id", "message"], ["operation_id", "operation"], ["transport_session_id", "transport-session"]]:
		if not bool(Wire.require_id(value, pair[0], pair[1]).get("success", false)): return Wire.failure("INVALID_PLAYER_LEAVE_COMMAND")
	if String(value.get("logical_player_id", "")).strip_edges().is_empty() or String(value.get("logical_player_id", "")) != String(value.get("logical_player_id", "")).to_lower(): return Wire.failure("INVALID_PLAYER_LEAVE_COMMAND")
	for field in ["authority_epoch", "ownership_epoch"]:
		if not bool(Wire.require_positive_integer(value, field).get("success", false)): return Wire.failure("INVALID_PLAYER_LEAVE_COMMAND")
	return Wire.success()
