class_name InventoryInteractionRouter
extends RefCounted

const PRIMARY: int = MOUSE_BUTTON_LEFT
const SECONDARY: int = MOUSE_BUTTON_RIGHT
const MIDDLE: int = MOUSE_BUTTON_MIDDLE

var profile: InventoryInteractionProfile


func setup(value: InventoryInteractionProfile) -> void:
	profile = value


func resolve_mouse(
	button_index: int,
	shift_pressed: bool,
	alt_pressed: bool,
	ctrl_pressed: bool,
	is_drag: bool,
	is_double_click: bool = false
) -> Dictionary:
	if profile == null:
		return {}
	var gesture := gesture_name(button_index, shift_pressed, alt_pressed, ctrl_pressed, is_drag, is_double_click)
	if gesture.is_empty():
		return {}
	var binding := profile.resolve(gesture)
	if binding.is_empty() and (shift_pressed or alt_pressed or ctrl_pressed):
		binding = profile.resolve(gesture_name(button_index, false, false, false, is_drag, is_double_click))
	if binding.is_empty():
		return {}
	binding["gesture"] = gesture
	return binding


func quantity_for(binding: Dictionary, total_quantity: int) -> int:
	var available := maxi(1, total_quantity)
	match String(binding.get("quantity_mode", "ALL")):
		"ONE":
			return 1
		"HALF_CEIL":
			return maxi(1, int(ceil(float(available) * 0.5)))
		"THIRD_CEIL":
			return maxi(1, int(ceil(float(available) / 3.0)))
		_:
			return available


func can_drag(button_index: int, shift_pressed: bool, alt_pressed: bool, ctrl_pressed: bool) -> bool:
	var binding := resolve_mouse(button_index, shift_pressed, alt_pressed, ctrl_pressed, true)
	return String(binding.get("action", "")) == "MOVE_TO_TARGET"


static func gesture_name(
	button_index: int,
	shift_pressed: bool,
	alt_pressed: bool,
	ctrl_pressed: bool,
	is_drag: bool,
	is_double_click: bool = false
) -> String:
	var base := ""
	match button_index:
		MOUSE_BUTTON_LEFT:
			base = "PRIMARY"
		MOUSE_BUTTON_RIGHT:
			base = "SECONDARY"
		MOUSE_BUTTON_MIDDLE:
			base = "MIDDLE"
		_:
			return ""
	var prefixes := PackedStringArray()
	if ctrl_pressed:
		prefixes.append("CTRL")
	if alt_pressed:
		prefixes.append("ALT")
	if shift_pressed:
		prefixes.append("SHIFT")
	var suffix := "_DOUBLE_CLICK" if is_double_click else ("_DRAG" if is_drag else "_CLICK")
	return ("_".join(prefixes) + "_" if not prefixes.is_empty() else "") + base + suffix
