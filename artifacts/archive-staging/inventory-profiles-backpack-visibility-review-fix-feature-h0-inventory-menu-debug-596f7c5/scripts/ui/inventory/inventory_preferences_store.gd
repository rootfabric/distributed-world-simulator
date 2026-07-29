class_name InventoryPreferencesStore
extends RefCounted

const SCHEMA: String = "planet_simulator.inventory_ui_preferences.v2"
const LEGACY_SCHEMA: String = "planet_simulator.inventory_ui_preferences.v1"
const ROOT_PATH: String = "user://planet_simulator/ui"

var preferences_scope_id: String = "default"
var file_path: String = ""


func setup(value: String) -> void:
	preferences_scope_id = value.strip_edges()
	if preferences_scope_id.is_empty():
		preferences_scope_id = "default"
	var safe_profile := preferences_scope_id.replace("/", "_").replace("\\", "_").replace(":", "_")
	file_path = "%s/inventory_preferences_%s.json" % [ROOT_PATH, safe_profile]


func load_preferences() -> Dictionary:
	var defaults := default_preferences()
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		return defaults
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return defaults
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return defaults
	var data := Dictionary(parsed)
	var schema := String(data.get("schema", ""))
	if schema not in [SCHEMA, LEGACY_SCHEMA]:
		return defaults
	return {
		"schema": SCHEMA,
		"search_query": String(data.get("search_query", defaults.search_query)),
		"active_filter": String(data.get("active_filter", defaults.active_filter)),
		"sort_mode": String(data.get("sort_mode", defaults.sort_mode)),
		"inspector_visible": bool(data.get("inspector_visible", defaults.inspector_visible)),
		"interaction_profile_id": String(data.get("interaction_profile_id", defaults.interaction_profile_id)).strip_edges().to_lower(),
	}


func save_preferences(values: Dictionary) -> bool:
	if file_path.is_empty():
		setup(preferences_scope_id)
	var absolute_root := ProjectSettings.globalize_path(ROOT_PATH)
	if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
		return false
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return false
	var data := {
		"schema": SCHEMA,
		"search_query": String(values.get("search_query", "")),
		"active_filter": String(values.get("active_filter", "ALL")),
		"sort_mode": String(values.get("sort_mode", "CONTAINER_ORDER")),
		"inspector_visible": bool(values.get("inspector_visible", true)),
		"interaction_profile_id": String(values.get("interaction_profile_id", "planet_default")).strip_edges().to_lower(),
	}
	file.store_string(JSON.stringify(data, "  ", false, true))
	return true


func delete_preferences() -> void:
	if not file_path.is_empty() and FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))


static func default_preferences() -> Dictionary:
	return {
		"schema": SCHEMA,
		"search_query": "",
		"active_filter": "ALL",
		"sort_mode": "CONTAINER_ORDER",
		"inspector_visible": true,
		"interaction_profile_id": "planet_default",
	}
