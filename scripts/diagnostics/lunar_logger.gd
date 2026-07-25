extends Node

const LOG_DIR: String = "user://logs"
const LOG_PATH: String = "user://logs/lunar_simulation.jsonl"
const MAX_LOG_BYTES: int = 2 * 1024 * 1024
const ROTATED_FILE_COUNT: int = 3

var memory_only: bool = false
var session_id: String = ""
var recent_entries: Array[Dictionary] = []
var max_recent_entries: int = 100


func setup(use_memory_only: bool = false) -> void:
	memory_only = use_memory_only
	session_id = "%d-%d" % [
		int(Time.get_unix_time_from_system()),
		Time.get_ticks_msec(),
	]
	if not memory_only:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(LOG_DIR)
		)
		_rotate_if_needed()
	info("application", "logger_started", {
		"session_id": session_id,
		"log_path": LOG_PATH,
	})


func info(category: String, event_name: String, data: Dictionary = {}) -> void:
	_write("INFO", category, event_name, data)


func warning(category: String, event_name: String, data: Dictionary = {}) -> void:
	_write("WARNING", category, event_name, data)


func error(category: String, event_name: String, data: Dictionary = {}) -> void:
	_write("ERROR", category, event_name, data)


func get_log_path() -> String:
	return LOG_PATH


func get_recent_entries() -> Array[Dictionary]:
	return recent_entries.duplicate(true)


func clear_recent_entries() -> void:
	recent_entries.clear()


func _write(
	level: String,
	category: String,
	event_name: String,
	data: Dictionary
) -> void:
	var entry: Dictionary = {
		"schema": "lunar.log.v1",
		"timestamp_utc": Time.get_datetime_string_from_system(true, true),
		"ticks_msec": Time.get_ticks_msec(),
		"session_id": session_id,
		"level": level,
		"category": category,
		"event": event_name,
		"data": data.duplicate(true),
	}
	recent_entries.append(entry)
	while recent_entries.size() > max_recent_entries:
		recent_entries.pop_front()

	var line: String = JSON.stringify(entry)
	print(line)
	if memory_only:
		return

	_rotate_if_needed()
	var mode: int = (
		FileAccess.READ_WRITE
		if FileAccess.file_exists(LOG_PATH)
		else FileAccess.WRITE
	)
	var file := FileAccess.open(LOG_PATH, mode)
	if file == null:
		push_error("Could not open lunar log: %s" % LOG_PATH)
		return
	if mode == FileAccess.READ_WRITE:
		file.seek_end()
	file.store_line(line)
	file.flush()


func _rotate_if_needed() -> void:
	if memory_only or not FileAccess.file_exists(LOG_PATH):
		return
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return
	var current_size: int = file.get_length()
	file = null
	if current_size < MAX_LOG_BYTES:
		return

	for index in range(ROTATED_FILE_COUNT, 0, -1):
		var source_path: String = (
			LOG_PATH if index == 1 else "%s.%d" % [LOG_PATH, index - 1]
		)
		var target_path: String = "%s.%d" % [LOG_PATH, index]
		if not FileAccess.file_exists(source_path):
			continue
		if FileAccess.file_exists(target_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target_path))
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(source_path),
			ProjectSettings.globalize_path(target_path)
		)
