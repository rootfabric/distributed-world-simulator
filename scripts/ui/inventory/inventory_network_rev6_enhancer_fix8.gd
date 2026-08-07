extends "res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix7.gd"

# Fix8 closes the remaining graphical activation hole observed on the real M7
# client. The visible overlay button can still miss both BaseButton.pressed and
# InventoryScreen.gui_input, which leaves no SORT_REQUESTED trace at all.
#
# `_input()` runs before GUI dispatch and therefore sees the physical mouse-down
# regardless of which Control later consumes it. When that press lands inside a
# visible sort button, we consume the event and route it through the exact same
# debounced fix6/fix7 dispatch path. Authority, optimistic presentation and
# reconciliation stay unchanged.

const FIX8_SCHEMA: String = "planet_simulator.inventory_network_rev6_enhancer.fix8.v1"

var _sort_global_input_activations: int = 0
var _sort_global_player_hits: int = 0
var _sort_global_external_hits: int = 0


func setup(controller, network_bridge) -> Dictionary:
	var result: Dictionary = super.setup(controller, network_bridge)
	if not bool(result.get("success", false)):
		return result
	set_process_input(true)
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["schema"] = FIX8_SCHEMA
	details["sort_activation_mode"] = "BUTTON_PRESS_SCREEN_FALLBACK_GLOBAL_INPUT"
	details["sort_global_input_fallback"] = true
	result["details"] = details
	return result


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if screen == null or not is_instance_valid(screen):
		return

	var inventory_visible: bool = false
	if screen.has_method("is_inventory_visible"):
		inventory_visible = bool(screen.call("is_inventory_visible"))
	else:
		inventory_visible = bool(screen.get("visible"))
	if not inventory_visible:
		return
	if _sort_in_progress or _pickup_merge_in_progress:
		return
	if _session_is_active(screen.get("transfer_session")):
		return

	var target: int = _sort_target_at_point(mouse_event.position)
	if target < 0 and screen is CanvasItem:
		# Canvas transforms can make viewport event coordinates differ from the
		# Control global rect in composed test/runtime layouts. Check the actual
		# canvas mouse point as a second deterministic hit-test source.
		target = _sort_target_at_point((screen as CanvasItem).get_global_mouse_position())
	if target < 0:
		return

	_mark_sort_input_handled()
	_sort_global_input_activations += 1
	var external: bool = target == 1
	if external:
		_sort_global_external_hits += 1
	else:
		_sort_global_player_hits += 1
	print("[inventory_sort] %s" % JSON.stringify({
		"event": "SORT_GLOBAL_INPUT_HIT",
		"container": "external" if external else "player",
		"point": [mouse_event.position.x, mouse_event.position.y],
	}, "", true, true))
	_dispatch_sort_press(external, "global_input_fallback")


func _sort_target_at_point(point: Vector2) -> int:
	if (
		player_sort_button != null
		and is_instance_valid(player_sort_button)
		and player_sort_button.visible
		and player_sort_button.get_global_rect().has_point(point)
	):
		return 0
	if (
		external_sort_button != null
		and is_instance_valid(external_sort_button)
		and external_sort_button.visible
		and external_sort_button.get_global_rect().has_point(point)
	):
		return 1
	return -1


func get_report() -> Dictionary:
	var result: Dictionary = super.get_report()
	result["schema"] = FIX8_SCHEMA
	result["sort_activation_mode"] = "BUTTON_PRESS_SCREEN_FALLBACK_GLOBAL_INPUT"
	result["sort_global_input_fallback"] = true
	result["sort_global_input_activations"] = _sort_global_input_activations
	result["sort_global_player_hits"] = _sort_global_player_hits
	result["sort_global_external_hits"] = _sort_global_external_hits
	return result
