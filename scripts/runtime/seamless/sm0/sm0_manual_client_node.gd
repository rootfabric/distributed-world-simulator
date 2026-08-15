extends "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd"

const ManualContracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const MANUAL_MOVE_STEP := 0.25

var _manual_axis := Vector2.ZERO


func set_manual_axis(axis: Vector2) -> void:
	_manual_axis = axis.limit_length(1.0)


func get_view_state() -> Dictionary:
	return {
		"client_state": _state,
		"authority_id": _current_authority_id,
		"zone_id": _current_zone_id,
		"authority_epoch": _directory_epoch,
		"directory_revision": _directory_revision,
		"ownership_epoch": _ownership_epoch,
		"handoffs_completed": _handoffs_completed,
		"player_entity_id": _player_entity_id,
		"player": _last_player.duplicate(true),
		"pending_transfer": _pending_transfer.duplicate(true),
		"errors": _errors.duplicate(),
	}


func _send_next_move() -> void:
	if _manual_axis.length_squared() < 0.0001:
		return
	_input_sequence += 1
	var movement := _manual_axis * MANUAL_MOVE_STEP
	var request_id := "move/%d" % _input_sequence
	var message := ManualContracts.create_message("CLIENT_MOVE", {
		"logical_player_id": _logical_player_id,
		"session_id": _session_id,
		"ownership_epoch": _ownership_epoch,
		"input_sequence": _input_sequence,
		"delta_x": movement.x,
		"delta_z": movement.y,
	}, request_id)
	_set_outstanding("MOVE", request_id, message)
	_send_message(message)
