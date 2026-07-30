class_name InventoryInteractionProfile
extends RefCounted

const SCHEMA: String = "planet_simulator.inventory_interaction_profile.v1"
const SUPPORTED_ACTIONS: PackedStringArray = [
	"ACTIVATE_SLOT",
	"CARRY_ALL_OR_PLACE_ALL",
	"CARRY_HALF_OR_PLACE_ONE",
	"CARRY_EXACT_OR_PLACE_ONE",
	"MOVE_TO_TARGET",
	"OPEN_CONTEXT_MENU",
	"PLACE_ALL_OR_SELECT",
	"QUICK_TRANSFER",
	"SELECT_ITEM",
]
const SUPPORTED_QUANTITY_MODES: PackedStringArray = [
	"ALL",
	"HALF_CEIL",
	"ONE",
	"THIRD_CEIL",
]
const SUPPORTED_OUTSIDE_ACTIONS: PackedStringArray = ["CANCEL", "DROP_TO_WORLD"]

var profile_id: String = ""
var display_name: String = ""
var description: String = ""
var drag_threshold_px: float = 5.0
var bindings: Dictionary = {}
var outside_drop: Dictionary = {"action": "DROP_TO_WORLD"}
var legend: PackedStringArray = PackedStringArray()
var ui_style: String = "DEFAULT"
var container_layout: String = "DOMAIN"
var slot_columns: int = 6
var source_path: String = ""


func load_from_dictionary(data: Dictionary, path: String = "") -> Dictionary:
	if String(data.get("schema", "")) != SCHEMA:
		return _error("PROFILE_SCHEMA_UNSUPPORTED", {"path": path})
	var requested_id := String(data.get("profile_id", "")).strip_edges().to_lower()
	if requested_id.is_empty():
		return _error("PROFILE_ID_REQUIRED", {"path": path})
	var raw_bindings = data.get("bindings", [])
	if not raw_bindings is Array:
		return _error("PROFILE_BINDINGS_INVALID", {"profile_id": requested_id, "path": path})
	var parsed_bindings: Dictionary = {}
	for raw_binding in raw_bindings:
		if not raw_binding is Dictionary:
			return _error("PROFILE_BINDING_INVALID", {"profile_id": requested_id, "path": path})
		var binding := Dictionary(raw_binding).duplicate(true)
		var gesture := String(binding.get("gesture", "")).strip_edges().to_upper()
		var action := String(binding.get("action", "")).strip_edges().to_upper()
		var quantity_mode := String(binding.get("quantity_mode", "ALL")).strip_edges().to_upper()
		if gesture.is_empty():
			return _error("PROFILE_GESTURE_REQUIRED", {"profile_id": requested_id, "path": path})
		if parsed_bindings.has(gesture):
			return _error("PROFILE_GESTURE_DUPLICATE", {"profile_id": requested_id, "gesture": gesture, "path": path})
		if action not in SUPPORTED_ACTIONS:
			return _error("PROFILE_ACTION_UNSUPPORTED", {"profile_id": requested_id, "gesture": gesture, "action": action, "path": path})
		if quantity_mode not in SUPPORTED_QUANTITY_MODES:
			return _error("PROFILE_QUANTITY_MODE_UNSUPPORTED", {"profile_id": requested_id, "gesture": gesture, "quantity_mode": quantity_mode, "path": path})
		binding["gesture"] = gesture
		binding["action"] = action
		binding["quantity_mode"] = quantity_mode
		parsed_bindings[gesture] = binding
	var parsed_outside := Dictionary(data.get("outside_drop", {})).duplicate(true)
	var outside_action := String(parsed_outside.get("action", "DROP_TO_WORLD")).strip_edges().to_upper()
	if outside_action not in SUPPORTED_OUTSIDE_ACTIONS:
		return _error("PROFILE_OUTSIDE_ACTION_UNSUPPORTED", {"profile_id": requested_id, "action": outside_action, "path": path})
	parsed_outside["action"] = outside_action
	var raw_legend = data.get("legend", [])
	var parsed_legend := PackedStringArray()
	if raw_legend is Array:
		for line in raw_legend:
			var text := String(line).strip_edges()
			if not text.is_empty():
				parsed_legend.append(text)
	profile_id = requested_id
	display_name = String(data.get("display_name", requested_id)).strip_edges()
	description = String(data.get("description", "")).strip_edges()
	drag_threshold_px = clampf(float(data.get("drag_threshold_px", 5.0)), 1.0, 64.0)
	ui_style = String(data.get("ui_style", "DEFAULT")).strip_edges().to_upper()
	if ui_style not in ["DEFAULT", "SEVEN_DAYS"]:
		return _error("PROFILE_UI_STYLE_UNSUPPORTED", {"profile_id": requested_id, "ui_style": ui_style, "path": path})
	container_layout = String(data.get("container_layout", "DOMAIN")).strip_edges().to_upper()
	if container_layout not in ["DOMAIN", "FIXED_SLOTS"]:
		return _error("PROFILE_CONTAINER_LAYOUT_UNSUPPORTED", {"profile_id": requested_id, "container_layout": container_layout, "path": path})
	slot_columns = clampi(int(data.get("slot_columns", 6)), 1, 16)
	bindings = parsed_bindings
	outside_drop = parsed_outside
	legend = parsed_legend
	source_path = path
	return {"success": true, "profile": self}


func resolve(gesture: String) -> Dictionary:
	var normalized := gesture.strip_edges().to_upper()
	if not bindings.has(normalized):
		return {}
	return Dictionary(bindings[normalized]).duplicate(true)


func has_gesture(gesture: String) -> bool:
	return bindings.has(gesture.strip_edges().to_upper())


func outside_drop_action() -> String:
	return String(outside_drop.get("action", "DROP_TO_WORLD"))


func status_text() -> String:
	return " · ".join(legend)


func to_dictionary() -> Dictionary:
	var ordered_bindings: Array[Dictionary] = []
	for gesture in bindings:
		ordered_bindings.append(Dictionary(bindings[gesture]).duplicate(true))
	return {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"display_name": display_name,
		"description": description,
		"drag_threshold_px": drag_threshold_px,
		"bindings": ordered_bindings,
		"outside_drop": outside_drop.duplicate(true),
		"legend": Array(legend),
		"ui_style": ui_style,
		"container_layout": container_layout,
		"slot_columns": slot_columns,
		"source_path": source_path,
	}


func _error(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
