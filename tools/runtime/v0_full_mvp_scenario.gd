extends SceneTree

const Acceptance = preload("res://tests/runtime/v0/v0_full_mvp_acceptance.gd")
const DEFAULT_DRIVER := "res://tests/runtime/v0/v0_current_mvp_driver.gd"

var _result_file := ""
var _driver_path := DEFAULT_DRIVER
var _integration_base := ""
var _soak_seconds := Acceptance.DEFAULT_DEV_SOAK_SECONDS
var _run_id := ""
var _final_mode := false
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
	_integration_base = String(parsed["options"].get("integration_base", ""))
	_soak_seconds = int(parsed["options"].get("soak_seconds", Acceptance.DEFAULT_DEV_SOAK_SECONDS))
	_run_id = String(parsed["options"].get("run_id", ""))
	_final_mode = bool(parsed["options"].get("final_mode", false))
	if not _is_lower_hex_40(_integration_base):
		push_error("V0 full MVP scenario requires --integration-base=<40-char lowercase commit SHA>")
		quit(1)
		return
	if _final_mode and _driver_path != DEFAULT_DRIVER:
		push_error("V0 final mode rejects driver override; canonical driver is fixed to %s" % DEFAULT_DRIVER)
		quit(1)
		return
	if _final_mode and _soak_seconds < Acceptance.FINAL_SOAK_SECONDS:
		push_error("V0 final mode requires --soak-seconds >= %d" % Acceptance.FINAL_SOAK_SECONDS)
		quit(1)
		return

	var driver_script = load(_driver_path)
	if driver_script == null:
		push_error("V0 full MVP driver could not be loaded: %s" % _driver_path)
		quit(1)
		return
	_driver = driver_script.new()
	var context := {
		"integration_base": _integration_base,
		"soak_seconds": _soak_seconds,
		"run_id": _run_id,
		"result_file": _result_file,
		"final_mode": _final_mode,
		"driver_is_canonical": _driver_path == DEFAULT_DRIVER,
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

	var summary := Acceptance.build_summary(_results, _integration_base, _soak_seconds, _run_id)
	summary["final_mode"] = _final_mode
	summary["driver"] = _driver_path
	summary["driver_is_canonical"] = _driver_path == DEFAULT_DRIVER
	summary["final_checkpoint_eligible"] = (
		_final_mode
		and _driver_path == DEFAULT_DRIVER
		and String(summary.get("aggregate_state", "")) == Acceptance.STATE_PASS
		and bool(summary.get("final_soak_duration_satisfied", false))
	)
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
	var start_ticks_msec := Time.get_ticks_msec()
	var value = _driver.call("run_phase", phase.duplicate(true), context.duplicate(true))
	var end_ticks_msec := Time.get_ticks_msec()
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
	var state := String(result.get("state", Acceptance.STATE_FAIL))
	var reason := String(result.get("reason", ""))
	var evidence := Dictionary(result.get("evidence", {})).duplicate(true)
	if int(phase.get("id", 0)) == 35:
		return _normalize_soak_phase(phase, state, reason, evidence, start_ticks_msec, end_ticks_msec)
	return Acceptance.phase_result(phase, state, reason, evidence)


func _normalize_soak_phase(
	phase: Dictionary,
	state: String,
	reason: String,
	evidence: Dictionary,
	start_ticks_msec: int,
	end_ticks_msec: int
) -> Dictionary:
	if evidence.has("elapsed_seconds"):
		evidence["driver_reported_elapsed_seconds"] = evidence.get("elapsed_seconds")
		evidence.erase("elapsed_seconds")
	for key in ["trusted_start_ticks_msec", "trusted_end_ticks_msec", "trusted_elapsed_seconds", "trusted_sample_count", "trusted_soak_result"]:
		evidence.erase(key)
	var elapsed_seconds := float(end_ticks_msec - start_ticks_msec) / 1000.0
	var samples: Array = []
	var samples_value = evidence.get("observation_samples", [])
	if samples_value is Array:
		samples = Array(samples_value)
	evidence["trusted_start_ticks_msec"] = start_ticks_msec
	evidence["trusted_end_ticks_msec"] = end_ticks_msec
	evidence["trusted_elapsed_seconds"] = elapsed_seconds
	evidence["trusted_sample_count"] = samples.size()
	var tracker := Acceptance.SoakTracker.new()
	for sample_value in samples:
		if sample_value is Dictionary:
			tracker.observe(Dictionary(sample_value))
	var tracker_result: Dictionary = tracker.finish(elapsed_seconds, Acceptance.FINAL_SOAK_SECONDS)
	evidence["trusted_soak_result"] = tracker_result
	if state.strip_edges().to_upper() == Acceptance.STATE_PASS:
		if _soak_seconds < Acceptance.FINAL_SOAK_SECONDS:
			return Acceptance.phase_result(
				phase,
				Acceptance.STATE_DEPENDENCY_PENDING,
				"SOAK_REQUEST_BELOW_FINAL_REQUIREMENT",
				evidence
			)
		if String(tracker_result.get("state", "")) != Acceptance.STATE_PASS:
			return Acceptance.phase_result(
				phase,
				String(tracker_result.get("state", Acceptance.STATE_FAIL)),
				String(tracker_result.get("error_code", "V0_SOAK_FAILED")),
				evidence
			)
	return Acceptance.phase_result(phase, state, reason, evidence)


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
		"integration_base": "",
		"soak_seconds": Acceptance.DEFAULT_DEV_SOAK_SECONDS,
		"run_id": "",
		"final_mode": false,
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
			"integration-base":
				options["integration_base"] = value
			"run-id":
				options["run_id"] = value
			"final":
				if value not in ["true", "false"]:
					errors.append("--final must be true or false")
				else:
					options["final_mode"] = value == "true"
			"soak-seconds":
				if not value.is_valid_int() or value.to_int() < 1:
					errors.append("--soak-seconds must be a positive integer")
				else:
					options["soak_seconds"] = value.to_int()
			_:
				errors.append("Unknown argument: --%s" % key)
	return {"success": errors.is_empty(), "options": options, "errors": errors}


func _is_lower_hex_40(value: String) -> bool:
	if value.length() != 40 or value != value.to_lower():
		return false
	for character in value:
		if String(character) not in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true
