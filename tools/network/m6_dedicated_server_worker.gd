extends SceneTree

const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m6/m6_process_support.gd")

var runtime
var control_file := ""
var result_file := ""
var stopping := false


func _init() -> void:
	var options := Support.parse_arguments(OS.get_cmdline_user_args())
	result_file = String(options.get("result-file", "")).strip_edges()
	control_file = String(options.get("control-file", "")).strip_edges()
	var port := int(String(options.get("port", "0")))
	var persistence_root := String(options.get("persistence-root", "")).strip_edges()
	if port < 1 or persistence_root.is_empty() or result_file.is_empty():
		Support.write(result_file, {
			"state": "FAILED",
			"passed": false,
			"error_code": "INVALID_M6_SERVER_WORKER_ARGUMENTS",
		})
		quit(2)
		return
	runtime = Runtime.new()
	runtime.name = "M6DedicatedServerRuntime"
	root.add_child(runtime)
	var setup: Dictionary = runtime.setup({
		"host": "127.0.0.1",
		"port": port,
		"result_file": result_file,
		"authority_owner_id": "simulation/m6/process",
		"authority_epoch": 1,
		"persistence_root": persistence_root,
	})
	if not bool(setup.get("success", false)):
		Support.write(result_file, {
			"state": "FAILED",
			"passed": false,
			"error_code": String(setup.get("error_code", "M6_SERVER_SETUP_FAILED")),
			"details": setup.get("details", {}),
		})
		quit(3)


func _process(_delta: float) -> bool:
	if stopping or runtime == null or control_file.is_empty():
		return false
	var control := Support.read(control_file)
	if not bool(control.get("stop", false)):
		return false
	stopping = true
	var report: Dictionary = runtime.get_report() if runtime != null else {}
	var stopped: Dictionary = runtime.stop()
	report["state"] = "STOPPED" if bool(stopped.get("success", false)) else "FAILED"
	report["passed"] = bool(stopped.get("success", false))
	report["stop_result"] = stopped
	Support.write(result_file, report)
	quit(0 if bool(stopped.get("success", false)) else 4)
	return true
