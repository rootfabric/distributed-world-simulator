extends RefCounted

const MAX_REPLACE_ATTEMPTS := 20
const RETRY_DELAY_MS := 5


static func write_dictionary(path: String, value: Dictionary, pretty := true) -> Dictionary:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		return _failure("ATOMIC_JSON_PATH_EMPTY", "JSON path cannot be empty")
	var directory := normalized_path.get_base_dir()
	if not directory.is_empty():
		var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
		if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
			return _failure("ATOMIC_JSON_DIRECTORY_FAILED", "Cannot create report directory: %s" % directory)
	var suffix := "%d.%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var temporary_path := "%s.tmp.%s" % [normalized_path, suffix]
	var backup_path := "%s.bak.%s" % [normalized_path, suffix]
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("ATOMIC_JSON_TEMP_OPEN_FAILED", "Cannot open temporary report: %s" % temporary_path)
	file.store_string(JSON.stringify(value, "  " if pretty else "", true, true) + "\n")
	file.flush()
	file.close()
	var verified := read_dictionary(temporary_path)
	if not bool(verified.get("success", false)):
		DirAccess.remove_absolute(temporary_path)
		return _failure("ATOMIC_JSON_TEMP_VERIFY_FAILED", "Temporary report is not valid JSON")
	for _attempt in range(MAX_REPLACE_ATTEMPTS):
		var had_target := FileAccess.file_exists(normalized_path)
		if had_target:
			if FileAccess.file_exists(backup_path):
				DirAccess.remove_absolute(backup_path)
			var backup_error := DirAccess.rename_absolute(normalized_path, backup_path)
			if backup_error != OK:
				OS.delay_msec(RETRY_DELAY_MS)
				continue
		var replace_error := DirAccess.rename_absolute(temporary_path, normalized_path)
		if replace_error == OK:
			if FileAccess.file_exists(backup_path):
				DirAccess.remove_absolute(backup_path)
			return {"success": true}
		if had_target and FileAccess.file_exists(backup_path) and not FileAccess.file_exists(normalized_path):
			DirAccess.rename_absolute(backup_path, normalized_path)
		OS.delay_msec(RETRY_DELAY_MS)
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(normalized_path):
		DirAccess.rename_absolute(backup_path, normalized_path)
	return _failure("ATOMIC_JSON_REPLACE_FAILED", "Cannot atomically replace report: %s" % normalized_path)


static func read_dictionary(path: String) -> Dictionary:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return {"success": false, "error_code": "ATOMIC_JSON_NOT_FOUND", "value": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"success": false, "error_code": "ATOMIC_JSON_OPEN_FAILED", "value": {}}
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return {"success": false, "error_code": "ATOMIC_JSON_EMPTY", "value": {}}
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK or not parser.data is Dictionary:
		return {"success": false, "error_code": "ATOMIC_JSON_INCOMPLETE", "value": {}}
	return {"success": true, "value": Dictionary(parser.data).duplicate(true)}


static func read_value(path: String) -> Dictionary:
	var result := read_dictionary(path)
	if not bool(result.get("success", false)):
		return {}
	return Dictionary(result.get("value", {})).duplicate(true)


static func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message}
