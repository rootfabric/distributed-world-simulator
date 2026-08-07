extends Node

# Incremental M7/7-Days inventory hardening layered on top of the accepted
# rev5 slot-aware network branch. It deliberately reuses item.transfer for all
# authoritative mutations so the existing M7/NX6 command path remains the
# single source of truth.

const SCHEMA := "planet_simulator.inventory_network_rev6_enhancer.v1"
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

var _last_carry_active := false
var _suppressed_container_id := ""
var _suppressed_item_id := ""
var _pickup_queue: Array[Dictionary] = []
var _sort_in_progress := false
var _pickup_stack_operations := 0
var _sort_operations := 0
var _pointer_repairs := 0
var _carry_suppressions := 0


func setup(controller, network_bridge) -> Dictionary:
	gameplay_controller = controller
	bridge = network_bridge
	if gameplay_controller == null:
		return _failure("INVENTORY_REV6_GAMEPLAY_REQUIRED")
	inventory_ui = gameplay_controller.get("inventory_ui")
	if inventory_ui == null or inventory_ui.get("active_screen") == null:
		return _failure("INVENTORY_REV6_COMPONENT_SCREEN_REQUIRED")
	screen = inventory_ui.get("active_screen")
	command_facade = screen.get("command_facade")
	if command_facade == null:
		return _failure("INVENTORY_REV6_COMMAND_FACADE_REQUIRED")

	projection = CarryAwareProjection.new()
	var old_projection = screen.get("slot_projection")
	if old_projection != null:
		projection.configure(screen.get("active_interaction_profile"))
		if old_projection.has_method("export_layouts"):
			projection.import_layouts(old_projection.export_layouts())
	else:
		projection.configure(screen.get("active_interaction_profile"))
	screen.set("slot_projection", projection)
	var cursor_controller = screen.get("cursor_controller")
	if cursor_controller != null:
		cursor_controller.set("slot_projection", projection)

	_setup_sort_buttons()
	if (
		bridge != null
		and bridge.has_signal("authoritative_item_command_completed")
		and not bridge.authoritative_item_command_completed.is_connected(_on_authoritative_item_command_completed)
	):
		bridge.authoritative_item_command_completed.connect(_on_authoritative_item_command_completed)
	set_process(true)
	call_deferred("_refresh_screen")
	return {
		"success": true,
		"error_code": "",
		"details": {
			"schema": SCHEMA,
			"carry_aware_projection": true,
			"sort_buttons": true,
			"pickup_auto_stack": true,
		}
	}


func _process(_delta: float) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	var inventory_visible := bool(screen.call("is_inventory_visible")) if screen.has_method("is_inventory_visible") else bool(screen.visible)
	if inventory_visible and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pointer_repairs += 1

	var transfer_session = screen.get("transfer_session")
	var carry_active := transfer_session != null and transfer_session.is_active()
	if carry_active and not _last_carry_active:
		_apply_origin_suppression()
	elif not carry_active and _last_carry_active:
		_clear_origin_suppression(true)
	if not carry_active:
		var carry_preview = screen.get("carry_preview")
		if carry_preview != null and is_instance_valid(carry_preview):
			carry_preview.visible = false
	_last_carry_active = carry_active

	_update_sort_button_visibility(inventory_visible, carry_active)
	_process_pickup_queue()


func _setup_sort_buttons() -> void:
	var player_panel = screen.get("player_panel")
	var external_panel = screen.get("external_panel")
	if player_panel != null:
		player_sort_button = _create_sort_button("PlayerInventorySort", "Сортировать", "Объединить стаки и отсортировать рюкзак по названию")
		player_panel.add_child(player_sort_button)
		_anchor_sort_button(player_sort_button)
		player_sort_button.pressed.connect(_on_player_sort_pressed)
	if external_panel != null:
		external_sort_button = _create_sort_button("ExternalInventorySort", "Сортировать", "Объединить стаки и отсортировать контейнер по названию")
		external_panel.add_child(external_sort_button)
		_anchor_sort_button(external_sort_button)
		external_sort_button.pressed.connect(_on_external_sort_pressed)


func _create_sort_button(node_name: String, caption: String, tooltip_text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.tooltip_text = tooltip_text
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
	var seven_days := false
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
	var transfer_session = screen.get("transfer_session")
	var cursor_controller = screen.get("cursor_controller")
	if transfer_session == null or cursor_controller == null:
		return
	var debug: Dictionary = cursor_controller.debug_snapshot()
	if not bool(debug.get("network_virtual", false)):
		return
	var origin_item_id := String(transfer_session.origin_item_id)
	var origin_container_id := String(transfer_session.source_container_id)
	if origin_item_id.is_empty() or origin_container_id.is_empty():
		return
	var source = gameplay_controller.get_item(origin_item_id)
	if source == null:
		return
	# A half-stack carry intentionally leaves the remainder visible in the source
	# slot. The duplicate artifact reported in rev5 concerns whole-stack pickup.
	if int(transfer_session.requested_quantity) < int(source.quantity):
		return
	_suppressed_container_id = origin_container_id
	_suppressed_item_id = origin_item_id
	projection.suppress_item(_suppressed_container_id, _suppressed_item_id)
	_carry_suppressions += 1
	call_deferred("_refresh_screen")


func _clear_origin_suppression(refresh_after: bool) -> void:
	if projection == null:
		return
	if not _suppressed_container_id.is_empty() and not _suppressed_item_id.is_empty():
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
	if not bool(result.get("success", false)) or not operation_id.contains("-pickup-"):
		return
	var details: Dictionary = Dictionary(result.get("details", {}))
	var canonical_item_id := String(details.get("item_id", result.get("item_id", "")))
	if canonical_item_id.is_empty() or bridge == null or not bridge.has_method("get_adapter"):
		return
	var adapter = bridge.get_adapter()
	if adapter == null or not adapter.has_method("to_replica_item_id"):
		return
	var replica_item_id := String(adapter.to_replica_item_id(canonical_item_id))
	if replica_item_id.is_empty():
		return
	_pickup_queue.append({"item_id": replica_item_id, "attempts_left": 12})


func _process_pickup_queue() -> void:
	if _pickup_queue.is_empty() or _sort_in_progress:
		return
	var entry: Dictionary = Dictionary(_pickup_queue[0])
	var item_id := String(entry.get("item_id", ""))
	var source = gameplay_controller.get_item(item_id)
	if source == null:
		entry["attempts_left"] = int(entry.get("attempts_left", 0)) - 1
		if int(entry["attempts_left"]) <= 0:
			_pickup_queue.pop_front()
		else:
			_pickup_queue[0] = entry
		return
	var relation: Dictionary = source.relation
	if String(relation.get("container_id", "")) != String(gameplay_controller.player_inventory_id):
		entry["attempts_left"] = int(entry.get("attempts_left", 0)) - 1
		if int(entry["attempts_left"]) <= 0:
			_pickup_queue.pop_front()
		else:
			_pickup_queue[0] = entry
		return
	_pickup_queue.pop_front()
	_auto_stack_picked_item(item_id)


func _auto_stack_picked_item(source_item_id: String) -> void:
	var source = gameplay_controller.get_item(source_item_id)
	if source == null:
		return
	var inventory = gameplay_controller.get_container(gameplay_controller.player_inventory_id)
	if inventory == null:
		return
	var target_ids: Array[String] = []
	for item_id_value in inventory.item_ids:
		var item_id := String(item_id_value)
		if item_id == source_item_id:
			continue
		var target = gameplay_controller.get_item(item_id)
		if target == null or not source.is_stack_compatible(target):
			continue
		target_ids.append(item_id)
	target_ids.sort_custom(func(a: String, b: String) -> bool:
		var item_a = gameplay_controller.get_item(a)
		var item_b = gameplay_controller.get_item(b)
		return int(item_a.relation.get("slot_index", 9999)) < int(item_b.relation.get("slot_index", 9999))
	)
	for target_id in target_ids:
		source = gameplay_controller.get_item(source_item_id)
		var target = gameplay_controller.get_item(target_id)
		if source == null or target == null:
			break
		var definition = gameplay_controller.get_definition(target.definition_id)
		if definition == null:
			continue
		var headroom := maxi(0, int(definition.max_stack) - int(target.quantity))
		if headroom <= 0:
			continue
		var amount := mini(int(source.quantity), headroom)
		var result: Dictionary = command_facade.transfer_quantity(
			source_item_id,
			amount,
			gameplay_controller.player_inventory_id,
			int(target.relation.get("slot_index", -1)),
			target_id
		)
		if not bool(result.get("success", false)):
			break
		_pickup_stack_operations += 1
	call_deferred("_refresh_screen")


func _on_player_sort_pressed() -> void:
	_sort_container(String(gameplay_controller.player_inventory_id), true)


func _on_external_sort_pressed() -> void:
	var container_id := String(screen.get("external_container_id"))
	if not container_id.is_empty():
		_sort_container(container_id, false)


func _sort_container(container_id: String, player_inventory: bool) -> void:
	if _sort_in_progress or container_id.is_empty():
		return
	var transfer_session = screen.get("transfer_session")
	if transfer_session != null and transfer_session.is_active():
		_show_error("Сначала завершите перенос предмета")
		return
	_sort_in_progress = true
	if not _merge_container_stacks(container_id):
		_sort_in_progress = false
		return
	_refresh_screen()
	var sorted := _sort_container_slots(container_id, player_inventory)
	_sort_in_progress = false
	_refresh_screen()
	if sorted:
		_sort_operations += 1
		_show_success("Стаки объединены, предметы отсортированы по названию")


func _merge_container_stacks(container_id: String) -> bool:
	var ids := _container_item_ids_by_slot(container_id)
	for target_index in range(ids.size()):
		var target_id := String(ids[target_index])
		var target = gameplay_controller.get_item(target_id)
		if target == null:
			continue
		var definition = gameplay_controller.get_definition(target.definition_id)
		if definition == null or int(definition.max_stack) <= 1:
			continue
		for source_index in range(target_index + 1, ids.size()):
			var source_id := String(ids[source_index])
			if source_id.is_empty() or source_id == target_id:
				continue
			target = gameplay_controller.get_item(target_id)
			var source = gameplay_controller.get_item(source_id)
			if target == null or source == null or not source.is_stack_compatible(target):
				continue
			var headroom := maxi(0, int(definition.max_stack) - int(target.quantity))
			if headroom <= 0:
				break
			var amount := mini(headroom, int(source.quantity))
			var result: Dictionary = command_facade.transfer_quantity(
				source_id,
				amount,
				container_id,
				int(target.relation.get("slot_index", -1)),
				target_id
			)
			if not bool(result.get("success", false)):
				_show_error("Не удалось объединить стаки: %s" % String(result.get("error_code", "UNKNOWN")))
				return false
	return true


func _sort_container_slots(container_id: String, player_inventory: bool) -> bool:
	var container = gameplay_controller.get_container(container_id)
	if container == null or not container.is_slot_container():
		_show_error("Сортировка требует слот-контейнер")
		return false
	var capacity := int(container.slot_count)
	var desired := _container_item_ids_by_name(container_id)
	if desired.is_empty():
		return true
	var slots := _slot_map(container_id, capacity)
	var empty_slot := _first_empty_slot(slots)
	var temporary_item_id := ""
	var temporary_kind := ""
	var temporary_slot := -1

	if empty_slot < 0:
		temporary_item_id = String(desired[desired.size() - 1])
		var source_slot := slots.find(temporary_item_id)
		if player_inventory:
			var hotbar = gameplay_controller.get_container(gameplay_controller.player_hotbar_id)
			if hotbar != null:
				for hotbar_index in range(int(hotbar.slot_count)):
					if String(hotbar.get_item_at_slot(hotbar_index)).is_empty():
						temporary_slot = hotbar_index
						break
			if temporary_slot >= 0:
				var temp_result: Dictionary = command_facade.transfer_quantity(
					temporary_item_id,
					-1,
					gameplay_controller.player_hotbar_id,
					temporary_slot,
					""
				)
				if bool(temp_result.get("success", false)):
					temporary_kind = "HOTBAR"
					slots[source_slot] = ""
					empty_slot = source_slot
		else:
			var player_free := _first_free_slot_for_container(String(gameplay_controller.player_inventory_id))
			if player_free >= 0:
				var temp_result: Dictionary = command_facade.transfer_quantity(
					temporary_item_id,
					-1,
					gameplay_controller.player_inventory_id,
					player_free,
					""
				)
				if bool(temp_result.get("success", false)):
					temporary_kind = "PLAYER_INVENTORY"
					temporary_slot = player_free
					slots[source_slot] = ""
					empty_slot = source_slot
		if empty_slot < 0:
			_show_error("Для полной сортировки нужен один свободный слот")
			return false

	for target_slot in range(desired.size()):
		var desired_id := String(desired[target_slot])
		if String(slots[target_slot]) == desired_id:
			continue
		var desired_source_slot := slots.find(desired_id)
		if desired_source_slot < 0:
			if desired_id != temporary_item_id:
				_show_error("Сортировка потеряла позицию предмета")
				return false
			# Keep the temporary item outside until its final alphabetical slot.
			if not String(slots[target_slot]).is_empty():
				var occupant_id := String(slots[target_slot])
				if not _move_whole_stack(occupant_id, container_id, empty_slot):
					return false
				slots[empty_slot] = occupant_id
				slots[target_slot] = ""
				empty_slot = target_slot
			if not _move_whole_stack(temporary_item_id, container_id, target_slot):
				return false
			slots[target_slot] = temporary_item_id
			temporary_item_id = ""
			continue
		if not String(slots[target_slot]).is_empty():
			var occupant_id := String(slots[target_slot])
			if not _move_whole_stack(occupant_id, container_id, empty_slot):
				return false
			slots[empty_slot] = occupant_id
			slots[target_slot] = ""
			empty_slot = target_slot
		if not _move_whole_stack(desired_id, container_id, target_slot):
			return false
		slots[desired_source_slot] = ""
		slots[target_slot] = desired_id
		empty_slot = desired_source_slot

	# Safety: if the temporary item was alphabetically last and the loop did not
	# consume it because of an already-matching slot, return it explicitly.
	if not temporary_item_id.is_empty():
		var final_slot := desired.find(temporary_item_id)
		if final_slot < 0:
			_show_error("Временный предмет отсутствует в плане сортировки")
			return false
		if not String(slots[final_slot]).is_empty():
			var occupant_id := String(slots[final_slot])
			if not _move_whole_stack(occupant_id, container_id, empty_slot):
				return false
			slots[empty_slot] = occupant_id
			slots[final_slot] = ""
		if not _move_whole_stack(temporary_item_id, container_id, final_slot):
			return false
	return true


func _move_whole_stack(item_id: String, container_id: String, target_slot: int) -> bool:
	if item_id.is_empty() or target_slot < 0:
		return false
	var result: Dictionary = command_facade.transfer_quantity(
		item_id,
		-1,
		container_id,
		target_slot,
		""
	)
	if not bool(result.get("success", false)):
		_show_error("Не удалось переместить предмет при сортировке: %s" % String(result.get("error_code", "UNKNOWN")))
		return false
	return true


func _container_item_ids_by_slot(container_id: String) -> Array[String]:
	var rows: Array[Dictionary] = []
	var container = gameplay_controller.get_container(container_id)
	if container == null:
		return []
	for item_id_value in container.item_ids:
		var item_id := String(item_id_value)
		var item = gameplay_controller.get_item(item_id)
		if item == null:
			continue
		rows.append({
			"item_id": item_id,
			"slot": int(item.relation.get("slot_index", 9999)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["slot"]) != int(b["slot"]):
			return int(a["slot"]) < int(b["slot"])
		return String(a["item_id"]) < String(b["item_id"])
	)
	var result: Array[String] = []
	for row in rows:
		result.append(String(row["item_id"]))
	return result


func _container_item_ids_by_name(container_id: String) -> Array[String]:
	var result := _container_item_ids_by_slot(container_id)
	result.sort_custom(func(a: String, b: String) -> bool:
		var item_a = gameplay_controller.get_item(a)
		var item_b = gameplay_controller.get_item(b)
		if item_a == null or item_b == null:
			return a < b
		var definition_a = gameplay_controller.get_definition(item_a.definition_id)
		var definition_b = gameplay_controller.get_definition(item_b.definition_id)
		var name_a := String(item_a.display_name)
		var name_b := String(item_b.display_name)
		if name_a.is_empty() and definition_a != null:
			name_a = String(definition_a.display_name)
		if name_b.is_empty() and definition_b != null:
			name_b = String(definition_b.display_name)
		var compare := name_a.naturalnocasecmp_to(name_b)
		if compare != 0:
			return compare < 0
		if String(item_a.definition_id) != String(item_b.definition_id):
			return String(item_a.definition_id) < String(item_b.definition_id)
		return a < b
	)
	return result


func _slot_map(container_id: String, capacity: int) -> Array[String]:
	var slots: Array[String] = []
	slots.resize(capacity)
	for index in range(capacity):
		slots[index] = ""
	var container = gameplay_controller.get_container(container_id)
	if container == null:
		return slots
	for item_id_value in container.item_ids:
		var item_id := String(item_id_value)
		var item = gameplay_controller.get_item(item_id)
		if item == null:
			continue
		var slot_index := int(item.relation.get("slot_index", -1))
		if slot_index >= 0 and slot_index < capacity:
			slots[slot_index] = item_id
	return slots


func _first_empty_slot(slots: Array[String]) -> int:
	for index in range(slots.size()):
		if String(slots[index]).is_empty():
			return index
	return -1


func _first_free_slot_for_container(container_id: String) -> int:
	var container = gameplay_controller.get_container(container_id)
	if container == null or not container.is_slot_container():
		return -1
	var slots := _slot_map(container_id, int(container.slot_count))
	return _first_empty_slot(slots)


func _refresh_screen() -> void:
	if screen != null and is_instance_valid(screen) and screen.has_method("refresh"):
		screen.refresh()


func _show_success(message: String) -> void:
	if screen == null:
		return
	var status_label = screen.get("status_label")
	if status_label != null:
		status_label.text = message
	var toast_layer = screen.get("toast_layer")
	if toast_layer != null and toast_layer.has_method("show_success"):
		toast_layer.show_success(message)


func _show_error(message: String) -> void:
	if screen == null:
		return
	var status_label = screen.get("status_label")
	if status_label != null:
		status_label.text = message
	var toast_layer = screen.get("toast_layer")
	if toast_layer != null and toast_layer.has_method("show_error"):
		toast_layer.show_error(message)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
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
