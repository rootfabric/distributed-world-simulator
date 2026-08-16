extends "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd"

const ManualContracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const MANUAL_MOVE_STEP := 0.25

var _manual_axis := Vector2.ZERO

# Branch-local performance instrumentation. This does not participate in
# authority decisions or movement. It measures one healthy handoff entirely on
# the client clock: accepted boundary-crossing MOVE_ACK -> redirect ->
# ACTIVATE_ACK / SM0_CROSSING_COMPLETED.
var _latency_trigger_ms := 0
var _latency_redirect_ms := 0
var _latency_trigger_sequence := 0
var _latency_source_authority_id := ""
var _latency_transfer_id := ""


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


func _handle_move_ack(request_id: String, payload: Dictionary) -> void:
	var should_capture := (
		_latency_trigger_ms == 0
		and _matches_outstanding(request_id)
		and bool(payload.get("accepted", false))
	)
	if should_capture:
		var player: Dictionary = Dictionary(payload.get("player", {}))
		var position: Dictionary = Dictionary(player.get("position", {}))
		var x := float(position.get("x", 0.0))
		var crossed_boundary := (
			(_current_zone_id == ManualContracts.ZONE_A and x >= 0.0)
			or (_current_zone_id == ManualContracts.ZONE_B and x < 0.0)
		)
		if crossed_boundary:
			_latency_trigger_ms = Time.get_ticks_msec()
			_latency_trigger_sequence = int(player.get("last_input_sequence", _input_sequence))
			_latency_source_authority_id = _current_authority_id
			_event("SM0_CLIENT_HANDOFF_LATENCY_TRIGGER", {
				"source_authority_id": _latency_source_authority_id,
				"source_zone_id": _current_zone_id,
				"input_sequence": _latency_trigger_sequence,
				"position": position.duplicate(true),
			})
	super._handle_move_ack(request_id, payload)


func _handle_redirect(payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	super._handle_redirect(payload, remote_ip, remote_port)
	if (
		_latency_trigger_ms <= 0
		or not _latency_transfer_id.is_empty()
		or _state != "ACTIVATING"
		or _pending_transfer.is_empty()
	):
		return
	var transfer_id := String(_pending_transfer.get("transfer_id", ""))
	if transfer_id.is_empty():
		return
	_latency_transfer_id = transfer_id
	_latency_redirect_ms = Time.get_ticks_msec()
	_event("SM0_CLIENT_HANDOFF_LATENCY_REDIRECT", {
		"transfer_id": transfer_id,
		"source_authority_id": _latency_source_authority_id,
		"target_authority_id": String(_pending_transfer.get("target_authority_id", "")),
		"input_sequence": _latency_trigger_sequence,
		"trigger_to_redirect_ms": maxi(0, _latency_redirect_ms - _latency_trigger_ms),
	})


func _handle_activate_ack(request_id: String, payload: Dictionary) -> void:
	var handoffs_before := _handoffs_completed
	var transfer_before := String(_pending_transfer.get("transfer_id", ""))
	super._handle_activate_ack(request_id, payload)
	if _handoffs_completed != handoffs_before + 1 or _latency_trigger_ms <= 0:
		return
	var completed_transfer := transfer_before
	if completed_transfer.is_empty():
		completed_transfer = String(payload.get("transfer_id", ""))
	if not _latency_transfer_id.is_empty() and completed_transfer != _latency_transfer_id:
		_event("SM0_CLIENT_HANDOFF_LATENCY_TRANSFER_MISMATCH", {
			"expected_transfer_id": _latency_transfer_id,
			"completed_transfer_id": completed_transfer,
		})
		_reset_latency_measurement()
		return
	var completed_ms := Time.get_ticks_msec()
	var redirect_ms := _latency_redirect_ms if _latency_redirect_ms > 0 else completed_ms
	var velocity: Dictionary = Dictionary(_last_player.get("velocity", {}))
	_event("SM0_CLIENT_HANDOFF_LATENCY_MEASURED", {
		"handoff_index": _handoffs_completed,
		"transfer_id": completed_transfer,
		"source_authority_id": _latency_source_authority_id,
		"target_authority_id": _current_authority_id,
		"input_sequence": _latency_trigger_sequence,
		"trigger_to_redirect_ms": maxi(0, redirect_ms - _latency_trigger_ms),
		"redirect_to_activate_ms": maxi(0, completed_ms - redirect_ms),
		"total_ms": maxi(0, completed_ms - _latency_trigger_ms),
		"player_entity_id": _player_entity_id,
		"identity_changes": _identity_changes,
		"velocity": velocity.duplicate(true),
	})
	_reset_latency_measurement()


func _reset_latency_measurement() -> void:
	_latency_trigger_ms = 0
	_latency_redirect_ms = 0
	_latency_trigger_sequence = 0
	_latency_source_authority_id = ""
	_latency_transfer_id = ""
