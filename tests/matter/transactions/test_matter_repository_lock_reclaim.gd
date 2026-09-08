extends SceneTree

# Execute inherited production methods; only scheduling/liveness are controlled.
# No copy of acquire/release/reclaim is used by this regression.
class MW10Reaper:
	extends "res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_repository.gd"
	var after_decision: Callable
	var after_quarantine: Callable
	var liveness: String = ""
	func _lock_is_stale(owner: Dictionary) -> bool:
		var result: bool = super._lock_is_stale(owner)
		if result and after_decision.is_valid():
			after_decision.call()
		return result
	func _read_lock_owner_at(path: String) -> Dictionary:
		var owner: Dictionary = super._read_lock_owner_at(path)
		if path.ends_with(".stale") and after_quarantine.is_valid():
			after_quarantine.call()
		return owner
	func _process_liveness(pid: int) -> String:
		return super._process_liveness(pid) if liveness.is_empty() else liveness

class MW9Reaper:
	extends "res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_repository.gd"
	var after_decision: Callable
	var after_quarantine: Callable
	var liveness: String = ""
	func _lock_is_stale(owner: Dictionary) -> bool:
		var result: bool = super._lock_is_stale(owner)
		if result and after_decision.is_valid():
			after_decision.call()
		return result
	func _read_lock_owner_at(path: String) -> Dictionary:
		var owner: Dictionary = super._read_lock_owner_at(path)
		if path.ends_with(".stale") and after_quarantine.is_valid():
			after_quarantine.call()
		return owner
	func _process_liveness(pid: int) -> String:
		return super._process_liveness(pid) if liveness.is_empty() else liveness

var assertions: int = 0
var failures: Array[String] = []
var observations: Array = []
var root_path: String


func _init() -> void:
	root_path = ProjectSettings.globalize_path("res://artifacts/test-results/lock-reclaim-%d-%d" % [
		OS.get_process_id(), Time.get_ticks_usec()])
	var aba_only: bool = "--case=aba" in OS.get_cmdline_user_args()
	var writer_only: bool = "--case=empty-writer" in OS.get_cmdline_user_args()
	for spec in [["mw10", MW10Reaper], ["mw9", MW9Reaper]]:
		var label: String = spec[0]
		if writer_only:
			_test_interrupted_writer(spec[1], label)
			continue
		_test_delayed_reclaimer(spec[1], label)
		if not aba_only:
			_test_unknown_owner(spec[1], label)
			_test_release_after_reported_error(spec[1], label)
			_test_marker_validation(spec[1], label)
			_test_interrupted_release(spec[1], label)
			_test_interrupted_writer(spec[1], label)
	var report: Dictionary = {
		"test": "matter_repository_lock_reclaim", "assertions": assertions,
		"verdict": "PASS" if failures.is_empty() else "FAIL", "failures": failures,
		"case": "aba" if aba_only else ("empty-writer" if writer_only else "all"), "observations": observations,
	}
	DirAccess.make_dir_recursive_absolute(root_path)
	_write_json(root_path.path_join("report.json"), report)
	print(JSON.stringify(report))
	print("Matter repository lock reclaim: %s (%d assertions, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	# Keep the report, including failures; clean only this run's synthetic locks.
	for subdir in DirAccess.get_directories_at(root_path):
		_remove_tree(root_path.path_join(subdir))
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)
		print("[lock-reclaim][FAIL] %s" % label)


func _repository(script: Script, path: String):
	var repository = script.new()
	var configured: Dictionary = repository.configure(path)
	_check(bool(configured.get("success", false)), "%s:configure" % path.get_file())
	return repository


func _token(result: Dictionary) -> String:
	return String(result.get("details", {}).get("token", ""))


func _legacy_stopped_owner(repository) -> void:
	DirAccess.make_dir_recursive_absolute(repository.lock_path())
	_write_json(repository.lock_path().path_join("owner.json"), {
		"pid": 99999999, "token": "legacy-stopped-owner",
		"created_unix_ms": int(Time.get_unix_time_from_system() * 1000.0) - 3600000,
	})


func _test_delayed_reclaimer(script: Script, label: String) -> void:
	var path: String = root_path.path_join(label + "-aba")
	var delayed = _repository(script, path)
	var reclaimer = _repository(script, path)
	var holder = _repository(script, path)
	var contender = _repository(script, path)
	_legacy_stopped_owner(delayed)
	var state: Dictionary = {"b": {}, "c": {}, "reclaimed_a": false, "quarantine_seen": false}
	delayed.after_decision = func() -> void:
		state["reclaimed_a"] = reclaimer._remove_stale_lock()
		state["b"] = holder._acquire_lock()
	delayed.after_quarantine = func() -> void:
		state["quarantine_seen"] = true
		state["c"] = contender._acquire_lock()
	var stale_result: bool = delayed._remove_stale_lock()
	delayed.after_decision = Callable()
	delayed.after_quarantine = Callable()
	if not bool(state["quarantine_seen"]):
		state["c"] = contender._acquire_lock()
	_check(bool(state["reclaimed_a"]), label + ":old-owner-reclaimed")
	_check(bool(state["b"].get("success", false)), label + ":live-b-acquired")
	_check(not bool(state["c"].get("success", false)), label + ":c-must-not-acquire-before-b-release")
	var current: Dictionary = holder._read_lock_owner()
	_check(String(current.get("token", "")) == _token(state["b"]), label + ":b-marker-must-survive")
	var released: Dictionary = holder._release_lock(_token(state["b"]))
	_check(bool(released.get("success", false)), label + ":b-must-release-own-lock")
	observations.append({"repository": label, "case": "delayed-reclaimer",
		"stale_result": stale_result, "quarantine_seen": state["quarantine_seen"],
		"b_acquire": state["b"], "c_acquire_before_b_release": state["c"], "b_release": released})
	if bool(state["c"].get("success", false)):
		contender._release_lock(_token(state["c"]))
	var next: Dictionary = contender._acquire_lock()
	_check(bool(next.get("success", false)), label + ":c-can-acquire-after-release")
	_check(bool(contender._release_lock(_token(next)).get("success", false)), label + ":c-release")


func _test_unknown_owner(script: Script, label: String) -> void:
	var repository = _repository(script, root_path.path_join(label + "-unknown"))
	_legacy_stopped_owner(repository)
	repository.liveness = "UNKNOWN"
	_check(not repository._remove_stale_lock(), label + ":unknown-owner-never-reclaimed-by-age")
	_check(FileAccess.file_exists(repository.lock_path().path_join("owner.json")), label + ":unknown-owner-marker-preserved")
	repository.liveness = "STOPPED"
	_check(repository._remove_stale_lock(), label + ":confirmed-stopped-legacy-owner-reclaimed")


func _test_release_after_reported_error(script: Script, label: String) -> void:
	var path: String = root_path.path_join(label + "-release")
	var first = _repository(script, path)
	var second = _repository(script, path)
	var acquired: Dictionary = first._acquire_lock()
	_check(bool(acquired.get("success", false)), label + ":release-a-acquired")
	var state: Dictionary = {"b": {}, "moved": false}
	first._lock_release_rename_override = func(source: String, destination: String) -> int:
		if bool(state["moved"]):
			return ERR_BUSY
		var error: int = DirAccess.rename_absolute(source, destination)
		if error != OK:
			return error
		state["moved"] = true
		# On the new protocol source is a unique file; only empty-dir cleanup.
		DirAccess.remove_absolute(first.lock_path())
		state["b"] = second._acquire_lock()
		return ERR_BUSY
	var result: Dictionary = first._release_lock(_token(acquired))
	first._lock_release_rename_override = Callable()
	_check(bool(result.get("success", false)), label + ":reported-error-after-move-is-released")
	_check(bool(state["b"].get("success", false)), label + ":release-b-acquired")
	_check(String(second._read_lock_owner().get("token", "")) == _token(state["b"]), label + ":release-must-not-touch-successor")
	_check(bool(second._release_lock(_token(state["b"])).get("success", false)), label + ":release-b-completes")


func _test_marker_validation(script: Script, label: String) -> void:
	var repository = _repository(script, root_path.path_join(label + "-marker"))
	var acquired: Dictionary = repository._acquire_lock()
	_check(bool(acquired.get("success", false)), label + ":marker-acquired")
	var owner: Dictionary = repository._read_lock_owner()
	var marker: String = String(owner.get("_owner_file_name", "owner.json"))
	_check(marker == "owner-%s.json" % _token(acquired), label + ":marker-binds-unique-token")
	_check(_token(acquired).length() == 64, label + ":token-is-256-bit-identity")
	_check(not bool(repository._release_lock("../wrong").get("success", false)), label + ":invalid-release-token-rejected")
	_write_json(repository.lock_path().path_join("extra.json"), {})
	_check(not repository._remove_stale_lock(), label + ":ambiguous-owner-fails-closed")
	_check(FileAccess.file_exists(repository.lock_path().path_join(marker)), label + ":ambiguous-marker-preserved")
	DirAccess.remove_absolute(repository.lock_path().path_join("extra.json"))
	_check(bool(repository._release_lock(_token(acquired)).get("success", false)), label + ":marker-release")


func _test_interrupted_release(script: Script, label: String) -> void:
	var repository = _repository(script, root_path.path_join(label + "-interrupted-release"))
	var acquired: Dictionary = repository._acquire_lock()
	_check(bool(acquired.get("success", false)), label + ":interrupted-acquired")
	var owner: Dictionary = repository._read_lock_owner()
	var marker: String = String(owner.get("_owner_file_name", "owner.json"))
	var moved: int = DirAccess.rename_absolute(repository.lock_path().path_join(marker),
		repository.lock_path().get_base_dir().path_join("released-marker.json"))
	_check(moved == OK, label + ":interrupted-marker-moved")
	_check(bool(repository._wait_for_unlock().get("success", false)), label + ":empty-released-directory-does-not-block-reader")


func _test_interrupted_writer(script: Script, label: String) -> void:
	var repository = _repository(script, root_path.path_join(label + "-empty-writer"))
	var acquired: Dictionary = repository._acquire_lock()
	_check(bool(acquired.get("success", false)), label + ":empty-writer-acquired")
	var owner: Dictionary = repository._read_lock_owner()
	var marker: String = String(owner.get("_owner_file_name", "owner.json"))
	var moved: int = DirAccess.rename_absolute(repository.lock_path().path_join(marker),
		repository.lock_path().get_base_dir().path_join("released-marker.json"))
	_check(moved == OK, label + ":empty-writer-marker-moved")
	# Exercise the writer's fallback directly, so Linux rename-over-empty
	# cannot mask a missing cleanup step on Windows. No sleep or old mtime.
	_check(repository._remove_stale_lock(), label + ":fresh-empty-writer-lock-reclaimed")
	_check(not DirAccess.dir_exists_absolute(repository.lock_path()), label + ":fresh-empty-writer-directory-removed")
	var successor: Dictionary = repository._acquire_lock()
	_check(bool(successor.get("success", false)), label + ":empty-writer-successor-acquired")
	_check(bool(repository._release_lock(_token(successor)).get("success", false)), label + ":empty-writer-successor-released")


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "fixture-write:" + path)
		return
	file.store_string(JSON.stringify(value))
	file.flush()
	file.close()


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)
