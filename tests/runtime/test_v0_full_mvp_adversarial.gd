extends SceneTree

const Acceptance = preload("res://tests/runtime/v0/v0_full_mvp_acceptance.gd")
const SCENARIO := "res://tools/runtime/v0_full_mvp_scenario.gd"
const FALSE_GREEN_DRIVER := "res://tests/runtime/v0/reviewer_false_green_driver.gd"
const FAKE_SOAK_DRIVER := "res://tests/runtime/v0/reviewer_fake_soak_driver.gd"
const INTEGRATION_BASE := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_empty_evidence_false_green()
	_test_final_custom_driver_rejected()
	_test_fabricated_soak_elapsed_ignored()
	_test_default_driver_fail_closed()
	_finish()


func _test_empty_evidence_false_green() -> void:
	var path := _result_path("empty-evidence")
	var run := _run_scenario([
		"--driver=%s" % FALSE_GREEN_DRIVER,
		"--result-file=%s" % path,
		"--soak-seconds=1800",
		"--integration-base=%s" % INTEGRATION_BASE,
		"--run-id=adversarial-empty-evidence",
	])
	_assert(int(run.get("exit_code", 0)) != 0, "A: PASS + evidence={} cannot exit 0")
	var summary := _read_summary(path)
	_assert(String(summary.get("aggregate_state", "")) == Acceptance.STATE_FAIL, "A: empty-evidence false-GREEN aggregates FAIL")
	_assert(int(summary.get("counts", {}).get(Acceptance.STATE_PASS, -1)) == 0, "A: no empty-evidence phase is credited PASS")


func _test_final_custom_driver_rejected() -> void:
	var run := _run_scenario([
		"--final=true",
		"--driver=%s" % FALSE_GREEN_DRIVER,
		"--soak-seconds=1800",
		"--integration-base=%s" % INTEGRATION_BASE,
		"--run-id=adversarial-final-driver",
	])
	_assert(int(run.get("exit_code", 0)) != 0, "B: custom driver is rejected in final mode")
	_assert(String(run.get("output", "")).contains("final mode rejects driver override"), "B: rejection names final driver trust boundary")


func _test_fabricated_soak_elapsed_ignored() -> void:
	var path := _result_path("fake-soak")
	var run := _run_scenario([
		"--driver=%s" % FAKE_SOAK_DRIVER,
		"--result-file=%s" % path,
		"--soak-seconds=1800",
		"--integration-base=%s" % INTEGRATION_BASE,
		"--run-id=adversarial-fake-soak",
	])
	_assert(int(run.get("exit_code", 0)) != 0, "C: requested 1800 with instant driver cannot exit 0")
	var summary := _read_summary(path)
	var phase35 := Dictionary(Array(summary.get("phases", []))[34])
	var evidence := Dictionary(phase35.get("evidence", {}))
	_assert(String(phase35.get("state", "")) != Acceptance.STATE_PASS, "C: instant phase 35 is not PASS")
	_assert(float(evidence.get("trusted_elapsed_seconds", 1800.0)) < float(Acceptance.FINAL_SOAK_SECONDS), "C: trusted monotonic elapsed records the short observation")
	_assert(int(evidence.get("driver_reported_elapsed_seconds", -1)) == 1800, "D: fabricated driver elapsed is retained only as untrusted diagnostic evidence")
	_assert(not bool(summary.get("final_soak_duration_satisfied", true)), "D: fabricated elapsed cannot satisfy final soak")


func _test_default_driver_fail_closed() -> void:
	var path := _result_path("default-pending")
	var run := _run_scenario([
		"--result-file=%s" % path,
		"--soak-seconds=30",
		"--integration-base=%s" % INTEGRATION_BASE,
		"--run-id=default-dependency-pending",
	])
	_assert(int(run.get("exit_code", 0)) != 0, "H: default dependency-pending driver remains nonzero")
	var summary := _read_summary(path)
	_assert(String(summary.get("aggregate_state", "")) == Acceptance.STATE_DEPENDENCY_PENDING, "H: default driver remains DEPENDENCY_PENDING")
	_assert(not bool(summary.get("final_checkpoint_eligible", true)), "H: default pending run is not final-checkpoint eligible")


func _run_scenario(user_arguments: Array[String]) -> Dictionary:
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		SCENARIO,
		"--",
	])
	for argument in user_arguments:
		args.append(argument)
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true)
	return {"exit_code": exit_code, "output": "\n".join(PackedStringArray(output))}


func _result_path(label: String) -> String:
	return "user://v0-r1-a1-%s-%d.json" % [label, OS.get_process_id()]


func _read_summary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if value:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("V0 full MVP adversarial contracts: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
