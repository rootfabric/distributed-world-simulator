extends SceneTree

const Loader = preload("res://scripts/ui/inventory/interactions/inventory_interaction_profile_loader.gd")
const Router = preload("res://scripts/ui/inventory/interactions/inventory_interaction_router.gd")
const Profile = preload("res://scripts/ui/inventory/interactions/inventory_interaction_profile.gd")
const PreferencesStore = preload("res://scripts/ui/inventory/inventory_preferences_store.gd")
const Gameplay = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")

const STORE_ROOT := "user://planet_simulator/item_graphs"
const STATE_KEY := "test-inventory-interaction-profiles"
const PREFERENCES_SCOPE := "inventory_interaction_profiles_test"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_loader_and_router()
	_test_preferences_roundtrip()
	await _test_runtime_profiles()
	_finish()


func _test_profile_loader_and_router() -> void:
	var loader := Loader.new()
	var catalog := loader.load_catalog()
	_assert(bool(catalog.get("success", false)), "Interaction profile catalog must load")
	_assert(loader.ordered_profile_ids.size() == 3, "Catalog must expose exactly three inventory profiles")
	_assert(Array(loader.ordered_profile_ids) == ["planet_default", "rust_like", "seven_days_like"], "Profile order must remain stable for UI selector")

	var default_profile = loader.get_profile("planet_default")
	var rust_profile = loader.get_profile("rust_like")
	var seven_profile = loader.get_profile("seven_days_like")
	_assert(default_profile != null and default_profile.display_name == "Как было", "Default profile must preserve current controls")
	_assert(rust_profile != null and rust_profile.display_name == "Rust", "Rust profile must be available")
	_assert(seven_profile != null and seven_profile.display_name == "7 Days", "7 Days profile must be available")
	_assert(default_profile.outside_drop_action() == "DROP_TO_WORLD", "Default drag outside must drop carried quantity to WORLD")
	_assert(seven_profile.outside_drop_action() == "CANCEL", "7 Days virtual carry must cancel outside instead of mutating graph")

	var router := Router.new()
	router.setup(default_profile)
	var default_right := router.resolve_mouse(MOUSE_BUTTON_RIGHT, false, false, false, true)
	_assert(String(default_right.get("action", "")) == "MOVE_TO_TARGET", "Default RMB drag must remain a transfer gesture")
	_assert(bool(default_right.get("ask_quantity_after_target", false)), "Default RMB drag must select target before quantity")
	_assert(router.quantity_for(default_right, 9) == 9, "Default RMB drag popup maximum must preserve full source quantity")

	router.setup(rust_profile)
	var rust_primary := router.resolve_mouse(MOUSE_BUTTON_LEFT, false, false, false, false)
	var rust_secondary := router.resolve_mouse(MOUSE_BUTTON_RIGHT, false, false, false, false)
	var rust_context := router.resolve_mouse(MOUSE_BUTTON_RIGHT, false, true, false, false)
	var rust_half := router.resolve_mouse(MOUSE_BUTTON_MIDDLE, false, false, false, true)
	var rust_third := router.resolve_mouse(MOUSE_BUTTON_MIDDLE, true, false, false, true)
	_assert(String(rust_primary.get("action", "")) == "PLACE_ALL_OR_SELECT", "Rust LMB click must select normally or place all carried units")
	_assert(String(rust_secondary.get("action", "")) == "CARRY_EXACT_OR_PLACE_ONE", "Rust RMB click must select exact quantity before target or place one")
	_assert(String(rust_context.get("action", "")) == "OPEN_CONTEXT_MENU", "Rust Alt+RMB must retain advanced actions")
	_assert(router.quantity_for(rust_half, 5) == 3, "Rust MMB drag must carry ceil(half)")
	_assert(router.quantity_for(rust_third, 8) == 3, "Rust Shift+MMB drag must carry ceil(third)")
	_assert(String(rust_third.get("gesture", "")) == "SHIFT_MIDDLE_DRAG", "Rust third-stack gesture must resolve without fallback")

	router.setup(seven_profile)
	var seven_left := router.resolve_mouse(MOUSE_BUTTON_LEFT, false, false, false, false)
	var seven_right := router.resolve_mouse(MOUSE_BUTTON_RIGHT, false, false, false, false)
	var seven_context := router.resolve_mouse(MOUSE_BUTTON_RIGHT, false, true, false, false)
	_assert(String(seven_left.get("action", "")) == "CARRY_ALL_OR_PLACE_ALL", "7 Days LMB click must carry or place all")
	_assert(String(seven_right.get("action", "")) == "CARRY_HALF_OR_PLACE_ONE", "7 Days RMB click must carry half or place one")
	_assert(String(seven_context.get("action", "")) == "OPEN_CONTEXT_MENU", "7 Days Alt+RMB must retain advanced actions")

	var invalid_profile := Profile.new()
	var invalid_result := invalid_profile.load_from_dictionary({
		"schema": Profile.SCHEMA,
		"profile_id": "invalid",
		"bindings": [
			{"gesture": "PRIMARY_CLICK", "action": "SELECT_ITEM"},
			{"gesture": "PRIMARY_CLICK", "action": "QUICK_TRANSFER"},
		],
	})
	_assert(not bool(invalid_result.get("success", true)), "Duplicate gestures must be rejected")
	_assert(String(invalid_result.get("error_code", "")) == "PROFILE_GESTURE_DUPLICATE", "Duplicate gesture rejection must be explicit")

	var fallback := loader.resolve_profile("missing-profile")
	_assert(bool(fallback.get("success", false)) and bool(fallback.get("fallback_used", false)), "Unknown profile must use deterministic fallback")
	_assert((fallback.get("profile") as InventoryInteractionProfile).profile_id == "planet_default", "Fallback must resolve to configured default")


func _test_preferences_roundtrip() -> void:
	var preferences := PreferencesStore.new()
	preferences.setup(PREFERENCES_SCOPE)
	preferences.delete_preferences()
	_assert(preferences.save_preferences({
		"search_query": "камень",
		"active_filter": "RESOURCE",
		"sort_mode": "NAME",
		"inspector_visible": false,
		"interaction_profile_id": "rust_like",
	}), "Preferences must save selected interaction profile")
	var loaded := preferences.load_preferences()
	_assert(String(loaded.get("interaction_profile_id", "")) == "rust_like", "Preferences must restore selected interaction profile")
	_assert(String(loaded.get("schema", "")) == PreferencesStore.SCHEMA, "Preferences must migrate to v2 schema")
	preferences.delete_preferences()


func _test_runtime_profiles() -> void:
	var store = Factory.create_json_state_store(STORE_ROOT)
	store.delete_state(STATE_KEY)
	var preferences := PreferencesStore.new()
	preferences.setup("playground")
	preferences.delete_preferences()
	var fixture := await _create_controller()
	var controller = fixture.controller
	var screen = controller.inventory_ui.active_screen
	_assert_success(fixture.setup, "Item gameplay fixture must initialize")
	controller.set_inventory_visible(true)
	screen.refresh()
	_assert(screen.interaction_profile_option.item_count == 3, "Inventory toolbar must expose three profile choices")
	_assert(screen.active_interaction_profile.profile_id == "planet_default", "Runtime must start with default profile")
	var player_cell_count := Array(screen.player_panel.current_model.get("cells", [])).size()
	_assert(player_cell_count > 0, "Profile fixture must render player backpack cells before switching profiles")

	var rust_profile = screen.interaction_profile_loader.get_profile("rust_like")
	screen._apply_interaction_profile(rust_profile, false, true)
	_assert(screen.active_interaction_profile.profile_id == "rust_like", "Runtime profile switch must apply without world reload")
	_assert(Array(screen.player_panel.current_model.get("cells", [])).size() == player_cell_count, "Rust profile switch must preserve the backpack model")
	_assert(screen.player_panel.get_rendered_cell_count() == player_cell_count, "Rust profile switch must keep all backpack cells rendered")
	var beacon = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	var beacon_cell = screen.player_panel.find_cell_by_item_id(beacon.instance_id)
	var rust_third_payload: Dictionary = beacon_cell.build_drag_payload_for_binding(rust_profile.resolve("SHIFT_MIDDLE_DRAG"))
	_assert(int(rust_third_payload.get("quantity", 0)) == 1, "Rust third drag must compute against live three-unit stack")
	_assert(not bool(rust_third_payload.get("ask_quantity", true)), "Rust fractional drag must not open post-target quantity dialog")

	var battery = _find_item(controller, "battery_pack", controller.player_inventory_id)
	_assert(battery != null and int(battery.quantity) == 2, "Rust fixture must provide two batteries")
	var battery_total_before := _total_quantity(controller, "battery_pack")
	var battery_relation_before: Dictionary = battery.relation.duplicate(true)
	var battery_revision_before := int(battery.revision)
	var battery_payload: Dictionary = screen._cell_data_for_item(battery.instance_id)
	screen._on_interaction_requested("CARRY_EXACT_OR_PLACE_ONE", battery_payload)
	_assert(screen.split_dialog.visible, "Rust RMB click must open exact quantity dialog before target")
	_assert(screen.pending_quantity_operation == "BEGIN_VIRTUAL_CARRY", "Rust quantity dialog must use virtual-carry operation")
	_assert(battery.relation == battery_relation_before and int(battery.quantity) == 2 and int(battery.revision) == battery_revision_before, "Opening Rust split dialog must not mutate Item Graph")
	screen.split_dialog.hide()
	screen.split_dialog.clear_request()
	screen._on_split_confirmed(battery.instance_id, 1, "", -1, "")
	_assert(screen.transfer_session.is_active() and screen.transfer_session.remaining_quantity == 1, "Rust split confirmation must create exact virtual stack")
	_assert(battery.relation == battery_relation_before and int(battery.quantity) == 2 and int(battery.revision) == battery_revision_before, "Starting Rust virtual carry must not mutate Item Graph")
	var rust_hotbar = controller.get_container(controller.player_hotbar_id)
	var rust_empty_slots := _empty_slots(rust_hotbar)
	_assert(not rust_empty_slots.is_empty(), "Rust fixture must provide an empty hotbar target")
	var rust_target_slot: int = rust_empty_slots[0]
	screen._on_interaction_requested("PLACE_ALL_OR_SELECT", {
		"target_container_id": controller.player_hotbar_id,
		"target_slot_index": rust_target_slot,
		"target_item_id": "",
	})
	_assert(not screen.transfer_session.is_active(), "Rust LMB target click must commit all selected virtual quantity")
	_assert(int(battery.quantity) == 1, "Rust exact virtual transfer must remove selected quantity from source")
	var rust_split_id := String(rust_hotbar.get_item_at_slot(rust_target_slot))
	var rust_split = controller.get_item(rust_split_id)
	_assert(rust_split != null and int(rust_split.quantity) == 1, "Rust exact virtual transfer must create target aggregate")
	_assert(_total_quantity(controller, "battery_pack") == battery_total_before, "Rust exact virtual transfer must conserve total quantity")
	battery_payload = screen._cell_data_for_item(battery.instance_id)
	screen._on_interaction_requested("CARRY_EXACT_OR_PLACE_ONE", battery_payload)
	_assert(screen.split_dialog.visible, "Rust exact dialog must reopen for profile-switch cancellation test")
	var seven_profile = screen.interaction_profile_loader.get_profile("seven_days_like")
	screen._apply_interaction_profile(seven_profile, false, true)
	var projected_player: Dictionary = screen.player_panel.current_model
	_assert(bool(projected_player.get("is_profile_slot_layout", false)), "7 Days profile must render the backpack as stable domain-backed slots")
	_assert(String(projected_player.get("storage_mode", "")) == "SLOTS", "7 Days backpack must migrate to SLOTS")
	_assert(controller.get_container(controller.player_inventory_id).is_slot_container(), "7 Days profile must migrate the player container to domain slots")
	_assert(Array(projected_player.get("cells", [])).size() == int(projected_player.get("visual_capacity", 0)), "7 Days projected backpack must render every visual slot")
	_assert(screen.player_panel.get_rendered_cell_count() == int(projected_player.get("visual_capacity", 0)), "7 Days profile must keep empty backpack slots clickable")
	_assert(not screen.split_dialog.visible and screen.pending_quantity_operation == "TRANSFER_TO_TARGET", "Changing profile must cancel pending Rust quantity dialog")
	_assert(_total_quantity(controller, "battery_pack") == battery_total_before, "Cancelling Rust quantity dialog by profile switch must not mutate Item Graph")

	beacon = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	beacon_cell = screen.player_panel.find_cell_by_item_id(beacon.instance_id)
	var source_payload: Dictionary = beacon_cell.view_data.duplicate(true)
	source_payload["icon_texture"] = beacon_cell.icon_texture
	var original_beacon_id := String(beacon.instance_id)
	var original_quantity := int(beacon.quantity)
	var total_before := _total_quantity(controller, "survey_beacon")

	screen._on_interaction_requested("CARRY_HALF_OR_PLACE_ONE", source_payload)
	_assert(screen.transfer_session.is_active(), "7 Days RMB click must create a cursor-backed carry session")
	_assert(screen.transfer_session.domain_backed, "7 Days carry must use the transient domain cursor container")
	_assert(screen.transfer_session.remaining_quantity == 2, "7 Days RMB click must carry ceil(half) of three")
	var carried_item_id := String(screen.transfer_session.item_id)
	var carried_item = controller.get_item(carried_item_id)
	beacon = controller.get_item(original_beacon_id)
	_assert(carried_item_id != original_beacon_id, "Half-stack pickup must create a separate carried aggregate")
	_assert(carried_item != null and int(carried_item.quantity) == 2, "Transient cursor must own the selected half-stack")
	_assert(beacon != null and int(beacon.quantity) == original_quantity - 2, "Half-stack pickup must immediately reduce the source aggregate")
	_assert(String(carried_item.relation.get("container_id", "")) == screen.cursor_controller.cursor_container_id, "Carried aggregate must live in the transient cursor container")
	_assert(controller.is_transient_inventory_cursor_active(), "Controller must mark cursor container as transient")
	_assert(bool(controller.save_graph().get("skipped", false)), "Persistence must be suspended while transient cursor owns an item")
	_assert(screen.carry_preview.visible, "Cursor-backed carry must be visible at mouse position")

	var carried_relation_before_invalid: Dictionary = carried_item.relation.duplicate(true)
	var carried_quantity_before_invalid := int(carried_item.quantity)
	screen._on_interaction_requested("CARRY_HALF_OR_PLACE_ONE", {
		"target_container_id": "missing-container",
		"target_slot_index": 0,
		"target_item_id": "",
	})
	carried_item = controller.get_item(carried_item_id)
	_assert(screen.transfer_session.is_active() and screen.transfer_session.remaining_quantity == 2, "Rejected target must preserve carried quantity")
	_assert(carried_item != null and carried_item.relation == carried_relation_before_invalid and int(carried_item.quantity) == carried_quantity_before_invalid, "Rejected target must not mutate cursor aggregate")

	var hotbar = controller.get_container(controller.player_hotbar_id)
	var empty_slots := _empty_slots(hotbar)
	_assert(empty_slots.size() >= 2, "Fixture must provide two empty hotbar targets")
	var first_target := {
		"target_container_id": controller.player_hotbar_id,
		"target_slot_index": empty_slots[0],
		"target_item_id": "",
	}
	screen._on_interaction_requested("CARRY_HALF_OR_PLACE_ONE", first_target)
	_assert(screen.transfer_session.is_active() and screen.transfer_session.remaining_quantity == 1, "RMB target click must place one and retain one on cursor")
	carried_item = controller.get_item(carried_item_id)
	_assert(carried_item != null and int(carried_item.quantity) == 1, "Cursor aggregate must decrease by exactly one")
	var first_split_id := String(hotbar.get_item_at_slot(empty_slots[0]))
	var first_split = controller.get_item(first_split_id)
	_assert(first_split != null and int(first_split.quantity) == 1, "First target must receive one independent aggregate")

	var second_target := {
		"target_container_id": controller.player_hotbar_id,
		"target_slot_index": empty_slots[1],
		"target_item_id": "",
	}
	screen._on_interaction_requested("CARRY_HALF_OR_PLACE_ONE", second_target)
	_assert(not screen.transfer_session.is_active(), "Second RMB target click must exhaust cursor aggregate")
	_assert(not screen.carry_preview.visible, "Carry preview must disappear after final placement")
	_assert(not controller.is_transient_inventory_cursor_active(), "Transient cursor container must be removed after final placement")
	_assert(_total_quantity(controller, "survey_beacon") == total_before, "Cursor-backed placements must conserve total quantity")

	screen.refresh()
	beacon = controller.get_item(original_beacon_id)
	beacon_cell = screen.player_panel.find_cell_by_item_id(original_beacon_id)
	source_payload = beacon_cell.view_data.duplicate(true)
	source_payload["icon_texture"] = beacon_cell.icon_texture
	var relation_before_cancel: Dictionary = beacon.relation.duplicate(true)
	var quantity_before_cancel := int(beacon.quantity)
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", source_payload)
	_assert(screen.transfer_session.is_active(), "7 Days LMB click must move the full stack to cursor")
	_assert(String(beacon.relation.get("container_id", "")) == screen.cursor_controller.cursor_container_id, "Full-stack pickup must empty the visual source slot")
	screen._cancel_transfer_session(true)
	beacon = controller.get_item(original_beacon_id)
	_assert(not screen.transfer_session.is_active(), "Escape-equivalent cancel must clear cursor carry")
	_assert(beacon != null and beacon.relation == relation_before_cancel and int(beacon.quantity) == quantity_before_cancel, "Cancel must restore the carried stack to its original relation")
	_assert(not controller.is_transient_inventory_cursor_active(), "Cancel must remove transient cursor container")

	screen.refresh()
	beacon_cell = screen.player_panel.find_cell_by_item_id(original_beacon_id)
	source_payload = beacon_cell.view_data.duplicate(true)
	source_payload["icon_texture"] = beacon_cell.icon_texture
	screen._on_interaction_requested("CARRY_ALL_OR_PLACE_ALL", source_payload)
	screen._apply_interaction_profile(rust_profile, false, false)
	_assert(not screen.transfer_session.is_active(), "Changing profile must cancel cursor-backed carry")
	_assert(not controller.is_transient_inventory_cursor_active(), "Changing profile must not leave transient cursor state")

	var mount_stack = _find_item(controller, "beacon_mount_base", controller.player_inventory_id)
	_assert(mount_stack != null and int(mount_stack.quantity) >= 2, "Fixture must provide a splittable mount stack")
	var mount_quantity_before := int(mount_stack.quantity)
	var world_quantity_before := _quantity_in_relation(controller, "beacon_mount_base", Relations.WORLD)
	screen._on_drop_outside_requested(mount_stack.instance_id, 1)
	_assert(int(mount_stack.quantity) == mount_quantity_before - 1, "Drag outside must drop requested quantity instead of whole stack")
	_assert(_quantity_in_relation(controller, "beacon_mount_base", Relations.WORLD) == world_quantity_before + 1, "Partial outside drop must create exact WORLD quantity")
	_assert_success(controller.domain.validator.validate_graph(), "All profile interactions must preserve graph validity")

	store.delete_state(STATE_KEY)
	preferences.delete_preferences()
	controller.queue_free()
	fixture.world_root.queue_free()
	fixture.attachment_root.queue_free()
	await process_frame


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


func _empty_slots(container) -> Array[int]:
	var result: Array[int] = []
	for slot_index in range(int(container.slot_count)):
		if String(container.get_item_at_slot(slot_index)).is_empty():
			result.append(slot_index)
	return result


func _total_quantity(controller, definition_id: String) -> int:
	var total := 0
	for item in controller.domain.items.all_items():
		if item.definition_id == definition_id:
			total += int(item.quantity)
	return total


func _quantity_in_relation(controller, definition_id: String, relation_kind: String) -> int:
	var total := 0
	for item in controller.domain.items.all_items():
		if item.definition_id == definition_id and Relations.kind_of(item.relation) == relation_kind:
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
		print("Inventory interaction profiles: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory interaction profiles: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
