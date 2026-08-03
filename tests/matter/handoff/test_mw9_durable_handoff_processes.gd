extends SceneTree

const WORKER_SCRIPT := "res://tools/matter/mw9_handoff_recovery_worker.gd"
const Coordinator = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_coordinator.gd")
const COMMIT_CRASH_EXIT := 91
const PRECOMMIT_CRASH_EXIT := 92
const TIMEOUT_MS := 20000
const DEFAULT_CLAIM_RACE_ROUNDS := 8
const MAX_CLAIM_RACE_ROUNDS := 256

var assertions := 0
var failures: Array[String] = []
var root_path := ""


func _init() -> void:
	var options: Dictionary = _options()
	var claim_only: bool = String(options.get("claim-race-only", "false")).to_lower() == "true"
	var rounds: int = clampi(
		int(options.get("claim-race-rounds", DEFAULT_CLAIM_RACE_ROUNDS)),
		1, MAX_CLAIM_RACE_ROUNDS
	)
	root_path = ProjectSettings.globalize_path(
		"user://mw9-processes-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	if not claim_only:
		_test_commit_decision_recovery()
		_test_precommit_abort_recovery()
	_test_concurrent_expired_claim(rounds)
	_remove_tree(root_path)
	if failures.is_empty():
		if claim_only:
			print("MW9 claim race stress: PASS (%d assertions, %d rounds)" % [assertions, rounds])
		else:
			print("MW9 durable handoff processes: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		if claim_only:
			print("MW9 claim race stress: FAIL (%d assertions, %d failures, %d rounds)" % [assertions, failures.size(), rounds])
		else:
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


func _test_concurrent_expired_claim(rounds: int) -> void:
	for round_index in range(rounds):
		_test_concurrent_expired_claim_round(round_index)


func _test_concurrent_expired_claim_round(round_index: int) -> void:
	var label: String = "round %d" % (round_index + 1)
	var scenario: String = root_path.path_join("claim-race-%03d" % round_index)
	var repository: String = scenario.path_join("repository")
	var seed_pid: int = _spawn("seed-claim", repository, "")
	_assert(seed_pid > 0, "%s: claim seed process did not start" % label)
	_assert(_wait(seed_pid) == 0, "%s: claim seed process failed" % label)
	var ready_a: String = scenario.path_join("ready-a")
	var ready_b: String = scenario.path_join("ready-b")
	var go_file: String = scenario.path_join("go")
	var report_a: String = scenario.path_join("claim-a.json")
	var report_b: String = scenario.path_join("claim-b.json")
	var owner_a := "simulation-node/claim-racer-a-%03d" % round_index
	var owner_b := "simulation-node/claim-racer-b-%03d" % round_index
	var pid_a: int = _spawn("claim", repository, report_a, owner_a, ready_a, go_file)
	var pid_b: int = _spawn("claim", repository, report_b, owner_b, ready_b, go_file)
	_assert(pid_a > 0 and pid_b > 0, "%s: concurrent claim workers did not start" % label)
	_assert(_wait_for_files([ready_a, ready_b]), "%s: concurrent claim workers did not reach barrier" % label)
	_assert(_write_text(go_file, "go"), "%s: concurrent claim barrier release failed" % label)
	var exit_a: int = _wait(pid_a)
	var exit_b: int = _wait(pid_b)
	_assert(exit_a == 0, "%s: claim worker A process failed with %d" % [label, exit_a])
	_assert(exit_b == 0, "%s: claim worker B process failed with %d" % [label, exit_b])
	var a: Dictionary = _read_report(report_a)
	var b: Dictionary = _read_report(report_b)
	_assert(not a.is_empty() and not b.is_empty(), "%s: concurrent claim reports missing" % label)
	_assert(int(a.get("process_id", 0)) == pid_a, "%s: worker A PID diagnostics changed" % label)
	_assert(int(b.get("process_id", 0)) == pid_b, "%s: worker B PID diagnostics changed" % label)
	_assert(String(a.get("expected_lease_checksum", "")) == String(b.get("expected_lease_checksum", "")), "%s: contenders restored different lease frontiers" % label)
	var successes: int = int(bool(a.get("claim_success", false))) + int(bool(b.get("claim_success", false)))
	_assert(successes == 1, "%s: concurrent expired claim produced zero or multiple winners; A=%s B=%s" % [label, JSON.stringify(a), JSON.stringify(b)])
	var winner: Dictionary = a if bool(a.get("claim_success", false)) else b
	var loser: Dictionary = b if bool(a.get("claim_success", false)) else a
	_assert(String(winner.get("owner_id", "")) in [owner_a, owner_b], "%s: concurrent claim winner owner changed" % label)
	_assert(int(winner.get("authority_epoch", 0)) == 5, "%s: concurrent claim winner epoch changed" % label)
	_assert(int(winner.get("checkpoint_generation", 0)) == 2, "%s: concurrent claim winner generation changed" % label)
	_assert(String(winner.get("error", "")).is_empty(), "%s: winner reported an error" % label)
	_assert(not String(loser.get("error", "")).is_empty(), "%s: concurrent claim loser has no CAS error" % label)
	var verifier := Coordinator.new()
	_assert(bool(verifier.configure(repository, 120, 40).get("success", false)), "%s: concurrent claim verifier configure failed" % label)
	var restored: Dictionary = verifier.restore_latest()
	_assert(bool(restored.get("success", false)), "%s: concurrent claim final checkpoint restore failed" % label)
	var final_lease: Dictionary = verifier.lease("matter-region/mw9-alpha")
	_assert(String(final_lease.get("owner_id", "")) == String(winner.get("owner_id", "")), "%s: concurrent claim durable winner differs from report" % label)
	_assert(int(final_lease.get("authority_epoch", 0)) == 5, "%s: concurrent claim durable epoch changed" % label)
	_assert(int(verifier.checkpoint().get("generation", 0)) == 2, "%s: concurrent claim advanced checkpoint more than once" % label)
	_assert(Array(restored["details"].get("pending_files", [])).is_empty(), "%s: rejected concurrent claim leaked pending checkpoint" % label)
	_assert(not DirAccess.dir_exists_absolute(repository.path_join(".matter-handoff-state.lock")), "%s: concurrent claim left repository lock" % label)
	_assert(_repository_residue(repository).is_empty(), "%s: concurrent claim left lock/pending residue: %s" % [label, _repository_residue(repository)])


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
			var kill_started: int = Time.get_ticks_msec()
			while OS.is_process_running(pid) and Time.get_ticks_msec() - kill_started <= 5000:
				OS.delay_msec(10)
			return -998
		OS.delay_msec(10)
	# On Windows the process handle may report termination before the exit code
	# becomes observable. Poll briefly instead of turning a successful worker into
	# a harness failure or waiting forever on a recycled PID.
	for _attempt in range(200):
		var exit_code: int = OS.get_process_exit_code(pid)
		if exit_code != -1:
			return exit_code
		OS.delay_msec(5)
	return -997


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


func _options() -> Dictionary:
	var result: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
		result[parts[0]] = parts[1]
	return result


func _repository_residue(repository: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(repository)
	if directory == null:
		return result
	directory.include_hidden = true
	for file_name in directory.get_files():
		if file_name.ends_with(".pending.json") \
			or file_name.ends_with(".candidate") \
			or file_name.ends_with(".released") \
			or file_name.ends_with(".stale"):
			result.append(file_name)
	for directory_name in directory.get_directories():
		if directory_name.begins_with(".matter-handoff-state.lock"):
			result.append(directory_name)
	result.sort()
	return result


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
