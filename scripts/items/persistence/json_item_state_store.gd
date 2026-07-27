extends "res://scripts/items/persistence/item_state_store.gd"

const FILE_SCHEMA: String = "planet_simulator.item_state_file.v1"
const FILE_SCHEMA_VERSION: int = 1
const DEFAULT_ROOT_PATH: String = "user://planet_simulator/item_states"

var root_path: String = DEFAULT_ROOT_PATH


func _init(custom_root_path: String = DEFAULT_ROOT_PATH) -> void:
	var normalized: String = custom_root_path.strip_edges().replace("\\", "/")
	while normalized.ends_with("/") and not normalized.ends_with("://"):
		normalized = normalized.left(normalized.length() - 1)
	root_path = normalized if not normalized.is_empty() else DEFAULT_ROOT_PATH


func save_state(state_key: String, state: Dictionary) -> Dictionary:
	var payload_result: Dictionary = validate_payload(state)
	if not bool(payload_result.get("success", false)):
		return payload_result
	var key_result: Dictionary = _validate_key(state_key)
	if not bool(key_result.get("success", false)):
		return key_result
	var directory_result: Dictionary = _ensure_root_directory()
	if not bool(directory_result.get("success", false)):
		return directory_result

	var path: String = state_path(state_key)
	var temporary_path: String = path + ".tmp"
	var envelope: Dictionary = {
		"schema": FILE_SCHEMA,
		"schema_version": FILE_SCHEMA_VERSION,
		"state_key": state_key,
		"state": state.duplicate(true),
	}
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("OPEN_FOR_WRITE_FAILED", {
			"path": temporary_path,
			"godot_error": FileAccess.get_open_error(),
		})
	file.store_string(JSON.stringify(envelope, "\t", true, true))
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return _failure("WRITE_FAILED", {
			"path": temporary_path,
			"godot_error": write_error,
		})

	var rename_error: int = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(path)
	)
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return _failure("ATOMIC_RENAME_FAILED", {
			"path": path,
			"godot_error": rename_error,
		})
	return _success({"path": path, "state_key": state_key})


func load_state(state_key: String) -> Dictionary:
	var key_result: Dictionary = _validate_key(state_key)
	if not bool(key_result.get("success", false)):
		return key_result
	var path: String = state_path(state_key)
	if not FileAccess.file_exists(path):
		return _failure("STATE_NOT_FOUND", {"path": path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("OPEN_FOR_READ_FAILED", {
			"path": path,
			"godot_error": FileAccess.get_open_error(),
		})
	var raw_text: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_error: int = parser.parse(raw_text)
	if parse_error != OK:
		return _failure("INVALID_JSON", {
			"path": path,
			"line": parser.get_error_line(),
			"message": parser.get_error_message(),
		})
	var parsed = parser.data
	if not parsed is Dictionary:
		return _failure("INVALID_FILE_ROOT", {"path": path})
	var envelope: Dictionary = Dictionary(parsed)
	if String(envelope.get("schema", "")) != FILE_SCHEMA:
		return _failure("UNSUPPORTED_FILE_SCHEMA", {
			"schema": String(envelope.get("schema", "")),
		})
	if int(envelope.get("schema_version", 0)) != FILE_SCHEMA_VERSION:
		return _failure("UNSUPPORTED_FILE_VERSION", {
			"schema_version": int(envelope.get("schema_version", 0)),
		})
	if String(envelope.get("state_key", "")) != state_key:
		return _failure("STATE_KEY_MISMATCH", {
			"expected": state_key,
			"actual": String(envelope.get("state_key", "")),
		})
	var state_value = envelope.get("state", {})
	if not state_value is Dictionary:
		return _failure("INVALID_STATE_PAYLOAD")
	return _success({
		"path": path,
		"state_key": state_key,
		"state": Dictionary(state_value).duplicate(true),
	})


func delete_state(state_key: String) -> Dictionary:
	var key_result: Dictionary = _validate_key(state_key)
	if not bool(key_result.get("success", false)):
		return key_result
	var path: String = state_path(state_key)
	if not FileAccess.file_exists(path):
		return _success({"deleted": false, "path": path})
	var delete_error: int = DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)
	if delete_error != OK:
		return _failure("DELETE_FAILED", {
			"path": path,
			"godot_error": delete_error,
		})
	return _success({"deleted": true, "path": path})


func has_state(state_key: String) -> bool:
	return bool(_validate_key(state_key).get("success", false)) and FileAccess.file_exists(
		state_path(state_key)
	)


func state_path(state_key: String) -> String:
	var separator: String = "" if root_path.ends_with("/") else "/"
	return "%s%s%s.json" % [root_path, separator, state_key]


func _ensure_root_directory() -> Dictionary:
	var absolute_root: String = ProjectSettings.globalize_path(root_path)
	if DirAccess.dir_exists_absolute(absolute_root):
		return _success()
	var create_error: int = DirAccess.make_dir_recursive_absolute(absolute_root)
	if create_error != OK:
		return _failure("CREATE_DIRECTORY_FAILED", {
			"path": root_path,
			"godot_error": create_error,
		})
	return _success()


func _validate_key(state_key: String) -> Dictionary:
	if state_key.is_empty() or state_key != state_key.strip_edges():
		return _failure("INVALID_STATE_KEY", {"state_key": state_key})
	if state_key == "." or state_key.begins_with(".") or state_key.ends_with("."):
		return _failure("INVALID_STATE_KEY", {"state_key": state_key})
	if state_key.contains(".."):
		return _failure("INVALID_STATE_KEY", {"state_key": state_key})
	for index in range(state_key.length()):
		var code: int = state_key.unicode_at(index)
		var allowed: bool = (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or code in [45, 46, 95]
		)
		if not allowed:
			return _failure("INVALID_STATE_KEY", {"state_key": state_key})
	return _success()
