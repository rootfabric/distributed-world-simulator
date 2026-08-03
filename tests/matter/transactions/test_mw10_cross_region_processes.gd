extends SceneTree

const WORKER_SCRIPT := "res://tools/matter/mw10_cross_region_transaction_worker.gd"
const Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")
const AuthorityGate = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_authority_gate.gd")
const Coordinator = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_coordinator.gd")
const COMMIT_CRASH_EXIT := 91
const PRECOMMIT_CRASH_EXIT := 92
const TIMEOUT_MS := 30000

var assertions := 0
var failures: Array[String] = []
var root_path := ""


class NoopRuntime extends RefCounted:
	func prepare_region(_participant: Dictionary, _context: Dictionary) -> Dictionary:
		return {"success": false, "error_code": "NOOP", "details": {}}
	func commit_region(_participant: Dictionary, _prepare: Dictionary, _context: Dictionary) -> Dictionary:
		return {"success": false, "error_code": "NOOP", "details": {}}
	func rollback_region(_participant: Dictionary, _prepare: Dictionary, _context: Dictionary) -> Dictionary:
		return {"success": false, "error_code": "NOOP", "details": {}}
	func publish_invalidation(_outbox: Dictionary) -> Dictionary:
		return {"success": false, "error_code": "NOOP", "details": {}}


func _init() -> void:
	root_path = ProjectSettings.globalize_path("user://mw10-processes-%d" % Time.get_ticks_usec())
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	_test_commit_decision_recovery()
	_test_precommit_abort_recovery()
	_test_concurrent_begin_reservation_race()
	_remove_tree(root_path)
	if failures.is_empty():
		print("MW10 cross-region Matter processes: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("MW10 cross-region Matter processes: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)


func _test_commit_decision_recovery() -> void:
	var scenario: String = root_path.path_join("commit")
	var repository: String = scenario.path_join("repository")
	var runtime: String = scenario.path_join("runtime")
	var report: String = scenario.path_join("report.json")
	var seed_pid: int = _spawn("seed-commit", repository, runtime, "")
	_assert(seed_pid > 0, "Commit seed process did not start")
	_assert(_wait(seed_pid) == COMMIT_CRASH_EXIT, "Commit seed crash code changed")
	_assert(FileAccess.file_exists(repository.path_join("matter-cross-region-transactions.json")), "Commit seed checkpoint missing")
	_assert(_count_files(runtime.path_join("committed")) == 1, "Commit seed did not persist exactly one participant commit")
	_assert(_count_files(runtime.path_join("published")) == 0, "Commit seed published invalidation before global commit")
	var recover_pid: int = _spawn("recover-commit", repository, runtime, report)
	_assert(recover_pid > 0, "Commit recovery process did not start")
	_assert(_wait(recover_pid) == 0, "Commit recovery process failed")
	var value: Dictionary = _read_report(report)
	_assert(not value.is_empty(), "Commit recovery report missing")
	_assert(bool(value.get("passed", false)), "Commit recovery report failed")
	_assert(String(value.get("actual_action", "")) == "COMPLETE_COMMIT", "Commit recovery action changed")
	_assert(String(value.get("record_phase", "")) == "COMMITTED", "Commit recovery phase changed")
	_assert(String(value.get("record_decision", "")) == "COMMIT", "Commit recovery decision changed")
	_assert(int(value.get("reservation_count", -1)) == 0, "Commit recovery retained reservations")
	_assert(int(value.get("committed_file_count", 0)) == 2, "Commit recovery did not commit both participants")
	_assert(int(value.get("published_file_count", 0)) == 1, "Commit recovery did not publish one invalidation batch")
	_assert(String(value.get("outcome", "")) == "COMMITTED", "Commit recovery operation outcome changed")


func _test_precommit_abort_recovery() -> void:
	var scenario: String = root_path.path_join("abort")
	var repository: String = scenario.path_join("repository")
	var runtime: String = scenario.path_join("runtime")
	var report: String = scenario.path_join("report.json")
	var seed_pid: int = _spawn("seed-precommit", repository, runtime, "")
	_assert(seed_pid > 0, "Abort seed process did not start")
	_assert(_wait(seed_pid) == PRECOMMIT_CRASH_EXIT, "Abort seed crash code changed")
	_assert(_count_files(runtime.path_join("staged")) == 1, "Abort seed did not leave one prepared participant")
	_assert(_count_files(runtime.path_join("committed")) == 0, "Abort seed committed before decision")
	var recover_pid: int = _spawn("recover-abort", repository, runtime, report)
	_assert(recover_pid > 0, "Abort recovery process did not start")
	_assert(_wait(recover_pid) == 0, "Abort recovery process failed")
	var value: Dictionary = _read_report(report)
	_assert(not value.is_empty(), "Abort recovery report missing")
	_assert(bool(value.get("passed", false)), "Abort recovery report failed")
	_assert(String(value.get("actual_action", "")) == "ABORT_UNDECIDED", "Abort recovery action changed")
	_assert(String(value.get("record_phase", "")) == "ABORTED", "Abort recovery phase changed")
	_assert(String(value.get("record_decision", "")) == "ABORT", "Abort recovery decision changed")
	_assert(int(value.get("reservation_count", -1)) == 0, "Abort recovery retained reservations")
	_assert(int(value.get("committed_file_count", -1)) == 0, "Abort recovery left committed state")
	_assert(int(value.get("rolled_back_file_count", 0)) == 1, "Abort recovery did not roll back prepared participant")
	_assert(int(value.get("published_file_count", -1)) == 0, "Abort recovery published invalidation")
	_assert(String(value.get("outcome", "")) == "ABORTED", "Abort recovery operation outcome changed")


func _test_concurrent_begin_reservation_race() -> void:
	var scenario: String = root_path.path_join("begin-race")
	var repository: String = scenario.path_join("repository")
	var runtime: String = scenario.path_join("runtime")
	var seed_pid: int = _spawn("seed-race", repository, runtime, "")
	_assert(seed_pid > 0, "Race seed process did not start")
	_assert(_wait(seed_pid) == 0, "Race seed process failed")
	var ready_a: String = scenario.path_join("ready-a")
	var ready_b: String = scenario.path_join("ready-b")
	var go_file: String = scenario.path_join("go")
	var report_a: String = scenario.path_join("race-a.json")
	var report_b: String = scenario.path_join("race-b.json")
	var pid_a: int = _spawn("begin-race", repository, runtime, report_a, ready_a, go_file, "a")
	var pid_b: int = _spawn("begin-race", repository, runtime, report_b, ready_b, go_file, "b")
	_assert(pid_a > 0 and pid_b > 0, "Race workers did not start")
	_assert(_wait_for_files([ready_a, ready_b]), "Race workers did not reach barrier")
	_assert(_write_text(go_file, "go"), "Race barrier release failed")
	_assert(_wait(pid_a) == 0, "Race worker A process failed")
	_assert(_wait(pid_b) == 0, "Race worker B process failed")
	var a: Dictionary = _read_report(report_a)
	var b: Dictionary = _read_report(report_b)
	_assert(not a.is_empty() and not b.is_empty(), "Race reports missing")
	var successes: int = int(bool(a.get("begin_success", false))) + int(bool(b.get("begin_success", false)))
	_assert(successes == 1, "Concurrent begin produced zero or multiple winners")
	var winner: Dictionary = a if bool(a.get("begin_success", false)) else b
	var loser: Dictionary = b if bool(a.get("begin_success", false)) else a
	_assert(String(winner.get("transaction_id", "")).begins_with("matter-transaction/process-race-"), "Race winner identity changed")
	_assert(not String(loser.get("error", "")).is_empty(), "Race loser has no CAS/progression error")
	var coordinator = _verifier(repository)
	_assert(coordinator != null, "Race verifier configure failed")
	if coordinator != null:
		_assert(bool(coordinator.restore_latest().get("success", false)), "Race final checkpoint restore failed")
		var checkpoint: Dictionary = coordinator.checkpoint()
		_assert(int(checkpoint.get("generation", 0)) == 2, "Race advanced checkpoint more than once")
		_assert(Array(checkpoint.get("region_reservations", [])).size() == 2, "Race durable winner did not reserve exactly two regions")
		var records: Dictionary = {}
		for raw_record in checkpoint.get("transaction_records", []):
			records[String(raw_record["transaction_id"])] = raw_record
		_assert(records.size() == 1, "Race persisted more than one transaction")
		_assert(records.has(String(winner.get("transaction_id", ""))), "Race durable winner differs from worker report")
		_assert(Array(coordinator.repository().list_pending_files()).is_empty(), "Race loser leaked pending checkpoint")
		_assert(not DirAccess.dir_exists_absolute(coordinator.repository().lock_path()), "Race left repository lock")


func _spawn(
	phase: String,
	repository: String,
	runtime: String,
	report: String,
	ready_file: String = "",
	go_file: String = "",
	contender: String = ""
) -> int:
	var arguments: Array[String] = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", WORKER_SCRIPT, "--",
		"--phase=%s" % phase,
		"--repository-root=%s" % repository,
		"--runtime-root=%s" % runtime,
		"--report-file=%s" % report,
		"--ready-file=%s" % ready_file,
		"--go-file=%s" % go_file,
		"--contender=%s" % contender,
	]
	return OS.create_process(OS.get_executable_path(), arguments, false)


func _verifier(repository: String):
	var gate := AuthorityGate.new()
	if not bool(gate.configure(Fixture.lease_provider()).get("success", false)):
		return null
	var coordinator := Coordinator.new()
	if not bool(coordinator.configure(repository, gate, NoopRuntime.new()).get("success", false)):
		return null
	return coordinator


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


func _count_files(path: String) -> int:
	var directory := DirAccess.open(path)
	return 0 if directory == null else directory.get_files().size()


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
