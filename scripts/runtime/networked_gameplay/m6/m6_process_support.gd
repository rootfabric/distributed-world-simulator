extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const CHECKPOINT := "v16.10.5-persistence-m6-dedicated-recovery"
const BUILD_ID := "m6-dedicated-persistence-recovery"
const HOTBAR_OPERATION_ID := "operation/m6/process/a/hotbar/1"
const HOTBAR_PAYLOAD := {"item_id": "item/shared/ore/1", "slot_index": 2}


static func write(path: String, value: Dictionary) -> bool:
	if path.strip_edges().is_empty():
		return false
	return bool(AtomicJson.write_dictionary(path, value).get("success", false))


static func read(path: String) -> Dictionary:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return Dictionary(parsed) if parsed is Dictionary else {}


static func parse_arguments(arguments) -> Dictionary:
	var result: Dictionary = {}
	for argument_value in arguments:
		var argument := String(argument_value).strip_edges()
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		result[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return result
