extends SceneTree

# Deterministic MW10 cross-region repository lock-lifecycle probe.
# Baseline (pre-repair source) must FAIL with exactly the predicted
# ownerless-grace-fence and atomic-release failures; the repaired candidate
# must PASS. Runs fully in-process against a temporary repository root.

const Repository = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_repository.gd")
const LOCK_OWNER_FILE_NAME := "owner.json"
const TRANSIENT_RELEASE_FAILURES := 3

var assertions := 0
var failures: Array[String] = []
var _remaining_release_failures := 0
var _injected_release_failures := 0
var _root_path := ""


func _init() -> void:
	_root_path = ProjectSettings.globalize_path(
		"user://mw10-lock-lifecycle-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_remove_tree(_root_path)
	_test_ownerless_grace_fence()
	_test_atomic_release_retry()
	_test_stale_reclaim_and_live_protection()
	_test_sequential_reacquire()
	_remove_tree(_root_path)
	var report := {
		"test": "mw10_lock_lifecycle",
		"assertions": assertions,
		"failures": failures,
		"verdict": "PASS" if failures.is_empty() else "FAIL",
	}
	print(JSON.stringify(report))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _configure() -> Variant:
	var repository := Repository.new()
	var configured: Dictionary = repository.configure(_root_path)
	if not bool(configured.get("success", false)):
		_assert(false, "configure:repository-configure-failed:%s" % JSON.stringify(configured))
		return null
	return repository


# Case 1: the ownerless-window artifact (live acquired lock whose owner.json
# is missing, exactly what the old in-place release or an interrupted write
# produced) must NOT be treated as a stale lock by another instance.
func _test_ownerless_grace_fence() -> void:
	var holder = _configure()
	if holder == null:
		return
	var acquired: Dictionary = holder.call("_acquire_lock")
	if not bool(acquired.get("success", false)):
		_assert(false, "ownerless-grace-fence:acquire-failed")
		return
	DirAccess.remove_absolute(String(holder.lock_path()).path_join(LOCK_OWNER_FILE_NAME))
	var contender = _configure()
	if contender == null:
		return
	var removed: bool = contender.call("_remove_stale_lock")
	_assert(removed == false, "ownerless-grace-fence:stale-removal-must-refuse")
	_assert(DirAccess.dir_exists_absolute(String(holder.lock_path())), "ownerless-grace-fence:live-lock-must-survive")
	holder.call("_release_lock", String(acquired.get("details", {}).get("token", "")))


# Case 2: release must survive transient rename failures through the atomic
# namespace rename and never leave an ownerless canonical window.
func _test_atomic_release_retry() -> void:
	var repository = _configure()
	if repository == null:
		return
	var acquired: Dictionary = repository.call("_acquire_lock")
	if not bool(acquired.get("success", false)):
		_assert(false, "atomic-release-retry:acquire-failed")
		return
	var token: String = String(acquired.get("details", {}).get("token", ""))
	_remaining_release_failures = TRANSIENT_RELEASE_FAILURES
	_injected_release_failures = 0
	repository.set("_lock_release_rename_override", Callable(self, "_rename_with_transient_failures"))
	var released: Dictionary = repository.call("_release_lock", token)
	repository.set("_lock_release_rename_override", Callable())
	_assert(bool(released.get("success", false)), "atomic-release-retry:transient-failures-escape-retry")
	_assert(int(released.get("details", {}).get("attempts", 0)) == TRANSIENT_RELEASE_FAILURES + 1,
		"atomic-release-retry:attempts-bounded")
	_assert(bool(released.get("details", {}).get("released_atomically", false)),
		"atomic-release-retry:released-atomically")
	_assert(not DirAccess.dir_exists_absolute(String(repository.lock_path())),
		"atomic-release-retry:canonical-residue")
	var released_path: String = _root_path.path_join(
		".matter-cross-region-transactions.lock.%s.released" % token
	)
	_assert(not DirAccess.dir_exists_absolute(released_path),
		"atomic-release-retry:released-residue")
	_assert(_injected_release_failures == TRANSIENT_RELEASE_FAILURES,
		"atomic-release-retry:injection-count")


# Case 3: genuinely stale locks (dead pid, aged owner) are still reclaimed;
# a live self-owned lock never is.
func _test_stale_reclaim_and_live_protection() -> void:
	var repository = _configure()
	if repository == null:
		return
	var lock_path: String = String(repository.lock_path())
	DirAccess.make_dir_recursive_absolute(lock_path)
	var stale_owner := JSON.stringify({
		"pid": 99999999,
		"token": "99999999-1",
		"created_unix_ms": int(Time.get_unix_time_from_system() * 1000.0) - 60000,
	})
	var owner_file := FileAccess.open(lock_path.path_join(LOCK_OWNER_FILE_NAME), FileAccess.WRITE)
	owner_file.store_string(stale_owner)
	owner_file.close()
	_assert(bool(repository.call("_remove_stale_lock")), "stale-reclaim:dead-owner-reclaimed")
	_assert(not DirAccess.dir_exists_absolute(lock_path), "stale-reclaim:canonical-freed")
	var acquired: Dictionary = repository.call("_acquire_lock")
	_assert(bool(acquired.get("success", false)), "stale-reclaim:reacquire-after-reclaim")
	_assert(bool(not repository.call("_remove_stale_lock")), "stale-reclaim:live-self-lock-protected")
	_assert(DirAccess.dir_exists_absolute(lock_path), "stale-reclaim:live-self-lock-survives")
	repository.call("_release_lock", String(acquired.get("details", {}).get("token", "")))


# Case 4: after a clean release another instance must acquire and release
# without interference from release residue.
func _test_sequential_reacquire() -> void:
	var first = _configure()
	if first == null:
		return
	var acquired: Dictionary = first.call("_acquire_lock")
	var token: String = String(acquired.get("details", {}).get("token", ""))
	var released: Dictionary = first.call("_release_lock", token)
	_assert(bool(released.get("success", false)), "sequential-reacquire:first-release")
	var second = _configure()
	if second == null:
		return
	var reacquired: Dictionary = second.call("_acquire_lock")
	_assert(bool(reacquired.get("success", false)), "sequential-reacquire:second-acquire")
	var second_released: Dictionary = second.call(
		"_release_lock", String(reacquired.get("details", {}).get("token", ""))
	)
	_assert(bool(second_released.get("success", false)), "sequential-reacquire:second-release")


func _rename_with_transient_failures(source_path: String, destination_path: String) -> int:
	if _remaining_release_failures > 0:
		_remaining_release_failures -= 1
		_injected_release_failures += 1
		return ERR_BUSY
	return DirAccess.rename_absolute(source_path, destination_path)


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
