extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const SCHEMA := "planet_simulator.player_input_command.v1"
const FIELDS: Array[String] = ["schema", "message_id", "operation_id", "logical_player_id", "transport_session_id", "authority_epoch", "ownership_epoch", "input_sequence", "input_kind", "payload"]
const INPUT_KINDS := ["MOVEMENT_DELTA", "AUTHORITATIVE_STATE"]

static func create(message_id: String, operation_id: String, logical_player_id: String, transport_session_id: String, authority_epoch: int, ownership_epoch: int, input_sequence: int, input_kind: String, payload: Dictionary) -> Dictionary:
	return Wire.create(SCHEMA, {"message_id": message_id, "operation_id": operation_id, "logical_player_id": logical_player_id.strip_edges().to_lower(), "transport_session_id": transport_session_id.strip_edges(), "authority_epoch": authority_epoch, "ownership_epoch": ownership_epoch, "input_sequence": input_sequence, "input_kind": input_kind, "payload": payload.duplicate(true)})

static func validate(value: Dictionary) -> Dictionary:
	var check := Wire.validate(value, SCHEMA, FIELDS)
	if not bool(check.get("success", false)): return Wire.failure("INVALID_PLAYER_INPUT_COMMAND")
	for pair in [["message_id", "message"], ["operation_id", "operation"], ["transport_session_id", "transport-session"]]:
		if not bool(Wire.require_id(value, pair[0], pair[1]).get("success", false)): return Wire.failure("INVALID_PLAYER_INPUT_COMMAND")
	if String(value.get("logical_player_id", "")).strip_edges().is_empty() or String(value.get("logical_player_id", "")) != String(value.get("logical_player_id", "")).to_lower(): return Wire.failure("INVALID_PLAYER_INPUT_COMMAND")
	for field in ["authority_epoch", "ownership_epoch", "input_sequence"]:
		if not bool(Wire.require_positive_integer(value, field).get("success", false)): return Wire.failure("INVALID_PLAYER_INPUT_COMMAND")
	if String(value.get("input_kind", "")) not in INPUT_KINDS or not value.get("payload") is Dictionary: return Wire.failure("INVALID_PLAYER_INPUT_COMMAND")
	if String(value.get("input_kind", "")) == "MOVEMENT_DELTA":
		var exact := preload("res://scripts/network/contracts/network_contract_utils.gd").validate_exact_fields(value.get("payload", {}), ["delta_x", "delta_z"])
		if not bool(exact.get("success", false)): return Wire.failure("INVALID_PLAYER_INPUT_COMMAND")
		for field in ["delta_x", "delta_z"]:
			if typeof(value["payload"].get(field)) not in [TYPE_INT, TYPE_FLOAT]: return Wire.failure("INVALID_PLAYER_INPUT_COMMAND")
	elif String(value.get("input_kind", "")) == "AUTHORITATIVE_STATE":
		var exact_state := preload("res://scripts/network/contracts/network_contract_utils.gd").validate_exact_fields(value.get("payload", {}), ["player_state", "delta_seconds"])
		if not bool(exact_state.get("success", false)) or not value["payload"].get("player_state") is Dictionary: return Wire.failure("INVALID_PLAYER_INPUT_COMMAND")
	return Wire.success()
