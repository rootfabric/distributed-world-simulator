extends Node

signal ready_for_clients(report: Dictionary)

const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")
const RecoveryRepository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const RecoveryCoordinator = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")
const M6AuthorityAdapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const M6ReplayOutbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")

const SCHEMA := "planet_simulator.m3_dedicated_server_runtime.v1"
const M6_CHECKPOINT := "v16.10.5-persistence-m6-dedicated-recovery"
const M6_BUILD_ID := "m6-dedicated-persistence-recovery"
const M7_CHECKPOINT := "v16.10.6.1-testing-m7-playable-networked-playground"
const M7_BUILD_ID := "m7-playable-networked-playground"
const M7_MOVEMENT_CHECKPOINT_INTERVAL_MS := 1500

var _boundary
var _service
var _configured := false
var _host := "127.0.0.1"
var _port := 0
var _result_file := ""
var _authority_owner_id := "simulation/m3/dedicated"
var _authority_epoch := 1
var _peer_to_player: Dictionary = {}
var _peer_to_session: Dictionary = {}
var _joins := 0
var _leaves := 0
var _moves := 0
var _presentation_updates := 0
var _rejections := 0
var _broadcasts := 0
var _messages_sent := 0
var _messages_received := 0
var _last_error_code := ""
var _last_two_connected_checksum := ""
var _persistence_root := ""
var _persistence_enabled := false
var _recovery_repository
var _recovery_coordinator
var _recovery_authority
var _replay_outbox
var _checkpoint_generation := 0
var _recovered := false
var _recovery_source := ""
var _last_checkpoint_operation_id := ""
var _persistence_failures := 0
var _last_persistence_error_details: Dictionary = {}
var _durable_commits := 0
var _fatal_persistence_failure := false
var _playable_sandbox := false
var _movement_checkpoint_dirty := false
var _last_movement_checkpoint_ms := 0
var _movement_checkpoints := 0
var _movement_commands_since_checkpoint := 0
var _debug_logging := false
var _last_debug_report_ms := 0
var _peer_last_input_ms: Dictionary = {}

func setup(config: Dictionary) -> Dictionary:
	if _configured:
		return _failure("M3_SERVER_ALREADY_CONFIGURED")
	_host = String(config.get("host", "127.0.0.1")).strip_edges()
	_port = int(config.get("port", 0))
	_result_file = String(config.get("result_file", "")).strip_edges()
	_authority_owner_id = String(config.get("authority_owner_id", _authority_owner_id)).strip_edges()
	_authority_epoch = int(config.get("authority_epoch", 1))
	_persistence_root = String(config.get("persistence_root", "")).strip_edges()
	_persistence_enabled = not _persistence_root.is_empty()
	_playable_sandbox = bool(config.get("playable_sandbox", false))
	_debug_logging = bool(config.get("debug_logging", false))
	if _host.is_empty() or _port < 1 or _port > 65535 or _authority_owner_id.is_empty() or _authority_epoch < 1:
		return _failure("INVALID_M3_SERVER_CONFIGURATION")
	_service = Service.new()
	var service_setup: Dictionary = _service.setup(_authority_owner_id, _authority_epoch, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/m3/single-server",
		"playable_sandbox": _playable_sandbox,
	})
	if not bool(service_setup.get("success", false)):
		return service_setup
	if _persistence_enabled:
		var recovery_setup := _setup_recovery()
		if not bool(recovery_setup.get("success", false)):
			_service.shutdown()
			_service = null
			return recovery_setup
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(Port.new(), 524288, 64, 2097152)
	if not bool(configured.get("success", false)):
		return configured
	var started: Dictionary = _boundary.start_server(Support.endpoint(_host, _port, true))
	if not bool(started.get("success", false)):
		return started
	_configured = true
	_last_movement_checkpoint_ms = Time.get_ticks_msec()
	_last_debug_report_ms = _last_movement_checkpoint_ms
	set_process(true)
	_debug_event("SERVER_READY", {"host":_host,"port":_port,"persistence_root":_persistence_root,"recovered":_recovered})
	_write_report("READY", false)
	ready_for_clients.emit(get_report())
	return _success({"host": _host, "port": _port})

func _process(_delta: float) -> void:
	if not _configured or _boundary == null or _fatal_persistence_failure:
		return
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_last_error_code = String(polled.get("error_code", "M3_SERVER_POLL_FAILED"))
		_write_report("FAILED", false)
		return
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_type := String(event.get("event_type", ""))
		var peer_id := String(event.get("peer_id", ""))
		var session_id := String(event.get("session_id", ""))
		if event_type == "MESSAGE_RECEIVED":
			_messages_received += 1
			_handle_message(peer_id, session_id, event.get("frame", {}).get("payload", {}))
		elif event_type == "PEER_DISCONNECTED":
			_handle_disconnect(peer_id, session_id)
	_maybe_persist_movement_checkpoint()
	if _debug_logging and Time.get_ticks_msec() - _last_debug_report_ms >= 2000:
		_last_debug_report_ms = Time.get_ticks_msec()
		_debug_event("SERVER_HEALTH", {
			"connected_peers":_peer_to_player.size(),"moves":_moves,"rejections":_rejections,
			"messages_received":_messages_received,"messages_sent":_messages_sent,
			"checkpoint_generation":_checkpoint_generation,"movement_dirty":_movement_checkpoint_dirty,
			"movement_commands_since_checkpoint":_movement_commands_since_checkpoint,
			"last_error_code":_last_error_code,
		})

func _handle_message(peer_id: String, session_id: String, payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"JOIN": _handle_join(peer_id, session_id, payload)
		"MOVE": _handle_move(peer_id, session_id, payload)
		"PLAYER_INPUT": _handle_player_input(peer_id, session_id, payload)
		"PLAYER_STATE": _handle_player_state_rejected(peer_id, session_id, payload)
		"PRESENTATION": _handle_presentation(peer_id, session_id, payload)
		"ITEM_COMMAND": _handle_item_command(peer_id, session_id, payload)
		"LEAVE": _handle_leave(peer_id, session_id, payload)
		_: _send_result(peer_id, String(payload.get("operation_id", "")), "UNKNOWN", _failure("UNKNOWN_M3_MESSAGE_TYPE"))

func _handle_join(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(payload.get("logical_player_id", "")).strip_edges().to_lower()
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if logical_id.is_empty() or not _is_canonical_operation_id(operation_id):
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "INVALID_JOIN_PAYLOAD"})
		return
	var result: Dictionary = _service.join(logical_id, session_id, operation_id)
	if not _persist_command_result(operation_id, "JOIN", logical_id, result):
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "M6_DURABLE_COMMIT_FAILED"})
		return
	if not bool(result.get("success", false)):
		_rejections += 1
		var rejection_sent := _send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "JOIN_REJECTED"))})
		if rejection_sent:
			_mark_operation_delivered(operation_id)
		_write_report("READY", false)
		return
	_peer_to_player[peer_id] = logical_id
	_peer_to_session[peer_id] = session_id
	_peer_last_input_ms[peer_id] = Time.get_ticks_msec()
	_debug_event("PLAYER_JOINED", {"peer_id":peer_id,"session_id":session_id,"logical_player_id":logical_id})
	var replay := _is_replay_result(result)
	if not replay:
		_joins += 1
	var join_sent := _send(peer_id, "JOIN_ACK", {
		"operation_id": operation_id,
		"player": result.get("details", {}).get("player", {}),
		"snapshot": result.get("details", {}).get("snapshot", {}),
		"item_graph_snapshot": _service.create_canonical_item_graph_snapshot(),
	})
	if not replay:
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
		_broadcast_snapshot("PLAYER_JOINED")
		_capture_two_connected_checksum()
	if join_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)

func _handle_move(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "MOVE", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "MOVE",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	var result: Dictionary = _service.move_player(
		logical_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		int(payload.get("input_sequence", 0)),
		float(payload.get("delta_x", 0.0)),
		float(payload.get("delta_z", 0.0)),
		operation_id
	)
	if not _persist_command_result(operation_id, "MOVE", logical_id, result):
		_send_result(peer_id, operation_id, "MOVE", _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	var result_sent := _send_result(peer_id, operation_id, "MOVE", result)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			_moves += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}))
			_broadcast_snapshot("PLAYER_MOVED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _handle_player_input(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "PLAYER_INPUT", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(peer_id, operation_id, "PLAYER_INPUT", "OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID")
		return
	var intent_value = payload.get("intent", {})
	if not intent_value is Dictionary:
		_reject_uncommitted_command(peer_id, operation_id, "PLAYER_INPUT", "MOVEMENT_INTENT_REQUIRED")
		return
	var now_ms := Time.get_ticks_msec()
	var previous_ms := int(_peer_last_input_ms.get(peer_id, now_ms - 50))
	_peer_last_input_ms[peer_id] = now_ms
	var authority_intent := Dictionary(intent_value).duplicate(true)
	authority_intent["delta_seconds"] = clampf(float(now_ms - previous_ms) / 1000.0, 1.0 / 30.0, 0.1)
	var result: Dictionary = _service.submit_movement_intent(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		int(payload.get("input_sequence", 0)), authority_intent, operation_id
	)
	_send_result(peer_id, operation_id, "PLAYER_INPUT", result)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			_moves += 1
			_movement_checkpoint_dirty = true
			_movement_commands_since_checkpoint += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}))
			_broadcast_snapshot("PLAYER_INPUT_SIMULATED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
		_debug_event("PLAYER_INPUT_REJECTED", {
			"peer_id":peer_id,"player":logical_id,"operation_id":operation_id,
			"error_code":String(result.get("error_code", "")),
		})

func _handle_player_state_rejected(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, operation_id, "PLAYER_STATE", _failure("STALE_TRANSPORT_SESSION"))
		return
	_reject_uncommitted_command(peer_id, operation_id, "PLAYER_STATE", "CLIENT_AUTHORITATIVE_STATE_FORBIDDEN")


func _handle_presentation(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "PRESENTATION", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "PRESENTATION",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	var result: Dictionary = _service.set_player_presentation(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		float(payload.get("orientation_yaw", 0.0)), bool(payload.get("flashlight_enabled", false)), operation_id
	)
	if not _persist_command_result(operation_id, "PRESENTATION", logical_id, result):
		_send_result(peer_id, operation_id, "PRESENTATION", _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	var result_sent := _send_result(peer_id, operation_id, "PRESENTATION", result)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			_presentation_updates += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}))
			_broadcast_snapshot("PLAYER_PRESENTATION_UPDATED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)

func _handle_item_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "ITEM_COMMAND", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	var command_type := String(payload.get("command_type", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "ITEM_COMMAND",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	if command_type.is_empty():
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", "ITEM_COMMAND_TYPE_REQUIRED")
		return
	var command_payload_value = payload.get("payload", {})
	if not command_payload_value is Dictionary:
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", "ITEM_COMMAND_PAYLOAD_REQUIRED")
		return
	var result: Dictionary = _service.handle_canonical_item_command(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		operation_id, command_type, Dictionary(command_payload_value)
	)
	if not _persist_command_result(operation_id, command_type, logical_id, result):
		_send_result(peer_id, operation_id, command_type, _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	var result_sent := _send_result(peer_id, operation_id, command_type, result)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			_broadcast_item_snapshot(command_type)
			# Item commands advance the shared gameplay revision. Republish the
			# player snapshot metadata as well, otherwise clients keep an older
			# revision/checksum even though their player records are unchanged.
			_broadcast_snapshot("ITEM_GRAPH_UPDATED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)

func _broadcast_item_snapshot(reason: String) -> void:
	var snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	for peer_id_value in _peer_to_player.keys():
		if _send(String(peer_id_value), "ITEM_GRAPH_SNAPSHOT", {"reason": reason, "snapshot": snapshot}):
			_broadcasts += 1

func _handle_leave(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(_peer_to_player.get(peer_id, payload.get("logical_player_id", "")))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_leave(
			peer_id, operation_id,
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	var result: Dictionary = _service.leave(logical_id, session_id, operation_id)
	if not _persist_command_result(operation_id, "LEAVE", logical_id, result):
		_send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": "M6_DURABLE_COMMIT_FAILED"})
		return
	var leave_sent := false
	if bool(result.get("success", false)):
		leave_sent = _send(peer_id, "LEAVE_ACK", {"operation_id": operation_id, "logical_player_id": logical_id})
		if not _is_replay_result(result):
			_leaves += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
		_peer_to_player.erase(peer_id)
		_peer_to_session.erase(peer_id)
		if not _is_replay_result(result):
			_broadcast_snapshot("PLAYER_LEFT")
	else:
		_rejections += 1
		leave_sent = _send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "LEAVE_REJECTED"))})
	if leave_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _handle_disconnect(peer_id: String, session_id: String) -> void:
	_peer_last_input_ms.erase(peer_id)
	_debug_event("PEER_DISCONNECTED", {"peer_id":peer_id,"session_id":session_id})
	var mapped_session := String(_peer_to_session.get(peer_id, ""))
	if _service == null or session_id.is_empty() or mapped_session != session_id:
		_peer_to_player.erase(peer_id)
		_peer_to_session.erase(peer_id)
		_write_report("READY", false)
		return
	var operation_id := "operation/m3/disconnect/%s" % session_id.sha256_text().left(16)
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var result: Dictionary = _service.leave_transport_session(session_id, operation_id)
	if not _persist_command_result(operation_id, "DISCONNECT", logical_id, result):
		return
	if bool(result.get("success", false)) and not _is_replay_result(result):
		_leaves += 1
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	else:
		_rejections += 1
	_mark_operation_delivered(operation_id)
	_peer_to_player.erase(peer_id)
	_peer_to_session.erase(peer_id)
	_broadcast_snapshot("PEER_DISCONNECTED")
	_write_report("READY", false)

func _reject_uncommitted_command(peer_id: String, operation_id: String, command_type: String, error_code: String) -> void:
	_rejections += 1
	_send_result(peer_id, operation_id, command_type, _failure(error_code))
	_write_report("READY", false)


func _reject_uncommitted_leave(peer_id: String, operation_id: String, error_code: String) -> void:
	_rejections += 1
	_send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": error_code})
	_write_report("READY", false)


func _send_result(peer_id: String, operation_id: String, command_type: String, result: Dictionary) -> bool:
	var wire: Dictionary = _service.create_targeted_command_result("message/m3/result/%s" % operation_id.sha256_text().left(12), operation_id, result)
	var payload := {
		"operation_id": operation_id,
		"command_type": command_type,
		"status": String(wire.get("status", "REJECTED")),
		"error_code": String(wire.get("error_code", "")),
		"details": wire.get("payload", {}),
		"checksum": String(wire.get("checksum", "")),
	}
	if command_type.begins_with("item.") or command_type.begins_with("inventory.") or command_type.begins_with("container."):
		payload["item_graph_snapshot"] = _service.create_canonical_item_graph_snapshot()
	return _send(peer_id, "COMMAND_RESULT", payload)

func _broadcast_delta(delta: Dictionary, excluded_peer_id: String = "") -> void:
	if delta.is_empty(): return
	for peer_id_value in _peer_to_player.keys():
		var peer_id := String(peer_id_value)
		if peer_id == excluded_peer_id: continue
		if _send(peer_id, "GAMEPLAY_DELTA", {"delta": delta}): _broadcasts += 1

func _broadcast_snapshot(reason: String) -> void:
	var snapshot: Dictionary = _service.create_snapshot()
	for peer_id_value in _peer_to_player.keys():
		if _send(String(peer_id_value), "GAMEPLAY_SNAPSHOT", {"reason": reason, "snapshot": snapshot}): _broadcasts += 1

func _send(peer_id: String, message_type: String, data: Dictionary) -> bool:
	if _boundary == null or peer_id.is_empty(): return false
	if not _ensure_peer_ready(peer_id): return false
	var payload := data.duplicate(true); payload["type"] = message_type
	var frame_result: Dictionary = _boundary.create_frame_for_peer(peer_id, "STATE", Support.MESSAGE_SCHEMA, payload)
	if not bool(frame_result.get("success", false)):
		_last_error_code = String(frame_result.get("error_code", "FRAME_CREATE_FAILED")); return false
	var sent: Dictionary = _boundary.send_to_peer(peer_id, frame_result.get("details", {}).get("frame", {}))
	if not bool(sent.get("success", false)):
		_last_error_code = String(sent.get("error_code", "SEND_FAILED")); return false
	var flushed: Dictionary = _boundary.flush_outbound(32, peer_id)
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "FLUSH_FAILED")); return false
	_messages_sent += 1
	return true

func _ensure_peer_ready(peer_id: String) -> bool:
	if String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY": return true
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, peer_id)
		if not bool(result.get("success", false)) and String(result.get("error_code", "")) != "INVALID_PEER_STATE_TRANSITION": return false
	return String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY"

func _capture_two_connected_checksum() -> void:
	if _peer_to_player.size() == 2 and _service != null:
		_last_two_connected_checksum = String(_service.create_snapshot().get("checksum", ""))

func _setup_recovery() -> Dictionary:
	_recovery_repository = RecoveryRepository.new()
	var repository_result: Dictionary = _recovery_repository.configure(_persistence_root)
	if not bool(repository_result.get("success", false)):
		return _failure("M6_RECOVERY_REPOSITORY_SETUP_FAILED", {"cause": repository_result})
	_recovery_authority = M6AuthorityAdapter.new()
	var authority_result: Dictionary = _recovery_authority.setup(
		_service,
		"session/m6/%s" % _authority_owner_id.sha256_text().left(16)
	)
	if not bool(authority_result.get("success", false)):
		return authority_result
	_replay_outbox = M6ReplayOutbox.new()
	var replay_result: Dictionary = _replay_outbox.setup(_service)
	if not bool(replay_result.get("success", false)):
		return replay_result
	_recovery_coordinator = RecoveryCoordinator.new()
	var coordinator_result: Dictionary = _recovery_coordinator.configure(
		_recovery_repository, _recovery_authority, _replay_outbox
	)
	if not bool(coordinator_result.get("success", false)):
		return coordinator_result
	var loaded: Dictionary = _recovery_repository.load_committed()
	if bool(loaded.get("success", false)):
		var checkpoint: Dictionary = loaded.get("details", {}).get("checkpoint", {})
		var authority_validation: Dictionary = _recovery_authority.validate_recovery_state(
			Dictionary(checkpoint.get("authority_state", {}))
		)
		if not bool(authority_validation.get("success", false)):
			return _failure("M6_DEDICATED_AUTHORITY_PREVALIDATION_FAILED", {"cause": authority_validation})
		var replay_validation: Dictionary = _replay_outbox.validate(
			Dictionary(checkpoint.get("replay_state", {}))
		)
		if not bool(replay_validation.get("success", false)):
			return _failure("M6_DEDICATED_REPLAY_PREVALIDATION_FAILED", {"cause": replay_validation})
		var recovered: Dictionary = _recovery_coordinator.recover_latest()
		if not bool(recovered.get("success", false)):
			return _failure("M6_DEDICATED_RECOVERY_FAILED", {"cause": recovered})
		checkpoint = recovered.get("details", {}).get("checkpoint", {})
		_checkpoint_generation = int(checkpoint.get("generation", 0))
		_last_checkpoint_operation_id = String(checkpoint.get("committed_operation_id", ""))
		_recovered = true
		_recovery_source = String(recovered.get("details", {}).get("source", ""))
		return _success({"recovered": true, "generation": _checkpoint_generation, "source": _recovery_source})
	var load_error := String(loaded.get("error_code", ""))
	if load_error != "AUTHORITATIVE_CHECKPOINT_NOT_FOUND":
		return _failure("M6_DEDICATED_RECOVERY_LOAD_FAILED", {"cause": loaded})
	var seeded := _persist_checkpoint("")
	if not bool(seeded.get("success", false)):
		return seeded
	return _success({"recovered": false, "generation": _checkpoint_generation, "source": "NEW"})


func _persist_command_result(operation_id: String, command_type: String, logical_player_id: String, result: Dictionary) -> bool:
	if not _persistence_enabled:
		return true
	if not _is_canonical_operation_id(operation_id):
		if bool(result.get("success", false)):
			_enter_persistence_failure("M6_COMMITTED_OPERATION_ID_INVALID")
			return false
		return true
	if _is_replay_result(result) or String(result.get("error_code", "")) == "OPERATION_REPLAY_CONFLICT":
		return true
	var replay_recorded := bool(_service.has_durable_replay_operation(operation_id))
	if not replay_recorded:
		if bool(result.get("success", false)):
			_enter_persistence_failure("M6_SUCCESS_RESULT_NOT_REPLAY_DURABLE")
			return false
		return true
	var staged: Dictionary = _replay_outbox.stage_committed(operation_id, command_type, {
		"logical_player_id": logical_player_id,
		"success": bool(result.get("success", false)),
		"error_code": String(result.get("error_code", "")),
		"result": result.duplicate(true),
		"player_snapshot_checksum": String(_service.create_snapshot().get("checksum", "")),
		"item_graph_checksum": String(_service.create_canonical_item_graph_snapshot().get("checksum", "")),
	})
	if not bool(staged.get("success", false)):
		_enter_persistence_failure(String(staged.get("error_code", "M6_OUTBOX_STAGE_FAILED")))
		return false
	var persisted := _persist_checkpoint(operation_id)
	if not bool(persisted.get("success", false)):
		_enter_persistence_failure(String(persisted.get("error_code", "M6_DURABLE_COMMIT_FAILED")))
		return false
	_durable_commits += 1
	# The command checkpoint contains the latest movement state as well. Do not
	# emit a redundant movement-only checkpoint at the same gameplay revision.
	if _movement_checkpoint_dirty:
		_movement_checkpoint_dirty = false
		_movement_commands_since_checkpoint = 0
		_last_movement_checkpoint_ms = Time.get_ticks_msec()
	return true


func _persist_checkpoint(operation_id: String) -> Dictionary:
	if not _persistence_enabled or _recovery_coordinator == null:
		return _success({"skipped": true})
	var next_generation := _checkpoint_generation + 1
	var checkpoint_id := "checkpoint/m6/dedicated/%d" % next_generation
	var persisted: Dictionary = _recovery_coordinator.persist_checkpoint(
		checkpoint_id,
		next_generation,
		_checkpoint_generation,
		operation_id
	)
	if not bool(persisted.get("success", false)):
		_last_persistence_error_details = persisted.duplicate(true)
		_debug_event("CHECKPOINT_PERSIST_REJECTED", {
			"operation_id":operation_id,
			"next_generation":next_generation,
			"cause":persisted,
		})
		return _failure("M6_CHECKPOINT_PERSIST_FAILED", {"cause": persisted})
	_checkpoint_generation = next_generation
	_last_checkpoint_operation_id = operation_id
	return _success({"generation": _checkpoint_generation, "checkpoint_id": checkpoint_id})


func _mark_operation_delivered(operation_id: String) -> void:
	if not _persistence_enabled or _replay_outbox == null or operation_id.is_empty():
		return
	var records: Array = _replay_outbox.get_records()
	for index in range(records.size() - 1, -1, -1):
		var record: Dictionary = records[index]
		if String(record.get("operation_id", "")) == operation_id:
			_replay_outbox.mark_delivered(int(record.get("sequence", 0)))
			return


func _is_replay_result(result: Dictionary) -> bool:
	return bool(result.get("replay", false)) or bool(result.get("details", {}).get("replay", false))


func _is_canonical_operation_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character in ["/", "_", ".", "-"]
		):
			return false
	return true


func _enter_persistence_failure(error_code: String) -> void:
	_persistence_failures += 1
	_last_error_code = error_code if not error_code.is_empty() else "M6_DURABLE_COMMIT_FAILED"
	_fatal_persistence_failure = true
	_debug_event("PERSISTENCE_FATAL", {
		"error_code":_last_error_code,
		"checkpoint_generation":_checkpoint_generation,
		"cause":_last_persistence_error_details,
	})
	set_process(false)
	_write_report("FAILED", false)
	if _boundary != null:
		_boundary.stop()


func _persistence_report() -> Dictionary:
	return {
		"enabled": _persistence_enabled,
		"root_path": _persistence_root,
		"checkpoint_generation": _checkpoint_generation,
		"recovered": _recovered,
		"recovery_source": _recovery_source,
		"last_checkpoint_operation_id": _last_checkpoint_operation_id,
		"durable_commits": _durable_commits,
		"failures": _persistence_failures,
		"fatal_failure": _fatal_persistence_failure,
		"last_error_details": _last_persistence_error_details.duplicate(true),
		"outbox": _replay_outbox.get_report() if _replay_outbox != null else {},
		"service_recovery": _service.get_recovery_report() if _service != null else {},
	}


func _maybe_persist_movement_checkpoint() -> void:
	if (
		not _playable_sandbox
		or not _persistence_enabled
		or not _movement_checkpoint_dirty
		or _fatal_persistence_failure
		or Time.get_ticks_msec() - _last_movement_checkpoint_ms < M7_MOVEMENT_CHECKPOINT_INTERVAL_MS
	):
		return
	var persisted := _persist_checkpoint("")
	if not bool(persisted.get("success", false)):
		_enter_persistence_failure(String(persisted.get("error_code", "M7_MOVEMENT_CHECKPOINT_FAILED")))
		return
	_movement_checkpoint_dirty = false
	_movement_checkpoints += 1
	_movement_commands_since_checkpoint = 0
	_last_movement_checkpoint_ms = Time.get_ticks_msec()
	_debug_event("MOVEMENT_CHECKPOINT_COMMITTED", {"generation":_checkpoint_generation})
	_write_report("READY", false)

func _debug_event(event_name: String, details: Dictionary = {}) -> void:
	if not _debug_logging:
		return
	print("[m7_server] %s" % JSON.stringify({
		"event":event_name,"process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),
		"details":details,
	}, "", true, true))

func detach_playable_world() -> Dictionary:
	# M3/M7 dedicated runtime owns gameplay state directly and has no separate
	# presentation world attachment. Keep SimulatorApp lifecycle polymorphic.
	return _success({"detached": false, "reason": "DEDICATED_RUNTIME_OWNS_NO_PLAYABLE_WORLD"})


func get_world_entity_store_for_kernel():
	return null

func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"checkpoint": (
			M7_CHECKPOINT if _playable_sandbox
			else M6_CHECKPOINT if _persistence_enabled
			else Support.CHECKPOINT
		),
		"build_id": (
			M7_BUILD_ID if _playable_sandbox
			else M6_BUILD_ID if _persistence_enabled
			else Support.BUILD_ID
		),
		"configured": _configured,
		"host": _host,
		"port": _port,
		"connected_peer_count": _peer_to_player.size(),
		"peer_to_player": _peer_to_player.duplicate(true),
		"joins": _joins,
		"leaves": _leaves,
		"moves": _moves,
		"presentation_updates": _presentation_updates,
		"rejections": _rejections,
		"broadcasts": _broadcasts,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"last_error_code": _last_error_code,
		"last_two_connected_checksum": _last_two_connected_checksum,
		"snapshot": _service.create_snapshot() if _service != null else {},
		"item_graph_snapshot": _service.create_canonical_item_graph_snapshot() if _service != null else {},
		"service": _service.get_report() if _service != null else {},
		"boundary": _boundary.get_snapshot() if _boundary != null else {},
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"direct_client_authority_references": 0,
		"persistence": _persistence_report(),
		"playable_sandbox": _playable_sandbox,
		"movement_persistence": {
			"mode":"THROTTLED_WORLD_CHECKPOINT",
			"interval_ms":M7_MOVEMENT_CHECKPOINT_INTERVAL_MS,
			"dirty":_movement_checkpoint_dirty,
			"checkpoint_count":_movement_checkpoints,
			"commands_since_checkpoint":_movement_commands_since_checkpoint,
		},
	}

func stop() -> Dictionary:
	set_process(false)
	if _persistence_enabled and not _fatal_persistence_failure and _service != null and _recovery_coordinator != null:
		var persisted: Dictionary = _persist_checkpoint("")
		if not bool(persisted.get("success", false)):
			_enter_persistence_failure(String(persisted.get("error_code", "M6_FINAL_CHECKPOINT_FAILED")))
	if _fatal_persistence_failure:
		_write_report("FAILED", false)
	else:
		_write_report("STOPPED", true)
	if _boundary != null:
		_boundary.stop()
	if _service != null:
		_service.shutdown()
	_boundary = null
	_service = null
	_configured = false
	if _fatal_persistence_failure:
		return _failure(_last_error_code if not _last_error_code.is_empty() else "M6_DURABLE_COMMIT_FAILED")
	return _success()

func _write_report(state: String, passed: bool) -> void:
	if _result_file.is_empty(): return
	var report := get_report(); report["state"] = state; report["passed"] = passed; report["process_id"] = OS.get_process_id()
	Support.write(_result_file, report)

func _exit_tree() -> void:
	if _configured: stop()

func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
