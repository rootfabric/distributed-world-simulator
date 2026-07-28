extends SceneTree

const ManifestScript = preload("res://scripts/testing/process_harness/process_harness_manifest.gd")
const JUnitScript = preload("res://scripts/testing/process_harness/junit_report_writer.gd")
const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	var loaded := ManifestScript.load_file("res://config/testing/network-process-scenarios.v1.json")
	_assert(bool(loaded.get("success", false)), "Valid N2 manifest did not load")
	if not bool(loaded.get("success", false)): _finish(); return
	var manifest: Dictionary = loaded["manifest"]
	_assert(bool(ManifestScript.validate(manifest).get("success", false)), "Valid manifest failed validation")
	_assert(Array(manifest["scenarios"]).size() == 6, "Scenario count changed")
	var selected := ManifestScript.select_scenarios(manifest, ["n1_snapshot_success", "client_failure_cleanup"])
	_assert(bool(selected.get("success", false)), "Scenario selection failed")
	_assert(Array(selected.get("scenarios", [])).size() == 2, "Scenario selection count incorrect")
	_expect_failure(ManifestScript.select_scenarios(manifest, ["missing"]), "SCENARIO_NOT_FOUND")
	_expect_failure(ManifestScript.select_scenarios(manifest, ["n1_snapshot_success", "n1_snapshot_success"]), "DUPLICATE_SCENARIO_REQUEST")

	var mutation := manifest.duplicate(true); mutation.erase("build_id"); _expect_failure(ManifestScript.validate(mutation), "MANIFEST_FIELDS_INVALID")
	mutation = manifest.duplicate(true); mutation["extra"] = true; _expect_failure(ManifestScript.validate(mutation), "MANIFEST_FIELDS_INVALID")
	mutation = manifest.duplicate(true); mutation["schema"] = "bad"; _expect_failure(ManifestScript.validate(mutation), "MANIFEST_SCHEMA_INVALID")
	mutation = manifest.duplicate(true); mutation["checkpoint"] = "../escape"; _expect_failure(ManifestScript.validate(mutation), "CHECKPOINT_INVALID")
	mutation = manifest.duplicate(true); mutation["defaults"].erase("host"); _expect_failure(ManifestScript.validate(mutation), "DEFAULTS_FIELDS_INVALID")
	mutation = manifest.duplicate(true); mutation["defaults"]["port_range_start"] = 12.5; _expect_failure(ManifestScript.validate(mutation), "DEFAULT_INTEGER_INVALID")
	mutation = manifest.duplicate(true); mutation["defaults"]["port_range_start"] = 100; _expect_failure(ManifestScript.validate(mutation), "PORT_RANGE_INVALID")
	mutation = manifest.duplicate(true); mutation["defaults"]["port_range_end"] = 70000; _expect_failure(ManifestScript.validate(mutation), "PORT_RANGE_INVALID")
	mutation = manifest.duplicate(true); mutation["defaults"]["poll_delay_ms"] = 0; _expect_failure(ManifestScript.validate(mutation), "TIMEOUT_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"] = []; _expect_failure(ManifestScript.validate(mutation), "SCENARIO_COUNT_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][1]["id"] = mutation["scenarios"][0]["id"]; _expect_failure(ManifestScript.validate(mutation), "DUPLICATE_SCENARIO_ID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["id"] = "../escape"; _expect_failure(ManifestScript.validate(mutation), "SCENARIO_IDENTIFIER_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["server_script"] = "res://missing/n2_server.gd"; _expect_failure(ManifestScript.validate(mutation), "SCRIPT_PATH_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["server_ready_state"] = "listening"; _expect_failure(ManifestScript.validate(mutation), "STATE_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["server_terminal_states"] = ["COMPLETE", "COMPLETE"]; _expect_failure(ManifestScript.validate(mutation), "DUPLICATE_STATE")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["expected_outcome"] = "MAYBE"; _expect_failure(ManifestScript.validate(mutation), "EXPECTED_OUTCOME_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["expected_failure_code"] = "BAD"; _expect_failure(ManifestScript.validate(mutation), "SUCCESS_WITH_FAILURE_CODE")
	mutation = manifest.duplicate(true); mutation["scenarios"][3]["expected_failure_code"] = ""; _expect_failure(ManifestScript.validate(mutation), "FAILURE_CODE_REQUIRED")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["server_args"]["port"] = 1; _expect_failure(ManifestScript.validate(mutation), "RESERVED_ARGUMENT_OVERRIDE")
	for reserved in ["host", "node-id", "result-file", "timeout-ms"]:
		mutation = manifest.duplicate(true); mutation["scenarios"][0]["client_args"][reserved] = "x"; _expect_failure(ManifestScript.validate(mutation), "RESERVED_ARGUMENT_OVERRIDE")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["server_args"]["Bad_Name"] = 1; _expect_failure(ManifestScript.validate(mutation), "INVALID_ARGUMENT_NAME")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["shared_fields"] = ["a..b"]; _expect_failure(ManifestScript.validate(mutation), "FIELD_PATH_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["server_expect"] = {".bad": true}; _expect_failure(ManifestScript.validate(mutation), "FIELD_PATH_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["assertions"][0]["actual"] = "bad."; _expect_failure(ManifestScript.validate(mutation), "FIELD_PATH_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["assertions"][0]["source"] = "peer"; _expect_failure(ManifestScript.validate(mutation), "ASSERTION_SOURCE_INVALID")
	mutation = manifest.duplicate(true); mutation["scenarios"][0]["timeout_ms"] = 1.5; _expect_failure(ManifestScript.validate(mutation), "SCENARIO_TIMEOUT_INVALID")
	mutation = manifest.duplicate(true)
	var runtime_node := Node.new()
	mutation["scenarios"][0]["server_args"]["runtime"] = runtime_node
	_expect_failure(ManifestScript.validate(mutation), "RUNTIME_OBJECT_REJECTED")
	runtime_node.free()
	mutation = manifest.duplicate(true); mutation["defaults"]["scenario_timeout_ms"] = 9007199254740992.0; _expect_failure(ManifestScript.validate(mutation), "DEFAULT_INTEGER_INVALID")

	var junit_path := ProjectSettings.globalize_path("res://artifacts/test-results/n2-junit-contract.xml")
	var junit := JUnitScript.write(junit_path, {"duration_seconds": 0.5, "failed_count": 1, "scenarios": [{"id": "bad<&", "passed": false, "failure_code": "BROKEN", "message": "a < b & c", "duration_seconds": 0.25}]})
	_assert(bool(junit.get("success", false)), "JUnit writer failed")
	var xml := FileAccess.get_file_as_string(junit_path)
	_assert(xml.contains("bad&lt;&amp;"), "JUnit testcase name was not escaped")
	_assert(xml.contains("a &lt; b &amp; c"), "JUnit failure message was not escaped")
	_assert(xml.contains('failures="1"'), "JUnit failure count missing")

	var atomic_path := ProjectSettings.globalize_path("res://artifacts/test-results/n2-atomic-json-%d.json" % OS.get_process_id())
	var atomic_first := AtomicJsonScript.write_dictionary(atomic_path, {"state": "LISTENING", "revision": 1})
	_assert(bool(atomic_first.get("success", false)), "Atomic JSON initial write failed")
	var atomic_first_read := AtomicJsonScript.read_dictionary(atomic_path)
	_assert(bool(atomic_first_read.get("success", false)), "Atomic JSON initial read failed")
	_assert(String(Dictionary(atomic_first_read.get("value", {})).get("state", "")) == "LISTENING", "Atomic JSON initial state changed")
	var atomic_second := AtomicJsonScript.write_dictionary(atomic_path, {"state": "COMPLETE", "revision": 2})
	_assert(bool(atomic_second.get("success", false)), "Atomic JSON replacement failed")
	var atomic_second_value := AtomicJsonScript.read_value(atomic_path)
	_assert(String(atomic_second_value.get("state", "")) == "COMPLETE", "Atomic JSON replacement state changed")
	_assert(int(atomic_second_value.get("revision", 0)) == 2, "Atomic JSON replacement revision changed")
	var partial_file := FileAccess.open(atomic_path, FileAccess.WRITE)
	_assert(partial_file != null, "Partial JSON test file could not be opened")
	if partial_file != null:
		partial_file.store_string('{"state":')
		partial_file.close()
	var partial_read := AtomicJsonScript.read_dictionary(atomic_path)
	_assert(not bool(partial_read.get("success", false)), "Partial JSON was accepted")
	_assert(String(partial_read.get("error_code", "")) == "ATOMIC_JSON_INCOMPLETE", "Partial JSON error code changed")
	_assert(AtomicJsonScript.read_value(atomic_path).is_empty(), "Partial JSON produced a dictionary")

	for runner_path in [
		"res://RUN_N2_PROCESS_HARNESS_TESTS.ps1",
		"res://RUN_NETWORK_CONTRACT_TESTS.ps1",
		"res://RUN_WORLD_REGRESSION_TESTS.ps1",
	]:
		var runner_text := FileAccess.get_file_as_string(runner_path)
		_assert(runner_text.contains('$ErrorActionPreference = "Continue"'), "%s does not neutralize native stderr termination" % runner_path)
		_assert(runner_text.contains("PSNativeCommandUseErrorActionPreference"), "%s does not handle PowerShell native error preference" % runner_path)
		_assert(runner_text.contains("finally"), "%s does not restore PowerShell preferences" % runner_path)
	var n2_runner_text := FileAccess.get_file_as_string("res://RUN_N2_PROCESS_HARNESS_TESTS.ps1")
	_assert(n2_runner_text.contains("Read-JsonReportWithRetry"), "N2 PowerShell runner does not retry report parsing")
	var world_runner_text := FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	_assert(world_runner_text.contains("function Write-JsonFileAtomically"), "World regression runner does not define atomic summary writing")
	_assert(world_runner_text.contains("[IO.File]::Replace"), "World regression runner does not atomically replace an existing summary")
	_assert(world_runner_text.contains("[IO.File]::Move"), "World regression runner does not atomically publish the first summary")
	_assert(world_runner_text.contains("$Stream.Flush($true)"), "World regression runner does not durably flush the temporary summary")
	_assert(world_runner_text.contains("ConvertFrom-Json -ErrorAction Stop"), "World regression runner does not validate temporary and final JSON")
	_assert(world_runner_text.contains("Write-JsonFileAtomically -Value $Summary -Path $ReportPath"), "Save-Summary does not use atomic publication")
	_assert(not world_runner_text.contains("Set-Content -Path $ReportPath"), "World regression runner still truncates the final summary directly")
	_finish()

func _expect_failure(result: Dictionary, code: String) -> void:
	_assert(not bool(result.get("success", false)), "Expected failure %s was accepted" % code)
	_assert(String(result.get("error_code", "")) == code, "Expected %s, got %s" % [code, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("N2 process harness contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("N2 process harness contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
