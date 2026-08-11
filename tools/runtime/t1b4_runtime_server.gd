extends SceneTree

const ServerScript = preload("res://scripts/labs/t1/t1b/t1b4_m3_failure_server_adapter.gd")

var _server
var _result_file: String = ""
var _control_file: String = ""
var _started_ms: int = 0
var _last_write_ms: int = 0
var _last_control_serial: int = 0
var _last_control_result: Dictionary = {}
var _shutdown_after_ms: int = 180000


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_result_file = String(args.get("result-file", ""))
	_control_file = String(args.get("control-file", ""))
	_shutdown_after_ms = int(args.get("shutdown-after-ms", "180000"))
	_server = ServerScript.new()
	root.add_child(_server)
	var setup: Dictionary = _server.setup({
		"host": String(args.get("host", "127.0.0.1")),
		"port": int(args.get("port", "0")),
		"authority_owner_id": "simulation/t1b4/dedicated",
		"authority_epoch": 1,
		"result_file": String(args.get("m3-result-file", "")),
		"t1a6_m0_root": String(args.get("m0-root", "user://t1b4-server-m0")),
		"automated_acceptance": true,
	})
	if not bool(setup.get("success", false)):
		_write({"state": "FAILED", "passed": false, "setup": setup})
		quit(1)
		return
	_started_ms = Time.get_ticks_msec()
	_write_current("READY")
	process_frame.connect(_tick)


func _tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _started_ms >= _shutdown_after_ms:
		_write_current("TIMEOUT")
		quit(1)
		return
	_poll_control()
	if now - _last_write_ms >= 100:
		_write_current("READY")
		_last_write_ms = now


func _poll_control() -> void:
	if _control_file.is_empty() or not FileAccess.file_exists(_control_file):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_control_file))
	if not parsed is Dictionary:
		return
	var command: Dictionary = parsed
	var serial := int(command.get("serial", 0))
	if serial <= _last_control_serial:
		return
	_last_control_serial = serial
	var operation := String(command.get("operation", "")).to_upper()
	match operation:
		"INTEREST":
			var ids_value = command.get("selected_construct_ids", [])
			var ids: Array = Array(ids_value).duplicate() if ids_value is Array else []
			_last_control_result = _server.apply_runtime_interest(
				String(command.get("client_id", "")),
				int(command.get("interest_revision", 0)),
				ids
			)
		"FAILURE_PLAN":
			var requirements_value = command.get("requirements_by_runtime_id", {})
			var availability_value = command.get("base_availability_by_runtime_id", {})
			var edges_value = command.get("edges", [])
			_last_control_result = _server.apply_failure_plan(
				Dictionary(requirements_value).duplicate(true) if requirements_value is Dictionary else {},
				Dictionary(availability_value).duplicate(true) if availability_value is Dictionary else {},
				Array(edges_value).duplicate(true) if edges_value is Array else []
			)
		"CHECKPOINT":
			_last_control_result = _server.checkpoint_runtime(String(command.get("operation_id", "operation/t1b4/checkpoint/%d" % serial)))
		_:
			_last_control_result = {"success": false, "error_code": "T1B4_CONTROL_OPERATION_UNSUPPORTED", "details": {"operation": operation}}
	_write_current("READY")


func _write_current(state: String) -> void:
	_write({
		"schema": "planet_simulator.t1b4_runtime_server_report.v1",
		"state": state,
		"passed": state == "READY",
		"control_serial": _last_control_serial,
		"control_result": _last_control_result.duplicate(true),
		"m3": _server.get_report() if _server != null else {},
		"t1b4": _server.get_t1b4_runtime_report() if _server != null else {},
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
