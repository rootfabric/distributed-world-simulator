extends Node

# Standalone rev6 inventory hardening for the networked 7-Days-like profile.
# All authoritative mutations continue to use the existing command facade and
# therefore the M7/NX6 item.transfer path. Presentation-only cursor suppression
# never mutates the canonical Item Graph.

const FIX_SCHEMA: String = "planet_simulator.inventory_network_rev6_enhancer.fix3.v1"
const CarryAwareProjection = preload(
	"res://scripts/ui/inventory/interactions/inventory_slot_projection_carry_aware.gd"
)

var gameplay_controller
var inventory_ui
var screen
var command_facade
var bridge
var projection
var player_sort_button: Button
var external_sort_button: Button

var _last_carry_active: bool = false
var _suppressed_container_id: String = ""
var _suppressed_item_id: String = ""
var _pickup_queue: Array = []
var _sort_in_progress: bool = false
var _pickup_stack_operations: int = 0
var _sort_operations: int = 0
var _pointer_repairs: int = 0
var _carry_suppressions: int = 0


func setup(controller, network_bridge) -> Dictionary:
	gameplay_controller = controller
	bridge = network_bridge
	if gameplay_controller == null:
		return _failure("INVENTORY_REV6_GAMEPLAY_REQUIRED")

	inventory_ui = gameplay_controller.get("inventory_ui")
	if inventory_ui == null:
		return _failure("INVENTORY_REV6_UI_REQUIRED")
	screen = inventory_ui.get("active_screen")
	if screen == null:
		return _failure("INVENTORY_REV6_COMPONENT_SCREEN_REQUIRED")
	command_facade = screen.get("command_facade")
	if command_facade == null:
		return _failure("INVENTORY_REV6_COMMAND_FACADE_REQUIRED")

	projection = CarryAwareProjection.new()
	var active_profile = screen.get("active_interaction_profile")
	projection.configure(active_profile)
	var old_projection = screen.get("slot_projection")
	if old_projection != null and old_projection.has_method("export_layouts"):
		projection.import_layouts(old_projection.call("export_layouts"))
	screen.set("slot_projection", projection)
	var cursor_controller = screen.get("cursor_controller")
	if cursor_controller != null:
		cursor_controller.set("slot_projection", projection)

	_setup_sort_buttons()
	if bridge != null and bridge.has_signal("authoritative_item_command_completed"):
		var completion_callback: Callable = Callable(self, "_on_authoritative_item_command_completed")
		if not bridge.is_connected("authoritative_item_command_completed", completion_callback):
			bridge.connect("authoritative_item_command_completed", completion_callback)

	set_process(true)
	call_deferred("_refresh_screen")
	return {
		"success": true,
		"error_code": "",
		"details": {
			"schema": FIX_SCHEMA,
			"carry_aware_projection": true,
			"sort_buttons": true,
			"pickup_auto_stack": true,
			"pickup_stack_mode": "CONSOLIDATE_COMPATIBLE_ON_PICKUP_COMPLETION",
		},
	}


func _process(_delta: float) -> void:
	if screen == null or not is_instance_valid(screen):
		return

	var inventory_visible: bool = false
	if screen.has_method("is_inventory_visible"):
		inventory_visible = bool(screen.call("is_inventory_visible"))
	else:
		inventory_visible = bool(screen.get("visible"))

	if inventory_visible and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pointer_repairs += 1

	var transfer_session = screen.get("transfer_session")
	var carry_active: bool = _session_is_active(transfer_session)
	if carry_active and not _last_carry_active:
		_apply_origin_suppression()
	elif not carry_active and _last_carry_active:
		_clear_origin_suppression(true)

	if not carry_active:
		var carry_preview = screen.get("carry_preview")
		if carry_preview != null and is_instance_valid(carry_preview):
			carry_preview.set("visible", false)

	_last_carry_active = carry_active
	_update_sort_button_visibility(inventory_visible, carry_active)
	_process_pickup_queue()


func _session_is_active(transfer_session) -> bool:
	if transfer_session == null or not transfer_session.has_method("is_active"):
		return false
	return bool(transfer_session.call("is_active"))


func _setup_sort_buttons() -> void:
	var player_panel = screen.get("player_panel")
	var external_panel = screen.get("external_panel")
	if player_panel != null:
		player_sort_button = _create_sort_button(
			"PlayerInventorySort",
			"Сортировать",
			"Объединить стаки и отсортировать рюкзак по названию"
		)
		player_panel.add_child(player_sort_button)
		_anchor_sort_button(player_sort_button)
		player_sort_button.pressed.connect(_on_player_sort_pressed)
	if external_panel != null:
		external_sort_button = _create_sort_button(
			"ExternalInventorySort",
			"Сортировать",
			"Объединить стаки и отсортировать контейнер по названию"
		)
		external_panel.add_child(external_sort_button)
		_anchor_sort_button(external_sort_button)
		external_sort_button.pressed.connect(_on_external_sort_pressed)


func _create_sort_button(node_name: String, caption: String, hint: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = caption
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(112.0, 30.0)
	button.z_as_relative = false
	button.z_index = 3000
	return button


func _anchor_sort_button(button: Button) -> void:
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -124.0
	button.offset_top = 6.0
	button.offset_right = -8.0
	button.offset_bottom = 36.0


func _update_sort_button_visibility(inventory_visible: bool, carry_active: bool) -> void:
	var seven_days: bool = false
	var profile = screen.get("active_interaction_profile")
	if profile != null:
		seven_days = String(profile.get("profile_id")) == "seven_days_like"
	if player_sort_button != null:
		player_sort_button.visible = inventory_visible and seven_days and not carry_active
	if external_sort_button != null:
		external_sort_button.visible = (
			inventory_visible
			and seven_days
			and not carry_active
			and not String(screen.get("external_container_id")).is_empty()
		)


func _apply_origin_suppression() -> void:
	if projection == null:
		return
	var transfer_session = screen.get("transfer_session")
	var cursor_controller = screen.get("cursor_controller")
	if transfer_session == null or cursor_controller == null:
		return
	if not cursor_controller.has_method("debug_snapshot"):
		return
	var cursor_debug: Dictionary = Dictionary(cursor_controller.call("debug_snapshot"))
	if not bool(cursor_debug.get("network_virtual", false)):
		return

	var origin_item_id: String = String(transfer_session.get("origin_item_id"))
	var origin_container_id: String = String(transfer_session.get("source_container_id"))
	if origin_item_id.is_empty() or origin_container_id.is_empty():
		return
	var source = gameplay_controller.get_item(origin_item_id)
	if source == null:
		return
	var requested_quantity: int = int(transfer_session.get("requested_quantity"))
	if requested_quantity < int(source.get("quantity")):
		return

	_suppressed_container_id = origin_container_id
	_suppressed_item_id = origin_item_id
	projection.suppress_item(_suppressed_container_id, _suppressed_item_id)
	_carry_suppressions += 1
	call_deferred("_refresh_screen")


func _clear_origin_suppression(refresh_after: bool) -> void:
	if projection != null and not _suppressed_container_id.is_empty() and not _suppressed_item_id.is_empty():
		projection.reveal_item(_suppressed_container_id, _suppressed_item_id)
	_suppressed_container_id = ""
	_suppressed_item_id = ""
	if refresh_after:
		call_deferred("_refresh_screen")


func _on_authoritative_item_command_completed(
	operation_id: String,
	result: Dictionary,
	_canonical_snapshot: Dictionary
) -> void:
	if not bool(result.get("success", false)):
		return
	if not operation_id.contains("-pickup-"):
		return
	_pickup_queue.append({"attempts_left": 12})


func _process_pickup_queue() -> void:
	if _pickup_queue.is_empty() or _sort_in_progress:
		return
	var inventory = gameplay_controller.get_container(gameplay_controller.player_inventory_id)
	if inventory == null:
		var retry_entry: Dictionary = Dictionary(_pickup_queue[0])
		retry_entry["attempts_left"] = int(retry_entry.get("attempts_left", 0)) - 1
		if int(retry_entry["attempts_left"]) <= 0:
			_pickup_queue.pop_front()
		else:
			_pickup_queue[0] = retry_entry
		return

	_pickup_queue.pop_front()
	_sort_in_progress = true
	var merged: bool = _merge_container_stacks(String(gameplay_controller.player_inventory_id))
	_sort_in_progress = false
	if merged:
		_pickup_stack_operations += 1
		call_deferred("_refresh_screen")


func _on_player_sort_pressed() -> void:
	_sort_container(String(gameplay_controller.player_inventory_id), true)


func _on_external_sort_pressed() -> void:
	var container_id: String = String(screen.get("external_container_id"))
	if not container_id.is_empty():
		_sort_container(container_id, false)


func _sort_container(container_id: String, player_inventory: bool) -> void:
	if _sort_in_progress or container_id.is_empty():
		return
	var transfer_session = screen.get("transfer_session")
	if _session_is_active(transfer_session):
		_show_error("Сначала завершите перенос предмета")
		return

	_sort_in_progress = true
	if not _merge_container_stacks(container_id):
		_sort_in_progress = false
		return
	_refresh_screen()
	var sorted: bool = _sort_container_slots(container_id, player_inventory)
	_sort_in_progress = false
	_refresh_screen()
	if sorted:
		_sort_operations += 1
		_show_success("Стаки объединены, предметы отсортированы по названию")


func _merge_container_stacks(container_id: String) -> bool:
	var ids: Array = _container_item_ids_by_slot(container_id)
	for target_index in range(ids.size()):
		var target_id: String = String(ids[target_index])
		var target = gameplay_controller.get_item(target_id)
		if target == null:
			continue
		var definition = gameplay_controller.get_definition(target.get("definition_id"))
		if definition == null or int(definition.get("max_stack")) <= 1:
			continue

		for source_index in range(target_index + 1, ids.size()):
			var source_id: String = String(ids[source_index])
			if source_id.is_empty() or source_id == target_id:
				continue
			target = gameplay_controller.get_item(target_id)
			var source = gameplay_controller.get_item(source_id)
			if target == null or source == null:
				continue
			if not bool(source.call("is_stack_compatible", target)):
				continue
			var headroom: int = maxi(0, int(definition.get("max_stack")) - int(target.get("quantity")))
			if headroom <= 0:
				break
			var amount: int = mini(headroom, int(source.get("quantity")))
			var target_relation: Dictionary = Dictionary(target.get("relation"))
			var merge_result: Dictionary = command_facade.transfer_quantity(
				source_id,
				amount,
				container_id,
				int(target_relation.get("slot_index", -1)),
				target_id
			)
			if not bool(merge_result.get("success", false)):
				_show_error("Не удалось объединить стаки: %s" % String(merge_result.get("error_code", "UNKNOWN")))
				return false
	return true


func _sort_container_slots(container_id: String, player_inventory: bool) -> bool:
	var container = gameplay_controller.get_container(container_id)
	if container == null or not bool(container.call("is_slot_container")):
		_show_error("Сортировка требует слот-контейнер")
		return false

	var capacity: int = int(container.get("slot_count"))
	var desired: Array = _container_item_ids_by_name(container_id)
	if desired.is_empty():
		return true
	var slots: Array = _slot_map(container_id, capacity)
	var empty_slot: int = _first_empty_slot(slots)
	var temporary_item_id: String = ""

	if empty_slot < 0:
		temporary_item_id = String(desired[desired.size() - 1])
		var temporary_source_slot: int = slots.find(temporary_item_id)
		if temporary_source_slot < 0:
			_show_error("Сортировка не нашла временный предмет")
			return false

		var moved_to_buffer: bool = false
		if player_inventory:
			var hotbar = gameplay_controller.get_container(gameplay_controller.player_hotbar_id)
			if hotbar != null:
				for hotbar_index in range(int(hotbar.get("slot_count"))):
					if String(hotbar.call("get_item_at_slot", hotbar_index)).is_empty():
						var hotbar_result: Dictionary = command_facade.transfer_quantity(
							temporary_item_id,
							-1,
							gameplay_controller.player_hotbar_id,
							hotbar_index,
							""
						)
						moved_to_buffer = bool(hotbar_result.get("success", false))
						break
		else:
			var player_free: int = _first_free_slot_for_container(String(gameplay_controller.player_inventory_id))
			if player_free >= 0:
				var inventory_result: Dictionary = command_facade.transfer_quantity(
					temporary_item_id,
					-1,
					gameplay_controller.player_inventory_id,
					player_free,
					""
				)
				moved_to_buffer = bool(inventory_result.get("success", false))

		if not moved_to_buffer:
			_show_error("Для полной сортировки нужен один свободный слот")
			return false
		slots[temporary_source_slot] = ""
		empty_slot = temporary_source_slot

	for target_slot in range(desired.size()):
		var desired_id: String = String(desired[target_slot])
		if String(slots[target_slot]) == desired_id:
			continue

		var desired_source_slot: int = slots.find(desired_id)
		if desired_source_slot < 0:
			if desired_id != temporary_item_id:
				_show_error("Сортировка потеряла позицию предмета")
				return false
			if not String(slots[target_slot]).is_empty():
				var buffered_occupant: String = String(slots[target_slot])
				if not _move_whole_stack(buffered_occupant, container_id, empty_slot):
					return false
				slots[empty_slot] = buffered_occupant
				slots[target_slot] = ""
				empty_slot = target_slot
			if not _move_whole_stack(temporary_item_id, container_id, target_slot):
				return false
			slots[target_slot] = temporary_item_id
			temporary_item_id = ""
			continue

		if not String(slots[target_slot]).is_empty():
			var displaced_id: String = String(slots[target_slot])
			if not _move_whole_stack(displaced_id, container_id, empty_slot):
				return false
			slots[empty_slot] = displaced_id
			slots[target_slot] = ""
			empty_slot = target_slot

		if not _move_whole_stack(desired_id, container_id, target_slot):
			return false
		slots[desired_source_slot] = ""
		slots[target_slot] = desired_id
		empty_slot = desired_source_slot

	if not temporary_item_id.is_empty():
		var final_slot: int = desired.find(temporary_item_id)
		if final_slot < 0:
			_show_error("Временный предмет отсутствует в плане сортировки")
			return false
		if not String(slots[final_slot]).is_empty():
			var final_displaced_id: String = String(slots[final_slot])
			if not _move_whole_stack(final_displaced_id, container_id, empty_slot):
				return false
			slots[empty_slot] = final_displaced_id
			slots[final_slot] = ""
		if not _move_whole_stack(temporary_item_id, container_id, final_slot):
			return false
	return true


func _move_whole_stack(item_id: String, container_id: String, target_slot: int) -> bool:
	if item_id.is_empty() or target_slot < 0:
		return false
	var move_result: Dictionary = command_facade.transfer_quantity(
		item_id,
		-1,
		container_id,
		target_slot,
		""
	)
	if not bool(move_result.get("success", false)):
		_show_error("Не удалось переместить предмет при сортировке: %s" % String(move_result.get("error_code", "UNKNOWN")))
		return false
	return true


func _container_item_ids_by_slot(container_id: String) -> Array:
	var rows: Array = []
	var container = gameplay_controller.get_container(container_id)
	if container == null:
		return []
	for item_id_value in Array(container.get("item_ids")):
		var item_id: String = String(item_id_value)
		var item = gameplay_controller.get_item(item_id)
		if item == null:
			continue
		var relation: Dictionary = Dictionary(item.get("relation"))
		rows.append({"item_id": item_id, "slot": int(relation.get("slot_index", 9999))})
	rows.sort_custom(Callable(self, "_compare_slot_rows"))
	var result: Array = []
	for row_value in rows:
		result.append(String(Dictionary(row_value).get("item_id", "")))
	return result


func _compare_slot_rows(a, b) -> bool:
	var row_a: Dictionary = Dictionary(a)
	var row_b: Dictionary = Dictionary(b)
	if int(row_a.get("slot", 9999)) != int(row_b.get("slot", 9999)):
		return int(row_a.get("slot", 9999)) < int(row_b.get("slot", 9999))
	return String(row_a.get("item_id", "")) < String(row_b.get("item_id", ""))


func _container_item_ids_by_name(container_id: String) -> Array:
	var result: Array = _container_item_ids_by_slot(container_id)
	result.sort_custom(Callable(self, "_compare_item_ids_by_name"))
	return result


func _compare_item_ids_by_name(a, b) -> bool:
	var id_a: String = String(a)
	var id_b: String = String(b)
	var item_a = gameplay_controller.get_item(id_a)
	var item_b = gameplay_controller.get_item(id_b)
	if item_a == null or item_b == null:
		return id_a < id_b
	var definition_a = gameplay_controller.get_definition(item_a.get("definition_id"))
	var definition_b = gameplay_controller.get_definition(item_b.get("definition_id"))
	var name_a: String = String(item_a.get("display_name"))
	var name_b: String = String(item_b.get("display_name"))
	if name_a.is_empty() and definition_a != null:
		name_a = String(definition_a.get("display_name"))
	if name_b.is_empty() and definition_b != null:
		name_b = String(definition_b.get("display_name"))
	var name_compare: int = name_a.naturalnocasecmp_to(name_b)
	if name_compare != 0:
		return name_compare < 0
	var definition_id_a: String = String(item_a.get("definition_id"))
	var definition_id_b: String = String(item_b.get("definition_id"))
	if definition_id_a != definition_id_b:
		return definition_id_a < definition_id_b
	return id_a < id_b


func _slot_map(container_id: String, capacity: int) -> Array:
	var slots: Array = []
	slots.resize(capacity)
	for index in range(capacity):
		slots[index] = ""
	var container = gameplay_controller.get_container(container_id)
	if container == null:
		return slots
	for item_id_value in Array(container.get("item_ids")):
		var item_id: String = String(item_id_value)
		var item = gameplay_controller.get_item(item_id)
		if item == null:
			continue
		var relation: Dictionary = Dictionary(item.get("relation"))
		var slot_index: int = int(relation.get("slot_index", -1))
		if slot_index >= 0 and slot_index < capacity:
			slots[slot_index] = item_id
	return slots


func _first_empty_slot(slots: Array) -> int:
	for index in range(slots.size()):
		if String(slots[index]).is_empty():
			return index
	return -1


func _first_free_slot_for_container(container_id: String) -> int:
	var container = gameplay_controller.get_container(container_id)
	if container == null or not bool(container.call("is_slot_container")):
		return -1
	return _first_empty_slot(_slot_map(container_id, int(container.get("slot_count"))))


func _refresh_screen() -> void:
	if screen != null and is_instance_valid(screen) and screen.has_method("refresh"):
		screen.call("refresh")


func _show_success(message: String) -> void:
	if screen == null:
		return
	var status_label = screen.get("status_label")
	if status_label != null:
		status_label.set("text", message)
	var toast_layer = screen.get("toast_layer")
	if toast_layer != null and toast_layer.has_method("show_success"):
		toast_layer.call("show_success", message)


func _show_error(message: String) -> void:
	if screen == null:
		return
	var status_label = screen.get("status_label")
	if status_label != null:
		status_label.set("text", message)
	var toast_layer = screen.get("toast_layer")
	if toast_layer != null and toast_layer.has_method("show_error"):
		toast_layer.call("show_error", message)


func get_report() -> Dictionary:
	return {
		"schema": FIX_SCHEMA,
		"pickup_stack_mode": "CONSOLIDATE_COMPATIBLE_ON_PICKUP_COMPLETION",
		"pickup_queue": _pickup_queue.size(),
		"pickup_stack_operations": _pickup_stack_operations,
		"sort_operations": _sort_operations,
		"sort_in_progress": _sort_in_progress,
		"pointer_repairs": _pointer_repairs,
		"carry_suppressions": _carry_suppressions,
		"suppressed_item_id": _suppressed_item_id,
		"projection": projection.debug_snapshot() if projection != null else {},
	}


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
