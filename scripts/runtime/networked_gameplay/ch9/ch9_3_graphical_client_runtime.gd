class_name Ch9GraphicalClientRuntime
extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"

const RealtimeChannelPolicy = preload("res://scripts/network/realtime/realtime_channel_policy.gd")


func submit_equipment_command_nonblocking(
	command_type: String,
	payload: Dictionary,
	operation_id: String
) -> Dictionary:
	if not is_ready():
		return _failure("CH9_3_CLIENT_NOT_READY")
	if command_type not in ["equipment.equip", "equipment.unequip"]:
		return _failure("CH9_3_UNSUPPORTED_EQUIPMENT_COMMAND")
	var normalized_operation_id := operation_id.strip_edges()
	if normalized_operation_id.is_empty():
		return _failure("CH9_3_OPERATION_ID_REQUIRED")
	var sent: bool = _send_on_channel(
		"ITEM_COMMAND",
		{
			"logical_player_id": _logical_player_id,
			"ownership_epoch": _ownership_epoch,
			"operation_id": normalized_operation_id,
			"command_type": command_type,
			"payload": payload.duplicate(true),
		},
		RealtimeChannelPolicy.ITEM,
		"RELIABLE_ORDERED",
		true
	)
	return _success({
		"operation_id": normalized_operation_id,
		"command_type": command_type,
		"expect_result": false,
	}) if sent else _failure("CH9_3_EQUIPMENT_COMMAND_SEND_FAILED")
