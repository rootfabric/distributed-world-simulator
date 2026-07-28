extends SceneTree

const ManifestScript = preload("res://scripts/testing/process_harness/process_harness_manifest.gd")
const HarnessScript = preload("res://scripts/testing/process_harness/network_process_harness.gd")
const JUnitScript = preload("res://scripts/testing/process_harness/junit_report_writer.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	var loaded := ManifestScript.load_file("res://config/testing/network-process-scenarios.v1.json")
	_assert(bool(loaded.get("success", false)), "N2 manifest did not load")
	if not bool(loaded.get("success", false)): _finish(); return
	var output := ProjectSettings.globalize_path("res://artifacts/test-results/n2-harness-test-%d/runs" % OS.get_process_id())
	var harness = HarnessScript.new()
	var configured := harness.configure(loaded["manifest"], OS.get_executable_path(), ProjectSettings.globalize_path("res://"), output)
	_assert(bool(configured.get("success", false)), "N2 harness configure failed: %s" % configured)
	if not bool(configured.get("success", false)): _finish(); return
	var summary: Dictionary = harness.run_all()
	_assert(String(summary.get("schema", "")) == "planet_simulator.network_process_harness_summary.v1", "Summary schema incorrect")
	_assert(String(summary.get("checkpoint", "")) == "v16.6.0-network-n2-process-harness", "Summary checkpoint incorrect")
	_assert(String(summary.get("build_id", "")) == "n2-cross-platform-process-orchestration", "Summary build id incorrect")
	_assert(bool(summary.get("passed", false)), "N2 harness summary failed: %s" % summary)
	_assert(int(summary.get("scenario_count", -1)) == 6, "Scenario count incorrect")
	_assert(int(summary.get("passed_count", -1)) == 6, "Passed count incorrect")
	_assert(int(summary.get("failed_count", -1)) == 0, "Failed count incorrect")
	var by_id := {}; var ports := {}
	for scenario_value in Array(summary.get("scenarios", [])):
		var scenario: Dictionary = scenario_value; var id := String(scenario.get("id", "")); by_id[id] = scenario
		_assert(bool(scenario.get("passed", false)), "%s did not pass" % id)
		_assert(not bool(scenario.get("server_running_after_cleanup", true)), "%s server leaked" % id)
		_assert(not bool(scenario.get("client_running_after_cleanup", true)), "%s client leaked" % id)
		_assert(int(scenario.get("port", 0)) >= 24000, "%s port invalid" % id)
		_assert(not ports.has(int(scenario.get("port", 0))), "%s reused port" % id); ports[int(scenario.get("port", 0))] = true
		_assert(FileAccess.file_exists(String(scenario.get("server_log", ""))), "%s server log missing" % id)
		_assert(String(scenario.get("server_user_root", "")) != String(scenario.get("client_user_root", "")), "%s user roots not isolated" % id)
		_assert(not _contains_atomic_temporary_file(String(scenario.get("run_directory", ""))), "%s left an atomic JSON temporary file" % id)
	_assert(by_id.size() == 6, "Scenario IDs not unique")
	_assert(String(by_id["readiness_timeout_cleanup"].get("observed_failure_code", "")) == "READINESS_TIMEOUT", "Readiness failure not classified")
	_assert(String(by_id["client_failure_cleanup"].get("observed_failure_code", "")) == "CLIENT_FAILED", "Client failure not classified")
	_assert(String(by_id["nonzero_exit_after_terminal"].get("observed_failure_code", "")) == "PROCESS_EXIT_NONZERO", "Nonzero exit not classified")
	_assert(int(by_id["nonzero_exit_after_terminal"].get("client_exit_code", 0)) == 9, "Nonzero client exit code lost")
	var item_server: Dictionary = by_id["n1_remote_item_success"].get("server_report", {})
	var item_client: Dictionary = by_id["n1_remote_item_success"].get("client_report", {})
	_assert(int(item_server.get("mutation_count", -1)) == 1, "Remote item mutation count changed")
	_assert(int(item_server.get("operation_ledger_count", -1)) == 1, "Remote item ledger count changed")
	_assert(String(item_server.get("final_snapshot_checksum", "")) == String(item_client.get("final_snapshot_checksum", "")), "Remote item checksums differ")
	var replay_server: Dictionary = by_id["n1_reconnect_replay_success"].get("server_report", {})
	var replay_client: Dictionary = by_id["n1_reconnect_replay_success"].get("client_report", {})
	_assert(int(replay_server.get("mutation_count", -1)) == 1, "Reconnect repeated mutation")
	_assert(int(replay_server.get("handler_invocation_count", -1)) == 1, "Reconnect invoked handler twice")
	_assert(int(replay_server.get("operation_ledger_count", -1)) == 1, "Reconnect ledger count changed")
	_assert(int(replay_server.get("replay_served_count", -1)) == 2, "Reconnect replay count changed")
	_assert(int(replay_client.get("mutations_applied", -1)) == 1, "Client applied replay twice")
	_assert(int(replay_client.get("unique_transport_sessions", -1)) == 3, "Transport sessions not rotated")
	_assert(String(replay_server.get("final_snapshot_checksum", "")) == String(replay_client.get("final_snapshot_checksum", "")), "Reconnect checksums differ")
	var junit_path := ProjectSettings.globalize_path("res://artifacts/test-results/n2-harness-test-%d/junit.xml" % OS.get_process_id())
	var junit := JUnitScript.write(junit_path, summary)
	_assert(bool(junit.get("success", false)), "JUnit write failed")
	var xml := FileAccess.get_file_as_string(junit_path)
	_assert(xml.contains('tests="6"'), "JUnit scenario count incorrect")
	_assert(xml.contains('failures="0"'), "JUnit failure count incorrect")
	_assert(xml.contains("n1_reconnect_replay_success"), "JUnit scenario missing")
	_finish()

func _contains_atomic_temporary_file(directory_path: String) -> bool:
	if directory_path.is_empty():
		return false
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.contains(".tmp.") or entry.contains(".bak."):
			directory.list_dir_end()
			return true
		if directory.current_is_dir() and entry != "." and entry != "..":
			if _contains_atomic_temporary_file(directory_path.path_join(entry)):
				directory.list_dir_end()
				return true
		entry = directory.get_next()
	directory.list_dir_end()
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("N2 process harness processes: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("N2 process harness processes: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
