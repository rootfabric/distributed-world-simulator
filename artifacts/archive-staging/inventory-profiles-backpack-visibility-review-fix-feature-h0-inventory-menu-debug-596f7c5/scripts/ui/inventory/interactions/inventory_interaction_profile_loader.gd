class_name InventoryInteractionProfileLoader
extends RefCounted

const Profile = preload("res://scripts/ui/inventory/interactions/inventory_interaction_profile.gd")
const DEFAULT_UI_CONFIG_PATH: String = "res://config/ui/inventory_ui.json"
const DEFAULT_CATALOG_PATH: String = "res://config/ui/inventory_profiles/catalog.json"
const FALLBACK_PROFILE_ID: String = "planet_default"

var config_path: String = DEFAULT_UI_CONFIG_PATH
var catalog_path: String = DEFAULT_CATALOG_PATH
var default_profile_id: String = FALLBACK_PROFILE_ID
var environment_override_name: String = "PLANET_SIMULATOR_INVENTORY_PROFILE"
var allow_user_profile_override: bool = true
var profiles_by_id: Dictionary = {}
var ordered_profile_ids: PackedStringArray = PackedStringArray()
var errors: Array[Dictionary] = []


func load_catalog(ui_config_path: String = DEFAULT_UI_CONFIG_PATH) -> Dictionary:
	config_path = ui_config_path
	profiles_by_id.clear()
	ordered_profile_ids.clear()
	errors.clear()
	var ui_config := _read_json_dictionary(config_path)
	if bool(ui_config.get("success", false)):
		var data := Dictionary(ui_config.get("data", {}))
		catalog_path = String(data.get("interaction_profiles_catalog", DEFAULT_CATALOG_PATH)).strip_edges()
		default_profile_id = String(data.get("default_interaction_profile", FALLBACK_PROFILE_ID)).strip_edges().to_lower()
		environment_override_name = String(data.get("environment_override", "PLANET_SIMULATOR_INVENTORY_PROFILE")).strip_edges()
		allow_user_profile_override = bool(data.get("allow_user_profile_override", true))
	else:
		errors.append(ui_config)
		catalog_path = DEFAULT_CATALOG_PATH
		default_profile_id = FALLBACK_PROFILE_ID
		allow_user_profile_override = true
	var catalog_result := _read_json_dictionary(catalog_path)
	if not bool(catalog_result.get("success", false)):
		errors.append(catalog_result)
		return _catalog_result(false, "PROFILE_CATALOG_UNAVAILABLE")
	var catalog := Dictionary(catalog_result.get("data", {}))
	if String(catalog.get("schema", "")) != "planet_simulator.inventory_interaction_catalog.v1":
		var schema_error := _error("PROFILE_CATALOG_SCHEMA_UNSUPPORTED", {"path": catalog_path})
		errors.append(schema_error)
		return _catalog_result(false, "PROFILE_CATALOG_SCHEMA_UNSUPPORTED")
	var entries = catalog.get("profiles", [])
	if not entries is Array:
		var entries_error := _error("PROFILE_CATALOG_ENTRIES_INVALID", {"path": catalog_path})
		errors.append(entries_error)
		return _catalog_result(false, "PROFILE_CATALOG_ENTRIES_INVALID")
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			errors.append(_error("PROFILE_CATALOG_ENTRY_INVALID", {"path": catalog_path}))
			continue
		var entry := Dictionary(raw_entry)
		var path := String(entry.get("path", "")).strip_edges()
		var declared_id := String(entry.get("profile_id", "")).strip_edges().to_lower()
		var result := load_profile_path(path)
		if not bool(result.get("success", false)):
			errors.append(result)
			continue
		var profile: InventoryInteractionProfile = result.get("profile")
		if not declared_id.is_empty() and declared_id != profile.profile_id:
			errors.append(_error("PROFILE_CATALOG_ID_MISMATCH", {
				"declared_id": declared_id,
				"profile_id": profile.profile_id,
				"path": path,
			}))
			continue
		if profiles_by_id.has(profile.profile_id):
			errors.append(_error("PROFILE_ID_DUPLICATE", {"profile_id": profile.profile_id, "path": path}))
			continue
		profiles_by_id[profile.profile_id] = profile
		ordered_profile_ids.append(profile.profile_id)
	if not profiles_by_id.has(default_profile_id):
		default_profile_id = FALLBACK_PROFILE_ID if profiles_by_id.has(FALLBACK_PROFILE_ID) else (ordered_profile_ids[0] if not ordered_profile_ids.is_empty() else "")
	return _catalog_result(not profiles_by_id.is_empty(), "" if not profiles_by_id.is_empty() else "PROFILE_CATALOG_EMPTY")


func load_profile_path(path: String) -> Dictionary:
	if path.is_empty():
		return _error("PROFILE_PATH_REQUIRED")
	var read_result := _read_json_dictionary(path)
	if not bool(read_result.get("success", false)):
		return read_result
	var profile := Profile.new()
	return profile.load_from_dictionary(Dictionary(read_result.get("data", {})), path)


func resolve_profile(requested_profile_id: String = "") -> Dictionary:
	if profiles_by_id.is_empty():
		load_catalog(config_path)
	var requested := requested_profile_id.strip_edges().to_lower()
	if requested.is_empty():
		requested = default_profile_id
	if profiles_by_id.has(requested):
		return {"success": true, "profile": profiles_by_id[requested], "requested_profile_id": requested, "fallback_used": false}
	var fallback := default_profile_id
	if fallback.is_empty() or not profiles_by_id.has(fallback):
		fallback = FALLBACK_PROFILE_ID if profiles_by_id.has(FALLBACK_PROFILE_ID) else (ordered_profile_ids[0] if not ordered_profile_ids.is_empty() else "")
	if fallback.is_empty():
		return _error("PROFILE_NOT_AVAILABLE", {"requested_profile_id": requested})
	return {
		"success": true,
		"profile": profiles_by_id[fallback],
		"requested_profile_id": requested,
		"fallback_used": true,
		"error_code": "PROFILE_NOT_FOUND",
	}


func get_profile(profile_id: String) -> InventoryInteractionProfile:
	return profiles_by_id.get(profile_id.strip_edges().to_lower()) as InventoryInteractionProfile


func profile_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for profile_id in ordered_profile_ids:
		var profile: InventoryInteractionProfile = profiles_by_id.get(profile_id)
		if profile == null:
			continue
		options.append({
			"profile_id": profile.profile_id,
			"display_name": profile.display_name,
			"description": profile.description,
		})
	return options


func environment_profile_id() -> String:
	if environment_override_name.is_empty():
		return ""
	return OS.get_environment(environment_override_name).strip_edges().to_lower()


func create_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.inventory_interaction_loader_debug.v1",
		"config_path": config_path,
		"catalog_path": catalog_path,
		"default_profile_id": default_profile_id,
		"environment_override_name": environment_override_name,
		"allow_user_profile_override": allow_user_profile_override,
		"profile_ids": Array(ordered_profile_ids),
		"errors": errors.duplicate(true),
	}


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("JSON_FILE_NOT_FOUND", {"path": path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("JSON_FILE_OPEN_FAILED", {"path": path, "open_error": FileAccess.get_open_error()})
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		return _error("JSON_PARSE_FAILED", {
			"path": path,
			"line": json.get_error_line(),
			"message": json.get_error_message(),
		})
	if not json.data is Dictionary:
		return _error("JSON_ROOT_NOT_DICTIONARY", {"path": path})
	return {"success": true, "data": Dictionary(json.data)}


func _catalog_result(success: bool, error_code: String) -> Dictionary:
	var result := {
		"success": success,
		"default_profile_id": default_profile_id,
		"profiles": profile_options(),
		"errors": errors.duplicate(true),
	}
	if not error_code.is_empty():
		result["error_code"] = error_code
	return result


func _error(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
