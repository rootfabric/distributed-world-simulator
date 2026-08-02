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
const RETRY_DELAY_MS := 5
const LOCK_STALE_AFTER_MS := 30000
const PENDING_STALE_AFTER_SECONDS := 30

var _root_path := ""
var _active_path := ""
var _previous_path := ""
var _lock_path := ""


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
	var token: String = "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var candidate: String = _root_path.path_join(".matter-handoff-state.lock.%s.candidate" % token)
	_remove_directory(candidate)
	if DirAccess.make_dir_absolute(candidate) != OK:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_CANDIDATE_CREATE_FAILED")
	var owner: Dictionary = {
		"pid": OS.get_process_id(),
		"token": token,
		"created_unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
	}
	var owner_file := FileAccess.open(candidate.path_join(LOCK_OWNER_FILE_NAME), FileAccess.WRITE)
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
	for _attempt in range(MAX_LOCK_ATTEMPTS):
		if DirAccess.rename_absolute(candidate, _lock_path) == OK:
			return MatterUtils.success({"token": token})
		_remove_stale_lock()
		OS.delay_msec(RETRY_DELAY_MS)
	_remove_directory(candidate)
	return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_TIMEOUT")


func _release_lock(token: String) -> Dictionary:
	var owner: Dictionary = _read_lock_owner()
	if int(owner.get("pid", -1)) != OS.get_process_id() or String(owner.get("token", "")) != token:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_OWNERSHIP_MISMATCH")
	_remove_file(_lock_path.path_join(LOCK_OWNER_FILE_NAME))
	if DirAccess.remove_absolute(_lock_path) != OK:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_RELEASE_FAILED")
	return MatterUtils.success()


func _wait_for_unlock() -> Dictionary:
	for _attempt in range(MAX_LOCK_ATTEMPTS):
		if not DirAccess.dir_exists_absolute(_lock_path):
			return MatterUtils.success()
		_remove_stale_lock()
		if not DirAccess.dir_exists_absolute(_lock_path):
			return MatterUtils.success()
		OS.delay_msec(RETRY_DELAY_MS)
	return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LOCK_TIMEOUT")


func _remove_stale_lock() -> bool:
	if not DirAccess.dir_exists_absolute(_lock_path):
		return false
	var owner: Dictionary = _read_lock_owner()
	var pid: int = int(owner.get("pid", -1))
	var created_unix_ms: int = int(owner.get("created_unix_ms", 0))
	if pid == OS.get_process_id():
		return false
	if pid > 0 and OS.get_name() == "Linux" and DirAccess.dir_exists_absolute("/proc/%d" % pid):
		return false
	var now_unix_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	if created_unix_ms > 0 and now_unix_ms - created_unix_ms < LOCK_STALE_AFTER_MS:
		return false
	_remove_file(_lock_path.path_join(LOCK_OWNER_FILE_NAME))
	return DirAccess.remove_absolute(_lock_path) == OK


func _pending_is_stale(path: String) -> bool:
	var modified_seconds: int = int(FileAccess.get_modified_time(path))
	if modified_seconds <= 0:
		return false
	var now_seconds: int = int(Time.get_unix_time_from_system())
	return now_seconds - modified_seconds >= PENDING_STALE_AFTER_SECONDS


func _read_lock_owner() -> Dictionary:
	var path: String = _lock_path.path_join(LOCK_OWNER_FILE_NAME)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


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


func _remove_file(path: String) -> bool:
	return not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK


func _remove_directory(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	var owner_path: String = path.path_join(LOCK_OWNER_FILE_NAME)
	_remove_file(owner_path)
	return DirAccess.remove_absolute(path) == OK


func _global_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
