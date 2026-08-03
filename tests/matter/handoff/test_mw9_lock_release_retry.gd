extends SceneTree

const Repository = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_repository.gd")
const TRANSIENT_RELEASE_FAILURES := 3

var assertions := 0
var failures: Array[String] = []
var _remaining_release_failures := 0
var _injected_release_failures := 0


func _init() -> void:
	var root_path: String = ProjectSettings.globalize_path(
		"user://mw9-lock-release-retry-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_remove_tree(root_path)
	var repository := Repository.new()
	_assert_ok(repository.configure(root_path), "Repository configuration failed")
	var acquired: Dictionary = repository.call("_acquire_lock")
	_assert_ok(acquired, "Repository lock acquisition failed")
	var token: String = String(acquired.get("details", {}).get("token", ""))
	_assert(not token.is_empty(), "Repository lock token missing")
	_assert(DirAccess.dir_exists_absolute(repository.lock_path()), "Canonical repository lock missing")

	_remaining_release_failures = TRANSIENT_RELEASE_FAILURES
	_injected_release_failures = 0
	repository.set(
		"_lock_release_rename_override",
		Callable(self, "_rename_with_transient_release_failures")
	)
	var released: Dictionary = repository.call("_release_lock", token)
	repository.set("_lock_release_rename_override", Callable())

	_assert_ok(released, "Transient release rename failures escaped retry policy")
	_assert(
		int(released.get("details", {}).get("attempts", 0)) == TRANSIENT_RELEASE_FAILURES + 1,
		"Release retry attempt count changed"
	)
	_assert(
		_injected_release_failures == TRANSIENT_RELEASE_FAILURES,
		"Release fault injection count changed"
	)
	_assert(
		bool(released.get("details", {}).get("released_atomically", false)),
		"Release stopped using atomic namespace rename"
	)
	_assert(
		not bool(released.get("details", {}).get("cleanup_deferred", true)),
		"Release left deferred cleanup"
	)
	_assert(
		not DirAccess.dir_exists_absolute(repository.lock_path()),
		"Release retry left canonical lock residue"
	)
	var released_path: String = root_path.path_join(
		".matter-handoff-state.lock.%s.released" % token
	)
	_assert(
		not DirAccess.dir_exists_absolute(released_path),
		"Release retry left quarantine residue"
	)
	_assert(
		not FileAccess.file_exists(repository.lock_path().path_join("owner.json")),
		"Release retry left owner metadata residue"
	)

	_remove_tree(root_path)
	if failures.is_empty():
		print("MW9 lock release retry: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"MW9 lock release retry: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)


func _rename_with_transient_release_failures(
	source_path: String,
	destination_path: String
) -> int:
	if _remaining_release_failures > 0:
		_remaining_release_failures -= 1
		_injected_release_failures += 1
		return ERR_BUSY
	return DirAccess.rename_absolute(source_path, destination_path)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(
		bool(result.get("success", false)),
		"%s: %s" % [message, JSON.stringify(result)]
	)


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
