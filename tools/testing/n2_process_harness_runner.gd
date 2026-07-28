extends SceneTree

const ManifestScript = preload("res://scripts/testing/process_harness/process_harness_manifest.gd")
const HarnessScript = preload("res://scripts/testing/process_harness/network_process_harness.gd")
const JUnitScript = preload("res://scripts/testing/process_harness/junit_report_writer.gd")
const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

func _initialize() -> void:
	var parsed := _parse_options(OS.get_cmdline_user_args())
	if not bool(parsed.get("success", false)):
		push_error(String(parsed.get("message", "Invalid N2 harness options")))
		quit(2); return
	var options: Dictionary = parsed["options"]
	var manifest_result := ManifestScript.load_file(String(options["manifest_file"]))
	if not bool(manifest_result.get("success", false)):
		_write_json(String(options["result_file"]), manifest_result)
		quit(2); return
	var harness = HarnessScript.new()
	var configured := harness.configure(manifest_result["manifest"], OS.get_executable_path(), ProjectSettings.globalize_path("res://"), String(options["output_root"]))
	if not bool(configured.get("success", false)):
		_write_json(String(options["result_file"]), configured)
		quit(2); return
	var requested: Array[String] = []
	if not String(options["scenario"]).is_empty(): requested.append(String(options["scenario"]))
	var summary: Dictionary = harness.run_all(requested)
	_write_json(String(options["result_file"]), summary)
	var junit := JUnitScript.write(String(options["junit_file"]), summary)
	if not bool(junit.get("success", false)):
		push_error("JUnit report failed: %s" % junit)
		quit(2); return
	print("N2_PROCESS_HARNESS_RESULT %s" % JSON.stringify({"passed": summary.get("passed", false), "scenario_count": summary.get("scenario_count", 0), "passed_count": summary.get("passed_count", 0), "failed_count": summary.get("failed_count", 0)}))
	quit(0 if bool(summary.get("passed", false)) else 1)

func _parse_options(args) -> Dictionary:
	var project := ProjectSettings.globalize_path("res://")
	var options := {
		"manifest_file": project.path_join("config/testing/network-process-scenarios.v1.json"),
		"result_file": project.path_join("artifacts/test-results/n2-process-harness-summary.json"),
		"junit_file": project.path_join("artifacts/test-results/n2-process-harness-junit.xml"),
		"output_root": project.path_join("artifacts/test-results/n2-process-runs"),
		"scenario": "",
	}
	for raw in args:
		var arg := String(raw)
		if not arg.begins_with("--") or not arg.contains("="): return {"success": false, "message": "Invalid option: %s" % arg}
		var pos := arg.find("="); var key := arg.substr(2,pos-2); var value := arg.substr(pos+1)
		match key:
			"manifest": options["manifest_file"] = _absolute_path(value)
			"result-file": options["result_file"] = _absolute_path(value)
			"junit-file": options["junit_file"] = _absolute_path(value)
			"output-root": options["output_root"] = _absolute_path(value)
			"scenario": options["scenario"] = value
			_: return {"success": false, "message": "Unknown option: --%s" % key}
	for key in ["manifest_file", "result_file", "junit_file", "output_root"]:
		if String(options[key]).strip_edges().is_empty(): return {"success": false, "message": "%s cannot be empty" % key}
	return {"success": true, "options": options}

func _absolute_path(value: String) -> String:
	if value.begins_with("res://") or value.begins_with("user://"): return ProjectSettings.globalize_path(value).simplify_path()
	if value.is_absolute_path(): return value.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(value).simplify_path()

func _write_json(path: String, value: Dictionary) -> void:
	var result := AtomicJsonScript.write_dictionary(path, value)
	if not bool(result.get("success", false)):
		push_error("Atomic JSON report write failed: %s" % result)
