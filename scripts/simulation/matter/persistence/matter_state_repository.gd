extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CheckpointScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_checkpoint.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")

const ACTIVE_FILE_NAME: String = "matter-state.json"
const PREVIOUS_FILE_NAME: String = "matter-state.previous.json"
const MAX_REPLACE_ATTEMPTS: int = 20
const RETRY_DELAY_MS: int = 5

var _root_path: String = ""
var _active_path: String = ""
var _previous_path: String = ""


func configure(root_path: String) -> Dictionary:
	var normalized: String = root_path.strip_edges()
	if normalized.is_empty():
		return MatterUtilsScript.failure("MATTER_REPOSITORY_PATH_REQUIRED")
	_root_path = _global_path(normalized).simplify_path()
	_active_path = _root_path.path_join(ACTIVE_FILE_NAME)
	_previous_path = _root_path.path_join(PREVIOUS_FILE_NAME)
	var error: int = DirAccess.make_dir_recursive_absolute(_root_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return MatterUtilsScript.failure("MATTER_REPOSITORY_CREATE_FAILED", {"godot_error": error})
	return MatterUtilsScript.success({
		"root_path": _root_path,
		"active_path": _active_path,
		"previous_path": _previous_path,
	})


func save_atomic(checkpoint: Dictionary) -> Dictionary:
	if _active_path.is_empty():
		return MatterUtilsScript.failure("MATTER_REPOSITORY_NOT_CONFIGURED")
	var validation: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(validation.get("success", false)):
		return validation
	if FileAccess.file_exists(_active_path):
		var current: Dictionary = _read_checkpoint(_active_path)
		if not bool(current.get("success", false)):
			return MatterUtilsScript.failure("CURRENT_MATTER_CHECKPOINT_CORRUPTED", {
				"cause": current,
			})
		var progression: Dictionary = CheckpointScript.validate_progression(
			checkpoint, current["details"]["checkpoint"]
		)
		if not bool(progression.get("success", false)):
			return progression
	var prepared: Dictionary = prepare(checkpoint)
	if not bool(prepared.get("success", false)):
		return prepared
	return commit_prepared(String(prepared["details"]["pending_path"]))


func prepare(checkpoint: Dictionary) -> Dictionary:
	if _active_path.is_empty():
		return MatterUtilsScript.failure("MATTER_REPOSITORY_NOT_CONFIGURED")
	var validation: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(validation.get("success", false)):
		return validation
	var pending_path: String = _root_path.path_join(
		".matter-state.%d.%d.pending.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	var encoded: String = PersistenceCodecScript.encode_persistence_json(checkpoint)
	if encoded.is_empty():
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_CANONICAL_ENCODING_FAILED")
	var encoded_bytes: PackedByteArray = encoded.to_utf8_buffer()
	var file := FileAccess.open(pending_path, FileAccess.WRITE)
	if file == null:
		return MatterUtilsScript.failure("MATTER_PENDING_OPEN_FAILED", {
			"path": pending_path,
			"godot_error": FileAccess.get_open_error(),
		})
	file.store_buffer(encoded_bytes)
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		_remove(pending_path)
		return MatterUtilsScript.failure("MATTER_PENDING_WRITE_FAILED", {
			"path": pending_path,
			"godot_error": write_error,
		})
	var verification: Dictionary = _read_checkpoint(pending_path)
	if not bool(verification.get("success", false)):
		_remove(pending_path)
		return MatterUtilsScript.failure("MATTER_PENDING_VERIFY_FAILED", {"cause": verification})
	return MatterUtilsScript.success({
		"pending_path": pending_path,
		"generation": int(checkpoint["generation"]),
	})


func commit_prepared(pending_path: String) -> Dictionary:
	if _active_path.is_empty():
		return MatterUtilsScript.failure("MATTER_REPOSITORY_NOT_CONFIGURED")
	var normalized_pending: String = _global_path(pending_path).simplify_path()
	if normalized_pending.get_base_dir() != _root_path \
		or not normalized_pending.get_file().begins_with(".matter-state.") \
		or not normalized_pending.get_file().ends_with(".pending.json"):
		return MatterUtilsScript.failure("INVALID_MATTER_PENDING_PATH")
	var pending: Dictionary = _read_checkpoint(normalized_pending)
	if not bool(pending.get("success", false)):
		return MatterUtilsScript.failure("MATTER_PENDING_INVALID", {"cause": pending})
	var had_active: bool = FileAccess.file_exists(_active_path)
	if had_active:
		var current: Dictionary = _read_checkpoint(_active_path)
		if not bool(current.get("success", false)):
			return MatterUtilsScript.failure("CURRENT_MATTER_CHECKPOINT_CORRUPTED", {
				"cause": current,
			})
		var progression: Dictionary = CheckpointScript.validate_progression(
			pending["details"]["checkpoint"], current["details"]["checkpoint"]
		)
		if not bool(progression.get("success", false)):
			return progression
	for _attempt in range(MAX_REPLACE_ATTEMPTS):
		if had_active:
			_remove(_previous_path)
			var backup_error: int = DirAccess.rename_absolute(_active_path, _previous_path)
			if backup_error != OK:
				OS.delay_msec(RETRY_DELAY_MS)
				continue
		var replace_error: int = DirAccess.rename_absolute(normalized_pending, _active_path)
		if replace_error == OK:
			var active: Dictionary = _read_checkpoint(_active_path)
			if bool(active.get("success", false)):
				return MatterUtilsScript.success({
					"path": _active_path,
					"previous_path": _previous_path if had_active else "",
					"generation": int(active["details"]["checkpoint"]["generation"]),
				})
			_remove(_active_path)
			if had_active and FileAccess.file_exists(_previous_path):
				DirAccess.rename_absolute(_previous_path, _active_path)
			return MatterUtilsScript.failure("MATTER_COMMIT_VERIFY_FAILED", {"cause": active})
		if had_active and FileAccess.file_exists(_previous_path) \
			and not FileAccess.file_exists(_active_path):
			DirAccess.rename_absolute(_previous_path, _active_path)
		OS.delay_msec(RETRY_DELAY_MS)
	return MatterUtilsScript.failure("MATTER_ATOMIC_REPLACE_FAILED", {
		"pending_path": normalized_pending,
	})


func load_committed() -> Dictionary:
	if _active_path.is_empty():
		return MatterUtilsScript.failure("MATTER_REPOSITORY_NOT_CONFIGURED")
	var pending_files: Array[String] = list_pending_files()
	var active_error: Dictionary = {}
	if FileAccess.file_exists(_active_path):
		var active: Dictionary = _read_checkpoint(_active_path)
		if bool(active.get("success", false)):
			return MatterUtilsScript.success({
				"checkpoint": active["details"]["checkpoint"],
				"source": "ACTIVE",
				"pending_files": pending_files,
			})
		active_error = active
	if FileAccess.file_exists(_previous_path):
		var previous: Dictionary = _read_checkpoint(_previous_path)
		if bool(previous.get("success", false)):
			return MatterUtilsScript.success({
				"checkpoint": previous["details"]["checkpoint"],
				"source": "PREVIOUS_RECOVERY" if not active_error.is_empty() else "PREVIOUS",
				"pending_files": pending_files,
				"active_error": active_error,
			})
		return MatterUtilsScript.failure("MATTER_PREVIOUS_CHECKPOINT_CORRUPTED", {
			"cause": previous,
			"active_error": active_error,
		})
	if not active_error.is_empty():
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_CORRUPTED", {
			"cause": active_error,
			"pending_files": pending_files,
		})
	return MatterUtilsScript.failure("MATTER_CHECKPOINT_NOT_FOUND", {
		"path": _active_path,
		"pending_files": pending_files,
	})


func repair_active_from_previous() -> Dictionary:
	if _active_path.is_empty():
		return MatterUtilsScript.failure("MATTER_REPOSITORY_NOT_CONFIGURED")
	var previous: Dictionary = _read_checkpoint(_previous_path)
	if not bool(previous.get("success", false)):
		return MatterUtilsScript.failure("MATTER_PREVIOUS_CHECKPOINT_UNAVAILABLE", {
			"cause": previous,
		})
	var checkpoint: Dictionary = previous["details"]["checkpoint"]
	var prepared: Dictionary = prepare(checkpoint)
	if not bool(prepared.get("success", false)):
		return prepared
	var pending_path: String = String(prepared["details"]["pending_path"])
	if FileAccess.file_exists(_active_path) and not _remove(_active_path):
		_remove(pending_path)
		return MatterUtilsScript.failure("MATTER_CORRUPTED_ACTIVE_REMOVE_FAILED")
	var replace_error: int = DirAccess.rename_absolute(pending_path, _active_path)
	if replace_error != OK:
		_remove(pending_path)
		return MatterUtilsScript.failure("MATTER_PREVIOUS_RECOVERY_REPLACE_FAILED", {
			"godot_error": replace_error,
		})
	var active: Dictionary = _read_checkpoint(_active_path)
	if not bool(active.get("success", false)):
		_remove(_active_path)
		return MatterUtilsScript.failure("MATTER_PREVIOUS_RECOVERY_VERIFY_FAILED", {
			"cause": active,
		})
	if String(active["details"]["checkpoint"]["checksum"]) != String(checkpoint["checksum"]):
		_remove(_active_path)
		return MatterUtilsScript.failure("MATTER_PREVIOUS_RECOVERY_CHECKSUM_MISMATCH")
	return MatterUtilsScript.success({
		"path": _active_path,
		"generation": int(checkpoint["generation"]),
		"checksum": String(checkpoint["checksum"]),
	})


func list_pending_files() -> Array[String]:
	var result: Array[String] = []
	if _root_path.is_empty():
		return result
	var directory := DirAccess.open(_root_path)
	if directory == null:
		return result
	directory.include_hidden = true
	for file_name in directory.get_files():
		if file_name.begins_with(".matter-state.") and file_name.ends_with(".pending.json"):
			result.append(_root_path.path_join(file_name))
	result.sort()
	return result


func cleanup_pending_files() -> Dictionary:
	var removed: int = 0
	for path in list_pending_files():
		if _remove(path):
			removed += 1
	return MatterUtilsScript.success({"removed": removed})


func root_path() -> String:
	return _root_path


func active_path() -> String:
	return _active_path


func previous_path() -> String:
	return _previous_path


func _read_checkpoint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_FILE_NOT_FOUND", {"path": path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_OPEN_FAILED", {
			"path": path,
			"godot_error": FileAccess.get_open_error(),
		})
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_EMPTY", {"path": path})
	var checkpoint: Dictionary = PersistenceCodecScript.decode_persistence_json(text)
	if checkpoint.is_empty():
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_TRANSPORT_INVALID", {
			"path": path,
		})
	var validation: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(validation.get("success", false)):
		return MatterUtilsScript.failure(
			String(validation.get("error_code", "INVALID_MATTER_CHECKPOINT")),
			{"path": path, "cause": validation}
		)
	return MatterUtilsScript.success({"checkpoint": checkpoint})


func _global_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) \
		if path.begins_with("res://") or path.begins_with("user://") else path


func _remove(path: String) -> bool:
	return not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK
