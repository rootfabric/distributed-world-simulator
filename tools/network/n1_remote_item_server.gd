extends SceneTree

const SupportScript = preload("res://tools/network/n1_remote_item_process_support.gd")
const SessionScript = preload("res://scripts/network/session/n1_remote_item_server_session.gd")

var _session
var _options: Dictionary = {}
var _started_at_ms: int = 0
var _finished: bool = false


func _initialize() -> void:
	var parsed: Dictionary = SupportScript.parse_options(OS.get_cmdline_user_args(), "server")
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_session = SessionScript.new()
	var configured: Dictionary = _session.configure(
		SupportScript.create_endpoint(_options),
		SupportScript.create_service_config(String(_options["node_id"]))
	)
	if not bool(configured.get("success", false)):
		_finish_failure(String(configured.get("error_code", "CONFIGURE_FAILED")))
		return
	var started: Dictionary = _session.start()
	if not bool(started.get("success", false)):
		_finish_failure(String(started.get("error_code", "START_FAILED")))
		return
	_started_at_ms = Time.get_ticks_msec()
	SupportScript.write_json(String(_options["result_file"]), {
		"schema": "planet_simulator.n1_remote_item_process_state.v1",
		"mode": "server",
		"state": "LISTENING",
		"passed": false,
		"port": int(_options["port"]),
	})
	print("N1_REMOTE_ITEM_SERVER_LISTENING port=%d" % int(_options["port"]))


func _process(_delta: float) -> bool:
	if _finished or _session == null:
		return false
	var polled: Dictionary = _session.poll()
	if (not bool(polled.get("success", false)) and _session.is_terminal()) or _session.is_terminal():
		_finish_from_session()
		return false
	if Time.get_ticks_msec() - _started_at_ms > int(_options["timeout_ms"]):
		_finish_failure("SERVER_TIMEOUT", _session.get_report())
	return false


func _finalize() -> void:
	if _session != null:
		_session.stop()


func _finish_from_session() -> void:
	var report: Dictionary = _session.get_report()
	report["process_id"] = OS.get_process_id()
	report["resolved_user_data_dir"] = OS.get_user_data_dir()
	SupportScript.write_json(String(_options["result_file"]), report)
	_finished = true
	print("N1_REMOTE_ITEM_SERVER_RESULT %s" % JSON.stringify(report))
	quit(0 if bool(report.get("passed", false)) else 1)


func _finish_failure(error_code: String, details: Dictionary = {}) -> void:
	var report: Dictionary = {
		"process_id": OS.get_process_id(),
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"schema": "planet_simulator.n1_remote_item_server_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details.duplicate(true),
	}
	var path: String = String(_options.get("result_file", ""))
	if not path.is_empty():
		SupportScript.write_json(path, report)
	_finished = true
	push_error("N1 remote item server failed: %s" % error_code)
	quit(1)
