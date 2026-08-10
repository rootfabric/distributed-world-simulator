extends SceneTree

const ServerScript = preload("res://scripts/labs/t1/t1a6_m3_runtime_server_adapter.gd")

var _server
var _result_file: String = ""
var _started_ms: int = 0
var _last_write_ms: int = 0
var _shutdown_after_ms: int = 180000


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_result_file = String(args.get("result-file", ""))
	_shutdown_after_ms = int(args.get("shutdown-after-ms", "180000"))
	_server = ServerScript.new()
	root.add_child(_server)
	var setup: Dictionary = _server.setup({
		"host": String(args.get("host", "127.0.0.1")),
		"port": int(args.get("port", "0")),
		"authority_owner_id": "simulation/t1a6/dedicated",
		"authority_epoch": 1,
		"result_file": String(args.get("m3-result-file", "")),
		"t1a6_m0_root": String(args.get("m0-root", "user://t1a6-server-m0")),
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
	if now - _last_write_ms >= 100:
		_write_current("READY")
		_last_write_ms = now


func _write_current(state: String) -> void:
	_write({
		"schema": "planet_simulator.t1a6_runtime_server_report.v1",
		"state": state,
		"passed": state == "READY",
		"m3": _server.get_report() if _server != null else {},
		"t1a6": _server.get_t1a6_runtime_report() if _server != null else {},
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
