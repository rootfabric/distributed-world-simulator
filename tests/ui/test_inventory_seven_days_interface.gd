extends SceneTree

const Gameplay = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const PreferencesStore = preload("res://scripts/ui/inventory/inventory_preferences_store.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")

const STORE_ROOT := "user://planet_simulator/item_graphs"
const STATE_KEY := "test-inventory-seven-days-interface"
const PREFERENCES_SCOPE := "playground"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state_store = Factory.create_json_state_store(STORE_ROOT)
	state_store.delete_state(STATE_KEY)
	var preferences := PreferencesStore.new()
	preferences.setup(PREFERENCES_SCOPE)
	preferences.delete_preferences()
	var fixture: Dictionary = await _create_controller()
	var controller = fixture.controller
	var screen = controller.inventory_ui.active_screen
	_assert_success(Dictionary(fixture.setup), "7 Days interface fixture must initialize")
	controller.set_inventory_visible(true)
	var seven_profile = screen.interaction_profile_loader.get_profile("seven_days_like")
	screen._apply_interaction_profile(seven_profile, false, true)

	_test_profile_and_skin(screen, seven_profile)
	await _test_first_open_layout_and_escape(controller, screen)
	_test_fixed_slot_projection(controller, screen)
	await _test_immediate_pickup_pointer_and_hover(controller, screen)
	_test_click_move_between_visual_slots(controller, screen)
	_test_half_pickup_and_single_place(controller, screen)
	_test_occupied_slot_swap(controller, screen)
	_test_swap_cancel_unwinds(controller, screen)
	_test_shift_quick_transfer(controller, screen)
	_test_slot_persistence(controller, screen)
	_test_background_drop_one_keeps_cursor(controller, screen)
	_test_background_drop_all(controller, screen)
	_assert_success(controller.domain.validator.validate_graph(), "7 Days interactions must preserve complete Item Graph")
	_assert(not controller.is_transient_inventory_cursor_active(), "All tests must finish without transient cursor state")

	state_store.delete_state(STATE_KEY)
	preferences.delete_preferences()
	controller.queue_free()
	fixture.world_root.queue_free()
	fixture.attachment_root.queue_free()
	await process_frame
	_finish()


func _test_profile_and_skin(screen, seven_profile) -> void:
	_assert(seven_profile != null, "7 Days profile must load")
	_assert(seven_profile.ui_style == "SEVEN_DAYS", "7 Days profile must select dedicated visual skin")
	_assert(seven_profile.container_layout == "FIXED_SLOTS", "7 Days profile must request fixed slot projection")
	_assert(seven_profile.slot_columns == 10, "7 Days profile must render ten inventory columns")
	_assert(seven_profile.resolve("PRIMARY_DRAG").is_empty(), "7 Days LMB must be click-to-carry, not native drag-and-drop")
	_assert(not screen.get_node("Margin/Main/Header").visible, "7 Days skin must hide generic inventory heading")
	_assert(not screen.search_edit.visible and not screen.filter_option.visible and not screen.sort_option.visible, "7 Days skin must hide projection controls")
	_assert(not screen.inspector_toggle.visible, "7 Days skin must remove generic inspector toggle")
	_assert(screen.custom_minimum_size.x >= 1000.0, "7 Days skin must provide a wide two-container workspace")
	_assert(screen.player_panel.title_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "7 Days panel titles must use left-aligned black-bar layout")
	_assert(screen.columns.get_child(0) == screen.external_panel and screen.columns.get_child(1) == screen.player_panel, "7 Days layout must place external container left and player inventory right")
	_assert(not screen.inspector.visible, "7 Days two-grid workspace must hide generic inspector column")
	_assert(screen.player_panel.grid.get_theme_constant("h_separation") == 0, "Inventory slots must not have horizontal drop gaps")
	_assert(screen.player_panel.grid.get_theme_constant("v_separation") == 0, "Inventory slots must not have vertical drop gaps")


func _test_first_open_layout_and_escape(controller, screen) -> void:
	controller.set_inventory_visible(false)
	controller.set_inventory_visible(true)
	await process_frame
	var expected_position: Vector2 = (screen.get_viewport().get_visible_rect().size - screen.size) * 0.5
	_assert(
		screen.position.is_equal_approx(expected_position),
		"7 Days inventory must be centered immediately after opening: actual=%s expected=%s size=%s viewport=%s" % [
			screen.position,
			expected_position,
			screen.size,
			screen.get_viewport().get_visible_rect().size,
		]
	)
	var expected_size: Vector2 = screen.size
	screen.size = screen.get_viewport().get_visible_rect().size
	await process_frame
	_assert(screen.size.is_equal_approx(expected_size), "A late root-Control resize must be corrected without inventory interaction")
	expected_position = (screen.get_viewport().get_visible_rect().size - screen.size) * 0.5
	_assert(screen.position.is_equal_approx(expected_position), "A corrected late resize must keep the inventory centered")
	for frame_index in range(3):
		await process_frame
		_assert(screen.size.is_equal_approx(expected_size), "Inventory size must remain stable on idle frame %d" % frame_index)
		_assert(screen.position.is_equal_approx(expected_position), "Inventory position must remain centered on idle frame %d" % frame_index)
	var selected_item = _first_item_in_container(controller, controller.player_inventory_id)
	_assert(selected_item != null, "Escape regression fixture must provide a player item")
	if selected_item == null:
		return
	screen._on_item_selected(String(selected_item.instance_id))
	_assert(not screen.inspector.visible and not screen.inspector.current_item_id.is_empty(), "7 Days selection must not reveal the hidden inspector")
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	screen._input(escape_event)
	_assert(not controller.inventory_open and not screen.visible_inventory, "One Escape must close 7 Days inventory when its inspector is hidden")
	controller.set_inventory_visible(true)
	await process_frame


func _test_fixed_slot_projection(controller, screen) -> void:
	var player_model: Dictionary = screen.player_panel.current_model
	_assert(bool(player_model.get("is_profile_slot_layout", false)), "Player backpack must expose the dedicated fixed-slot layout")
	_assert(String(player_model.get("domain_storage_mode", "")) == "SLOTS", "7 Days adapter must migrate the underlying player container to SLOTS")
	_assert(String(player_model.get("storage_mode", "")) == "SLOTS", "Player model must expose slot UI semantics")
	_assert(controller.get_container(controller.player_inventory_id).is_slot_container(), "Player domain container must be slot-backed after profile activation")
	_assert(int(player_model.get("columns", 0)) == 10, "Projected backpack must use configured column count")
	_assert(Array(player_model.get("cells", [])).size() == int(player_model.get("visual_capacity", 0)), "Every projected slot, including empty slots, must render")
	_assert(_count_empty_cells(player_model) > 0, "Projected backpack must provide clickable empty cells")
	var first_cell = screen.player_panel.grid.get_child(0)
	_assert(first_cell.custom_minimum_size == Vector2(56.0, 56.0), "7 Days cells must use compact square geometry")

	screen.open_external_container("demo_crate_contents")
	var external_model: Dictionary = screen.external_panel.current_model
	_assert(screen.external_panel.visible, "Opening a real container must show external slot panel")
	_assert(bool(external_model.get("is_profile_slot_layout", false)), "External container must use the same fixed-slot adapter")
	_assert(controller.get_container("demo_crate_contents").is_slot_container(), "Opened external BULK container must migrate to domain slots")
	_assert(Array(external_model.get("cells", [])).size() == int(external_model.get("visual_capacity", 0)), "External container must render its full capacity")
	_assert(String(external_model.get("container_id", "")) == "demo_crate_contents", "External panel must remain bound to interacted container")
	_assert(controller.get_container("demo_crate_contents") != null, "External domain container must remain unchanged by UI projection")


func _test_immediate_pickup_pointer_and_hover(controller, screen) -> void:
	screen.close_external_container()
	screen.refresh()
	var source = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	var underlying = _find_item(controller, "battery_pack", controller.player_inventory_id)
	_assert(source != null and underlying != null, "Immediate pickup fixture must provide source and underlying items")
	if source == null or underlying == null:
		return
	var source_cell = screen.player_panel.find_cell_by_item_id(String(source.instance_id))
	var underlying_cell = screen.player_panel.find_cell_by_item_id(String(underlying.instance_id))
	_assert(source_cell != null and underlying_cell != null, "Immediate pickup fixture items must render")
	if source_cell == null or underlying_cell == null:
		return
	var source_screen_position: Vector2 = source_cell.global_position
	var pointer_local := Vector2(17.0, 23.0)
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	right_press.pressed = true
	right_press.position = pointer_local
	source_cell._gui_input(right_press)
	_assert(screen.transfer_session.is_active(), "RMB press must pick up the stack immediately without waiting for release or motion")
	_assert(screen._carry_pickup_button_held and screen._carry_pickup_button == MOUSE_BUTTON_RIGHT, "RMB pickup must enter held phase even while LMB is already held")
	_assert(screen._carry_preview_grab_offset.is_equal_approx(-pointer_local), "Carry preview must preserve the exact pointer offset inside the source cell")
	_assert(
		screen.carry_preview.position.is_equal_approx(source_screen_position),
		"Carry preview must start at the physical source-cell position without a side jump"
	)
	_assert(not screen.carry_preview_label.visible, "Carried stack must not render a name caption")
	_assert(screen.carry_preview_quantity_label.visible, "Carried stack must render its quantity over the icon")
	_assert(
		screen.carry_preview_quantity_label.text == str(screen.transfer_session.remaining_quantity),
		"Carried stack quantity must match the remaining cursor quantity"
	)
	underlying_cell._on_mouse_entered()
	_assert(not underlying_cell.drop_target_highlight, "Held pickup button must suppress destination highlighting")
	_assert(screen.tooltip.visible and screen.tooltip.current_item_id == String(underlying.instance_id), "Hover description must show the item under the carried stack")
	_assert(screen.tooltip.top_level, "7 Days hover description must stay outside inventory container layout")
	_assert(screen.tooltip.text_label.text == String(underlying.display_name), "Hover description must contain only the underlying item name")
	_assert(
		screen.tooltip.size.x <= 260.0 and screen.tooltip.size.y < 80.0,
		"Hover description must remain a compact name plate (actual: %s)" % screen.tooltip.size
	)
	var underlying_rect: Rect2 = underlying_cell.get_global_rect()
	var tooltip_rect: Rect2 = screen.tooltip.get_global_rect()
	_assert(not tooltip_rect.intersects(underlying_rect), "Hover description must not cover the hovered inventory slot")
	_assert(tooltip_rect.position.y >= underlying_rect.end.y, "Hover description must appear below the hovered slot when space is available")
	_assert(not screen.inspector.visible, "7 Days hover description must not reopen the generic inspector")
	var carried_quantity := int(screen.transfer_session.remaining_quantity)
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	screen._input(right_release)
	await process_frame
	_assert(screen.transfer_session.is_active() and int(screen.transfer_session.remaining_quantity) == carried_quantity, "Initial button release must only arm placement and must not place the stack")
	_assert(screen._carry_target_highlight_enabled and underlying_cell.drop_target_highlight, "Releasing pickup button must enable highlight for the hovered destination slot")
	underlying_cell._on_mouse_exited()
	_assert(not screen.tooltip.visible, "Hover description must disappear after leaving the underlying item")
	_assert(bool(screen._cancel_transfer_session(false)), "Immediate RMB pickup must remain safely cancellable")
	source_cell = screen.player_panel.find_cell_by_item_id(String(source.instance_id))
	var left_press := InputEventMouseButton.new()
	left_press.button_index = MOUSE_BUTTON_LEFT
	left_press.pressed = true
	left_press.position = Vector2(9.0, 11.0)
	source_cell._gui_input(left_press)
	_assert(screen.transfer_session.is_active() and screen._carry_pickup_button_held, "LMB press must also start carrying immediately before release")
	_assert(bool(screen._cancel_transfer_session(false)), "Immediate LMB pickup must remain safely cancellable")


func _test_click_move_between_visual_slots(controller, screen) -> void:
	screen.close_external_container()
	screen.refresh()
	var battery = _find_item(controller, "battery_pack", controller.player_inventory_id)
	_assert(battery != null, "Fixture must provide player battery stack")
	var source_cell = screen.player_panel.find_cell_by_item_id(String(battery.instance_id))
	_assert(source_cell != null, "Battery must have a projected source cell")
	var source_slot := int(source_cell.source_slot_index)
	var target_slot := _first_empty_projected_slot(screen.player_panel.current_model, [source_slot])
	_assert(target_slot >= 0, "Backpack must provide an empty target slot")
	var total_before := _total_quantity(controller, "battery_pack")
	var source_payload: Dictionary = source_cell.view_data.duplicate(true)
	source_payload["icon_texture"] = source_cell.icon_texture
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", source_payload)
	_assert(screen.transfer_session.is_active(), "LMB click must attach complete stack to cursor")
	_assert(screen.slot_projection.item_at_slot(controller.player_inventory_id, source_slot).is_empty(), "Picking up whole stack must visually empty its source slot")
	var carried_id := String(screen.transfer_session.item_id)
	var carried = controller.get_item(carried_id)
	_assert(carried != null and String(carried.relation.get("container_id", "")) == screen.cursor_controller.cursor_container_id, "Complete stack must move into transient cursor container")
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", _empty_target(controller.player_inventory_id, target_slot))
	_assert(not screen.transfer_session.is_active(), "Second LMB click must place complete stack")
	battery = controller.get_item(carried_id)
	_assert(battery != null and String(battery.relation.get("container_id", "")) == controller.player_inventory_id, "Placed item must return to player domain container")
	_assert(screen.slot_projection.item_at_slot(controller.player_inventory_id, target_slot) == carried_id, "Virtual slot layout must retain exact destination cell")
	_assert(screen.slot_projection.item_at_slot(controller.player_inventory_id, source_slot).is_empty(), "Moved source cell must remain empty")
	_assert(_total_quantity(controller, "battery_pack") == total_before, "Visual slot move must conserve quantity")


func _test_half_pickup_and_single_place(controller, screen) -> void:
	screen.refresh()
	var beacon = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	_assert(beacon != null and int(beacon.quantity) >= 3, "Fixture must provide a three-unit beacon stack")
	var source_cell = screen.player_panel.find_cell_by_item_id(String(beacon.instance_id))
	var source_payload: Dictionary = source_cell.view_data.duplicate(true)
	source_payload["icon_texture"] = source_cell.icon_texture
	var source_quantity := int(beacon.quantity)
	var total_before := _total_quantity(controller, "survey_beacon")
	var target_slot_a := _first_empty_projected_slot(screen.player_panel.current_model, [])
	var target_slot_b := _first_empty_projected_slot(screen.player_panel.current_model, [target_slot_a])
	_assert(target_slot_a >= 0 and target_slot_b >= 0, "Half-stack test must have two empty cells")
	var world_before := _quantity_in_world(controller, "survey_beacon")
	screen._on_interaction_requested("CARRY_HALF_OR_PLACE_ONE", source_payload)
	var expected_half := int(ceil(float(source_quantity) * 0.5))
	_assert(screen.transfer_session.remaining_quantity == expected_half, "RMB source click must pick ceil(half)")
	beacon = controller.get_item(String(beacon.instance_id))
	_assert(beacon != null and int(beacon.quantity) == source_quantity - expected_half, "Source stack must immediately retain the non-carried remainder")
	var target_cell = _cell_at_slot(screen.player_panel, target_slot_a)
	_assert(target_cell != null, "RMB placement test must resolve the empty target cell")
	_right_click(target_cell)
	_assert(screen.transfer_session.is_active() and screen.transfer_session.remaining_quantity == expected_half - 1, "RMB target click must place exactly one")
	var placed_one_id: String = screen.slot_projection.item_at_slot(controller.player_inventory_id, target_slot_a)
	var placed_one = controller.get_item(placed_one_id)
	_assert(placed_one != null and int(placed_one.quantity) == 1, "Single-place cell must contain one unit")
	var background_right_release := InputEventMouseButton.new()
	background_right_release.button_index = MOUSE_BUTTON_RIGHT
	background_right_release.pressed = false
	background_right_release.position = screen.player_panel.get_global_rect().end - Vector2(12.0, 12.0)
	_assert(screen._is_pointer_over_inventory_cell(target_cell.get_global_rect().get_center()), "Global drop routing must preserve releases over inventory cells")
	_assert(not screen._is_pointer_over_inventory_cell(background_right_release.position), "Global drop routing must recognize free panel background through nested controls")
	screen._input(background_right_release)
	_assert(_quantity_in_world(controller, "survey_beacon") == world_before + 1, "RMB outside cells must drop exactly one carried unit to WORLD")
	var expected_remainder := expected_half - 2
	_assert(screen.transfer_session.remaining_quantity == expected_remainder if expected_remainder > 0 else not screen.transfer_session.is_active(), "RMB outside cells must consume only one cursor unit")
	if expected_remainder > 0:
		screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", _empty_target(controller.player_inventory_id, target_slot_b))
		_assert(not screen.transfer_session.is_active(), "LMB target click must place all cursor remainder")
	_assert(_total_quantity(controller, "survey_beacon") == total_before, "Half pickup and single placement must conserve quantity")


func _test_occupied_slot_swap(controller, screen) -> void:
	screen.open_external_container("demo_crate_contents")
	screen.refresh()
	var battery = _find_item(controller, "battery_pack", controller.player_inventory_id)
	var rock = _find_item(controller, "lunar_rock", "demo_crate_contents")
	_assert(battery != null and rock != null, "Swap fixture must provide incompatible player and crate items")
	var battery_cell = screen.player_panel.find_cell_by_item_id(String(battery.instance_id))
	var rock_cell = screen.external_panel.find_cell_by_item_id(String(rock.instance_id))
	_assert(battery_cell != null and rock_cell != null, "Swap items must render in their panels")
	var battery_source_slot := int(battery_cell.source_slot_index)
	var rock_target_slot := int(rock_cell.source_slot_index)
	var battery_id := String(battery.instance_id)
	var rock_id := String(rock.instance_id)
	var battery_quantity := int(battery.quantity)
	var rock_quantity := int(rock.quantity)
	var battery_payload: Dictionary = battery_cell.view_data.duplicate(true)
	battery_payload["icon_texture"] = battery_cell.icon_texture
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", battery_payload)
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", _occupied_target("demo_crate_contents", rock_target_slot, rock_id))
	_assert(screen.transfer_session.is_active(), "Occupied incompatible target must leave displaced item on cursor")
	_assert(String(screen.transfer_session.item_id) == rock_id, "Displaced target item must become current cursor item")
	battery = controller.get_item(battery_id)
	rock = controller.get_item(rock_id)
	_assert(String(battery.relation.get("container_id", "")) == "demo_crate_contents", "Incoming item must replace occupied target relation")
	_assert(String(rock.relation.get("container_id", "")) == screen.cursor_controller.cursor_container_id, "Displaced target must move atomically into cursor container")
	_assert(screen.slot_projection.item_at_slot("demo_crate_contents", rock_target_slot) == battery_id, "External visual slot must show incoming item after swap")
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", _empty_target(controller.player_inventory_id, battery_source_slot))
	_assert(not screen.transfer_session.is_active(), "Placing displaced item into original empty slot must finish swap chain")
	rock = controller.get_item(rock_id)
	_assert(String(rock.relation.get("container_id", "")) == controller.player_inventory_id, "Displaced item must occupy selected player slot")
	_assert(screen.slot_projection.item_at_slot(controller.player_inventory_id, battery_source_slot) == rock_id, "Player visual slot must contain displaced item")
	_assert(int(controller.get_item(battery_id).quantity) == battery_quantity and int(rock.quantity) == rock_quantity, "Swap must preserve both aggregate quantities")


func _test_swap_cancel_unwinds(controller, screen) -> void:
	screen.open_external_container("demo_crate_contents")
	screen.refresh()
	var player_item = _first_item_in_container(controller, controller.player_inventory_id)
	var external_item = _first_incompatible_item(controller, "demo_crate_contents", player_item)
	_assert(player_item != null and external_item != null, "Cancel-swap fixture must provide incompatible aggregates")
	var player_cell = screen.player_panel.find_cell_by_item_id(String(player_item.instance_id))
	var external_cell = screen.external_panel.find_cell_by_item_id(String(external_item.instance_id))
	var player_slot := int(player_cell.source_slot_index)
	var external_slot := int(external_cell.source_slot_index)
	var player_id := String(player_item.instance_id)
	var external_id := String(external_item.instance_id)
	var player_relation: Dictionary = player_item.relation.duplicate(true)
	var external_relation: Dictionary = external_item.relation.duplicate(true)
	var payload: Dictionary = player_cell.view_data.duplicate(true)
	payload["icon_texture"] = player_cell.icon_texture
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", payload)
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", _occupied_target("demo_crate_contents", external_slot, external_id))
	_assert(String(screen.transfer_session.item_id) == external_id, "Swap cancel precondition must carry displaced item")
	var cancelled: bool = bool(screen._cancel_transfer_session(true))
	_assert(cancelled, "Esc cancellation must unwind occupied-slot swap chain")
	_assert(not screen.transfer_session.is_active(), "Swap cancellation must clear cursor")
	player_item = controller.get_item(player_id)
	external_item = controller.get_item(external_id)
	_assert(player_item.relation == player_relation, "Swap cancellation must restore initial player relation")
	_assert(external_item.relation == external_relation, "Swap cancellation must restore initial external relation")
	_assert(screen.slot_projection.item_at_slot(controller.player_inventory_id, player_slot) == player_id, "Swap cancellation must restore player visual slot")
	_assert(screen.slot_projection.item_at_slot("demo_crate_contents", external_slot) == external_id, "Swap cancellation must restore external visual slot")
	_assert(not controller.is_transient_inventory_cursor_active(), "Swap cancellation must remove cursor container")


func _test_shift_quick_transfer(controller, screen) -> void:
	screen.open_external_container("demo_crate_contents")
	screen.refresh()
	var player_item = _find_item(controller, "beacon_mount_base", controller.player_inventory_id)
	_assert(player_item != null, "Quick-transfer test needs a player-only item")
	var item_id := String(player_item.instance_id)
	var player_cell = screen.player_panel.find_cell_by_item_id(item_id)
	var player_slot := int(player_cell.source_slot_index)
	screen._on_quick_transfer_requested(item_id, controller.player_inventory_id, player_slot)
	player_item = controller.get_item(item_id)
	_assert(String(player_item.relation.get("container_id", "")) == "demo_crate_contents", "Shift+LMB from player must transfer to open external container")
	screen.refresh()
	var external_cell = screen.external_panel.find_cell_by_item_id(item_id)
	_assert(external_cell != null, "Quick-transferred item must render in external slot grid")
	screen._on_quick_transfer_requested(item_id, "demo_crate_contents", int(external_cell.source_slot_index))
	player_item = controller.get_item(item_id)
	_assert(String(player_item.relation.get("container_id", "")) == controller.player_inventory_id, "Shift+LMB from external container must transfer back to player")


func _test_slot_persistence(controller, screen) -> void:
	var save_result: Dictionary = controller.save_graph()
	_assert_success(save_result, "Domain-backed slot positions must save through Item Graph persistence")
	_assert(not bool(save_result.get("skipped", false)), "Slot persistence must not be skipped after cursor finalization")
	for container_id in [controller.player_inventory_id, "demo_crate_contents"]:
		var container = controller.get_container(container_id)
		_assert(container != null and container.is_slot_container(), "Persisted 7 Days container must remain SLOTS: %s" % container_id)
		var serialized: Dictionary = container.to_dict()
		var assignments := Dictionary(serialized.get("slot_assignments", {}))
		_assert(not assignments.is_empty(), "Serialized slot container must include assignments: %s" % container_id)
		for slot_key in assignments:
			var item_id := String(assignments[slot_key])
			var item = controller.get_item(item_id)
			_assert(item != null and int(item.relation.get("slot_index", -1)) == int(slot_key), "Serialized assignment must match item relation slot")


func _test_background_drop_one_keeps_cursor(controller, screen) -> void:
	screen.refresh()
	var source = _first_stack_in_container(controller, controller.player_inventory_id, 2)
	_assert(source != null, "RMB world-drop test must provide a stack with at least two units")
	if source == null:
		return
	var source_cell = screen.player_panel.find_cell_by_item_id(String(source.instance_id))
	_assert(source_cell != null, "RMB world-drop stack must render in the player inventory")
	if source_cell == null:
		return
	var definition_id := String(source.definition_id)
	var source_quantity := int(source.quantity)
	var world_before := _quantity_in_world(controller, definition_id)
	var source_payload: Dictionary = source_cell.view_data.duplicate(true)
	source_payload["icon_texture"] = source_cell.icon_texture
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", source_payload)
	var background_position: Vector2 = screen.player_panel.get_global_rect().end - Vector2(12.0, 12.0)
	var background_right_release := InputEventMouseButton.new()
	background_right_release.button_index = MOUSE_BUTTON_RIGHT
	background_right_release.pressed = false
	background_right_release.position = background_position
	screen._input(background_right_release)
	_assert(_quantity_in_world(controller, definition_id) == world_before + 1, "RMB free-background release must drop exactly one unit to WORLD")
	_assert(screen.transfer_session.is_active() and screen.transfer_session.remaining_quantity == source_quantity - 1, "RMB world drop must keep the remaining stack on the cursor")
	_assert(screen.carry_preview.visible, "RMB world drop must keep the remaining stack preview visible")
	_assert(screen.carry_preview.position.is_equal_approx(background_position + screen._carry_preview_grab_offset), "RMB world drop must keep the preview attached to the release position")
	_assert(screen.carry_preview_quantity_label.text == str(source_quantity - 1), "RMB world drop must update the carried quantity label")
	_assert(bool(screen._cancel_transfer_session(false)), "RMB world-drop remainder must remain safely cancellable")


func _test_background_drop_all(controller, screen) -> void:
	screen.refresh()
	var source = _first_item_in_container(controller, controller.player_inventory_id)
	_assert(source != null, "Background drop test must provide an item in the player inventory")
	if source == null:
		return
	var source_cell = screen.player_panel.find_cell_by_item_id(String(source.instance_id))
	_assert(source_cell != null, "Background drop test item must render in the player inventory")
	if source_cell == null:
		return
	var definition_id := String(source.definition_id)
	var source_quantity := int(source.quantity)
	var world_before := _quantity_in_world(controller, definition_id)
	var source_payload: Dictionary = source_cell.view_data.duplicate(true)
	source_payload["icon_texture"] = source_cell.icon_texture
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", source_payload)
	_assert(screen.transfer_session.is_active(), "LMB background drop precondition must carry the complete stack")
	var background_left_release := InputEventMouseButton.new()
	background_left_release.button_index = MOUSE_BUTTON_LEFT
	background_left_release.pressed = false
	background_left_release.position = screen.player_panel.get_global_rect().end - Vector2(12.0, 12.0)
	screen._input(background_left_release)
	_assert(_quantity_in_world(controller, definition_id) == world_before + source_quantity, "LMB outside cells must drop the complete carried stack to WORLD")
	_assert(not screen.transfer_session.is_active(), "LMB background drop must clear the cursor transfer session")
	_assert(not screen.carry_preview.visible, "LMB background drop must immediately hide the cursor preview")
	_assert(not controller.is_transient_inventory_cursor_active(), "LMB background drop must finalize the transient cursor container")


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
	return {
		"controller": controller,
		"setup": setup,
		"world_root": world_root,
		"attachment_root": attachment_root,
	}


func _empty_target(container_id: String, slot_index: int) -> Dictionary:
	return {
		"item_id": "",
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"target_item_id": "",
	}


func _occupied_target(container_id: String, slot_index: int, item_id: String) -> Dictionary:
	return {
		"item_id": item_id,
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"target_item_id": item_id,
	}


func _count_empty_cells(model: Dictionary) -> int:
	var count := 0
	for cell_value in Array(model.get("cells", [])):
		if String(Dictionary(cell_value).get("item_id", "")).is_empty():
			count += 1
	return count


func _first_empty_projected_slot(model: Dictionary, excluded: Array) -> int:
	for cell_value in Array(model.get("cells", [])):
		var cell := Dictionary(cell_value)
		var slot_index := int(cell.get("target_slot_index", -1))
		if slot_index in excluded:
			continue
		if String(cell.get("item_id", "")).is_empty():
			return slot_index
	return -1


func _cell_at_slot(panel, slot_index: int):
	for child in panel.grid.get_children():
		if child.visible and int(child.target_slot_index) == slot_index:
			return child
	return null


func _right_click(cell) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	cell._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	cell._gui_input(release)


func _find_item(controller, definition_id: String, container_id: String = ""):
	for item in controller.domain.items.all_items():
		if String(item.definition_id) != definition_id:
			continue
		if Relations.kind_of(item.relation) != Relations.CONTAINER:
			continue
		if not container_id.is_empty() and String(item.relation.get("container_id", "")) != container_id:
			continue
		return item
	return null


func _first_item_in_container(controller, container_id: String):
	for item in controller.domain.items.all_items():
		if Relations.kind_of(item.relation) == Relations.CONTAINER and String(item.relation.get("container_id", "")) == container_id:
			return item
	return null


func _first_stack_in_container(controller, container_id: String, minimum_quantity: int):
	for item in controller.domain.items.all_items():
		if (
			Relations.kind_of(item.relation) == Relations.CONTAINER
			and String(item.relation.get("container_id", "")) == container_id
			and int(item.quantity) >= minimum_quantity
		):
			return item
	return null


func _first_incompatible_item(controller, container_id: String, reference_item):
	if reference_item == null:
		return null
	for item in controller.domain.items.all_items():
		if Relations.kind_of(item.relation) != Relations.CONTAINER:
			continue
		if String(item.relation.get("container_id", "")) != container_id:
			continue
		if not reference_item.is_stack_compatible(item):
			return item
	return null


func _total_quantity(controller, definition_id: String) -> int:
	var total := 0
	for item in controller.domain.items.all_items():
		if String(item.definition_id) == definition_id:
			total += int(item.quantity)
	return total


func _quantity_in_world(controller, definition_id: String) -> int:
	var total := 0
	for item in controller.domain.items.all_items():
		if String(item.definition_id) == definition_id and Relations.kind_of(item.relation) == Relations.WORLD:
			total += int(item.quantity)
	return total


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("7 Days inventory interface: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("7 Days inventory interface: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
