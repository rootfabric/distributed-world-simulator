extends Node

const REQUEST_SCHEMA := "dws.live2.automation.request.v1"
const RESPONSE_SCHEMA := "dws.live2.automation.response.v1"
const BRIDGE_SCHEMA := "dws.live2.automation.bridge.v1"

const BIND_ADDRESS := "127.0.0.1"
const MAX_CLIENTS := 4
const MAX_REQUEST_BYTES := 64 * 1024
const MAX_RESPONSE_BYTES := 2 * 1024 * 1024

var _app
var _server: TCPServer
var _peers: Array[Dictionary] = []
var _token := ""
var _port := 0
var _output_dir := ""
var _requests := 0
var _rejections := 0
var _connections := 0
var _responses := 0
var _last_error_code := ""
var _configured := false


func setup(app, options: Dictionary) -> Dictionary:
	if _configured:
		return _failure("AUTOMATION_BRIDGE_ALREADY_CONFIGURED")
	if app == null or not is_instance_valid(app):
		return _failure("AUTOMATION_APP_REQUIRED")
	if not app.has_method("execute_runtime_command") or not app.has_method("get_current_runtime"):
		return _failure("AUTOMATION_APP_SURFACE_INVALID")
	var port := int(options.get("port", 0))
	var token := String(options.get("token", ""))
	var output_dir := String(options.get("output_dir", "user://live2-automation")).strip_edges()
	if port < 1 or port > 65535:
		return _failure("AUTOMATION_PORT_INVALID")
	if token.length() < 8:
		return _failure("AUTOMATION_TOKEN_TOO_SHORT")
	if output_dir.is_empty():
		return _failure("AUTOMATION_OUTPUT_DIR_REQUIRED")

	_app = app
	_token = token
	_port = port
	_output_dir = output_dir
	_server = TCPServer.new()
	var listen_error := _server.listen(_port, BIND_ADDRESS)
	if listen_error != OK:
		_server = null
		return _failure("AUTOMATION_LISTEN_FAILED", {"error": listen_error, "port": port})
	_configured = true
	set_process(true)
	var report := get_report()
	print("[live2_automation] %s" % JSON.stringify({
		"event": "AUTOMATION_BRIDGE_READY",
		"bind": BIND_ADDRESS,
		"port": _port,
		"schema": BRIDGE_SCHEMA,
	}))
	return _success(report)


func stop() -> void:
	set_process(false)
	for peer_record in _peers:
		var peer = peer_record.get("peer")
		if peer != null:
			peer.disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()
	_server = null
	_configured = false


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if not _configured or _server == null:
		return
	_accept_connections()
	for index in range(_peers.size() - 1, -1, -1):
		_poll_peer(index)


func _accept_connections() -> void:
	while _server.is_connection_available():
		var peer = _server.take_connection()
		if peer == null:
			return
		if _peers.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			_rejections += 1
			_last_error_code = "AUTOMATION_TOO_MANY_CLIENTS"
			continue
		peer.set_no_delay(true)
		_peers.append({
			"peer": peer,
			"buffer": "",
		})
		_connections += 1


func _poll_peer(index: int) -> void:
	if index < 0 or index >= _peers.size():
		return
	var record: Dictionary = _peers[index]
	var peer = record.get("peer")
	if peer == null:
		_peers.remove_at(index)
		return
	peer.poll()
	if peer.get_status() in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
		_peers.remove_at(index)
		return
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available := peer.get_available_bytes()
	if available <= 0:
		return
	var read = peer.get_partial_data(available)
	if not read is Array or read.size() < 2 or int(read[0]) != OK:
		_send_response(peer, _response("", false, {}, "AUTOMATION_READ_FAILED"))
		peer.disconnect_from_host()
		_peers.remove_at(index)
		return
	var bytes: PackedByteArray = read[1]
	var buffer := String(record.get("buffer", "")) + bytes.get_string_from_utf8()
	if buffer.to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		_send_response(peer, _response("", false, {}, "AUTOMATION_REQUEST_TOO_LARGE"))
		peer.disconnect_from_host()
		_peers.remove_at(index)
		return
	while buffer.contains("\n"):
		var newline := buffer.find("\n")
		var line := buffer.left(newline).strip_edges()
		buffer = buffer.substr(newline + 1)
		if line.is_empty():
			continue
		_handle_line(peer, line)
	record["buffer"] = buffer
	_peers[index] = record


func _handle_line(peer, line: String) -> void:
	_requests += 1
	var parsed = JSON.parse_string(line)
	if not parsed is Dictionary:
		_rejections += 1
		_send_response(peer, _response("", false, {}, "AUTOMATION_INVALID_JSON"))
		return
	var response := handle_request_for_testing(Dictionary(parsed))
	if not bool(response.get("ok", false)):
		_rejections += 1
		_last_error_code = String(response.get("error_code", "AUTOMATION_REQUEST_REJECTED"))
	_send_response(peer, response)


func _send_response(peer, response: Dictionary) -> void:
	var text := JSON.stringify(response, "", false, true) + "\n"
	var bytes := text.to_utf8_buffer()
	if bytes.size() > MAX_RESPONSE_BYTES:
		bytes = (JSON.stringify(
			_response(String(response.get("id", "")), false, {}, "AUTOMATION_RESPONSE_TOO_LARGE")
		) + "\n").to_utf8_buffer()
	var error := peer.put_data(bytes)
	if error == OK:
		_responses += 1
	else:
		_last_error_code = "AUTOMATION_WRITE_FAILED"


func handle_request_for_testing(request: Dictionary) -> Dictionary:
	var request_id := String(request.get("id", ""))
	if String(request.get("schema", "")) != REQUEST_SCHEMA:
		return _response(request_id, false, {}, "AUTOMATION_REQUEST_SCHEMA_INVALID")
	if String(request.get("token", "")) != _token:
		return _response(request_id, false, {}, "AUTOMATION_UNAUTHORIZED")
	var method := String(request.get("method", "")).strip_edges()
	var params_value = request.get("params", {})
	if not params_value is Dictionary:
		return _response(request_id, false, {}, "AUTOMATION_PARAMS_INVALID")
	var params: Dictionary = params_value
	match method:
		"ping":
			return _response(request_id, true, {
				"bridge": get_report(),
				"world_id": String(_app.get_current_world_id()) if _app.has_method("get_current_world_id") else "",
			})
		"commands.list":
			return _response(request_id, true, {
				"commands": (
					_app.command_registry.list_commands()
					if _app.get("command_registry") != null
					else []
				),
			})
		"command.execute":
			return _command_execute(request_id, params)
		"movement.set":
			return _movement_set(request_id, params)
		"movement.stop":
			return _movement_stop(request_id)
		"view.set":
			return _view_set(request_id, params)
		"state.get":
			return _state_get(request_id, params)
		"screenshot.capture":
			return _screenshot_capture(request_id, params)
		_:
			return _response(request_id, false, {}, "AUTOMATION_METHOD_UNKNOWN")


func _command_execute(request_id: String, params: Dictionary) -> Dictionary:
	var line := String(params.get("line", "")).strip_edges()
	if line.is_empty():
		return _response(request_id, false, {}, "AUTOMATION_COMMAND_REQUIRED")
	var result: Dictionary = _app.execute_runtime_command(line)
	return _response(
		request_id,
		bool(result.get("success", false)),
		{"command": line, "result": result},
		String(result.get("error_code", "")) if not bool(result.get("success", false)) else ""
	)


func _movement_set(request_id: String, params: Dictionary) -> Dictionary:
	var runtime = _app.get_current_runtime()
	if runtime == null or not runtime.has_method("automation_set_movement_intent"):
		return _response(request_id, false, {}, "AUTOMATION_MOVEMENT_NOT_SUPPORTED")
	var result: Dictionary = runtime.call("automation_set_movement_intent", params)
	return _response(
		request_id,
		bool(result.get("success", false)),
		{"movement": result},
		String(result.get("error_code", "")) if not bool(result.get("success", false)) else ""
	)


func _movement_stop(request_id: String) -> Dictionary:
	var runtime = _app.get_current_runtime()
	if runtime == null or not runtime.has_method("automation_stop_movement"):
		return _response(request_id, false, {}, "AUTOMATION_MOVEMENT_NOT_SUPPORTED")
	var result: Dictionary = runtime.call("automation_stop_movement")
	return _response(
		request_id,
		bool(result.get("success", false)),
		{"movement": result},
		String(result.get("error_code", "")) if not bool(result.get("success", false)) else ""
	)


func _view_set(request_id: String, params: Dictionary) -> Dictionary:
	var runtime = _app.get_current_runtime()
	if runtime == null or not runtime.has_method("automation_set_view"):
		return _response(request_id, false, {}, "AUTOMATION_VIEW_NOT_SUPPORTED")
	var result: Dictionary = runtime.call("automation_set_view", params)
	return _response(
		request_id,
		bool(result.get("success", false)),
		{"view": result},
		String(result.get("error_code", "")) if not bool(result.get("success", false)) else ""
	)


func _state_get(request_id: String, params: Dictionary) -> Dictionary:
	var kind := String(params.get("kind", "runtime")).strip_edges().to_lower()
	match kind:
		"runtime":
			var result: Dictionary = _app.execute_runtime_command("runtime.snapshot")
			if not bool(result.get("success", false)):
				return _response(request_id, false, {}, String(result.get("error_code", "AUTOMATION_RUNTIME_SNAPSHOT_FAILED")))
			return _response(request_id, true, {"snapshot": result.get("snapshot", {})})
		"jitter":
			var result: Dictionary = _app.execute_runtime_command("network.jitter.snapshot")
			if not bool(result.get("success", false)):
				return _response(request_id, false, {}, String(result.get("error_code", "AUTOMATION_JITTER_SNAPSHOT_FAILED")))
			return _response(request_id, true, {"jitter": result.get("jitter", {})})
		"automation":
			var runtime = _app.get_current_runtime()
			if runtime == null or not runtime.has_method("automation_get_state"):
				return _response(request_id, false, {}, "AUTOMATION_STATE_NOT_SUPPORTED")
			return _response(request_id, true, {"automation": runtime.call("automation_get_state")})
		_:
			return _response(request_id, false, {}, "AUTOMATION_STATE_KIND_UNKNOWN")


func _screenshot_capture(request_id: String, params: Dictionary) -> Dictionary:
	if get_viewport() == null:
		return _response(request_id, false, {}, "AUTOMATION_VIEWPORT_UNAVAILABLE")
	var filename := String(params.get("filename", "")).strip_edges()
	if filename.is_empty():
		filename = "capture-%d.png" % Time.get_ticks_msec()
	if filename.contains("/") or filename.contains("\\") or filename in [".", ".."]:
		return _response(request_id, false, {}, "AUTOMATION_SCREENSHOT_FILENAME_INVALID")
	if not filename.to_lower().ends_with(".png"):
		filename += ".png"
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return _response(request_id, false, {}, "AUTOMATION_SCREENSHOT_DIR_FAILED")
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return _response(request_id, false, {}, "AUTOMATION_SCREENSHOT_UNAVAILABLE")
	var path := absolute_dir.path_join(filename)
	var save_error := image.save_png(path)
	if save_error != OK:
		return _response(request_id, false, {}, "AUTOMATION_SCREENSHOT_SAVE_FAILED")
	return _response(request_id, true, {
		"path": path,
		"width": image.get_width(),
		"height": image.get_height(),
	})


func get_report() -> Dictionary:
	return {
		"schema": BRIDGE_SCHEMA,
		"configured": _configured,
		"bind_address": BIND_ADDRESS,
		"port": _port,
		"output_dir": _output_dir,
		"connections": _connections,
		"requests": _requests,
		"responses": _responses,
		"rejections": _rejections,
		"connected_clients": _peers.size(),
		"last_error_code": _last_error_code,
	}


func _response(
	request_id: String,
	ok: bool,
	result: Dictionary = {},
	error_code: String = ""
) -> Dictionary:
	return {
		"schema": RESPONSE_SCHEMA,
		"id": request_id,
		"ok": ok,
		"error_code": error_code,
		"result": result.duplicate(true),
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
