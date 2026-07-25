extends RefCounted

const PROFILE_SCHEMA: String = "lunar.controller_profile.v1"


static func load_profile(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var profile: Dictionary = parsed
	var errors: Array[String] = validate_profile(profile)
	if not errors.is_empty():
		return {}
	profile["source_path"] = path
	return profile


static func validate_profile(profile: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if String(profile.get("schema", "")) != PROFILE_SCHEMA:
		errors.append("Unexpected controller profile schema.")
	if String(profile.get("profile_id", "")).is_empty():
		errors.append("profile_id is required.")
	if String(profile.get("controller_script", "")).is_empty():
		errors.append("controller_script is required.")
	elif not ResourceLoader.exists(String(profile.get("controller_script", ""))):
		errors.append("controller_script does not exist.")
	if not profile.get("movement", {}) is Dictionary:
		errors.append("movement must be a dictionary.")
	if not profile.get("camera", {}) is Dictionary:
		errors.append("camera must be a dictionary.")
	if not profile.get("capabilities", []) is Array:
		errors.append("capabilities must be an array.")
	return errors
