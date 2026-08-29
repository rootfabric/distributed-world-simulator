extends Node

signal finished(exit_code: int)

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")
const ProjectionContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_contract.gd")
const ProjectionStore = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_store.gd")

const PROJECTION_MESSAGE := "P5_PLAYER_PROJECTION"
const PROJECTION_PUBLISH_INTERVAL_MS := 250
const STOP_POLL_INTERVAL_MS := 250

var _authority_id := ""
var _zone_id := ""
var _peer_authority_id := ""
var _local_player_id := ""
var _peer_player_id := ""
var _authority_epoch := 1
var _control_host := "127.0.0.1"
var _control_port := 0
var _peer_control_host := "127.0.0.1"
var _peer_control_port := 0
var _stop_file := ""

var _authority: Authority
var _projection_store: ProjectionStore
var _control_socket: PacketPeerUDP
var _last_projection_publish_ms := 0
var _last_stop_poll_ms := 0
var _last_published_checksum := ""
var _local_session_id := ""


func setup(config: Dictionary) -> Dictionary:
	_authority_id = String(config.get("authority_id", "")).strip_edges()
	_zone_id = String(config.get("zone_id", "")).strip_edges()
	_control_host = String(config.get("control_host", "127.0.0.1")).strip_edges()
	_control_port = int(config.get("control_port", 0))
	_peer_control_host = String(config.get("peer_control_host", "127.0.0.1")).strip_edges()
	_peer_control_port = int(config.get("peer_control_port", 0))
	_local_player_id = String(config.get("local_player_id", "")).strip_edges()
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	_peer_authority_id = Contracts.peer_authority(_authority_id)
	_peer_player_id = "b" if _local_player_id == "a" else "a"

	if (
		_authority_id not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B]
		or Contracts.authority_for_zone(_zone_id) != _authority_id
		or _control_port < 1
		or _peer_control_port < 1
		or _local_player_id not in ["a", "b"]
		or (_authority_id == Contracts.AUTHORITY_A and _local_player_id != "a")
		or (_authority_id == Contracts.AUTHORITY_B and _local_player_id != "b")
	):
		return _failure("SM0_P5_INVALID_SERVER_CONFIGURATION")

	_projection_store = ProjectionStore.new()
	var projection_setup := _projection_store.setup(_authority_id)
	if not bool(projection_setup.get("success", false)):
		return projection_setup

	_authority = Authority.new()
	var authority_setup: Dictionary = _authority.setup(_authority_id, _authority_epoch, 0)
	if not bool(authority_setup.get("success", false)):
		return _failure("SM0_P5_AUTHORITY_SETUP_FAILED", {"cause": authority_setup})

	_local_session_id = "transport-session/sm0/p5/%s" % _local_player_id
	var join: Dictionary = _authority.join(
		_local_player_id,
		_local_session_id,
		"operation/sm0/p5/%s/join" % _local_player_id
	)
	if not bool(join.get("success", false)):
		return _failure("SM0_P5_LOCAL_PLAYER_JOIN_FAILED", {"cause": join})

	var player: Dictionary = _authority.get_player(_local_player_id)
	if player.is_empty():
		return _failure("SM0_P5_LOCAL_PLAYER_MISSING_AFTER_JOIN")
	var initial_delta_x := -0.25 if _authority_id == Contracts.AUTHORITY_A else 0.25
	var initial_move: Dictionary = _authority.move_player(
		_local_player_id,
		_local_session_id,
		int(player.get("ownership_epoch", 0)),
		int(player.get("last_input_sequence", 0)) + 1,
		initial_delta_x,
		0.0,
		"operation/sm0/p5/%s/initial-position" % _local_player_id
	)
	if not bool(initial_move.get("success", false)):
		return _failure("SM0_P5_LOCAL_PLAYER_INITIAL_MOVE_FAILED", {"cause": initial_move})

	_control_socket = PacketPeerUDP.new()
	var bind_error := _control_socket.bind(_control_port, _control_host)
	if bind_error != OK:
		return _failure("SM0_P5_CONTROL_BIND_FAILED", {"error": bind_error, "port": _control_port})

	set_process(true)
	_event("SM0_P5_READY", {
		"canonical_player": _authority.get_player(_local_player_id),
		"peer_player_id": _peer_player_id,
		"projection_read_only": true,
	})
	_publish_projection(true)
	return _success()


func _process(_delta: float) -> void:
	_poll_control()
	var now := Time.get_ticks_msec()
	if now - _last_projection_publish_ms >= PROJECTION_PUBLISH_INTERVAL_MS:
		_publish_projection(false)
	if not _stop_file.is_empty() and now - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now
		if FileAccess.file_exists(_stop_file):
			shutdown(0, "stop-file")


func _poll_control() -> void:
	if _control_socket == null:
		return
	while _control_socket.get_available_packet_count() > 0:
		var packet := _control_socket.get_packet()
		var message := Contracts.decode_message(packet)
		var message_check := Contracts.validate_message(message)
		if not bool(message_check.get("success", false)):
			_event("SM0_P5_PROJECTION_REJECTED", {
				"error_code": String(message_check.get("error_code", "SM0_P5_MESSAGE_INVALID")),
			})
			continue
		if String(message.get("type", "")) != PROJECTION_MESSAGE:
			continue
		_accept_projection(Dictionary(message.get("payload", {})))


func _accept_projection(snapshot: Dictionary) -> Dictionary:
	if String(snapshot.get("owner_authority_id", "")) != _peer_authority_id:
		return _projection_rejected("SM0_P5_PROJECTION_UNEXPECTED_OWNER", snapshot)
	if String(snapshot.get("logical_player_id", "")) != _peer_player_id:
		return _projection_rejected("SM0_P5_PROJECTION_UNEXPECTED_PLAYER", snapshot)
	var accepted := _projection_store.accept(snapshot)
	if not bool(accepted.get("success", false)):
		return _projection_rejected(String(accepted.get("error_code", "SM0_P5_PROJECTION_REJECTED")), snapshot)
	if not bool(Dictionary(accepted.get("details", {})).get("replay", false)):
		_event("SM0_P5_PROJECTION_ACCEPTED", {
			"logical_player_id": String(snapshot.get("logical_player_id", "")),
			"owner_authority_id": String(snapshot.get("owner_authority_id", "")),
			"state_revision": int(snapshot.get("state_revision", 0)),
			"checksum": String(snapshot.get("checksum", "")),
		})
	return accepted


func _projection_rejected(error_code: String, snapshot: Dictionary) -> Dictionary:
	_event("SM0_P5_PROJECTION_REJECTED", {
		"error_code": error_code,
		"logical_player_id": String(snapshot.get("logical_player_id", "")),
		"owner_authority_id": String(snapshot.get("owner_authority_id", "")),
	})
	return _failure(error_code)


func _publish_projection(force_event: bool) -> Dictionary:
	_last_projection_publish_ms = Time.get_ticks_msec()
	if _authority == null or _control_socket == null:
		return _failure("SM0_P5_PROJECTION_PUBLISHER_NOT_READY")
	var player: Dictionary = _authority.get_player(_local_player_id)
	if player.is_empty():
		return _failure("SM0_P5_LOCAL_PLAYER_NOT_FOUND")
	var snapshot := ProjectionContract.create_from_player(
		player,
		_authority_id,
		_zone_id,
		_authority_epoch
	)
	var validation := ProjectionContract.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	if _control_socket.set_dest_address(_peer_control_host, _peer_control_port) != OK:
		return _failure("SM0_P5_PROJECTION_DESTINATION_FAILED")
	var message := Contracts.create_message(PROJECTION_MESSAGE, snapshot)
	var put_error := _control_socket.put_packet(Contracts.encode_message(message))
	if put_error != OK:
		return _failure("SM0_P5_PROJECTION_SEND_FAILED", {"error": put_error})
	var checksum := String(snapshot.get("checksum", ""))
	if force_event or checksum != _last_published_checksum:
		_last_published_checksum = checksum
		_event("SM0_P5_PROJECTION_PUBLISHED", {
			"logical_player_id": _local_player_id,
			"state_revision": int(snapshot.get("state_revision", 0)),
			"checksum": checksum,
		})
	return _success({"snapshot": snapshot})


func apply_move_for_tests(payload: Dictionary) -> Dictionary:
	var logical_player_id := String(payload.get("logical_player_id", "")).strip_edges()
	if logical_player_id != _local_player_id:
		var blocked := _projection_store.reject_mutation(logical_player_id, "move")
		if String(blocked.get("error_code", "")) == "SM0_P5_PROJECTION_READ_ONLY":
			_event("SM0_P5_PROJECTION_MUTATION_BLOCKED", {
				"logical_player_id": logical_player_id,
				"operation": "move",
				"owner_authority_id": String(Dictionary(blocked.get("details", {})).get("owner_authority_id", "")),
			})
		return blocked
	var current: Dictionary = _authority.get_player(_local_player_id)
	if current.is_empty():
		return _failure("SM0_P5_LOCAL_PLAYER_NOT_FOUND")
	var input_sequence := int(payload.get("input_sequence", int(current.get("last_input_sequence", 0)) + 1))
	var result: Dictionary = _authority.move_player(
		_local_player_id,
		_local_session_id,
		int(current.get("ownership_epoch", 0)),
		input_sequence,
		float(payload.get("delta_x", 0.0)),
		float(payload.get("delta_z", 0.0)),
		"operation/sm0/p5/%s/move/%d" % [_local_player_id, input_sequence]
	)
	if bool(result.get("success", false)):
		_publish_projection(true)
	return result


func status_for_tests() -> Dictionary:
	return {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"local_player_id": _local_player_id,
		"canonical_player": _authority.get_player(_local_player_id) if _authority != null else {},
		"peer_projection": _projection_store.get_projection(_peer_player_id) if _projection_store != null else {},
		"projection_count": _projection_store.size() if _projection_store != null else 0,
		"writer_count": _writer_count(),
	}


func publish_now_for_tests() -> Dictionary:
	return _publish_projection(true)


func shutdown(exit_code: int = 0, reason: String = "test") -> void:
	if _control_socket != null:
		_control_socket.close()
	set_process(false)
	_event("SM0_P5_PROCESS_EXIT", {"exit_code": exit_code, "reason": reason})
	finished.emit(exit_code)


func _writer_count() -> int:
	if _authority == null:
		return 0
	var player: Dictionary = _authority.get_player(_local_player_id)
	return 1 if not player.is_empty() and bool(player.get("connected", false)) else 0


func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {
		"schema": "distributed_world_simulator.sm0_event.v1",
		"event": event_name,
		"severity": "INFO",
		"process_role": "server-a" if _authority_id == Contracts.AUTHORITY_A else "server-b",
		"process_id": OS.get_process_id(),
		"time_msec": Time.get_ticks_msec(),
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"writer_count": _writer_count(),
	}
	for key in details.keys():
		event[key] = details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event, "", false, true))


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}