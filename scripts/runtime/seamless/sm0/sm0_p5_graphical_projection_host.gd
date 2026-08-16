extends Node

signal finished(exit_code: int)

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const ViewContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_view_contract.gd")
const P5Server = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_server_node.gd")

const VIEW_MESSAGE := "P5_PROJECTION_VIEW"
const VIEW_PUBLISH_INTERVAL_MS := 100
const STOP_POLL_INTERVAL_MS := 250

var _authority_id := ""
var _zone_id := ""
var _local_player_id := ""
var _view_host := "127.0.0.1"
var _view_port := 0
var _stop_file := ""
var _server
var _view_socket: PacketPeerUDP
var _view_sequence := 0
var _last_publish_ms := 0
var _last_stop_poll_ms := 0
var _last_remote_checksum := ""
var _last_remote_present := false


func setup(config: Dictionary) -> Dictionary:
	_authority_id = String(config.get("authority_id", "")).strip_edges()
	_zone_id = String(config.get("zone_id", "")).strip_edges()
	_local_player_id = String(config.get("local_player_id", "")).strip_edges()
	_view_host = String(config.get("view_host", "127.0.0.1")).strip_edges()
	_view_port = int(config.get("view_port", 0))
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	if (
		_authority_id not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B]
		or Contracts.authority_for_zone(_zone_id) != _authority_id
		or _local_player_id != ("a" if _authority_id == Contracts.AUTHORITY_A else "b")
		or _view_port < 1
	):
		return _failure("SM0_P5_GRAPHICAL_HOST_INVALID_CONFIGURATION")

	_server = P5Server.new()
	_server.name = "Sm0P5CanonicalProjectionServer"
	add_child(_server)
	var server_setup: Dictionary = _server.setup({
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"local_player_id": _local_player_id,
		"control_host": String(config.get("control_host", "127.0.0.1")),
		"control_port": int(config.get("control_port", 0)),
		"peer_control_host": String(config.get("peer_control_host", "127.0.0.1")),
		"peer_control_port": int(config.get("peer_control_port", 0)),
		"stop_file": "",
	})
	if not bool(server_setup.get("success", false)):
		return _failure("SM0_P5_GRAPHICAL_HOST_SERVER_SETUP_FAILED", {"cause": server_setup})

	_view_socket = PacketPeerUDP.new()
	set_process(true)
	_event("SM0_P5_GRAPHICAL_HOST_READY", {"view_port": _view_port, "command_channel": false})
	_publish_view(true)
	return _success()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_publish_ms >= VIEW_PUBLISH_INTERVAL_MS:
		_publish_view(false)
	if not _stop_file.is_empty() and now - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now
		if FileAccess.file_exists(_stop_file):
			shutdown(0, "stop-file")


func _publish_view(force_event: bool) -> Dictionary:
	_last_publish_ms = Time.get_ticks_msec()
	if _server == null or _view_socket == null:
		return _failure("SM0_P5_GRAPHICAL_HOST_NOT_READY")
	var status: Dictionary = _server.status_for_tests()
	var local_player: Dictionary = Dictionary(status.get("canonical_player", {}))
	var remote_projection: Dictionary = Dictionary(status.get("peer_projection", {}))
	if local_player.is_empty():
		return _failure("SM0_P5_GRAPHICAL_HOST_LOCAL_PLAYER_MISSING")
	_view_sequence += 1
	var view := ViewContract.create(
		_authority_id,
		_zone_id,
		_view_sequence,
		local_player,
		remote_projection,
		1
	)
	var validation := ViewContract.validate(view)
	if not bool(validation.get("success", false)):
		return validation
	if _view_socket.set_dest_address(_view_host, _view_port) != OK:
		return _failure("SM0_P5_GRAPHICAL_HOST_VIEW_DESTINATION_FAILED")
	var message := Contracts.create_message(VIEW_MESSAGE, view)
	var put_error := _view_socket.put_packet(Contracts.encode_message(message))
	if put_error != OK:
		return _failure("SM0_P5_GRAPHICAL_HOST_VIEW_SEND_FAILED", {"error": put_error})

	var remote_present := not remote_projection.is_empty()
	var remote_checksum := String(remote_projection.get("checksum", ""))
	if force_event or remote_present != _last_remote_present or remote_checksum != _last_remote_checksum:
		_last_remote_present = remote_present
		_last_remote_checksum = remote_checksum
		_event("SM0_P5_GRAPHICAL_VIEW_PUBLISHED", {
			"view_sequence": _view_sequence,
			"remote_present": remote_present,
			"remote_player_id": String(remote_projection.get("logical_player_id", "")),
			"command_channel": false,
		})
	return _success({"view": view})


func apply_move_for_tests(payload: Dictionary) -> Dictionary:
	return _server.apply_move_for_tests(payload) if _server != null else _failure("SM0_P5_GRAPHICAL_HOST_NOT_READY")


func status_for_tests() -> Dictionary:
	var status: Dictionary = _server.status_for_tests() if _server != null else {}
	status["view_sequence"] = _view_sequence
	status["command_channel"] = false
	return status


func publish_view_now_for_tests() -> Dictionary:
	return _publish_view(true)


func shutdown(exit_code: int = 0, reason: String = "test") -> void:
	if _view_socket != null:
		_view_socket.close()
	if _server != null:
		_server.shutdown(exit_code, reason)
	set_process(false)
	_event("SM0_P5_GRAPHICAL_HOST_EXIT", {"exit_code": exit_code, "reason": reason})
	finished.emit(exit_code)


func _writer_count() -> int:
	return int(status_for_tests().get("writer_count", 0)) if _server != null else 0


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
