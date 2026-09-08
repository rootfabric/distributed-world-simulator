extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Checkpoint = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_checkpoint.gd")
const PersistenceCodec = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")

const ACTIVE_FILE_NAME := "matter-handoff-state.json"
const PREVIOUS_FILE_NAME := "matter-handoff-state.previous.json"
const LOCK_DIRECTORY_NAME := ".matter-handoff-state.lock"
const LOCK_OWNER_FILE_NAME := "owner.json"
const MAX_REPLACE_ATTEMPTS := 20
const MAX_LOCK_ATTEMPTS := 1000
const MAX_LOCK_RELEASE_ATTEMPTS := 200
const RETRY_DELAY_MS := 5
const LOCK_STALE_AFTER_MS := 30000
const PENDING_STALE_AFTER_SECONDS := 30

var _root_path := ""
var _active_path := ""
var _previous_path := ""
var _lock_path := ""
var _lock_release_rename_override: Callable = Callable()


func configure(root_path: String) -> Dictionary:
	var normalized: String = root_path.strip_edges()
	if normalized.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPOSITORY_PATH_REQUIRED")
	_root_path = _global_path(normalized).simplify_path()
	_active_path = _root_path.path_join(ACTIVE_FILE_NAME)
	_previous_path = _root_path.path_join(PREVIOUS_FILE_NAME)
	_lock_path = _root_path.path_join(LOCK_DIRECTORY_NAME)
	var error: int = DirAccess.make_dir_recursive_absolute(_root_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPOSITORY_CREATE_FAILED", {"godot_error": error})
	return MatterUtils.success({
		"root_path": _root_path,
		"active_path": _active_path,
		"previous_path": _previous_path,
		"lock_path": _lock_path,
	})


func save_atomic(checkpoint: Dictionary) -> Dictionary:
	if _active_path.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPOSITORY_NOT_CONFIGURED")
	var checked: Dictionary = Checkpoint.validate(checkpoint)
	if not bool(checked.get("success", false)):
		return checked
	if FileAccess.file_exists(_active_path):
		var current: Dictionary = _read_checkpoint(_active_path)
		if not bool(current.get("success", false)):
			return MatterUtils.failure("CURRENT_MATTER_DURABLE_HANDOFF_CHECKPOINT_CORRUPTED", {"cause": current})
		checked = Checkpoint.validate_progression(checkpoint, current["details"]["checkpoint"])
		if not bool(checked.get("success", false)):
			return checked
	var prepared: Dictionary = prepare(checkpoint)
	if not bool(prepared.get("success", false)):
		return prepared
	var pending_path: String = String(prepared["details"]["pending_path"])
	var committed: Dictionary = commit_prepared(pending_path)
	if not bool(committed.get("success", false)):
		_remove_file(pending_path)
	return committed


func prepare(checkpoint: Dictionary) -> Dictionary:
	if _active_path.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPOSITORY_NOT_CONFIGURED")
	var checked: Dictionary = Checkpoint.validate(checkpoint)
	if not bool(checked.get("success", false)):
		return checked
	var pending_path: String = _root_path.path_join(
		".matter-handoff-state.%d.%d.pending.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	var encoded: String = PersistenceCodec.encode_persistence_json(checkpoint)
	if encoded.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_ENCODING_FAILED")
	var file := FileAccess.open(pending_path, FileAccess.WRITE)
	if file == null:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_PENDING_OPEN_FAILED", {"godot_error": FileAccess.get_open_error()})
	file.store_buffer(encoded.to_utf8_buffer())
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(pending_path)
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_PENDING_WRITE_FAILED", {"godot_error": write_error})
	var verification: Dictionary = _read_checkpoint(pending_path)
	if not bool(verification.get("success", false)):
		_remove_file(pending_path)
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_PENDING_VERIFY_FAILED", {"cause": verification})
	return MatterUtils.success({"pending_path": pending_path, "generation": int(checkpoint["generation"])})


func commit_prepared(pending_path: String) -> Dictionary:
	if _active_path.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPOSITORY_NOT_CONFIGURED")
	var normalized_pending: String = _global_path(pending_path).simplify_path()
	if normalized_pending.get_base_dir() != _root_path \
		or not normalized_pending.get_file().begins_with(".matter-handoff-state.") \
		or not normalized_pending.get_file().ends_with(".pending.json"):
		return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_PENDING_PATH")
	var lock: Dictionary = _acquire_lock()
	if not bool(lock.get("success", false)):
		return lock
	var token: String = String(lock["details"]["token"])
	var result: Dictionary = _commit_prepared_locked(normalized_pending)
	var released: Dictionary = _release_lock(token)
	if not bool(released.get("success", false)) and bool(result.get("success", false)):
		return released
	return result


func load_committed() -> Dictionary:
	if _active_path.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPOSITORY_NOT_CONFIGURED")
	var unlocked: Dictionary = _wait_for_unlock()
	if not bool(unlocked.get("success", false)):
		return unlocked
	var pending_files: Array[String] = list_pending_files()
	var active_error: Dictionary = {}
	if FileAccess.file_exists(_active_path):
		var active: Dictionary = _read_checkpoint(_active_path)
		if bool(active.get("success", false)):
			return MatterUtils.success({
				"checkpoint": active["details"]["checkpoint"],
				"source": "ACTIVE",
				"pending_files": pending_files,
			})
		active_error = active
	if FileAccess.file_exists(_previous_path):
		var previous: Dictionary = _read_checkpoint(_previous_path)
		if bool(previous.get("success", false)):
			return MatterUtils.success({
				"checkpoint": previous["details"]["checkpoint"],
				"source": "PREVIOUS_RECOVERY",
				"pending_files": pending_files,
				"active_error": active_error,
			})
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_PREVIOUS_CHECKPOINT_CORRUPTED", {"cause": previous})
	if not active_error.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_CORRUPTED", {"cause": active_error})
	return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_NOT_FOUND", {"pending_files": pending_files})


func repair_active_from_previous() -> Dictionary:
	if _active_path.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPOSITORY_NOT_CONFIGURED")
	var lock: Dictionary = _acquire_lock()
	if not bool(lock.get("success", false)):
		return lock
	var token: String = String(lock["details"]["token"])
	var result: Dictionary = _repair_active_from_previous_locked()
	var released: Dictionary = _release_lock(token)
	if not bool(released.get("success", false)) and bool(result.get("success", false)):
		return released
	return result


func list_pending_files() -> Array[String]:
	var result: Array[String] = []
	if _root_path.is_empty():
		return result
	var directory := DirAccess.open(_root_path)
	if directory == null:
		return result
	directory.include_hidden = true
	for file_name in directory.get_files():
		if file_name.begins_with(".matter-handoff-state.") and file_name.ends_with(".pending.json"):
			result.append(_root_path.path_join(file_name))
	result.sort()
	return result


func cleanup_pending_files() -> Dictionary:
	var removed := 0
	var preserved := 0
	for path in list_pending_files():
		var owner_pid: int = _pending_owner_pid(path.get_file())
		if owner_pid > 0 and owner_pid != OS.get_process_id() and not _pending_is_stale(path):
			preserved += 1
			continue
		if _remove_file(path):
			removed += 1
	return MatterUtils.success({"removed": removed, "preserved_live": preserved})


func active_path() -> String:
	return _active_path


func previous_path() -> String:
	return _previous_path


func lock_path() -> String:
	return _lock_path


func _commit_prepared_locked(normalized_pending: String) -> Dictionary:
	var pending: Dictionary = _read_checkpoint(normalized_pending)
	if not bool(pending.get("success", false)):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_PENDING_INVALID", {"cause": pending})
	var pending_checkpoint: Dictionary = pending["details"]["checkpoint"]
	var had_active: bool = FileAccess.file_exists(_active_path)
	if had_active:
		var current: Dictionary = _read_checkpoint(_active_path)
		if not bool(current.get("success", false)):
			return MatterUtils.failure("CURRENT_MATTER_DURABLE_HANDOFF_CHECKPOINT_CORRUPTED", {"cause": current})
		var progression: Dictionary = Checkpoint.validate_progression(
			pending_checkpoint, current["details"]["checkpoint"]
		)
		if not bool(progression.get("success", false)):
			return progression
	elif FileAccess.file_exists(_previous_path):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RECOVERY_REQUIRED")
	elif int(pending_checkpoint["generation"]) != 1:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_INITIAL_GENERATION_REQUIRED")
	for _attempt in range(MAX_REPLACE_ATTEMPTS):
		if had_active:
			_remove_file(_previous_path)
			if DirAccess.rename_absolute(_active_path, _previous_path) != OK:
				OS.delay_msec(RETRY_DELAY_MS)
				continue
		var replace_error: int = DirAccess.rename_absolute(normalized_pending, _active_path)
		if replace_error == OK:
			var active: Dictionary = _read_checkpoint(_active_path)
			if bool(active.get("success", false)) \
				and String(active["details"]["checkpoint"]["checksum"]) == String(pending_checkpoint["checksum"]):
				return MatterUtils.success({
					"path": _active_path,
					"previous_path": _previous_path if had_active else "",
					"generation": int(active["details"]["checkpoint"]["generation"]),
				})
			_remove_file(_active_path)
			if had_active and FileAccess.file_exists(_previous_path):
				DirAccess.rename_absolute(_previous_path, _active_path)
			return MatterUtils.failure("MATTER_DURABLE_HANDOFF_COMMIT_VERIFY_FAILED", {"cause": active})
		if had_active and FileAccess.file_exists(_previous_path) and not FileAccess.file_exists(_active_path):
			DirAccess.rename_absolute(_previous_path, _active_path)
		OS.delay_msec(RETRY_DELAY_MS)
	return MatterUtils.failure("MATTER_DURABLE_HANDOFF_ATOMIC_REPLACE_FAILED")


func _repair_active_from_previous_locked() -> Dictionary:
	var previous: Dictionary = _read_checkpoint(_previous_path)
	if not bool(previous.get("success", false)):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_PREVIOUS_UNAVAILABLE", {"cause": previous})
	var checkpoint: Dictionary = previous["details"]["checkpoint"]
	var encoded: String = PersistenceCodec.encode_persistence_json(checkpoint)
	if encoded.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_PREVIOUS_ENCODING_FAILED")
	var temporary: String = _root_path.path_join(".matter-handoff-repair.%d.json" % Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPAIR_OPEN_FAILED")
	file.store_string(encoded)
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(temporary)
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPAIR_WRITE_FAILED", {"godot_error": write_error})
	_remove_file(_active_path)
	if DirAccess.rename_absolute(temporary, _active_path) != OK:
		_remove_file(temporary)
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPAIR_REPLACE_FAILED")
	var active: Dictionary = _read_checkpoint(_active_path)
	if not bool(active.get("success", false)) \
		or String(active["details"]["checkpoint"]["checksum"]) != String(checkpoint["checksum"]):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_REPAIR_VERIFY_FAILED")
	return MatterUtils.success({"path": _active_path, "generation": int(checkpoint["generation"])})


func _acquire_lock() -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	# CSPRNG identity prevents ABA across PID reuse and process restarts.
	var entropy: PackedByteArray = Crypto.new().generate_random_bytes(32)
	if entropy.size() != 32:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_CANDIDATE_CREATE_FAILED")
	var token: String = entropy.hex_encode()
	var candidate: String = _root_path.path_join(".matter-handoff-state.lock.%s.candidate" % token)
	if DirAccess.make_dir_absolute(candidate) != OK:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_CANDIDATE_CREATE_FAILED")
	var owner: Dictionary = {
		"pid": OS.get_process_id(),
		"token": token,
		"created_unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
	}
	var owner_file := FileAccess.open(candidate.path_join(_lock_owner_file_name(token)), FileAccess.WRITE)
	if owner_file == null:
		_remove_directory(candidate)
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_OWNER_WRITE_FAILED")
	owner_file.store_string(JSON.stringify(owner))
	owner_file.flush()
	var owner_error: int = owner_file.get_error()
	owner_file.close()
	if owner_error != OK:
		_remove_directory(candidate)
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_OWNER_WRITE_FAILED")
	var stale_reclaims := 0
	for attempt in range(MAX_LOCK_ATTEMPTS):
		if DirAccess.rename_absolute(candidate, _lock_path) == OK:
			return MatterUtils.success({
				"token": token,
				"attempts": attempt + 1,
				"stale_reclaims": stale_reclaims,
				"waited_ms": Time.get_ticks_msec() - started_msec,
			})
		if _remove_stale_lock():
			stale_reclaims += 1
		OS.delay_msec(RETRY_DELAY_MS)
	_remove_directory(candidate)
	return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_TIMEOUT", {
		"attempts": MAX_LOCK_ATTEMPTS,
		"stale_reclaims": stale_reclaims,
		"waited_ms": Time.get_ticks_msec() - started_msec,
		"observed_owner": _read_lock_owner(),
	})


func _release_lock(token: String) -> Dictionary:
	var owner: Dictionary = _read_lock_owner()
	var file_name: String = _lock_owner_file_name(token)
	if file_name.is_empty() or int(owner.get("pid", -1)) != OS.get_process_id() \
		or String(owner.get("token", "")) != token \
		or String(owner.get("_owner_file_name", "")) != file_name:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_OWNERSHIP_MISMATCH", {
			"expected_pid": OS.get_process_id(), "expected_token": token,
			"observed_owner": owner,
		})
	# The token-addressed file, not the reusable directory name, is the lock.
	# After its atomic removal the critical section is over. rmdir is only
	# cleanup: it cannot remove a successor's populated lock directory.
	var source_path: String = _lock_path.path_join(file_name)
	var released_path: String = _root_path.path_join("%s.%s.released" % [LOCK_DIRECTORY_NAME, token])
	var started_msec: int = Time.get_ticks_msec()
	var last_error: int = OK
	for attempt in range(MAX_LOCK_RELEASE_ATTEMPTS):
		last_error = _rename_lock_for_release(source_path, released_path)
		var moved: bool = last_error == OK
		if not moved:
			# An error reported after a successful move must not cause another
			# attempt against a newer owner. Inspect only our unique receipt.
			var released_owner: Dictionary = _read_lock_owner_file(released_path)
			moved = not FileAccess.file_exists(source_path) \
				and int(released_owner.get("pid", -1)) == OS.get_process_id() \
				and String(released_owner.get("token", "")) == token
		if moved:
			DirAccess.remove_absolute(_lock_path)
			var cleaned: bool = _remove_file(released_path)
			return MatterUtils.success({
				"released_atomically": true, "attempts": attempt + 1,
				"reported_rename_error": last_error,
				"waited_ms": Time.get_ticks_msec() - started_msec,
				"cleanup_deferred": not cleaned,
				"cleanup_path": released_path if not cleaned else "",
			})
		OS.delay_msec(RETRY_DELAY_MS)
	return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_RELEASE_FAILED", {
		"godot_error": last_error, "attempts": MAX_LOCK_RELEASE_ATTEMPTS,
		"waited_ms": Time.get_ticks_msec() - started_msec,
		"observed_owner": _read_lock_owner(),
	})


func _wait_for_unlock() -> Dictionary:
	for _attempt in range(MAX_LOCK_ATTEMPTS):
		if not DirAccess.dir_exists_absolute(_lock_path):
			return MatterUtils.success()
		# A process may stop after removing its marker but before rmdir.
		# Empty-only cleanup is safe against a concurrent populated successor.
		if DirAccess.remove_absolute(_lock_path) == OK:
			return MatterUtils.success()
		_remove_stale_lock()
		if not DirAccess.dir_exists_absolute(_lock_path):
			return MatterUtils.success()
		OS.delay_msec(RETRY_DELAY_MS)
	return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_TIMEOUT")


func _remove_stale_lock() -> bool:
	if not DirAccess.dir_exists_absolute(_lock_path):
		return false
	# A release may have removed its marker but crashed before rmdir.
	# Empty-only removal is safe immediately, including on platforms whose
	# rename cannot replace an empty directory; no age fence is needed.
	if DirAccess.remove_absolute(_lock_path) == OK:
		return true
	var owner: Dictionary = _read_lock_owner()
	if not _lock_is_stale(owner):
		return false
	if owner.is_empty():
		# Empty/malformed reads never authorize removal of any file. Atomic
		# rmdir refuses a nonempty directory, including a newly acquired one.
		return DirAccess.remove_absolute(_lock_path) == OK
	var file_name: String = String(owner.get("_owner_file_name", ""))
	if file_name.is_empty():
		return false
	# A delayed reclaimer of A can address only A's unique marker. Unlike
	# quarantine-renaming the directory, this cannot move or delete B's lock.
	# Legacy owner.json is read-only migration support; old and new writers
	# must never share a repository during a rolling upgrade.
	if DirAccess.remove_absolute(_lock_path.path_join(file_name)) != OK:
		return false
	DirAccess.remove_absolute(_lock_path)
	return true


func _lock_is_stale(owner: Dictionary) -> bool:
	if owner.is_empty():
		var modified_ms: int = int(FileAccess.get_modified_time(_lock_path)) * 1000
		return modified_ms > 0 \
			and int(Time.get_unix_time_from_system() * 1000.0) - modified_ms >= LOCK_STALE_AFTER_MS
	var pid: int = int(owner.get("pid", -1))
	var token: String = String(owner.get("token", ""))
	var created_ms: int = int(owner.get("created_unix_ms", 0))
	if pid <= 0 or token.is_empty() or created_ms <= 0 or pid == OS.get_process_id():
		return false
	if int(Time.get_unix_time_from_system() * 1000.0) - created_ms < LOCK_STALE_AFTER_MS:
		return false
	# Elapsed time is not evidence that an unobservable owner has stopped.
	return _process_liveness(pid) == "STOPPED"


func _process_liveness(pid: int) -> String:
	if pid <= 0:
		return "UNKNOWN"
	if pid == OS.get_process_id():
		return "RUNNING"
	var platform: String = OS.get_name()
	if platform == "Linux":
		return "RUNNING" if DirAccess.dir_exists_absolute("/proc/%d" % pid) else "STOPPED"
	if platform == "Windows":
		var output: Array = []
		var exit_code: int = OS.execute(
			"tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"],
			output, true, false
		)
		if exit_code != 0:
			return "UNKNOWN"
		for chunk in output:
			for line in String(chunk).split("\n", false):
				var columns: PackedStringArray = line.strip_edges().split(",", false)
				if columns.size() >= 2 and columns[1].strip_edges().trim_prefix("\"").trim_suffix("\"") == str(pid):
					return "RUNNING"
		return "STOPPED"
	if platform in ["macOS", "FreeBSD", "NetBSD", "OpenBSD"]:
		var output: Array = []
		var exit_code: int = OS.execute("/bin/kill", ["-0", str(pid)], output, true, false)
		return "RUNNING" if exit_code == 0 else "STOPPED"
	return "UNKNOWN"


func _pending_is_stale(path: String) -> bool:
	var modified_seconds: int = int(FileAccess.get_modified_time(path))
	if modified_seconds <= 0:
		return false
	var now_seconds: int = int(Time.get_unix_time_from_system())
	return now_seconds - modified_seconds >= PENDING_STALE_AFTER_SECONDS


func _read_lock_owner() -> Dictionary:
	return _read_lock_owner_at(_lock_path)


func _read_lock_owner_at(directory_path: String) -> Dictionary:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return {}
	directory.include_hidden = true
	var files: PackedStringArray = directory.get_files()
	if files.size() != 1 or not directory.get_directories().is_empty():
		return {}
	var file_name: String = files[0]
	var owner: Dictionary = _read_lock_owner_file(directory_path.path_join(file_name))
	if owner.is_empty():
		return {}
	if file_name != LOCK_OWNER_FILE_NAME \
		and file_name != _lock_owner_file_name(String(owner.get("token", ""))):
		return {}
	owner["_owner_file_name"] = file_name
	return owner


func _read_lock_owner_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _lock_owner_file_name(token: String) -> String:
	return "owner-%s.json" % token if token.length() == 64 and token.is_valid_hex_number(false) else ""


func _read_checkpoint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_FILE_MISSING", {"path": path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_OPEN_FAILED", {"path": path})
	var encoded: String = file.get_as_text()
	file.close()
	var checkpoint: Dictionary = PersistenceCodec.decode_persistence_json(encoded)
	if checkpoint.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_DECODE_FAILED", {"path": path})
	var checked: Dictionary = Checkpoint.validate(checkpoint)
	if not bool(checked.get("success", false)):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_INVALID", {"path": path, "cause": checked})
	return MatterUtils.success({"checkpoint": checkpoint})


func _pending_owner_pid(file_name: String) -> int:
	var prefix := ".matter-handoff-state."
	var suffix := ".pending.json"
	if not file_name.begins_with(prefix) or not file_name.ends_with(suffix):
		return -1
	var middle: String = file_name.substr(prefix.length(), file_name.length() - prefix.length() - suffix.length())
	var parts: PackedStringArray = middle.split(".", false, 1)
	return int(parts[0]) if parts.size() == 2 and parts[0].is_valid_int() else -1


func _rename_lock_for_release(source_path: String, destination_path: String) -> int:
	if _lock_release_rename_override.is_valid():
		return int(_lock_release_rename_override.call(source_path, destination_path))
	return DirAccess.rename_absolute(source_path, destination_path)


func _remove_file(path: String) -> bool:
	return not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK


func _remove_directory(path: String) -> bool:
	# Only private, unpublished candidates may use file-removing cleanup.
	if path == _lock_path or not path.ends_with(".candidate"):
		return false
	var directory := DirAccess.open(path)
	if directory == null:
		return not DirAccess.dir_exists_absolute(path)
	directory.include_hidden = true
	for file_name in directory.get_files():
		var token: String = file_name.trim_prefix("owner-").trim_suffix(".json")
		if file_name != _lock_owner_file_name(token):
			return false
		if not _remove_file(path.path_join(file_name)):
			return false
	return DirAccess.remove_absolute(path) == OK


func _global_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
