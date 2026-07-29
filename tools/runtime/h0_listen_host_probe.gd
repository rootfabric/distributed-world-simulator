extends SceneTree

const RuntimeScript = preload("res://scripts/runtime/listen_host/listen_host_runtime.gd")
const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")


func _init() -> void:
	var result_file: String = ""
	for raw_argument in OS.get_cmdline_user_args():
		var argument: String = String(raw_argument)
		if argument.begins_with("--result-file="):
			result_file = argument.trim_prefix("--result-file=")
	if result_file.strip_edges().is_empty():
		push_error("--result-file is required")
		quit(2)
		return
	var runtime = RuntimeScript.new()
	var setup_result: Dictionary = runtime.setup({
		"authority_owner_id": "sim-n1",
		"authority_epoch": 5,
		"server_tick": 500,
		"session_id": "session/h0/listen-host/process",
	})
	var scenario_result: Dictionary = {}
	if bool(setup_result.get("success", false)):
		scenario_result = runtime.run_vertical_scenario()
	var report: Dictionary = runtime.get_report()
	report["checkpoint"] = "v16.9.1-runtime-h1-playable-listen-host"
	report["build_id"] = "h1-playable-listen-host"
	report["setup_success"] = bool(setup_result.get("success", false))
	report["scenario_success"] = bool(scenario_result.get("success", false))
	var write_result: Dictionary = AtomicJsonScript.write_dictionary(result_file, report)
	if not bool(write_result.get("success", false)):
		push_error("Failed to write H0 report: %s" % write_result)
		quit(3)
		return
	print("H0 listen-host probe: %s" % ("PASS" if bool(report.get("passed", false)) else "FAIL"))
	quit(0 if bool(report.get("passed", false)) else 1)
