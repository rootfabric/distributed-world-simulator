extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const NetworkCommand = preload("res://scripts/network/contracts/network_command_envelope.gd")
const SCHEMA := "planet_simulator.item_command.v1"
const FIELDS: Array[String] = ["schema", "message_id", "operation_id", "logical_player_id", "transport_session_id", "authority_epoch", "ownership_epoch", "expected_revision", "command_type", "payload"]

static func create(message_id: String, operation_id: String, logical_player_id: String, transport_session_id: String, authority_epoch: int, ownership_epoch: int, expected_revision: int, command_type: String, payload: Dictionary) -> Dictionary:
	return Wire.create(SCHEMA, {"message_id": message_id, "operation_id": operation_id, "logical_player_id": logical_player_id.strip_edges().to_lower(), "transport_session_id": transport_session_id.strip_edges(), "authority_epoch": authority_epoch, "ownership_epoch": ownership_epoch, "expected_revision": expected_revision, "command_type": command_type, "payload": payload.duplicate(true)})

static func validate(value: Dictionary) -> Dictionary:
	if not bool(Wire.validate(value, SCHEMA, FIELDS).get("success", false)): return Wire.failure("INVALID_ITEM_COMMAND")
	for pair in [["message_id", "message"], ["operation_id", "operation"], ["transport_session_id", "transport-session"]]:
		if not bool(Wire.require_id(value, pair[0], pair[1]).get("success", false)): return Wire.failure("INVALID_ITEM_COMMAND")
	for field in ["authority_epoch", "ownership_epoch"]:
		if not bool(Wire.require_positive_integer(value, field).get("success", false)): return Wire.failure("INVALID_ITEM_COMMAND")
	if not bool(Wire.require_positive_integer(value, "expected_revision", true).get("success", false)) or String(value.get("command_type", "")).is_empty() or not value.get("payload") is Dictionary: return Wire.failure("INVALID_ITEM_COMMAND")
	return Wire.success()

static func validate_network_envelope(value: Dictionary) -> Dictionary:
	var check: Dictionary = NetworkCommand.validate(value)
	if not bool(check.get("success", false)): return Wire.failure(String(check.get("error_code", "INVALID_ITEM_COMMAND")))
	if not String(value.get("command_type", "")).begins_with("item.") and not String(value.get("command_type", "")).begins_with("inventory.") and not String(value.get("command_type", "")).begins_with("container."): return Wire.failure("INVALID_ITEM_COMMAND_TYPE")
	return Wire.success()
