extends SceneTree

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

var _options: Dictionary = {}
var _started: int = 0
var _ready_written := false
var _finished := false

func _initialize() -> void:
	_options = _parse(OS.get_cmdline_user_args())
	if not bool(_options.get("success", false)):
		quit(2)
		return
	_started = Time.get_ticks_msec()
	match String(_options["mode"]):
		"hang-no-ready":
			pass
		"ready-hang", "complete", "complete-nonzero":
			_write("LISTENING", false, "")
			_ready_written = true
		"fail":
			_write("FAILED", false, String(_options["failure_code"]))
			_finished = true
			quit(7)
		_:
			_write("FAILED", false, "INVALID_PROBE_MODE")
			_finished = true
			quit(2)

func _process(_delta: float) -> bool:
	if _finished: return false
	var elapsed := Time.get_ticks_msec() - _started
	match String(_options["mode"]):
		"complete", "complete-nonzero":
			if elapsed >= int(_options["complete_delay_ms"]):
				_write("COMPLETE", true, "")
				_finished = true
				quit(9 if String(_options["mode"]) == "complete-nonzero" else 0)
		"ready-hang", "hang-no-ready":
			pass
	return false

func _parse(args) -> Dictionary:
	var result := {"success": true, "mode": "", "result_file": "", "node_id": "probe", "complete_delay_ms": 150, "failure_code": "PROBE_FAILED"}
	for raw in args:
		var arg := String(raw)
		if not arg.begins_with("--") or not arg.contains("="): result["success"] = false; continue
		var pos := arg.find("="); var key := arg.substr(2, pos-2); var value := arg.substr(pos+1)
		match key:
			"mode": result["mode"] = value
			"result-file": result["result_file"] = value
			"node-id": result["node_id"] = value
			"complete-delay-ms": result["complete_delay_ms"] = value.to_int() if value.is_valid_int() else 150
			"failure-code": result["failure_code"] = value
			"host", "port", "timeout-ms": pass
			_: result["success"] = false
	if String(result["mode"]).is_empty() or String(result["result_file"]).is_empty(): result["success"] = false
	return result

func _write(state: String, passed: bool, failure_code: String) -> void:
	AtomicJsonScript.write_dictionary(String(_options["result_file"]), {
		"schema": "planet_simulator.n2_harness_probe.v1", "state": state, "passed": passed,
		"failure_code": failure_code, "node_id": String(_options["node_id"]),
		"process_id": OS.get_process_id(), "resolved_user_data_dir": OS.get_user_data_dir(),
	})
