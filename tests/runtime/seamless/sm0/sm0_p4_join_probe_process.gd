extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

var _socket: PacketPeerUDP
var _server_host := "127.0.0.1"
var _server_port := 24580
var _client_port := 24782
var _timeout_ms := 5000
var _result_file := ""
var _started_ms := 0
var _request_id := ""
var _done := false


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	_server_host = String(options.get("server-host", _server_host))
	_server_port = int(options.get("server-port", _server_port))
	_client_port = int(options.get("client-port", _client_port))
	_timeout_ms = int(options.get("timeout-ms", _timeout_ms))
	_result_file = String(options.get("result-file", ""))
	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(_client_port, "127.0.0.1")
	if bind_result != OK:
		_finish(false, "SM0_P4_JOIN_PROBE_BIND_FAILED", {"error": bind_result})
		return
	if _socket.set_dest_address(_server_host, _server_port) != OK:
		_finish(false, "SM0_P4_JOIN_PROBE_ROUTE_FAILED", {})
		return
	_request_id = "p4-reconnect-probe/%d/%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	_started_ms = Time.get_ticks_msec()
	_send_join()


func _process(_delta: float) -> bool:
	if _done:
		return false
	while _socket != null and _socket.get_available_packet_count() > 0:
		var message := Contracts.decode_message(_socket.get_packet())
		var validation := Contracts.validate_message(message)
		if not bool(validation.get("success", false)):
			_finish(false, "SM0_P4_JOIN_PROBE_INVALID_RESPONSE", {"cause": validation})
			return false
		if String(message.get("request_id", "")) != _request_id:
			continue
		var message_type := String(message.get("type", ""))
		var payload: Dictionary = Dictionary(message.get("payload", {}))
		if message_type == "JOIN_ACK":
			_finish(false, "SM0_P4_RESTART_RECONNECT_JOIN_UNEXPECTEDLY_ACCEPTED", payload)
			return false
		if message_type == "SM0_ERROR":
			var error_code := String(payload.get("error_code", ""))
			if error_code in ["SM0_P4_JOIN_REQUIRES_PEER_SYNC", "SM0_AUTHORITY_NOT_ACTIVE"]:
				_finish(true, error_code, payload)
				return false
			_finish(false, "SM0_P4_JOIN_PROBE_UNEXPECTED_REJECTION", {"remote_error_code": error_code, "payload": payload})
			return false
	if Time.get_ticks_msec() - _started_ms >= _timeout_ms:
		_finish(false, "SM0_P4_JOIN_PROBE_TIMEOUT", {})
		return false
	if (Time.get_ticks_msec() - _started_ms) % 250 < 20:
		_send_join()
	return false


func _send_join() -> void:
	if _socket == null:
		return
	var message := Contracts.create_message("CLIENT_JOIN", {
		"logical_player_id": "a",
		"session_id": "transport-session/sm0/reconnect-probe/%d" % OS.get_process_id(),
	}, _request_id)
	_socket.put_packet(Contracts.encode_message(message))


func _finish(success: bool, result_code: String, details: Dictionary) -> void:
	if _done:
		return
	_done = true
	var result := {
		"schema": "distributed_world_simulator.sm0_p4_join_probe.v1",
		"result": "PASS" if success else "FAIL",
		"result_code": result_code,
		"server_port": _server_port,
		"client_port": _client_port,
		"details": details.duplicate(true),
	}
	print("[SM0_P4_JOIN_PROBE] %s" % JSON.stringify(result, "", false, true))
	if not _result_file.is_empty():
		var file := FileAccess.open(_result_file, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "  ", false, true))
			file.close()
	if _socket != null:
		_socket.close()
	quit(0 if success else 1)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg_value in args:
		var arg := String(arg_value)
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var separator := arg.find("=")
		result[arg.substr(2, separator - 2)] = arg.substr(separator + 1)
	return result
