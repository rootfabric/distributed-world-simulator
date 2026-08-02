extends RefCounted

const ProfileScript = preload("res://scripts/network/conditions/network_condition_profile.gd")

const DEFAULT_PRESETS_PATH: String = "res://config/network/network-condition-presets.v1.json"


static func load_document(path: String = DEFAULT_PRESETS_PATH) -> Dictionary:
	var normalized_path: String = path.strip_edges()
	if normalized_path.is_empty():
		return _failure("EMPTY_PRESET_PATH")
	if not FileAccess.file_exists(normalized_path):
		return _failure("PRESET_FILE_NOT_FOUND", {"path": normalized_path})
	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null:
		return _failure("PRESET_FILE_OPEN_FAILED", {"path": normalized_path})
	var text: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _failure("PRESET_JSON_INVALID", {"path": normalized_path})
	var document: Dictionary = Dictionary(parsed)
	var validation: Dictionary = ProfileScript.validate_document(document)
	if not bool(validation.get("success", false)):
		return _failure("PRESET_DOCUMENT_INVALID", {
			"path": normalized_path,
			"cause": validation,
		})
	return _success({"path": normalized_path, "document": document.duplicate(true)})


static func load_profile(profile_id: String, path: String = DEFAULT_PRESETS_PATH) -> Dictionary:
	var normalized_id: String = profile_id.strip_edges().to_upper()
	if not ProfileScript.is_profile_id(normalized_id):
		return _failure("INVALID_PROFILE_ID")
	var document_result: Dictionary = load_document(path)
	if not bool(document_result.get("success", false)):
		return document_result
	var document: Dictionary = document_result.get("details", {}).get("document", {})
	for profile_value in document.get("profiles", []):
		if profile_value is Dictionary and String(profile_value.get("profile_id", "")) == normalized_id:
			return _success({
				"path": String(document_result.get("details", {}).get("path", path)),
				"profile": Dictionary(profile_value).duplicate(true),
			})
	return _failure("PROFILE_NOT_FOUND", {
		"profile_id": normalized_id,
		"path": String(document_result.get("details", {}).get("path", path)),
	})


static func list_profile_ids(path: String = DEFAULT_PRESETS_PATH) -> Dictionary:
	var document_result: Dictionary = load_document(path)
	if not bool(document_result.get("success", false)):
		return document_result
	var ids: Array[String] = []
	for profile_value in document_result.get("details", {}).get("document", {}).get("profiles", []):
		if profile_value is Dictionary:
			ids.append(String(profile_value.get("profile_id", "")))
	ids.sort()
	return _success({"profile_ids": ids})


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
