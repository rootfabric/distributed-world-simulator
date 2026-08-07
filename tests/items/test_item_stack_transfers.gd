extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Gameplay = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const SlotControl = preload("res://scripts/items/presentation/item_slot_control.gd")

const STORE_ROOT := "user://planet_simulator/item_graphs"
const STATE_KEY := "test-item-stack-transfers"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# This contract verifies the baseline BULK inventory semantics. The 7 Days
	# profile intentionally performs a one-way BULK -> SLOTS domain migration,
	# so an inherited process environment must not silently change this fixture.
	OS.set_environment("PLANET_SIMULATOR_INVENTORY_PROFILE", "planet_default")
	var store = Factory.create_json_state_store(STORE_ROOT)
	store.delete_state(STATE_KEY)
	var fixture := await _create_controller()
	var controller = fixture.controller
	var backpack = controller.get_container(controller.player_inventory_id)
	var hotbar = controller.get_container(controller.player_hotbar_id)
	_assert(backpack != null and not backpack.is_slot_container(), "Player backpack must be a BULK container without fixed slots")
	_assert(hotbar != null and hotbar.is_slot_container(), "Hotbar must remain a fixed SLOTS container")

	var first = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	_assert(first != null and first.quantity == 3, "Fixture must start with three beacons")
	_assert_success(controller.move_item_to_container(first.instance_id, controller.player_hotbar_id, 0), "First stack must move into hotbar slot 1")
	var second = controller.domain.items.create_item("survey_beacon", 4, {}, Relations.container(controller.player_hotbar_id, 1))
	hotbar.assign_item(second.instance_id, 1)
	var total_before: int = _total_quantity_for_definition(controller, "survey_beacon")

	var fill_result: Dictionary = controller.move_item_to_container(second.instance_id, controller.player_hotbar_id, 0)
	_assert_success(fill_result, "Dropping a stack onto a compatible occupied slot must fill it")
	_assert(first.quantity == 5, "Occupied target stack must fill to max_stack=5")
	_assert(second.quantity == 2, "Overflow must remain in the original source slot")
	_assert(hotbar.get_item_at_slot(0) == first.instance_id, "Target stack identity must remain stable")
	_assert(hotbar.get_item_at_slot(1) == second.instance_id, "Partial slot merge must preserve source membership")
	_assert(_total_quantity_for_definition(controller, "survey_beacon") == total_before, "Partial merge must conserve total quantity")

	var empty_move: Dictionary = controller.move_item_to_container(second.instance_id, controller.player_hotbar_id, 2)
	_assert_success(empty_move, "Dropping onto an empty fixed slot must move the stack")
	_assert(hotbar.get_item_at_slot(2) == second.instance_id, "Empty fixed slot must receive the original stack")
	_assert(hotbar.get_item_at_slot(0) == first.instance_id and first.quantity == 5, "Empty-slot move must not auto-merge with another slot")
	_assert(hotbar.get_item_at_slot(1).is_empty(), "Old fixed slot must be cleared")

	var context_slot = SlotControl.new()
	get_root().add_child(context_slot)
	context_slot.setup_slot({
		"item_id": second.instance_id,
		"source_container_id": controller.player_hotbar_id,
		"source_slot_index": 2,
		"target_container_id": controller.player_hotbar_id,
		"target_slot_index": 2,
		"quantity": second.quantity,
	})
	var left_payload: Dictionary = context_slot.build_drag_payload(false)
	var right_payload: Dictionary = context_slot.build_drag_payload(true)
	_assert(not bool(left_payload.get("ask_quantity", true)), "Left drag must always carry the whole stack immediately")
	_assert(bool(right_payload.get("ask_quantity", false)), "Right drag must defer quantity selection until a valid target is chosen")
	_assert(int(right_payload.get("quantity", 0)) == 2, "Right drag payload must preserve source stack size as popup maximum")
	context_slot.queue_free()

	controller.inventory_ui.refresh()
	var live_source_slot = controller.inventory_ui.hotbar_grid.get_child(2)
	var live_target_slot = controller.inventory_ui.hotbar_grid.get_child(3)
	var deferred_payload: Dictionary = live_source_slot.build_drag_payload(true)
	live_target_slot._drop_data(Vector2.ZERO, deferred_payload)
	_assert(controller.inventory_ui.quantity_popup.visible, "Right-button drop on a valid target must open quantity popup only after target selection")
	_assert(controller.inventory_ui.pending_item_id == second.instance_id, "Quantity popup must bind exact source aggregate")
	_assert(controller.inventory_ui.pending_target_slot_index == 3, "Quantity popup must bind chosen destination slot")
	_assert(int(controller.inventory_ui.quantity_spin.max_value) == 2, "Quantity popup must use source stack size as maximum")
	_assert(hotbar.get_item_at_slot(3).is_empty(), "Opening post-drop quantity menu must not mutate inventory yet")
	controller.inventory_ui.quantity_spin.value = 1.0
	controller.inventory_ui._on_quantity_confirmed()
	var split_id: String = String(hotbar.get_item_at_slot(3))
	var split_item = controller.get_item(split_id)
	_assert(split_item != null and split_item.quantity == 1, "Confirmed right-drag quantity must create separate stack in empty fixed slot")
	_assert(second.quantity == 1 and hotbar.get_item_at_slot(2) == second.instance_id, "Post-drop split must leave remainder in source slot")
	_assert(not controller.inventory_ui.quantity_popup.visible and controller.inventory_ui.pending_item_id.is_empty(), "Quantity popup state must clear after confirmed move")

	var occupied_merge: Dictionary = controller.move_item_to_container(split_id, controller.player_hotbar_id, 2)
	_assert_success(occupied_merge, "Dropping one stack directly onto another must merge automatically")
	_assert(controller.get_item(split_id) == null, "Fully merged source stack must be removed")
	_assert(second.quantity == 2, "Occupied-slot merge must add source quantity")
	_assert(hotbar.get_item_at_slot(3).is_empty(), "Merged source slot must become empty")

	_assert_success(controller.move_item_to_container(first.instance_id, controller.player_inventory_id), "Full stack must move into BULK backpack")
	_assert_success(controller.move_item_to_container(second.instance_id, controller.player_inventory_id), "Second stack must move separately when first is full")
	_assert(first.quantity == 5 and second.quantity == 2, "BULK container must keep remainder stack when existing target is full")
	var same_bulk_split: Dictionary = controller.move_item_quantity_to_container(second.instance_id, 1, controller.player_inventory_id)
	_assert_success(same_bulk_split, "Partial drop into the same BULK container must return an explicit no-change result")
	_assert(bool(same_bulk_split.get("no_change", false)) and second.quantity == 2, "BULK container must not pretend that a visually separate stack can exist")
	_assert(String(same_bulk_split.get("message", "")).contains("фиксированный слот"), "BULK no-change result must explain where a separate stack can be created")
	var crate = _find_item(controller, "portable_crate", "", Relations.WORLD)
	var crate_beacons = _find_item(controller, "survey_beacon", crate.get_owned_container_id())
	_assert(crate_beacons != null and crate_beacons.quantity == 4, "Demo BULK crate must provide four beacons")
	var bulk_result: Dictionary = controller.move_item_to_container(crate_beacons.instance_id, controller.player_inventory_id)
	_assert_success(bulk_result, "BULK transfer must auto-stack across partial compatible stacks")
	_assert(bool(bulk_result.get("merged", false)), "BULK transfer must report stacking")
	_assert(second.quantity == 5, "BULK auto-stack must fill the partial stack first")
	var bulk_remainder = controller.get_item(crate_beacons.instance_id)
	_assert(bulk_remainder != null and bulk_remainder.quantity == 1, "BULK auto-stack must keep only unmerged remainder as a separate stack")
	_assert(String(bulk_remainder.relation.get("container_id", "")) == controller.player_inventory_id, "BULK remainder must move into target container")
	_assert(_total_quantity_for_definition(controller, "survey_beacon") == total_before, "BULK auto-stack must conserve all transferred units")

	var same_bulk_target = controller.domain.items.create_item("survey_beacon", 2, {}, Relations.container(controller.player_inventory_id))
	var same_bulk_source = controller.domain.items.create_item("survey_beacon", 2, {}, Relations.container(controller.player_inventory_id))
	backpack.assign_item(same_bulk_target.instance_id)
	backpack.assign_item(same_bulk_source.instance_id)
	var same_bulk_result: Dictionary = controller.move_item_quantity_to_container(
		same_bulk_source.instance_id,
		-1,
		controller.player_inventory_id,
		-1,
		same_bulk_target.instance_id
	)
	_assert_success(same_bulk_result, "Dropping one BULK entry directly onto another must stack exact target")
	_assert(same_bulk_target.quantity == 4, "Exact BULK target must receive source quantity")
	_assert(controller.get_item(same_bulk_source.instance_id) == null, "Exact BULK merge must remove consumed source aggregate")

	var named = controller.domain.items.create_item("survey_beacon", 2, {}, Relations.destroyed(), "Маяк Alpha")
	var named_move: Dictionary = controller.move_item_to_container(named.instance_id, controller.player_inventory_id)
	_assert_success(named_move, "Named beacon stack must still enter BULK container")
	_assert(controller.get_item(named.instance_id) != null and named.quantity == 2, "Individually named stack must not merge with standard beacons")

	var limited := ContainerState.new({
		"container_id": "limited_bulk",
		"owner_kind": "SYSTEM",
		"owner_id": "test",
		"storage_mode": ContainerState.STORAGE_BULK,
		"slot_count": 2,
	})
	var source_bulk := ContainerState.new({
		"container_id": "source_bulk",
		"owner_kind": "SYSTEM",
		"owner_id": "test",
		"storage_mode": ContainerState.STORAGE_BULK,
	})
	controller.domain.containers.add_container(limited)
	controller.domain.containers.add_container(source_bulk)
	var limited_a = controller.domain.items.create_item("survey_beacon", 4, {}, Relations.container(limited.container_id))
	var limited_b = controller.domain.items.create_item("survey_beacon", 4, {}, Relations.container(limited.container_id))
	var limited_source = controller.domain.items.create_item("survey_beacon", 2, {}, Relations.container(source_bulk.container_id))
	limited.assign_item(limited_a.instance_id)
	limited.assign_item(limited_b.instance_id)
	source_bulk.assign_item(limited_source.instance_id)
	var no_free_entry_result: Dictionary = controller.move_item_to_container(limited_source.instance_id, limited.container_id)
	_assert_success(no_free_entry_result, "Full BULK container must accept a source fully absorbable across several stacks")
	_assert(limited_a.quantity == 5 and limited_b.quantity == 5, "BULK merge must distribute quantity across multiple compatible stacks")
	_assert(controller.get_item(limited_source.instance_id) == null, "Fully distributed BULK source must be removed")
	_assert(limited.item_ids.size() == 2, "BULK merge must not create a third entry when entry limit is reached")

	var ledger_bulk := ContainerState.new({"container_id": "ledger_bulk", "storage_mode": ContainerState.STORAGE_BULK})
	var ledger_source_bulk := ContainerState.new({"container_id": "ledger_source_bulk", "storage_mode": ContainerState.STORAGE_BULK})
	controller.domain.containers.add_container(ledger_bulk)
	controller.domain.containers.add_container(ledger_source_bulk)
	var ledger_target = controller.domain.items.create_item("survey_beacon", 3, {}, Relations.container(ledger_bulk.container_id))
	var ledger_source = controller.domain.items.create_item("survey_beacon", 2, {}, Relations.container(ledger_source_bulk.container_id))
	ledger_bulk.assign_item(ledger_target.instance_id)
	ledger_source_bulk.assign_item(ledger_source.instance_id)
	var source_revision_before: int = int(ledger_source.revision)
	var target_revision_before: int = int(ledger_target.revision)
	var first_stack_command: Dictionary = controller.domain.transfer.stack_items(
		ledger_source.instance_id,
		ledger_target.instance_id,
		2,
		"stack-ledger-replay",
		source_revision_before,
		target_revision_before
	)
	_assert_success(first_stack_command, "Revision-guarded stack command must succeed")
	_assert(ledger_target.quantity == 5 and controller.get_item(ledger_source.instance_id) == null, "Stack command must consume source exactly once")
	var replay_stack_command: Dictionary = controller.domain.transfer.stack_items(
		ledger_source.instance_id,
		ledger_target.instance_id,
		2,
		"stack-ledger-replay",
		source_revision_before,
		target_revision_before
	)
	_assert(first_stack_command == replay_stack_command, "Exact stack replay must return stored result before looking up removed source")
	_assert(ledger_target.quantity == 5, "Exact stack replay must not mutate target twice")
	var stack_payload_conflict: Dictionary = controller.domain.transfer.stack_items(
		ledger_source.instance_id,
		ledger_target.instance_id,
		1,
		"stack-ledger-replay",
		source_revision_before,
		target_revision_before
	)
	_assert(String(stack_payload_conflict.get("error_code", "")) == "OPERATION_ID_CONFLICT", "Different stack payload under same operation ID must conflict")

	_test_atomic_item_swap(controller)

	_assert_success(controller.domain.validator.validate_graph(), "Stack operations must leave a valid unique item graph")
	var first_session_id: String = controller.operation_session_id
	_assert_success(controller.save_graph(), "Stack fixture must persist ledger before restart collision check")
	controller.queue_free()
	await process_frame
	var restarted_fixture := await _create_controller()
	var restarted = restarted_fixture.controller
	_assert(restarted.operation_session_id != first_session_id, "Each runtime must allocate a fresh UI operation namespace")
	var restarted_battery = _find_item(restarted, "battery_pack", restarted.player_inventory_id)
	var restart_move: Dictionary = restarted.move_item_to_container(restarted_battery.instance_id, restarted.player_hotbar_id, 9)
	_assert_success(restart_move, "First UI operation after loading persistent ledger must not collide with old operation IDs")
	_assert(String(restart_move.get("error_code", "")) != "OPERATION_ID_CONFLICT", "Session-scoped operation IDs must eliminate restart OPERATION_ID_CONFLICT")
	store.delete_state(STATE_KEY)
	restarted.queue_free()
	await process_frame
	_finish()


func _test_atomic_item_swap(controller) -> void:
	var swap_left := ContainerState.new({
		"container_id": "swap_left",
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": 1,
		"slot_rules": [{"accepted_tags": []}],
		"maximum_mass_kg": 3.0,
	})
	var swap_right := ContainerState.new({
		"container_id": "swap_right",
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": 1,
		"slot_rules": [{"accepted_tags": []}],
	})
	controller.domain.containers.add_container(swap_left)
	controller.domain.containers.add_container(swap_right)
	var light = controller.domain.items.create_item("survey_beacon", 1, {}, Relations.container(swap_left.container_id, 0))
	var heavy = controller.domain.items.create_item("battery_pack", 1, {}, Relations.container(swap_right.container_id, 0))
	swap_left.assign_item(light.instance_id, 0)
	swap_right.assign_item(heavy.instance_id, 0)
	var light_revision := int(light.revision)
	var heavy_revision := int(heavy.revision)
	var rejected: Dictionary = controller.domain.transfer.swap_items(
		light.instance_id,
		heavy.instance_id,
		"swap-capacity-rejected",
		light_revision,
		heavy_revision
	)
	_assert(String(rejected.get("error_code", "")) == "MAXIMUM_MASS_EXCEEDED", "Swap must reject a final container capacity violation")
	_assert(swap_left.get_item_at_slot(0) == light.instance_id and swap_right.get_item_at_slot(0) == heavy.instance_id, "Rejected swap must restore both slot memberships")
	_assert(light.revision == light_revision and heavy.revision == heavy_revision, "Rejected swap must restore both item revisions")
	_assert(String(light.relation.get("container_id", "")) == swap_left.container_id and String(heavy.relation.get("container_id", "")) == swap_right.container_id, "Rejected swap must restore both item relations")

	swap_left.maximum_mass_kg = 20.0
	var accepted: Dictionary = controller.domain.transfer.swap_items(
		light.instance_id,
		heavy.instance_id,
		"swap-accepted",
		light_revision,
		heavy_revision
	)
	_assert_success(accepted, "Atomic swap must succeed when both final containers accept the displaced items")
	_assert(swap_left.get_item_at_slot(0) == heavy.instance_id and swap_right.get_item_at_slot(0) == light.instance_id, "Atomic swap must exchange exact domain slots")
	_assert(String(light.relation.get("container_id", "")) == swap_right.container_id and int(light.relation.get("slot_index", -1)) == 0, "First item relation must move to the second exact slot")
	_assert(String(heavy.relation.get("container_id", "")) == swap_left.container_id and int(heavy.relation.get("slot_index", -1)) == 0, "Second item relation must move to the first exact slot")
	_assert(light.revision == light_revision + 1 and heavy.revision == heavy_revision + 1, "Successful swap must advance both aggregate revisions exactly once")

	var replay: Dictionary = controller.domain.transfer.swap_items(
		light.instance_id,
		heavy.instance_id,
		"swap-accepted",
		light_revision,
		heavy_revision
	)
	_assert(replay == accepted, "Exact swap replay must return the stored operation result")
	_assert(swap_left.get_item_at_slot(0) == heavy.instance_id and swap_right.get_item_at_slot(0) == light.instance_id, "Exact swap replay must not exchange the items a second time")

	var stale: Dictionary = controller.domain.transfer.swap_items(
		light.instance_id,
		heavy.instance_id,
		"swap-stale-revision",
		light_revision,
		heavy_revision
	)
	_assert(String(stale.get("error_code", "")) == "REVISION_CONFLICT", "Swap must reject stale first-item revision")
	_assert(swap_left.get_item_at_slot(0) == heavy.instance_id and swap_right.get_item_at_slot(0) == light.instance_id, "Revision-conflicted swap must preserve slot membership")



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


func _total_quantity_for_definition(controller, definition_id: String) -> int:
	var total: int = 0
	for item in controller.domain.items.all_items():
		if item.definition_id == definition_id:
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
		print("Item stack transfers: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Item stack transfers: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
