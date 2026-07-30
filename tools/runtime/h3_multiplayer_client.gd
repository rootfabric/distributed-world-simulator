extends SceneTree

const Support = preload("res://tools/runtime/h3_multiplayer_process_support.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Replica = preload("res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd")
const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")

var _options: Dictionary = {}
var _boundary
var _replica
var _logical_player_id := ""
var _peer_id := "peer/enet/server"
var _session_id := ""
var _phase := 1
var _started_ms := 0
var _join_sent := false
var _finished := false
var _player_entity_id := ""
var _first_ownership_epoch := 0
var _second_ownership_epoch := 0
var _current_ownership_epoch := 0
var _move_successes := 0
var _pickup_status := ""
var _pickup_error_code := ""
var _remote_movement_observed := false
var _a_left_observed := false
var _rejoined := false
var _final_snapshot: Dictionary = {}
var _targeted_results_received := 0
var _deltas_received := 0


func _initialize() -> void:
	var parsed := Support.parse(OS.get_cmdline_user_args(), true)
	_options = parsed.get("options", {})
	if not bool(parsed.get("success", false)):
		_fail("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_logical_player_id = String(_options.get("client_id", ""))
	_replica = Replica.new()
	_started_ms = Time.get_ticks_msec()
	_connect_phase()


func _connect_phase() -> void:
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(Port.new(), 524288, 32, 1048576)
	if not bool(configured.get("success", false)):
		_fail(String(configured.get("error_code", "BOUNDARY_CONFIGURATION_FAILED")))
		return
	_session_id = "transport-session/h3/%s/%d" % [_logical_player_id, _phase]
	var connected: Dictionary = _boundary.connect_client(
		Support.endpoint(_options),
		_peer_id,
		_session_id,
		"route/h3/server/%s/%d" % [_logical_player_id, _phase],
		_phase
	)
	if not bool(connected.get("success", false)):
		_fail(String(connected.get("error_code", "CONNECT_FAILED")))
		return
	_join_sent = false


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		_fail(String(polled.get("error_code", "POLL_FAILED")), _boundary.get_snapshot())
		return false
	if not _join_sent and String(_boundary.get_peer_snapshot(_peer_id).get("state", "")) == "TRANSPORT_CONNECTED":
		if not _ensure_ready():
			_fail("PEER_READY_FAILED")
			return false
		_send("JOIN", {
			"logical_player_id": _logical_player_id,
			"operation_id": "operation/h3/%s/join/%d" % [_logical_player_id, _phase],
		})
		_join_sent = true
	for event in polled.get("details", {}).get("events", []):
		if String(event.get("event_type", "")) != "MESSAGE_RECEIVED":
			continue
		_handle_message(event.get("frame", {}).get("payload", {}))
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout_ms", 30000)):
		_fail("CLIENT_TIMEOUT", {"client_id": _logical_player_id, "phase": _phase, "replica": _replica.get_report()})
	return false


func _handle_message(payload: Dictionary) -> void:
	var message_type := String(payload.get("type", ""))
	match message_type:
		"JOIN_ACK": _handle_join_ack(payload)
		"GAMEPLAY_DELTA": _handle_delta(payload.get("delta", {}))
		"GAMEPLAY_SNAPSHOT": _handle_snapshot(payload.get("snapshot", {}))
		"START_MOVEMENT": _start_movement(payload)
		"START_CONTENTION": _start_contention(payload)
		"COMMAND_RESULT": _handle_command_result(payload)
		"DISCONNECT_AND_REJOIN": _start_reconnect(payload)
		"LEAVE_ACK": _handle_leave_ack()
		"CONTINUE_AFTER_A_LEFT": _continue_after_a_left(payload)
		"SCENARIO_COMPLETE": _complete(payload)
		_: _fail("UNKNOWN_SERVER_MESSAGE", {"message_type": message_type})


func _handle_join_ack(payload: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_snapshot(payload.get("snapshot", {}))
	if not bool(accepted.get("success", false)):
		_fail(String(accepted.get("error_code", "JOIN_SNAPSHOT_REJECTED")))
		return
	var player: Dictionary = payload.get("player", {})
	var entity_id := String(player.get("player_entity_id", ""))
	var ownership_epoch := int(player.get("ownership_epoch", 0))
	if _player_entity_id.is_empty():
		_player_entity_id = entity_id
		_first_ownership_epoch = ownership_epoch
	elif entity_id != _player_entity_id:
		_fail("PLAYER_ENTITY_ID_CHANGED")
		return
	else:
		_second_ownership_epoch = ownership_epoch
		_rejoined = true
	_current_ownership_epoch = ownership_epoch
	_observe_replica()


func _handle_delta(delta: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_delta(delta)
	if not bool(accepted.get("success", false)):
		_fail(String(accepted.get("error_code", "GAMEPLAY_DELTA_REJECTED")), {"delta": delta, "replica": _replica.get_snapshot()})
		return
	if not bool(accepted.get("details", {}).get("replay", false)):
		_deltas_received += 1
	_observe_replica()


func _handle_snapshot(snapshot: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		_fail(String(accepted.get("error_code", "GAMEPLAY_SNAPSHOT_REJECTED")))
		return
	_observe_replica()


func _start_movement(payload: Dictionary) -> void:
	_handle_snapshot(payload.get("snapshot", {}))
	var delta_x := 1.0 if _logical_player_id == "a" else -1.0
	var delta_z := 0.5 if _logical_player_id == "a" else -0.5
	_send("MOVE", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _current_ownership_epoch,
		"input_sequence": 1,
		"delta_x": delta_x,
		"delta_z": delta_z,
		"operation_id": "operation/h3/%s/move/1" % _logical_player_id,
	})


func _start_contention(payload: Dictionary) -> void:
	_handle_snapshot(payload.get("snapshot", {}))
	_send("PICKUP", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _current_ownership_epoch,
		"item_id": Authority.SHARED_ITEM_ID,
		"operation_id": "operation/h3/%s/pickup/shared/1" % _logical_player_id,
	})


func _handle_command_result(payload: Dictionary) -> void:
	_targeted_results_received += 1
	var command_type := String(payload.get("command_type", ""))
	var status := String(payload.get("status", ""))
	if command_type == "MOVE":
		if status != "SUCCEEDED":
			_fail("MOVEMENT_REJECTED", {"payload": payload})
			return
		_move_successes += 1
	elif command_type == "PICKUP":
		_pickup_status = status
		_pickup_error_code = String(payload.get("error_code", ""))
		if status not in ["SUCCEEDED", "REJECTED"]:
			_fail("INVALID_PICKUP_RESULT", {"payload": payload})


func _start_reconnect(payload: Dictionary) -> void:
	if _logical_player_id != "a" or _phase != 1:
		_fail("UNEXPECTED_RECONNECT_REQUEST")
		return
	_handle_snapshot(payload.get("snapshot", {}))
	_send("LEAVE", {
		"logical_player_id": "a",
		"operation_id": "operation/h3/a/leave/1",
	})


func _handle_leave_ack() -> void:
	if _logical_player_id != "a" or _phase != 1:
		_fail("UNEXPECTED_LEAVE_ACK")
		return
	_boundary.stop()
	_phase = 2
	_connect_phase()


func _continue_after_a_left(payload: Dictionary) -> void:
	if _logical_player_id != "b":
		_fail("CONTINUE_SENT_TO_WRONG_PLAYER")
		return
	_handle_snapshot(payload.get("snapshot", {}))
	_send("MOVE", {
		"logical_player_id": "b",
		"ownership_epoch": _current_ownership_epoch,
		"input_sequence": 2,
		"delta_x": 0.0,
		"delta_z": 1.5,
		"operation_id": "operation/h3/b/move/2",
	})


func _complete(payload: Dictionary) -> void:
	_handle_snapshot(payload.get("snapshot", {}))
	_final_snapshot = _replica.get_snapshot()
	var player_a: Dictionary = _replica.get_player("a")
	var player_b: Dictionary = _replica.get_player("b")
	var shared_item: Dictionary = _replica.get_shared_item()
	if player_a.is_empty() or player_b.is_empty():
		_fail("FINAL_PLAYER_REPLICA_MISSING")
		return
	if bool(shared_item.get("available", true)):
		_fail("SHARED_ITEM_STILL_AVAILABLE")
		return
	var inventory_count := Array(player_a.get("inventory", [])).count(Authority.SHARED_ITEM_ID) + Array(player_b.get("inventory", [])).count(Authority.SHARED_ITEM_ID)
	if inventory_count != 1:
		_fail("SHARED_ITEM_DUPLICATED", {"inventory_count": inventory_count})
		return
	if not _remote_movement_observed:
		_fail("REMOTE_MOVEMENT_NOT_OBSERVED")
		return
	if _logical_player_id == "a" and (not _rejoined or _second_ownership_epoch != 2):
		_fail("PLAYER_A_RECONNECT_NOT_REPLICATED")
		return
	if _logical_player_id == "b" and (not _a_left_observed or _move_successes < 2):
		_fail("PLAYER_B_DID_NOT_CONTINUE")
		return
	_success()


func _observe_replica() -> void:
	var remote_id := "b" if _logical_player_id == "a" else "a"
	var remote: Dictionary = _replica.get_player(remote_id)
	if not remote.is_empty() and int(remote.get("last_input_sequence", 0)) >= 1:
		_remote_movement_observed = true
	var player_a: Dictionary = _replica.get_player("a")
	if _logical_player_id == "b" and not player_a.is_empty() and not bool(player_a.get("connected", true)):
		_a_left_observed = true


func _send(message_type: String, data: Dictionary) -> void:
	var payload := data.duplicate(true)
	payload["type"] = message_type
	var frame_result: Dictionary = _boundary.create_frame_for_peer(_peer_id, "COMMAND", Support.MESSAGE_SCHEMA, payload)
	if not bool(frame_result.get("success", false)):
		_fail(String(frame_result.get("error_code", "FRAME_CREATE_FAILED")))
		return
	var sent: Dictionary = _boundary.send_to_peer(_peer_id, frame_result.get("details", {}).get("frame", {}))
	if not bool(sent.get("success", false)):
		_fail(String(sent.get("error_code", "SEND_FAILED")))


func _ensure_ready() -> bool:
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, _peer_id)
		if not bool(result.get("success", false)):
			return false
	return true


func _success() -> void:
	var report := {
		"schema": "planet_simulator.h3_multiplayer_client_report.v1",
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"state": "COMPLETE",
		"passed": true,
		"client_id": _logical_player_id,
		"player_entity_id": _player_entity_id,
		"first_ownership_epoch": _first_ownership_epoch,
		"second_ownership_epoch": _second_ownership_epoch,
		"rejoined": _rejoined,
		"move_successes": _move_successes,
		"pickup_status": _pickup_status,
		"pickup_error_code": _pickup_error_code,
		"remote_movement_observed": _remote_movement_observed,
		"a_left_observed": _a_left_observed,
		"targeted_results_received": _targeted_results_received,
		"deltas_received": _deltas_received,
		"replica": _replica.get_report(),
		"final_snapshot_checksum": String(_final_snapshot.get("checksum", "")),
		"process_id": OS.get_process_id(),
	}
	Support.write(String(_options["result_file"]), report)
	_finished = true
	print("H3_CLIENT_RESULT %s" % JSON.stringify(report))
	quit(0)


func _fail(error_code: String, details: Dictionary = {}) -> void:
	if _finished:
		return
	var report := {
		"schema": "planet_simulator.h3_multiplayer_client_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"client_id": _logical_player_id,
		"phase": _phase,
		"details": details.duplicate(true),
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result_file", "")).is_empty():
		Support.write(String(_options["result_file"]), report)
	_finished = true
	push_error("H3 client %s failed: %s" % [_logical_player_id, error_code])
	quit(1)


func _finalize() -> void:
	if _boundary != null:
		_boundary.stop()
