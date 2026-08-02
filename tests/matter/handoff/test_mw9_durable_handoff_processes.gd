extends SceneTree

const WORKER_SCRIPT := "res://tools/matter/mw9_handoff_recovery_worker.gd"
const Coordinator = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_coordinator.gd")
const COMMIT_CRASH_EXIT := 91
const PRECOMMIT_CRASH_EXIT := 92
const TIMEOUT_MS := 20000

var assertions := 0
var failures: Array[String] = []
var root_path := ""


func _init() -> void:
	root_path = ProjectSettings.globalize_path("user://mw9-processes-%d" % Time.get_ticks_usec())
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	_test_commit_decision_recovery()
	_test_precommit_abort_recovery()
	_test_concurrent_expired_claim()
	_remove_tree(root_path)
	if failures.is_empty():
		print("MW9 durable handoff processes: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("MW9 durable handoff processes: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)


func _test_commit_decision_recovery() -> void:
	var scenario: String = root_path.path_join("commit")
	var repository: String = scenario.path_join("repository")
	var report: String = scenario.path_join("report.json")
	var seed_pid: int = _spawn("seed-commit", repository, "")
	_assert(seed_pid > 0, "Commit seed process did not start")
	_assert(_wait(seed_pid) == COMMIT_CRASH_EXIT, "Commit seed crash code changed")
	_assert(FileAccess.file_exists(repository.path_join("matter-handoff-state.json")), "Commit seed checkpoint missing")
	var recover_pid: int = _spawn("recover-commit", repository, report)
	_assert(recover_pid > 0, "Commit recovery process did not start")
	_assert(_wait(recover_pid) == 0, "Commit recovery process failed")
	var value: Dictionary = _read_report(report)
	_assert(not value.is_empty(), "Commit recovery report missing")
	_assert(bool(value.get("passed", false)), "Commit recovery report failed")
	_assert(String(value.get("actual_action", "")) == "COMPLETE_COMMIT", "Commit action changed")
	_assert(String(value.get("owner_id", "")) == "simulation-node/target-mw9", "Commit recovery owner changed")
	_assert(int(value.get("authority_epoch", 0)) == 5, "Commit recovery epoch changed")
	_assert(String(value.get("record_phase", "")) == "COMMITTED", "Commit recovery journal phase changed")
	_assert(not String(value.get("fencing_token_checksum", "")).is_empty(), "Commit recovery fencing token missing")
	_assert(not String(value.get("summary_manifest_checksum", "")).is_empty(), "Commit recovery lost RL1 summary manifest")


func _test_precommit_abort_recovery() -> void:
	var scenario: String = root_path.path_join("abort")
	var repository: String = scenario.path_join("repository")
	var report: String = scenario.path_join("report.json")
	var seed_pid: int = _spawn("seed-precommit", repository, "")
	_assert(seed_pid > 0, "Abort seed process did not start")
	_assert(_wait(seed_pid) == PRECOMMIT_CRASH_EXIT, "Abort seed crash code changed")
	var recover_pid: int = _spawn("recover-abort", repository, report)
	_assert(recover_pid > 0, "Abort recovery process did not start")
	_assert(_wait(recover_pid) == 0, "Abort recovery process failed")
	var value: Dictionary = _read_report(report)
	_assert(not value.is_empty(), "Abort recovery report missing")
	_assert(bool(value.get("passed", false)), "Abort recovery report failed")
	_assert(String(value.get("actual_action", "")) == "ABORT_UNDECIDED", "Abort action changed")
	_assert(String(value.get("owner_id", "")) == "simulation-node/source-mw9", "Abort recovery owner changed")
	_assert(int(value.get("authority_epoch", 0)) == 4, "Abort recovery epoch changed")
	_assert(String(value.get("record_phase", "")) == "ABORTED", "Abort recovery journal phase changed")
	_assert(String(value.get("record_decision", "")) == "ABORT", "Abort recovery decision changed")
	_assert(not String(value.get("package_checksum", "")).is_empty(), "Abort recovery lost durable package")


func _test_concurrent_expired_claim() -> void:
	var scenario: String = root_path.path_join("claim-race")
	var repository: String = scenario.path_join("repository")
	var seed_pid: int = _spawn("seed-claim", repository, "")
	_assert(seed_pid > 0, "Claim seed process did not start")
	_assert(_wait(seed_pid) == 0, "Claim seed process failed")
	var ready_a: String = scenario.path_join("ready-a")
	var ready_b: String = scenario.path_join("ready-b")
	var go_file: String = scenario.path_join("go")
	var report_a: String = scenario.path_join("claim-a.json")
	var report_b: String = scenario.path_join("claim-b.json")
	var owner_a := "simulation-node/claim-racer-a"
	var owner_b := "simulation-node/claim-racer-b"
	var pid_a: int = _spawn("claim", repository, report_a, owner_a, ready_a, go_file)
	var pid_b: int = _spawn("claim", repository, report_b, owner_b, ready_b, go_file)
	_assert(pid_a > 0 and pid_b > 0, "Concurrent claim workers did not start")
	_assert(_wait_for_files([ready_a, ready_b]), "Concurrent claim workers did not reach barrier")
	_assert(_write_text(go_file, "go"), "Concurrent claim barrier release failed")
	_assert(_wait(pid_a) == 0, "Claim worker A process failed")
	_assert(_wait(pid_b) == 0, "Claim worker B process failed")
	var a: Dictionary = _read_report(report_a)
	var b: Dictionary = _read_report(report_b)
	_assert(not a.is_empty() and not b.is_empty(), "Concurrent claim reports missing")
	var successes: int = int(bool(a.get("claim_success", false))) + int(bool(b.get("claim_success", false)))
	_assert(successes == 1, "Concurrent expired claim produced zero or multiple winners")
	var winner: Dictionary = a if bool(a.get("claim_success", false)) else b
	var loser: Dictionary = b if bool(a.get("claim_success", false)) else a
	_assert(String(winner.get("owner_id", "")) in [owner_a, owner_b], "Concurrent claim winner owner changed")
	_assert(int(winner.get("authority_epoch", 0)) == 5, "Concurrent claim winner epoch changed")
	_assert(int(winner.get("checkpoint_generation", 0)) == 2, "Concurrent claim winner generation changed")
	_assert(not String(loser.get("error", "")).is_empty(), "Concurrent claim loser has no CAS error")
	var verifier := Coordinator.new()
	_assert(bool(verifier.configure(repository, 120, 40).get("success", false)), "Concurrent claim verifier configure failed")
	var restored: Dictionary = verifier.restore_latest()
	_assert(bool(restored.get("success", false)), "Concurrent claim final checkpoint restore failed")
	var final_lease: Dictionary = verifier.lease("matter-region/mw9-alpha")
	_assert(String(final_lease.get("owner_id", "")) == String(winner.get("owner_id", "")), "Concurrent claim durable winner differs from report")
	_assert(int(final_lease.get("authority_epoch", 0)) == 5, "Concurrent claim durable epoch changed")
	_assert(int(verifier.checkpoint().get("generation", 0)) == 2, "Concurrent claim advanced checkpoint more than once")
	_assert(Array(restored["details"].get("pending_files", [])).is_empty(), "Rejected concurrent claim leaked pending checkpoint")
	_assert(not DirAccess.dir_exists_absolute(repository.path_join(".matter-handoff-state.lock")), "Concurrent claim left repository lock")


func _spawn(
	phase: String,
	repository: String,
	report: String,
	owner: String = "",
	ready_file: String = "",
	go_file: String = ""
) -> int:
	var arguments: Array[String] = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", WORKER_SCRIPT, "--",
		"--phase=%s" % phase,
		"--repository-root=%s" % repository,
		"--report-file=%s" % report,
		"--owner-id=%s" % owner,
		"--ready-file=%s" % ready_file,
		"--go-file=%s" % go_file,
	]
	return OS.create_process(OS.get_executable_path(), arguments, false)


func _wait(pid: int) -> int:
	var started: int = Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > TIMEOUT_MS:
			OS.kill(pid)
			return -998
		OS.delay_msec(20)
	return OS.get_process_exit_code(pid)


func _wait_for_files(paths: Array[String]) -> bool:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= TIMEOUT_MS:
		var all_present := true
		for path in paths:
			if not FileAccess.file_exists(path):
				all_present = false
				break
		if all_present:
			return true
		OS.delay_msec(20)
	return false


func _write_text(path: String, value: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.flush()
	var error: int = file.get_error()
	file.close()
	return error == OK


func _read_report(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value = JSON.parse_string(file.get_as_text())
	file.close()
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


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
