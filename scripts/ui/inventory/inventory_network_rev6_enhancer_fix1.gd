extends Node

# Networked 7-Days-like inventory hardening. All canonical mutations still go
# through the existing M7/NX6 command path. Carry visuals are presentation-only.

const FIX_SCHEMA: String = "planet_simulator.inventory_network_rev6_enhancer.fix5.v1"
const CarryAwareProjection = preload(
	"res://scripts/ui/inventory/interactions/inventory_slot_projection_carry_aware.gd"
)

const SORT_BUTTON_SIZE := Vector2(112.0, 30.0)
const SORT_BUTTON_MARGIN := Vector2(8.0, 6.0)
const INTERACTION_HINT_POSITION := Vector2(-300.0, -170.0)
const INTERACTION_HINT_SIZE := Vector2(600.0, 72.0)
const AUTHORITATIVE_TRANSFER_TIMEOUT_MS: int = 12000

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
var _carry_overlay_quantity: int = 0
var _pickup_queue: Array = []
var _pickup_merge_in_progress: bool = false
var _sort_in_progress: bool = false
var _pickup_stack_operations: int = 0
var _sort_operations: int = 0
var _pointer_repairs: int = 0
var _carry_suppressions: int = 0
var _sort_layout_updates: int = 0
var _interaction_hint_layout_updates: int = 0
var _authoritative_sort_waits: int = 0
var _authoritative_sort_failures: int = 0
var _hotbar_overlay_renders: int = 0
var _sort_click_guards: int = 0


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
	if gameplay_controller.has_signal("gameplay_state_changed"):
		var state_callback: Callable = Callable(self, "_on_gameplay_state_changed")
		if not gameplay_controller.is_connected("gameplay_state_changed", state_callback):
			gameplay_controller.connect("gameplay_state_changed", state_callback)

	set_process(true)
	call_deferred("_refresh_screen")
	call_deferred("_layout_sort_buttons")
	call_deferred("_layout_interaction_hint")
	return {
		"success": true,
		"error_code": "",
		"details": {
			"schema": FIX_SCHEMA,
			"carry_aware_projection": true,
			"carry_partial_remainder": true,
			"carry_hotbar_overlay": true,
			"sort_buttons": true,
			"sort_buttons_overlay": true,
			"sort_authoritative_serial": true,
			"interaction_hint_above_hotbar": true,
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
	if carry_active:
		_sync_origin_carry_overlay(false)
	elif _last_carry_active:
		_clear_origin_suppression(true)

	if not carry_active:
		var carry_preview = screen.get("carry_preview")
		if carry_preview != null and is_instance_valid(carry_preview):
			carry_preview.set("visible", false)

	_last_carry_active = carry_active
	_update_sort_button_visibility(inventory_visible, carry_active)
	_layout_sort_buttons()
	_layout_interaction_hint()
	_process_pickup_queue()


func _session_is_active(transfer_session) -> bool:
	if transfer_session == null or not transfer_session.has_method("is_active"):
		return false
	return bool(transfer_session.call("is_active"))


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


func _create_sort_button(node_name: String, caption: String, hint: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = caption
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = SORT_BUTTON_SIZE
	button.size = SORT_BUTTON_SIZE
	button.top_level = true
	button.z_as_relative = false
	button.z_index = 3000
	return button


func _wire_sort_button_input(button: Button) -> void:
	if button == null or bool(button.get_meta("rev6_sort_input_guard", false)):
		return
	button.set_meta("rev6_sort_input_guard", true)
	button.gui_input.connect(Callable(self, "_on_sort_button_gui_input").bind(button))


func _on_sort_button_gui_input(event: InputEvent, button: Button) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Prevent the click/release from falling through to the playground global
	# mouse-capture shortcut. Capturing the mouse recenters it on Windows.
	var viewport := button.get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sort_click_guards += 1


func _keep_inventory_pointer_visible() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pointer_repairs += 1
	if screen != null and screen.get_viewport() != null:
		screen.get_viewport().set_input_as_handled()


func _layout_sort_buttons() -> void:
	if screen == null or not is_instance_valid(screen):
		return
	var player_panel = screen.get("player_panel")
	var external_panel = screen.get("external_panel")
	_layout_sort_button_for_panel(player_sort_button, player_panel)
	_layout_sort_button_for_panel(external_sort_button, external_panel)
	_sort_layout_updates += 1


func _layout_sort_button_for_panel(button: Button, panel) -> void:
	if button == null or panel == null or not is_instance_valid(panel):
		return
	if not panel is Control:
		return
	var panel_control := panel as Control
	var panel_rect: Rect2 = panel_control.get_global_rect()
	button.size = SORT_BUTTON_SIZE
	button.global_position = Vector2(
		panel_rect.end.x - SORT_BUTTON_SIZE.x - SORT_BUTTON_MARGIN.x,
		panel_rect.position.y + SORT_BUTTON_MARGIN.y
	)


func _layout_interaction_hint() -> void:
	var runtime = get_parent()
	if runtime == null:
		return
	var hint = runtime.get("interaction_label")
	if hint == null or not is_instance_valid(hint) or not hint is Control:
		return
	var hint_control := hint as Control
	hint_control.position = INTERACTION_HINT_POSITION
	hint_control.size = INTERACTION_HINT_SIZE
	_interaction_hint_layout_updates += 1


func _update_sort_button_visibility(inventory_visible: bool, carry_active: bool) -> void:
	var seven_days: bool = false
	var profile = screen.get("active_interaction_profile")
	if profile != null:
		seven_days = String(profile.get("profile_id")) == "seven_days_like"
	var allow_sort: bool = inventory_visible and seven_days and not carry_active and not _sort_in_progress
	if player_sort_button != null:
		player_sort_button.visible = allow_sort
	if external_sort_button != null:
		external_sort_button.visible = (
			allow_sort
			and not String(screen.get("external_container_id")).is_empty()
		)


func _apply_origin_suppression() -> void:
	_sync_origin_carry_overlay(true)


func _sync_origin_carry_overlay(force_refresh: bool) -> void:
	if projection == null or screen == null:
		return
	var transfer_session = screen.get("transfer_session")
	var cursor_controller = screen.get("cursor_controller")
	if not _session_is_active(transfer_session) or cursor_controller == null:
		return
	if not cursor_controller.has_method("debug_snapshot"):
		return
	var cursor_debug: Dictionary = Dictionary(cursor_controller.call("debug_snapshot"))
	if not bool(cursor_debug.get("network_virtual", false)):
		return

	var origin_item_id: String = String(transfer_session.get("origin_item_id"))
	var origin_container_id: String = String(transfer_session.get("source_container_id"))
	var cursor_quantity: int = maxi(0, int(transfer_session.get("remaining_quantity")))
	if origin_item_id.is_empty() or origin_container_id.is_empty() or cursor_quantity <= 0:
		return

	var changed_origin: bool = (
		origin_item_id != _suppressed_item_id
		or origin_container_id != _suppressed_container_id
	)
	var changed_quantity: bool = cursor_quantity != _carry_overlay_quantity
	if not force_refresh and not changed_origin and not changed_quantity:
		return

	if changed_origin and not _suppressed_item_id.is_empty() and not _suppressed_container_id.is_empty():
		projection.reveal_item(_suppressed_container_id, _suppressed_item_id)

	if changed_origin:
		_carry_suppressions += 1
	_suppressed_container_id = origin_container_id
	_suppressed_item_id = origin_item_id
	_carry_overlay_quantity = cursor_quantity
	projection.set_carried_quantity(origin_container_id, origin_item_id, cursor_quantity)
	call_deferred("_refresh_screen")
	call_deferred("_refresh_persistent_hotbar_overlay")


func _clear_origin_suppression(refresh_after: bool) -> void:
	var source_was_hotbar: bool = _suppressed_container_id == String(gameplay_controller.player_hotbar_id)
	if projection != null and not _suppressed_container_id.is_empty() and not _suppressed_item_id.is_empty():
		projection.reveal_item(_suppressed_container_id, _suppressed_item_id)
	_suppressed_container_id = ""
	_suppressed_item_id = ""
	_carry_overlay_quantity = 0
	if refresh_after:
		call_deferred("_refresh_screen")
	if source_was_hotbar:
		call_deferred("_refresh_persistent_hotbar_normal")


func _refresh_persistent_hotbar_overlay() -> void:
	if (
		inventory_ui == null
		or projection == null
		or _suppressed_container_id != String(gameplay_controller.player_hotbar_id)
	):
		return
	var persistent_hotbar = inventory_ui.get("persistent_hotbar")
	var view_model = screen.get("view_model")
	if persistent_hotbar == null or view_model == null:
		return
	if not persistent_hotbar.has_method("render_hotbar") or not view_model.has_method("build_container"):
		return
	var model_value = view_model.call(
		"build_container",
		gameplay_controller.player_hotbar_id,
		int(gameplay_controller.selected_hotbar_index)
	)
	if not model_value is Dictionary:
		return
	var model: Dictionary = projection.apply_carry_overlay(Dictionary(model_value))
	var profile = screen.get("active_interaction_profile")
	if profile != null and persistent_hotbar.has_method("set_interaction_profile"):
		persistent_hotbar.call("set_interaction_profile", profile)
	persistent_hotbar.call(
		"render_hotbar",
		model,
		Callable(screen, "_icon_for_cell"),
		Callable(command_facade, "preview_transfer")
	)
	_hotbar_overlay_renders += 1


func _refresh_persistent_hotbar_normal() -> void:
	if inventory_ui != null and inventory_ui.has_method("_refresh_persistent_hotbar"):
		inventory_ui.call("_refresh_persistent_hotbar")


func _on_gameplay_state_changed() -> void:
	if not _suppressed_container_id.is_empty():
		call_deferred("_refresh_persistent_hotbar_overlay")


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
	if _pickup_queue.is_empty() or _sort_in_progress or _pickup_merge_in_progress:
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
	_pickup_merge_in_progress = true
	_run_pickup_merge()


func _run_pickup_merge() -> void:
	var result: Dictionary = await _merge_container_stacks_serial(
		String(gameplay_controller.player_inventory_id)
	)
	_pickup_merge_in_progress = false
	if bool(result.get("success", false)):
		_pickup_stack_operations += 1
		call_deferred("_refresh_screen")


func _on_player_sort_pressed() -> void:
	_keep_inventory_pointer_visible()
	_sort_container(String(gameplay_controller.player_inventory_id), true)


func _on_external_sort_pressed() -> void:
	_keep_inventory_pointer_visible()
	var container_id: String = String(screen.get("external_container_id"))
	if not container_id.is_empty():
		_sort_container(container_id, false)


func _sort_container(container_id: String, player_inventory: bool) -> void:
	if _sort_in_progress or _pickup_merge_in_progress or container_id.is_empty():
		return
	var transfer_session = screen.get("transfer_session")
	if _session_is_active(transfer_session):
		_show_error("Сначала завершите перенос предмета")
		return
	_sort_in_progress = true
	_update_sort_button_visibility(true, false)
	_show_status("Сортировка…")
	_run_sort_container(container_id, player_inventory)


func _run_sort_container(container_id: String, player_inventory: bool) -> void:
	var merge_result: Dictionary = await _merge_container_stacks_serial(container_id)
	if not bool(merge_result.get("success", false)):
		_sort_in_progress = false
		_show_error("Не удалось объединить стаки: %s" % String(merge_result.get("error_code", "UNKNOWN")))
		return
	_refresh_screen()
	var sort_result: Dictionary = await _sort_container_slots_serial(container_id, player_inventory)
	_sort_in_progress = false
	_refresh_screen()
	_keep_inventory_pointer_visible()
	if bool(sort_result.get("success", false)):
		_sort_operations += 1
		_show_success("Стаки объединены, предметы отсортированы по названию")
	else:
		_show_error(String(sort_result.get("message", "Сортировка не завершена: %s" % String(sort_result.get("error_code", "UNKNOWN")))))


func _merge_container_stacks_serial(container_id: String) -> Dictionary:
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
			if amount <= 0:
				continue
			var target_relation: Dictionary = Dictionary(target.get("relation"))
			var merge_result: Dictionary = await _submit_transfer_and_wait(
				source_id,
				amount,
				container_id,
				int(target_relation.get("slot_index", -1)),
				target_id
			)
			if not bool(merge_result.get("success", false)):
				return merge_result
	return _success()


func _sort_container_slots_serial(container_id: String, player_inventory: bool) -> Dictionary:
	var container = gameplay_controller.get_container(container_id)
	if container == null or not bool(container.call("is_slot_container")):
		return _failure("SORT_REQUIRES_SLOT_CONTAINER", "Сортировка требует слот-контейнер")

	var capacity: int = int(container.get("slot_count"))
	var desired: Array = _container_item_ids_by_name(container_id)
	if desired.is_empty():
		return _success()
	var slots: Array = _slot_map(container_id, capacity)
	var empty_slot: int = _first_empty_slot(slots)
	var temporary_item_id: String = ""

	if empty_slot < 0:
		temporary_item_id = String(desired[desired.size() - 1])
		var temporary_source_slot: int = slots.find(temporary_item_id)
		if temporary_source_slot < 0:
			return _failure("SORT_TEMP_ITEM_NOT_FOUND", "Сортировка не нашла временный предмет")

		var moved_to_buffer: bool = false
		if player_inventory:
			var hotbar = gameplay_controller.get_container(gameplay_controller.player_hotbar_id)
			if hotbar != null:
				for hotbar_index in range(int(hotbar.get("slot_count"))):
					if not String(hotbar.call("get_item_at_slot", hotbar_index)).is_empty():
						continue
					var hotbar_result: Dictionary = await _submit_transfer_and_wait(
						temporary_item_id,
						-1,
						gameplay_controller.player_hotbar_id,
						hotbar_index,
						""
					)
					moved_to_buffer = bool(hotbar_result.get("success", false))
					if not moved_to_buffer:
						return hotbar_result
					break
		else:
			var player_free: int = _first_free_slot_for_container(String(gameplay_controller.player_inventory_id))
			if player_free >= 0:
				var inventory_result: Dictionary = await _submit_transfer_and_wait(
					temporary_item_id,
					-1,
					gameplay_controller.player_inventory_id,
					player_free,
					""
				)
				moved_to_buffer = bool(inventory_result.get("success", false))
				if not moved_to_buffer:
					return inventory_result

		if not moved_to_buffer:
			return _failure("SORT_TEMP_SLOT_REQUIRED", "Для полной сортировки нужен один свободный слот")
		slots[temporary_source_slot] = ""
		empty_slot = temporary_source_slot

	for target_slot in range(desired.size()):
		var desired_id: String = String(desired[target_slot])
		if String(slots[target_slot]) == desired_id:
			continue

		var desired_source_slot: int = slots.find(desired_id)
		if desired_source_slot < 0:
			if desired_id != temporary_item_id:
				return _failure("SORT_ITEM_POSITION_LOST", "Сортировка потеряла позицию предмета")
			if not String(slots[target_slot]).is_empty():
				var buffered_occupant: String = String(slots[target_slot])
				var buffered_result: Dictionary = await _move_whole_stack_serial(
					buffered_occupant, container_id, empty_slot
				)
				if not bool(buffered_result.get("success", false)):
					return buffered_result
				slots[empty_slot] = buffered_occupant
				slots[target_slot] = ""
				empty_slot = target_slot
			var temp_place_result: Dictionary = await _move_whole_stack_serial(
				temporary_item_id, container_id, target_slot
			)
			if not bool(temp_place_result.get("success", false)):
				return temp_place_result
			slots[target_slot] = temporary_item_id
			temporary_item_id = ""
			continue

		if not String(slots[target_slot]).is_empty():
			var displaced_id: String = String(slots[target_slot])
			var displaced_result: Dictionary = await _move_whole_stack_serial(
				displaced_id, container_id, empty_slot
			)
			if not bool(displaced_result.get("success", false)):
				return displaced_result
			slots[empty_slot] = displaced_id
			slots[target_slot] = ""
			empty_slot = target_slot

		var desired_result: Dictionary = await _move_whole_stack_serial(
			desired_id, container_id, target_slot
		)
		if not bool(desired_result.get("success", false)):
			return desired_result
		slots[desired_source_slot] = ""
		slots[target_slot] = desired_id
		empty_slot = desired_source_slot

	if not temporary_item_id.is_empty():
		var final_slot: int = desired.find(temporary_item_id)
		if final_slot < 0:
			return _failure("SORT_TEMP_PLAN_MISSING", "Временный предмет отсутствует в плане сортировки")
		if not String(slots[final_slot]).is_empty():
			var final_displaced_id: String = String(slots[final_slot])
			var final_displaced_result: Dictionary = await _move_whole_stack_serial(
				final_displaced_id, container_id, empty_slot
			)
			if not bool(final_displaced_result.get("success", false)):
				return final_displaced_result
			slots[empty_slot] = final_displaced_id
			slots[final_slot] = ""
		var final_result: Dictionary = await _move_whole_stack_serial(
			temporary_item_id, container_id, final_slot
		)
		if not bool(final_result.get("success", false)):
			return final_result
	return _success()


func _move_whole_stack_serial(item_id: String, container_id: String, target_slot: int) -> Dictionary:
	if item_id.is_empty() or target_slot < 0:
		return _failure("SORT_MOVE_INVALID")
	return await _submit_transfer_and_wait(
		item_id,
		-1,
		container_id,
		target_slot,
		""
	)


func _submit_transfer_and_wait(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int,
	target_item_id: String
) -> Dictionary:
	var submit_result: Dictionary = command_facade.transfer_quantity(
		item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	if not bool(submit_result.get("success", false)):
		_authoritative_sort_failures += 1
		return submit_result
	if not bool(submit_result.get("pending", false)):
		return submit_result

	var operation_id: String = String(submit_result.get(
		"operation_id",
		submit_result.get("prediction_id", "")
	))
	if operation_id.is_empty():
		_authoritative_sort_failures += 1
		return _failure("SORT_PENDING_OPERATION_ID_MISSING")
	if bridge == null or not bridge.has_method("wait_for_authoritative_completion"):
		_authoritative_sort_failures += 1
		return _failure("SORT_AUTHORITATIVE_WAIT_UNAVAILABLE")

	_authoritative_sort_waits += 1
	var completion_value = await bridge.call(
		"wait_for_authoritative_completion",
		operation_id,
		AUTHORITATIVE_TRANSFER_TIMEOUT_MS
	)
	if not completion_value is Dictionary:
		_authoritative_sort_failures += 1
		return _failure("SORT_AUTHORITATIVE_RESULT_INVALID")
	var completion: Dictionary = Dictionary(completion_value).duplicate(true)
	if bridge.has_method("take_authoritative_completion"):
		bridge.call("take_authoritative_completion", operation_id)
	if not bool(completion.get("success", false)):
		_authoritative_sort_failures += 1
		return completion
	var tree := get_tree()
	if tree != null:
		await tree.process_frame
	return completion


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
	if not _suppressed_container_id.is_empty():
		call_deferred("_refresh_persistent_hotbar_overlay")


func _show_status(message: String) -> void:
	if screen == null:
		return
	var status_label = screen.get("status_label")
	if status_label != null:
		status_label.set("text", message)


func _show_success(message: String) -> void:
	_show_status(message)
	if screen == null:
		return
	var toast_layer = screen.get("toast_layer")
	if toast_layer != null and toast_layer.has_method("show_success"):
		toast_layer.call("show_success", message)


func _show_error(message: String) -> void:
	_show_status(message)
	if screen == null:
		return
	var toast_layer = screen.get("toast_layer")
	if toast_layer != null and toast_layer.has_method("show_error"):
		toast_layer.call("show_error", message)


func get_report() -> Dictionary:
	return {
		"schema": FIX_SCHEMA,
		"pickup_stack_mode": "CONSOLIDATE_COMPATIBLE_ON_PICKUP_COMPLETION",
		"sort_mode": "AUTHORITATIVE_SERIAL_TRANSFER",
		"pickup_queue": _pickup_queue.size(),
		"pickup_merge_in_progress": _pickup_merge_in_progress,
		"pickup_stack_operations": _pickup_stack_operations,
		"sort_operations": _sort_operations,
		"sort_in_progress": _sort_in_progress,
		"authoritative_sort_waits": _authoritative_sort_waits,
		"authoritative_sort_failures": _authoritative_sort_failures,
		"pointer_repairs": _pointer_repairs,
		"sort_click_guards": _sort_click_guards,
		"carry_suppressions": _carry_suppressions,
		"suppressed_container_id": _suppressed_container_id,
		"suppressed_item_id": _suppressed_item_id,
		"carry_overlay_quantity": _carry_overlay_quantity,
		"hotbar_overlay_renders": _hotbar_overlay_renders,
		"sort_layout_updates": _sort_layout_updates,
		"interaction_hint_layout_updates": _interaction_hint_layout_updates,
		"sort_button_size": SORT_BUTTON_SIZE,
		"interaction_hint_position": INTERACTION_HINT_POSITION,
		"projection": projection.debug_snapshot() if projection != null else {},
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, message: String = "") -> Dictionary:
	var result := {"success": false, "error_code": error_code, "details": {}}
	if not message.is_empty():
		result["message"] = message
	return result
