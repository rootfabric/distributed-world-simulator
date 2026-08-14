extends SceneTree

const Acceptance = preload("res://tests/runtime/v0/v0_full_mvp_acceptance.gd")
const DEFAULT_DRIVER := "res://tests/runtime/v0/v0_current_mvp_driver.gd"

var _result_file := ""
var _driver_path := DEFAULT_DRIVER
var _integration_head := ""
var _soak_seconds := Acceptance.DEFAULT_DEV_SOAK_SECONDS
var _run_id := ""
var _results: Array = []
var _driver


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed := _parse_args(OS.get_cmdline_user_args())
	if not bool(parsed.get("success", false)):
		push_error("V0 full MVP scenario argument error: %s" % parsed.get("errors", []))
		quit(1)
		return
	_result_file = String(parsed["options"].get("result_file", ""))
	_driver_path = String(parsed["options"].get("driver", DEFAULT_DRIVER))
	_integration_head = String(parsed["options"].get("integration_head", ""))
	_soak_seconds = int(parsed["options"].get("soak_seconds", Acceptance.DEFAULT_DEV_SOAK_SECONDS))
	_run_id = String(parsed["options"].get("run_id", ""))

	var driver_script = load(_driver_path)
	if driver_script == null:
		push_error("V0 full MVP driver could not be loaded: %s" % _driver_path)
		quit(1)
		return
	_driver = driver_script.new()
	var context := {
		"integration_head": _integration_head,
		"soak_seconds": _soak_seconds,
		"run_id": _run_id,
		"result_file": _result_file,
	}
	if _driver.has_method("setup"):
		var setup_value = _driver.call("setup", context)
		if not setup_value is Dictionary or not bool(Dictionary(setup_value).get("success", false)):
			push_error("V0 full MVP driver setup failed: %s" % setup_value)
			quit(1)
			return

	for phase in Acceptance.phases():
		var result := _run_phase(Dictionary(phase), context)
		_results.append(result)
		print("V0 %s %-18s %s" % [result.get("code", "??"), result.get("state", "FAIL"), result.get("name", "")])

	if _driver.has_method("shutdown"):
		var shutdown_value = _driver.call("shutdown", context)
		if shutdown_value is Dictionary and not bool(Dictionary(shutdown_value).get("success", false)):
			_results[-2] = Acceptance.phase_result(
				Acceptance.phases()[35],
				Acceptance.STATE_FAIL,
				"DRIVER_SHUTDOWN_FAILED",
				{"driver_result": shutdown_value}
			)

	var summary := Acceptance.build_summary(_results, _integration_head, _soak_seconds, _run_id)
	_write_summary(summary)
	print("V0 full MVP aggregate: %s | PASS=%d FAIL=%d DEPENDENCY_PENDING=%d NOT_IMPLEMENTED=%d" % [
		summary.get("aggregate_state", Acceptance.STATE_FAIL),
		int(summary.get("counts", {}).get(Acceptance.STATE_PASS, 0)),
		int(summary.get("counts", {}).get(Acceptance.STATE_FAIL, 0)),
		int(summary.get("counts", {}).get(Acceptance.STATE_DEPENDENCY_PENDING, 0)),
		int(summary.get("counts", {}).get(Acceptance.STATE_NOT_IMPLEMENTED, 0)),
	])
	match String(summary.get("aggregate_state", Acceptance.STATE_FAIL)):
		Acceptance.STATE_PASS:
			quit(0)
		Acceptance.STATE_FAIL:
			quit(1)
		Acceptance.STATE_DEPENDENCY_PENDING:
			quit(2)
		Acceptance.STATE_NOT_IMPLEMENTED:
			quit(3)
		_:
			quit(1)


func _run_phase(phase: Dictionary, context: Dictionary) -> Dictionary:
	if not _driver.has_method("run_phase"):
		return Acceptance.phase_result(
			phase,
			Acceptance.STATE_NOT_IMPLEMENTED,
			"DRIVER_RUN_PHASE_NOT_IMPLEMENTED",
			{"driver": _driver_path}
		)
	var value = _driver.call("run_phase", phase.duplicate(true), context.duplicate(true))
	if not value is Dictionary:
		return Acceptance.phase_result(
			phase,
			Acceptance.STATE_FAIL,
			"INVALID_DRIVER_PHASE_RESULT",
			{"driver": _driver_path}
		)
	var result := Dictionary(value)
	if int(result.get("id", -1)) != int(phase.get("id", -2)):
		return Acceptance.phase_result(
			phase,
			Acceptance.STATE_FAIL,
			"DRIVER_PHASE_ID_MISMATCH",
			{"driver_result": result}
		)
	var normalized := Acceptance.phase_result(
		phase,
		String(result.get("state", Acceptance.STATE_FAIL)),
		String(result.get("reason", "")),
		Dictionary(result.get("evidence", {}))
	)
	if (
		int(phase.get("id", 0)) == 35
		and String(normalized.get("state", "")) == Acceptance.STATE_PASS
		and _soak_seconds < Acceptance.FINAL_SOAK_SECONDS
	):
		return Acceptance.phase_result(
			phase,
			Acceptance.STATE_DEPENDENCY_PENDING,
			"SOAK_DURATION_BELOW_FINAL_REQUIREMENT",
			{
				"requested_seconds": _soak_seconds,
				"required_seconds": Acceptance.FINAL_SOAK_SECONDS,
			}
		)
	return normalized


func _write_summary(summary: Dictionary) -> void:
	if _result_file.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(_result_file) if _result_file.begins_with("res://") or _result_file.begins_with("user://") else _result_file
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		push_error("Could not write V0 full MVP summary: %s" % absolute)
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()


func _parse_args(arguments: PackedStringArray) -> Dictionary:
	var options := {
		"result_file": "",
		"driver": DEFAULT_DRIVER,
		"integration_head": "",
		"soak_seconds": Acceptance.DEFAULT_DEV_SOAK_SECONDS,
		"run_id": "",
	}
	var errors: Array[String] = []
	for argument_value in arguments:
		var argument := String(argument_value).strip_edges()
		if argument.is_empty():
			continue
		if not argument.begins_with("--") or not argument.contains("="):
			errors.append("Unknown argument: %s" % argument)
			continue
		var separator := argument.find("=")
		var key := argument.substr(2, separator - 2)
		var value := argument.substr(separator + 1)
		match key:
			"result-file":
				options["result_file"] = value
			"driver":
				options["driver"] = value
			"integration-head":
				options["integration_head"] = value
			"run-id":
				options["run_id"] = value
			"soak-seconds":
				if not value.is_valid_int() or value.to_int() < 1:
					errors.append("--soak-seconds must be a positive integer")
				else:
					options["soak_seconds"] = value.to_int()
			_:
				errors.append("Unknown argument: --%s" % key)
	return {"success": errors.is_empty(), "options": options, "errors": errors}
