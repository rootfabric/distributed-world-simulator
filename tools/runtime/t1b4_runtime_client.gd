extends SceneTree

const ClientScript = preload("res://scripts/labs/t1/t1a6_m3_runtime_client_adapter.gd")

var _client
var _result_file: String = ""
var _action_file: String = ""
var _client_id: String = "client/t1b4/a"
var _started_ms: int = 0
var _last_write_ms: int = 0
var _last_action_serial: int = 0
var _last_action_result: Dictionary = {}
var _shutdown_after_ms: int = 180000


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_result_file = String(args.get("result-file", ""))
	_action_file = String(args.get("action-file", ""))
	_client_id = String(args.get("client-id", "client/t1b4/a"))
	_shutdown_after_ms = int(args.get("shutdown-after-ms", "180000"))
	_client = ClientScript.new()
	root.add_child(_client)
	var setup: Dictionary = _client.setup({
		"host": String(args.get("host", "127.0.0.1")),
		"port": int(args.get("port", "0")),
		"logical_player_id": _client_id,
		"connect_timeout_ms": 30000,
		"command_timeout_ms": 10000,
		"automated_acceptance": true,
		"t1a6_presentation": true,
	})
	if not bool(setup.get("success", false)):
		_write({"state": "FAILED", "passed": false, "setup": setup})
		quit(1)
		return
	_started_ms = Time.get_ticks_msec()
	process_frame.connect(_tick)


func _tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _started_ms >= _shutdown_after_ms:
		_write_current("TIMEOUT")
		quit(1)
		return
	_poll_action()
	if now - _last_write_ms >= 100:
		_write_current("READY" if _client.is_ready() else "CONNECTING")
		_last_write_ms = now


func _poll_action() -> void:
	if _action_file.is_empty() or not FileAccess.file_exists(_action_file) or not _client.is_ready():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_action_file))
	if not parsed is Dictionary:
		return
	var command: Dictionary = parsed
	var serial := int(command.get("serial", 0))
	if serial <= _last_action_serial:
		return
	_last_action_serial = serial
	var action := String(command.get("action_kind", "")).to_upper()
	if action == "LEAVE":
		_last_action_result = _client.request_graceful_leave(3000)
		_write_current("LEFT")
		_client.stop()
		quit(0 if bool(_last_action_result.get("success", false)) else 1)
		return
	_last_action_result = _client.execute_construction_runtime_blocking(
		String(command.get("kind", "DOOR")),
		action,
		String(command.get("operation_id", "operation/t1b4/%s/action/%d" % [_client_id.sha256_text().left(8), serial])),
		int(command.get("expected_revision", -1)),
		Dictionary(command.get("payload", {})) if command.get("payload", {}) is Dictionary else {}
	)
	_client.force_t1a6_presentation_sync()
	_write_current("READY")


func _write_current(state: String) -> void:
	if _client != null:
		_client.force_t1a6_presentation_sync()
	_write({
		"schema": "planet_simulator.t1b4_runtime_client_report.v1",
		"state": state,
		"passed": state == "READY" or state == "LEFT",
		"client_id": _client_id,
		"action_serial": _last_action_serial,
		"action_result": _last_action_result.duplicate(true),
		"runtime_snapshot": _client.get_construction_runtime_snapshot() if _client != null else {},
		"presentation": _client.get_t1a6_presentation_report() if _client != null else {},
		"client": _client.get_report() if _client != null else {},
	})


func _write(value: Dictionary) -> void:
	if _result_file.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_result_file.get_base_dir())
	var file := FileAccess.open(_result_file, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  "))
		file.close()


func _parse_args(values: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for value in values:
		var text := String(value)
		if text.begins_with("--") and text.contains("="):
			var parts := text.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
