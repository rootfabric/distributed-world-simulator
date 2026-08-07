extends "res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix1.gd"

# Fix6 addresses the remaining graphical activation failure observed in a real
# M7 client. The sort buttons were visible, but their release-driven action
# could be lost and the LMB press then reached SimulatorApp._unhandled_input(),
# which executed input.mouse.capture. Sorting therefore never started.
#
# Keep the existing authoritative serial-transfer implementation from fix5,
# but make sort activation robust in two independent ways:
# 1. BaseButton ACTION_MODE_BUTTON_PRESS emits `pressed` on the mouse-down edge.
# 2. InventoryScreen has a geometry fallback that dispatches the same action if
#    the visible overlay button itself was not selected by GUI hit testing.
# A short debounce prevents the primary and fallback paths from double-firing.

const FIX6_SCHEMA: String = "planet_simulator.inventory_network_rev6_enhancer.fix6.v1"
const SORT_PRESS_DEBOUNCE_MS: int = 120

var _sort_press_activations: int = 0
var _sort_screen_fallback_activations: int = 0
var _last_sort_press_msec: int = -100000


func setup(controller, network_bridge) -> Dictionary:
	var result: Dictionary = super.setup(controller, network_bridge)
	if not bool(result.get("success", false)):
		return result
	if screen != null:
		# The inventory is modal gameplay UI: while it is visible, clicks inside
		# its panel must remain GUI input and must never become a gameplay
		# mouse-capture request.
		screen.mouse_filter = Control.MOUSE_FILTER_STOP
		var callback := Callable(self, "_on_inventory_screen_gui_input")
		if not screen.gui_input.is_connected(callback):
			screen.gui_input.connect(callback)
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["schema"] = FIX6_SCHEMA
	details["sort_activation_mode"] = "BUTTON_PRESS_WITH_SCREEN_FALLBACK"
	details["sort_press_debounce_ms"] = SORT_PRESS_DEBOUNCE_MS
	result["details"] = details
	return result


func _create_sort_button(node_name: String, caption: String, hint: String) -> Button:
	var button: Button = super._create_sort_button(node_name, caption, hint)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	return button


func _setup_sort_buttons() -> void:
	if player_sort_button == null:
		player_sort_button = _create_sort_button(
			"PlayerInventorySort",
			"Сортировать",
			"Объединить стаки и отсортировать рюкзак по названию"
		)
		screen.add_child(player_sort_button)
		player_sort_button.pressed.connect(_on_player_sort_pressed)
		_wire_sort_button_input(player_sort_button)
	if external_sort_button == null:
		external_sort_button = _create_sort_button(
			"ExternalInventorySort",
			"Сортировать",
			"Объединить стаки и отсортировать контейнер по названию"
		)
		screen.add_child(external_sort_button)
		external_sort_button.pressed.connect(_on_external_sort_pressed)
		_wire_sort_button_input(external_sort_button)
	_layout_sort_buttons()


func _on_player_sort_pressed() -> void:
	_dispatch_sort_press(false, "button_press")


func _on_external_sort_pressed() -> void:
	_dispatch_sort_press(true, "button_press")


func _on_inventory_screen_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if screen == null or not bool(screen.visible):
		return
	var point: Vector2 = screen.get_global_mouse_position()
	if (
		player_sort_button != null
		and player_sort_button.visible
		and player_sort_button.get_global_rect().has_point(point)
	):
		_mark_sort_input_handled()
		_sort_screen_fallback_activations += 1
		_dispatch_sort_press(false, "screen_fallback")
		return
	if (
		external_sort_button != null
		and external_sort_button.visible
		and external_sort_button.get_global_rect().has_point(point)
	):
		_mark_sort_input_handled()
		_sort_screen_fallback_activations += 1
		_dispatch_sort_press(true, "screen_fallback")


func _dispatch_sort_press(external: bool, activation_source: String) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_sort_press_msec < SORT_PRESS_DEBOUNCE_MS:
		return
	_last_sort_press_msec = now_msec
	_sort_press_activations += 1
	_mark_sort_input_handled()
	var container_id := (
		String(screen.get("external_container_id"))
		if external and screen != null
		else String(gameplay_controller.player_inventory_id)
	)
	print("[inventory_sort] %s" % JSON.stringify({
		"event": "SORT_REQUESTED",
		"activation_source": activation_source,
		"container_id": container_id,
		"external": external,
		"sort_in_progress": _sort_in_progress,
	}, "", true, true))
	if external:
		if container_id.is_empty():
			_show_error("Контейнер для сортировки не открыт")
			return
		super._on_external_sort_pressed()
	else:
		super._on_player_sort_pressed()


func _mark_sort_input_handled() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if screen != null and screen.get_viewport() != null:
		screen.get_viewport().set_input_as_handled()


func _run_sort_container(container_id: String, player_inventory: bool) -> void:
	print("[inventory_sort] %s" % JSON.stringify({
		"event": "SORT_STARTED",
		"container_id": container_id,
		"player_inventory": player_inventory,
		"item_ids": _container_item_ids_by_slot(container_id),
	}, "", true, true))
	var merge_result: Dictionary = await _merge_container_stacks_serial(container_id)
	if not bool(merge_result.get("success", false)):
		_sort_in_progress = false
		print("[inventory_sort] %s" % JSON.stringify({
			"event": "SORT_FAILED",
			"stage": "merge",
			"container_id": container_id,
			"error_code": String(merge_result.get("error_code", "UNKNOWN")),
		}, "", true, true))
		_show_error("Не удалось объединить стаки: %s" % String(merge_result.get("error_code", "UNKNOWN")))
		return
	_refresh_screen()
	var desired: Array = _container_item_ids_by_name(container_id)
	print("[inventory_sort] %s" % JSON.stringify({
		"event": "SORT_PLAN",
		"container_id": container_id,
		"desired_item_ids": desired,
	}, "", true, true))
	var sort_result: Dictionary = await _sort_container_slots_serial(container_id, player_inventory)
	_sort_in_progress = false
	_refresh_screen()
	_keep_inventory_pointer_visible()
	if bool(sort_result.get("success", false)):
		_sort_operations += 1
		print("[inventory_sort] %s" % JSON.stringify({
			"event": "SORT_COMPLETED",
			"container_id": container_id,
			"item_ids": _container_item_ids_by_slot(container_id),
		}, "", true, true))
		_show_success("Стаки объединены, предметы отсортированы по названию")
	else:
		print("[inventory_sort] %s" % JSON.stringify({
			"event": "SORT_FAILED",
			"stage": "reorder",
			"container_id": container_id,
			"error_code": String(sort_result.get("error_code", "UNKNOWN")),
			"message": String(sort_result.get("message", "")),
		}, "", true, true))
		_show_error(String(sort_result.get("message", "Сортировка не завершена: %s" % String(sort_result.get("error_code", "UNKNOWN")))))


func get_report() -> Dictionary:
	var result: Dictionary = super.get_report()
	result["schema"] = FIX6_SCHEMA
	result["sort_activation_mode"] = "BUTTON_PRESS_WITH_SCREEN_FALLBACK"
	result["sort_press_activations"] = _sort_press_activations
	result["sort_screen_fallback_activations"] = _sort_screen_fallback_activations
	result["sort_press_debounce_ms"] = SORT_PRESS_DEBOUNCE_MS
	return result
