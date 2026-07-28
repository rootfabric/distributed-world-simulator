extends SceneTree

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const WORKER_SCRIPT: String = "res://tools/persistence/r3_authoritative_recovery_worker.gd"
const COMMIT_CRASH_EXIT: int = 86
const PENDING_CRASH_EXIT: int = 87
const TIMEOUT_MS: int = 15000

var assertions: int = 0
var failures: Array[String] = []
var root_path: String = ""


func _init() -> void:
	root_path = ProjectSettings.globalize_path("user://r3-authoritative-processes-%d" % Time.get_ticks_usec())
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	_test_committed_crash_replay()
	_test_pending_crash_reexecute()
	_remove_tree(root_path)
	_finish()


func _test_committed_crash_replay() -> void:
	var scenario_root: String = root_path.path_join("committed")
	DirAccess.make_dir_recursive_absolute(scenario_root)
	var repository_root: String = scenario_root.path_join("repository")
	var context_path: String = scenario_root.path_join("client-context.json")
	var result_path: String = scenario_root.path_join("recovery-result.json")
	var seed_pid: int = _spawn("commit-crash", repository_root, context_path, "")
	_assert(seed_pid > 0, "Committed crash worker did not start")
	var seed_exit: int = _wait_for_exit(seed_pid, TIMEOUT_MS)
	_assert(seed_exit == COMMIT_CRASH_EXIT, "Committed crash worker exit code changed: %d" % seed_exit)
	_assert(FileAccess.file_exists(repository_root.path_join("authoritative-checkpoint.json")), "Committed checkpoint file missing")
	_assert(FileAccess.file_exists(repository_root.path_join("authoritative-checkpoint.previous.json")), "Previous checkpoint file missing")
	_assert(FileAccess.file_exists(context_path), "Committed client context missing")
	var recovery_pid: int = _spawn("recover-replay", repository_root, context_path, result_path)
	_assert(recovery_pid > 0, "Committed recovery worker did not start")
	var recovery_exit: int = _wait_for_exit(recovery_pid, TIMEOUT_MS)
	_assert(recovery_exit == 0, "Committed recovery worker failed: %d" % recovery_exit)
	var report_result: Dictionary = AtomicJsonScript.read_dictionary(result_path)
	_assert(bool(report_result.get("success", false)), "Committed recovery report missing")
	if not bool(report_result.get("success", false)):
		return
	var report: Dictionary = report_result["value"]
	_assert(bool(report["passed"]), "Committed recovery report failed")
	_assert(String(report["mode"]) == "REPLAY", "Committed recovery mode changed")
	_assert(String(report["repository_source"]) == "ACTIVE", "Committed recovery did not use active checkpoint")
	_assert(int(report["checkpoint_generation"]) == 2, "Committed recovery generation changed")
	_assert(int(report["before_mutation_count"]) == 1, "Committed recovery did not restore mutation")
	_assert(int(report["before_handler_invocation_count"]) == 1, "Committed recovery handler count changed")
	_assert(int(report["after_mutation_count"]) == 1, "Committed replay mutated twice")
	_assert(int(report["after_handler_invocation_count"]) == 1, "Committed replay invoked handler twice")
	_assert(int(report["operation_ledger_count"]) == 1, "Committed replay duplicated ledger record")
	_assert(int(report["aggregate_revision"]) == 13, "Committed replay revision changed")
	_assert(int(report["server_tick"]) == 501, "Committed replay tick changed")
	_assert(bool(report["replay_accepted"]), "Persisted resume ticket rejected")
	_assert(bool(report["replay_served"]), "Persisted replay record not served")
	_assert(String(report["final_snapshot_checksum"]) == String(report["expected_snapshot_checksum"]), "Committed recovery checksum mismatch")
	_assert(String(report["replay_snapshot_checksum"]) == String(report["expected_snapshot_checksum"]), "Persisted replay checksum mismatch")


func _test_pending_crash_reexecute() -> void:
	var scenario_root: String = root_path.path_join("pending")
	DirAccess.make_dir_recursive_absolute(scenario_root)
	var repository_root: String = scenario_root.path_join("repository")
	var context_path: String = scenario_root.path_join("client-context.json")
	var result_path: String = scenario_root.path_join("recovery-result.json")
	var seed_pid: int = _spawn("pending-crash", repository_root, context_path, "")
	_assert(seed_pid > 0, "Pending crash worker did not start")
	var seed_exit: int = _wait_for_exit(seed_pid, TIMEOUT_MS)
	_assert(seed_exit == PENDING_CRASH_EXIT, "Pending crash worker exit code changed: %d" % seed_exit)
	_assert(FileAccess.file_exists(repository_root.path_join("authoritative-checkpoint.json")), "Pending scenario baseline checkpoint missing")
	var pending_files: Array[String] = _list_pending(repository_root)
	_assert(pending_files.size() == 1, "Pending crash did not leave exactly one prepared checkpoint")
	var recovery_pid: int = _spawn("recover-reexecute", repository_root, context_path, result_path)
	_assert(recovery_pid > 0, "Pending recovery worker did not start")
	var recovery_exit: int = _wait_for_exit(recovery_pid, TIMEOUT_MS)
	_assert(recovery_exit == 0, "Pending recovery worker failed: %d" % recovery_exit)
	var report_result: Dictionary = AtomicJsonScript.read_dictionary(result_path)
	_assert(bool(report_result.get("success", false)), "Pending recovery report missing")
	if not bool(report_result.get("success", false)):
		return
	var report: Dictionary = report_result["value"]
	_assert(bool(report["passed"]), "Pending recovery report failed")
	_assert(String(report["mode"]) == "REEXECUTE", "Pending recovery mode changed")
	_assert(int(report["checkpoint_generation"]) == 1, "Uncommitted generation became authoritative")
	_assert(int(report["pending_file_count"]) == 1, "Pending checkpoint diagnostic missing after restart")
	_assert(int(report["before_mutation_count"]) == 0, "Uncommitted mutation survived restart")
	_assert(int(report["before_handler_invocation_count"]) == 0, "Uncommitted handler count survived restart")
	_assert(int(report["after_mutation_count"]) == 1, "Recovered command did not execute exactly once")
	_assert(int(report["after_handler_invocation_count"]) == 1, "Recovered command handler count is not one")
	_assert(int(report["operation_ledger_count"]) == 1, "Recovered command ledger count is not one")
	_assert(int(report["aggregate_revision"]) == 13, "Recovered command revision changed")
	_assert(int(report["server_tick"]) == 501, "Recovered command tick changed")
	_assert(String(report["final_snapshot_checksum"]) == String(report["expected_snapshot_checksum"]), "Pending recovery checksum mismatch")


func _spawn(phase: String, repository_root: String, context_path: String, result_path: String) -> int:
	var arguments: Array[String] = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", WORKER_SCRIPT,
		"--",
		"--phase=%s" % phase,
		"--repository-root=%s" % repository_root,
		"--context-file=%s" % context_path,
		"--result-file=%s" % result_path,
	]
	return OS.create_process(OS.get_executable_path(), arguments, false)


func _wait_for_exit(pid: int, timeout_ms: int) -> int:
	if pid <= 0:
		return -999
	var started: int = Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > timeout_ms:
			OS.kill(pid)
			return -998
		OS.delay_msec(20)
	return OS.get_process_exit_code(pid)


func _list_pending(repository_root: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(repository_root)
	if directory == null:
		return result
	directory.include_hidden = true
	for file_name in directory.get_files():
		if file_name.begins_with(".authoritative-checkpoint.") and file_name.ends_with(".pending.json"):
			result.append(file_name)
	return result


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	if failures.is_empty():
		print("R3.1 authoritative recovery processes: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("R3.1 authoritative recovery processes: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
		quit(1)
