extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Gameplay = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const ContextMenu = preload("res://scripts/ui/inventory/item_context_menu.gd")

const STORE_ROOT := "user://planet_simulator/item_graphs"
const STATE_KEY := "test-inventory-ui-i1"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store = Factory.create_json_state_store(STORE_ROOT)
	store.delete_state(STATE_KEY)
	var fixture := await _create_controller()
	var controller = fixture.controller
	var ui = controller.inventory_ui
	var screen = ui.active_screen
	_assert(ui.using_component_screen(), "UI-I1 must run on component inventory shell")
	_assert(screen != null and screen.context_menu != null and screen.tooltip != null, "UI-I1 screen must expose context, tooltip and split components")
	_assert(screen.player_panel.grid.get_theme_constant("h_separation") == 0, "Player inventory cells must not have horizontal drop gaps")
	_assert(screen.player_panel.grid.get_theme_constant("v_separation") == 0, "Player inventory cells must not have vertical drop gaps")

	var crate = _find_item(controller, "portable_crate", "", Relations.WORLD)
	var rack = _find_item(controller, "battery_rack", "", Relations.WORLD)
	_assert(crate != null and rack != null, "Playground fixture must provide BULK crate and SLOTS rack")
	var crate_id: String = crate.get_owned_container_id()
	var rack_id: String = rack.get_owned_container_id()
	_assert_success(controller.open_container(crate_id), "Opening crate through E contract must establish active two-pane pair")
	_assert(screen.external_panel.visible and screen.external_container_id == crate_id, "Opened crate must be visible as external panel")
	_assert_success(controller.open_container(rack_id), "Opening battery rack must establish a slot-container drag target")
	var battery_for_drag = _find_item(controller, "battery_pack", controller.player_inventory_id)
	await _test_layout_stability(screen, battery_for_drag.instance_id)
	var battery_cell_for_drag = screen.player_panel.find_cell_by_item_id(battery_for_drag.instance_id)
	var middle_drag_payload = battery_cell_for_drag.build_middle_drag_payload()
	_assert(int(middle_drag_payload.get("quantity", 0)) == int(ceil(float(battery_for_drag.quantity) * 0.5)), "Middle-button drag must carry the upper half of a stack")
	var rack_cell_for_drag = screen.external_panel.grid.get_child(1)
	var drag_payload = battery_cell_for_drag.build_drag_payload(false)
	_assert(drag_payload is Dictionary and int(drag_payload.get("quantity", 0)) == int(battery_for_drag.quantity), "LMB drag must produce the complete battery stack payload")
	_assert(rack_cell_for_drag._can_drop_data(Vector2.ZERO, drag_payload), "Battery rack slot must accept the battery drag payload")
	rack_cell_for_drag._drop_data(Vector2.ZERO, drag_payload)
	_assert(String(battery_for_drag.relation.get("container_id", "")) == rack_id and int(battery_for_drag.relation.get("slot_index", -1)) == 1, "Dropping battery on an empty rack slot must move the complete stack")
	_assert_success(controller.move_item_to_container(battery_for_drag.instance_id, controller.player_inventory_id), "Battery must move back after drag contract check")
	_assert_success(controller.open_container(crate_id), "Switching back to crate must preserve the remaining inventory scenario")

	var beacon = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	_assert(beacon != null and int(beacon.quantity) == 3, "Starter backpack must contain a stack of three beacons")
	var beacon_total_before := _total_quantity(controller, "survey_beacon")
	var beacon_cell = screen.player_panel.find_cell_by_item_id(beacon.instance_id)
	_assert(beacon_cell != null, "Player panel must render beacon aggregate")
	var shift_click := InputEventMouseButton.new()
	shift_click.button_index = MOUSE_BUTTON_LEFT
	shift_click.pressed = true
	shift_click.shift_pressed = true
	beacon_cell._gui_input(shift_click)
	_assert(String(beacon.relation.get("container_id", "")) == crate_id, "Shift+LMB must quick-transfer whole stack to opened BULK container")
	_assert(_total_quantity(controller, "survey_beacon") == beacon_total_before, "Quick transfer must conserve beacon quantity")
	_assert(screen.toast_layer.visible and screen.toast_layer.message_kind == "success", "Successful quick transfer must show success toast")
	_assert(screen.external_panel.feedback_label.visible, "Successful transfer must give local feedback on target panel")

	var external_beacon = _find_item(controller, "survey_beacon", crate_id)
	_assert(external_beacon != null, "External crate must expose transferred beacon aggregate")
	var external_cell = screen.external_panel.find_cell_by_item_id(external_beacon.instance_id)
	_assert(external_cell != null, "External panel must render transferred aggregate")
	external_cell._on_mouse_entered()
	_assert(not screen.tooltip.visible, "Hovering item must not cover inventory cells with a tooltip")
	_assert(screen.inspector.current_item_id == external_beacon.instance_id, "Hovering item must show details in the dedicated inspector")
	_assert(screen.inspector.physical_label.text.contains("Масса:") and screen.inspector.physical_label.text.contains("Объём:"), "Inspector must show unit and total physical properties")
	_assert(screen.inspector.tags_label.text.contains("Категории:"), "Inspector must expose definition tags")
	external_cell._on_mouse_exited()
	_assert(not screen.tooltip.visible, "Leaving an item must keep the grid unobstructed")

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	right_press.position = Vector2(10, 10)
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	right_release.position = Vector2(10, 10)
	external_cell._gui_input(right_press)
	external_cell._gui_input(right_release)
	_assert(screen.context_menu.visible, "RMB click without dragging must open context menu")
	var context_labels := _popup_labels(screen.context_menu)
	_assert(context_labels.has("Осмотреть"), "Context menu must expose inspect action")
	_assert(context_labels.has("Перенести весь стак") and context_labels.has("Перенести количество…"), "Context menu must expose whole and exact transfer actions")
	_assert(context_labels.has("Выбросить 1") and context_labels.has("Выбросить весь стак"), "Context menu must expose safe explicit drop actions")

	screen.context_menu._on_action_pressed(ContextMenu.ACTION_INSPECT)
	_assert(not screen.tooltip.visible and screen.inspector.current_item_id == external_beacon.instance_id, "Inspect action must use the dedicated inspector instead of a pinned tooltip")
	var escape_tooltip := InputEventKey.new()
	escape_tooltip.keycode = KEY_ESCAPE
	escape_tooltip.pressed = true
	screen._input(escape_tooltip)
	_assert(screen.visible_inventory and screen.inspector.current_item_id.is_empty(), "Escape must clear the inspector without closing inventory")

	# Re-open context for exact transfer from crate back to backpack.
	external_cell = screen.external_panel.find_cell_by_item_id(external_beacon.instance_id)
	external_cell._gui_input(right_press)
	external_cell._gui_input(right_release)
	screen.context_menu._on_action_pressed(ContextMenu.ACTION_TRANSFER_EXACT)
	_assert(screen.split_dialog.visible, "Exact transfer context action must open explicit split dialog")
	_assert(int(screen.split_dialog.quantity_spin.max_value) == int(external_beacon.quantity), "Split dialog maximum must match currently movable quantity")
	screen.split_dialog.maximum_button.pressed.emit()
	_assert(int(screen.split_dialog.quantity_spin.value) == int(external_beacon.quantity), "Maximum shortcut must select full available quantity")
	screen.split_dialog.half_button.pressed.emit()
	var expected_half := maxi(1, int(ceil(float(external_beacon.quantity) * 0.5)))
	_assert(int(screen.split_dialog.quantity_spin.value) == expected_half, "Half shortcut must select deterministic upper half")
	screen.split_dialog.one_button.pressed.emit()
	_assert(int(screen.split_dialog.quantity_spin.value) == 1, "One shortcut must select one item")
	screen.split_dialog.quantity_spin.value = float(expected_half)
	screen.split_dialog._confirm()
	_assert(not screen.split_dialog.visible, "Confirming split must close dialog")
	var backpack_beacons := _quantity_in_container(controller, "survey_beacon", controller.player_inventory_id)
	_assert(backpack_beacons == expected_half, "Exact split transfer must move chosen quantity to backpack")
	_assert(_total_quantity(controller, "survey_beacon") == beacon_total_before, "Split transfer must conserve total quantity")

	# SLOTS whole-stack quick transfer must skip an earlier partial stack when a later slot fits all.
	_assert_success(controller.open_container(rack_id), "Switching interaction context to battery rack must work")
	var rack_container = controller.get_container(rack_id)
	rack_container.maximum_mass_kg = 200.0
	rack_container.maximum_volume_l = 120.0
	var partial_target = controller.get_item(String(rack_container.get_item_at_slot(0)))
	partial_target.quantity = 3
	var whole_source = controller.domain.items.create_item(
		"battery_pack",
		4,
		{},
		Relations.container(controller.player_inventory_id)
	)
	controller.get_container(controller.player_inventory_id).assign_item(whole_source.instance_id)
	screen.refresh()
	var whole_preview: Dictionary = screen.command_facade.preview_quick_transfer(
		whole_source.instance_id,
		controller.player_inventory_id,
		rack_id
	)
	_assert_success(whole_preview, "Whole-stack preview must find a later slot that accepts all four batteries")
	_assert(bool(whole_preview.get("whole_stack_fits", false)), "Whole-stack preview must explicitly confirm complete fit")
	_assert(int(whole_preview.get("target_slot_index", -1)) == 1, "Quick transfer must skip partial slot 0 and choose empty slot 1")
	_assert(int(whole_preview.get("maximum_quantity", 0)) == 4, "Selected quick-transfer slot must accept the full source quantity")
	var whole_cell = screen.player_panel.find_cell_by_item_id(whole_source.instance_id)
	_assert(whole_cell != null, "Player panel must render whole-stack battery fixture")
	whole_cell._gui_input(shift_click)
	_assert(String(whole_source.relation.get("container_id", "")) == rack_id, "Shift+LMB must move the complete battery stack into rack")
	_assert(int(whole_source.relation.get("slot_index", -1)) == 1 and int(whole_source.quantity) == 4, "Complete source aggregate must occupy empty slot 1 without splitting")
	_assert(int(partial_target.quantity) == 3, "Earlier partial stack must remain unchanged when a full-fit slot exists")
	_assert(screen.toast_layer.message_kind == "success" and screen.toast_layer.message_label.text.contains("×4"), "Quick-transfer toast must report actual moved quantity ×4")

	# If no single slot can accept the whole request, quick-transfer must reject instead of silently moving a fragment.
	for slot_index in [2, 3]:
		var filler = controller.domain.items.create_item(
			"battery_pack",
			4,
			{},
			Relations.container(rack_id, slot_index)
		)
		rack_container.assign_item(filler.instance_id, slot_index)
	var blocked_source = controller.domain.items.create_item(
		"battery_pack",
		4,
		{},
		Relations.container(controller.player_inventory_id)
	)
	controller.get_container(controller.player_inventory_id).assign_item(blocked_source.instance_id)
	screen.refresh()
	var blocked_preview: Dictionary = screen.command_facade.preview_quick_transfer(
		blocked_source.instance_id,
		controller.player_inventory_id,
		rack_id
	)
	_assert(bool(blocked_preview.get("success", false)) and not bool(blocked_preview.get("whole_stack_fits", true)), "Partial stack may be exposed only as a split-dialog preview hint")
	_assert(int(blocked_preview.get("maximum_quantity", 0)) == 1, "Partial preview must expose only real headroom in slot 0")
	var blocked_relation: Dictionary = blocked_source.relation.duplicate(true)
	var partial_before := int(partial_target.quantity)
	var blocked_cell = screen.player_panel.find_cell_by_item_id(blocked_source.instance_id)
	blocked_cell._gui_input(shift_click)
	_assert(blocked_source.relation == blocked_relation and int(blocked_source.quantity) == 4, "Whole-stack quick transfer must not mutate source when no single slot fits")
	_assert(int(partial_target.quantity) == partial_before, "Rejected whole-stack transfer must not partially fill target stack")
	_assert(screen.toast_layer.message_kind == "error", "Rejected incomplete quick transfer must show an error toast")
	_assert(screen.toast_layer.message_label.text.contains("недостаточно места"), "Rejected toast must explain that one slot cannot fit the whole stack")

	# Invalid quick transfer to battery-only rack must stay local and explain failure.
	var player_beacon = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	var player_beacon_relation: Dictionary = player_beacon.relation.duplicate(true)
	var invalid_cell = screen.player_panel.find_cell_by_item_id(player_beacon.instance_id)
	invalid_cell._gui_input(shift_click)
	_assert(player_beacon.relation == player_beacon_relation, "Rejected Shift+LMB must not mutate source item")
	_assert(screen.toast_layer.visible and screen.toast_layer.message_kind == "error", "Rejected quick transfer must show error toast")
	_assert(screen.external_panel.feedback_label.visible, "Rejected transfer must show reason inside target container boundary")
	_assert(not screen.external_panel.feedback_label.text.is_empty(), "Local rejection feedback must contain user-facing reason")

	# Context hotbar assignment must use exact domain slot and remain graph-safe.
	invalid_cell = screen.player_panel.find_cell_by_item_id(player_beacon.instance_id)
	invalid_cell._gui_input(right_press)
	invalid_cell._gui_input(right_release)
	var hotbar_slots: Array[Dictionary] = screen.command_facade.hotbar_slot_options(player_beacon.instance_id)
	var chosen_slot := -1
	for slot in hotbar_slots:
		if bool(slot.get("enabled", false)) and not bool(slot.get("occupied", false)):
			chosen_slot = int(slot.get("slot_index", -1))
			break
	_assert(chosen_slot >= 0, "At least one hotbar slot must accept beacon")
	var hotbar_context: Dictionary = screen.context_menu.context.duplicate(true)
	hotbar_context["hotbar_slot_index"] = chosen_slot
	screen._on_context_action_requested(ContextMenu.ACTION_HOTBAR_SLOT_BASE + chosen_slot, hotbar_context)
	_assert(String(controller.get_container(controller.player_hotbar_id).get_item_at_slot(chosen_slot)) == player_beacon.instance_id, "Context hotbar action must move exact aggregate into requested slot")
	_assert(screen.toast_layer.message_kind == "success", "Hotbar assignment must report success")

	# Explicit drop-one and drop-all context actions use controller service, not direct UI mutations.
	var battery = _find_item(controller, "battery_pack", controller.player_inventory_id)
	_assert(battery != null and int(battery.quantity) == 2, "Starter battery stack must be available for drop actions")
	var battery_cell = screen.player_panel.find_cell_by_item_id(battery.instance_id)
	battery_cell._gui_input(right_press)
	battery_cell._gui_input(right_release)
	var battery_context: Dictionary = screen.context_menu.context.duplicate(true)
	screen._on_context_action_requested(ContextMenu.ACTION_DROP_ONE, battery_context)
	_assert(int(battery.quantity) == 1, "Drop one action must split exactly one unit from stack")
	_assert(_count_world_items(controller, "battery_pack") == 1, "Drop one must create one independent WORLD aggregate")
	battery_cell = screen.player_panel.find_cell_by_item_id(battery.instance_id)
	battery_cell._gui_input(right_press)
	battery_cell._gui_input(right_release)
	battery_context = screen.context_menu.context.duplicate(true)
	screen._on_context_action_requested(ContextMenu.ACTION_DROP_ALL, battery_context)
	_assert(Relations.kind_of(battery.relation) == Relations.WORLD, "Drop all must move remaining source aggregate to WORLD")
	_assert(_count_world_items(controller, "battery_pack") == 2, "Drop all after drop one must leave two independent WORLD aggregates")

	_assert_success(controller.domain.validator.validate_graph(), "UI-I1 interactions must preserve unique memberships and relations")
	_assert(_total_quantity(controller, "survey_beacon") == beacon_total_before, "UI-I1 scenario must finish without beacon loss or duplication")
	store.delete_state(STATE_KEY)
	controller.queue_free()
	await process_frame
	_finish()


func _test_layout_stability(screen, item_id: String) -> void:
	await process_frame
	var initial_size: Vector2 = screen.size
	screen._on_item_selected(item_id)
	await process_frame
	_assert(screen.size.is_equal_approx(initial_size), "Inventory size must stay stable after inspector content appears")
	screen.view_model.clear_selected_item()
	screen.refresh()
	await process_frame
	_assert(screen.size.is_equal_approx(initial_size), "Inventory size must stay stable after inspector content is cleared")


func _create_controller() -> Dictionary:
	var world_root := Node3D.new()
	world_root.name = "WorldRoot"
	get_root().add_child(world_root)
	var attachment_root := Node3D.new()
	attachment_root.name = "AttachmentRoot"
	get_root().add_child(attachment_root)
	var controller = Gameplay.new()
	controller.name = "ItemGameplayController"
	get_root().add_child(controller)
	var setup: Dictionary = controller.setup_runtime(
		null,
		world_root,
		attachment_root,
		null,
		"scenario/local",
		"",
		STATE_KEY,
		"playground",
		true
	)
	await process_frame
	return {"controller": controller, "setup": setup}


func _popup_labels(menu: PopupMenu) -> PackedStringArray:
	var labels := PackedStringArray()
	for index in range(menu.item_count):
		var text := menu.get_item_text(index)
		if not text.is_empty():
			labels.append(text)
	return labels


func _find_item(controller, definition_id: String, container_id: String = "", relation_kind: String = Relations.CONTAINER):
	for item in controller.domain.items.all_items():
		if item.definition_id != definition_id:
			continue
		if not relation_kind.is_empty() and Relations.kind_of(item.relation) != relation_kind:
			continue
		if not container_id.is_empty() and String(item.relation.get("container_id", "")) != container_id:
			continue
		return item
	return null


func _quantity_in_container(controller, definition_id: String, container_id: String) -> int:
	var total := 0
	for item in controller.domain.items.all_items():
		if item.definition_id == definition_id and Relations.kind_of(item.relation) == Relations.CONTAINER and String(item.relation.get("container_id", "")) == container_id:
			total += int(item.quantity)
	return total


func _total_quantity(controller, definition_id: String) -> int:
	var total := 0
	for item in controller.domain.items.all_items():
		if item.definition_id == definition_id:
			total += int(item.quantity)
	return total


func _count_world_items(controller, definition_id: String) -> int:
	var count := 0
	for item in controller.domain.items.all_items():
		if item.definition_id == definition_id and Relations.kind_of(item.relation) == Relations.WORLD:
			count += 1
	return count


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Inventory UI-I1 interactions: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory UI-I1 interactions: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
