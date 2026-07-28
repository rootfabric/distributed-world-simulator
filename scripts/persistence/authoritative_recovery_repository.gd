extends RefCounted

const CheckpointScript = preload("res://scripts/persistence/authoritative_checkpoint.gd")

const DEFAULT_FILE_NAME: String = "authoritative-checkpoint.json"
const MAX_REPLACE_ATTEMPTS: int = 20
const RETRY_DELAY_MS: int = 5

var root_path: String = ""
var active_path: String = ""
var previous_path: String = ""
var legacy_world_path: String = ""


func configure(configured_root_path: String) -> Dictionary:
	var normalized: String = configured_root_path.strip_edges()
	if normalized.is_empty():
		return _failure("AUTHORITATIVE_REPOSITORY_PATH_REQUIRED")
	root_path = _global_path(normalized).simplify_path()
	if root_path.is_empty():
		return _failure("AUTHORITATIVE_REPOSITORY_PATH_REQUIRED")
	active_path = root_path.path_join(DEFAULT_FILE_NAME)
	previous_path = root_path.path_join("authoritative-checkpoint.previous.json")
	legacy_world_path = root_path.path_join("world.json")
	var error: int = DirAccess.make_dir_recursive_absolute(root_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return _failure("AUTHORITATIVE_REPOSITORY_CREATE_FAILED", {"godot_error": error})
	return _success({"root_path": root_path, "active_path": active_path})


func save_atomic(checkpoint: Dictionary) -> Dictionary:
	if active_path.is_empty():
		return _failure("AUTHORITATIVE_REPOSITORY_NOT_CONFIGURED")
	var validation: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_AUTHORITATIVE_CHECKPOINT")), {"message": String(validation.get("message", ""))})
	if FileAccess.file_exists(active_path):
		var current_result: Dictionary = _read_checkpoint(active_path)
		if not bool(current_result.get("success", false)):
			return _failure("CURRENT_AUTHORITATIVE_CHECKPOINT_CORRUPTED", {"cause": current_result})
		var progression: Dictionary = CheckpointScript.validate_progression(checkpoint, current_result["details"]["checkpoint"])
		if not bool(progression.get("success", false)):
			return _failure(String(progression.get("error_code", "AUTHORITATIVE_CHECKPOINT_ROLLBACK")), {"message": String(progression.get("message", ""))})
	var prepared: Dictionary = prepare(checkpoint)
	if not bool(prepared.get("success", false)):
		return prepared
	return commit_prepared(String(prepared["details"]["pending_path"]))


func prepare(checkpoint: Dictionary) -> Dictionary:
	if active_path.is_empty():
		return _failure("AUTHORITATIVE_REPOSITORY_NOT_CONFIGURED")
	var validation: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_AUTHORITATIVE_CHECKPOINT")), {"message": String(validation.get("message", ""))})
	var pending_path: String = root_path.path_join(
		".authoritative-checkpoint.%d.%d.pending.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	var encoded: String = JSON.stringify(checkpoint, "", true, true) + "\n"
	var file := FileAccess.open(pending_path, FileAccess.WRITE)
	if file == null:
		return _failure("AUTHORITATIVE_PENDING_OPEN_FAILED", {"path": pending_path, "godot_error": FileAccess.get_open_error()})
	file.store_string(encoded)
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		_remove(pending_path)
		return _failure("AUTHORITATIVE_PENDING_WRITE_FAILED", {"path": pending_path, "godot_error": write_error})
	var verify: Dictionary = _read_checkpoint(pending_path)
	if not bool(verify.get("success", false)):
		_remove(pending_path)
		return _failure("AUTHORITATIVE_PENDING_VERIFY_FAILED", {"cause": verify})
	return _success({"pending_path": pending_path, "generation": int(checkpoint["generation"])})


func commit_prepared(pending_path: String) -> Dictionary:
	if active_path.is_empty():
		return _failure("AUTHORITATIVE_REPOSITORY_NOT_CONFIGURED")
	var normalized_pending: String = _global_path(pending_path).simplify_path()
	if normalized_pending.get_base_dir() != root_path or not normalized_pending.get_file().ends_with(".pending.json"):
		return _failure("INVALID_AUTHORITATIVE_PENDING_PATH")
	var pending_result: Dictionary = _read_checkpoint(normalized_pending)
	if not bool(pending_result.get("success", false)):
		return _failure("AUTHORITATIVE_PENDING_INVALID", {"cause": pending_result})
	var had_active: bool = FileAccess.file_exists(active_path)
	for _attempt in range(MAX_REPLACE_ATTEMPTS):
		if had_active:
			_remove(previous_path)
			var backup_error: int = DirAccess.rename_absolute(active_path, previous_path)
			if backup_error != OK:
				OS.delay_msec(RETRY_DELAY_MS)
				continue
		var replace_error: int = DirAccess.rename_absolute(normalized_pending, active_path)
		if replace_error == OK:
			var active_result: Dictionary = _read_checkpoint(active_path)
			if bool(active_result.get("success", false)):
				return _success({
					"path": active_path,
					"previous_path": previous_path if had_active else "",
					"generation": int(active_result["details"]["checkpoint"]["generation"]),
				})
			_remove(active_path)
			if had_active and FileAccess.file_exists(previous_path):
				DirAccess.rename_absolute(previous_path, active_path)
			return _failure("AUTHORITATIVE_COMMIT_VERIFY_FAILED", {"cause": active_result})
		if had_active and FileAccess.file_exists(previous_path) and not FileAccess.file_exists(active_path):
			DirAccess.rename_absolute(previous_path, active_path)
		OS.delay_msec(RETRY_DELAY_MS)
	return _failure("AUTHORITATIVE_ATOMIC_REPLACE_FAILED", {"pending_path": normalized_pending})


func load_committed() -> Dictionary:
	if active_path.is_empty():
		return _failure("AUTHORITATIVE_REPOSITORY_NOT_CONFIGURED")
	var pending_files: Array[String] = list_pending_files()
	if FileAccess.file_exists(active_path):
		var active_result: Dictionary = _read_checkpoint(active_path)
		if not bool(active_result.get("success", false)):
			return _failure("AUTHORITATIVE_CHECKPOINT_CORRUPTED", {"path": active_path, "cause": active_result, "pending_files": pending_files})
		return _success({"checkpoint": active_result["details"]["checkpoint"], "source": "ACTIVE", "pending_files": pending_files})
	if FileAccess.file_exists(previous_path):
		var previous_result: Dictionary = _read_checkpoint(previous_path)
		if not bool(previous_result.get("success", false)):
			return _failure("AUTHORITATIVE_PREVIOUS_CHECKPOINT_CORRUPTED", {"path": previous_path, "cause": previous_result})
		return _success({"checkpoint": previous_result["details"]["checkpoint"], "source": "PREVIOUS", "pending_files": pending_files})
	if FileAccess.file_exists(legacy_world_path):
		return _failure("LEGACY_WORLD_STATE_REQUIRES_MIGRATION", {
			"legacy_path": legacy_world_path,
			"expected_checkpoint_path": active_path,
			"action": "backup_or_clear_legacy_world_state_before_authoritative_recovery",
		})
	return _failure("AUTHORITATIVE_CHECKPOINT_NOT_FOUND", {"path": active_path, "pending_files": pending_files})


func list_pending_files() -> Array[String]:
	var result: Array[String] = []
	if root_path.is_empty():
		return result
	var directory := DirAccess.open(root_path)
	if directory == null:
		return result
	directory.include_hidden = true
	for file_name in directory.get_files():
		if file_name.begins_with(".authoritative-checkpoint.") and file_name.ends_with(".pending.json"):
			result.append(root_path.path_join(file_name))
	result.sort()
	return result


func cleanup_pending_files() -> Dictionary:
	var removed: int = 0
	for path in list_pending_files():
		if _remove(path):
			removed += 1
	return _success({"removed": removed})


func _read_checkpoint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("AUTHORITATIVE_CHECKPOINT_FILE_NOT_FOUND", {"path": path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("AUTHORITATIVE_CHECKPOINT_OPEN_FAILED", {"path": path, "godot_error": FileAccess.get_open_error()})
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return _failure("AUTHORITATIVE_CHECKPOINT_EMPTY", {"path": path})
	var parser := JSON.new()
	var error: int = parser.parse(text)
	if error != OK or not parser.data is Dictionary:
		return _failure("AUTHORITATIVE_CHECKPOINT_JSON_INVALID", {"path": path, "line": parser.get_error_line(), "message": parser.get_error_message()})
	var checkpoint: Dictionary = Dictionary(parser.data)
	var validation: Dictionary = CheckpointScript.validate(checkpoint)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_AUTHORITATIVE_CHECKPOINT")), {"path": path, "message": String(validation.get("message", ""))})
	return _success({"checkpoint": checkpoint})


func _global_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path


func _remove(path: String) -> bool:
	return not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
