extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.player_presentation_command.v1"
const FIELDS: Array[String] = ["schema", "message_id", "operation_id", "logical_player_id", "transport_session_id", "authority_epoch", "ownership_epoch", "orientation_yaw", "flashlight_enabled"]

static func create(message_id: String, operation_id: String, logical_player_id: String, transport_session_id: String, authority_epoch: int, ownership_epoch: int, orientation_yaw: float, flashlight_enabled: bool) -> Dictionary:
	return Wire.create(SCHEMA, {
		"message_id": message_id,
		"operation_id": operation_id,
		"logical_player_id": logical_player_id.strip_edges().to_lower(),
		"transport_session_id": transport_session_id.strip_edges(),
		"authority_epoch": authority_epoch,
		"ownership_epoch": ownership_epoch,
		"orientation_yaw": orientation_yaw,
		"flashlight_enabled": flashlight_enabled,
	})

static func validate(value: Dictionary) -> Dictionary:
	var check := Wire.validate(value, SCHEMA, FIELDS)
	if not bool(check.get("success", false)):
		return Wire.failure("INVALID_PLAYER_PRESENTATION_COMMAND")
	for pair in [["message_id", "message"], ["operation_id", "operation"], ["transport_session_id", "transport-session"]]:
		if not bool(Wire.require_id(value, pair[0], pair[1]).get("success", false)):
			return Wire.failure("INVALID_PLAYER_PRESENTATION_COMMAND")
	var logical_id := String(value.get("logical_player_id", ""))
	if logical_id.strip_edges().is_empty() or logical_id != logical_id.to_lower():
		return Wire.failure("INVALID_PLAYER_PRESENTATION_COMMAND")
	for field in ["authority_epoch", "ownership_epoch"]:
		if not bool(Wire.require_positive_integer(value, field).get("success", false)):
			return Wire.failure("INVALID_PLAYER_PRESENTATION_COMMAND")
	var yaw_value = value.get("orientation_yaw")
	if typeof(yaw_value) not in [TYPE_INT, TYPE_FLOAT]:
		return Wire.failure("INVALID_PLAYER_PRESENTATION_COMMAND")
	var yaw := float(yaw_value)
	if is_nan(yaw) or is_inf(yaw) or absf(yaw) > PI:
		return Wire.failure("INVALID_PLAYER_PRESENTATION_COMMAND")
	if typeof(value.get("flashlight_enabled")) != TYPE_BOOL:
		return Wire.failure("INVALID_PLAYER_PRESENTATION_COMMAND")
	if not bool(Utils.canonicalize(value).get("success", false)):
		return Wire.failure("INVALID_PLAYER_PRESENTATION_COMMAND")
	return Wire.success()
