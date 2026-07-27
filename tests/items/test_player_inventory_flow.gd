extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Gameplay = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const MountSocket = preload("res://scripts/items/presentation/item_mount_socket.gd")
const WorldInteractor = preload("res://scripts/interaction/world_interactor.gd")

const STORE_ROOT := "user://planet_simulator/item_graphs"
const STATE_KEY := "test-player-flow-r2"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store = Factory.create_json_state_store(STORE_ROOT)
	store.delete_state(STATE_KEY)
	var fixture := await _create_controller(true)
	var controller = fixture.controller
	_assert(not bool(fixture.setup.persistence_blocked), "Fresh R2 runtime must be writable")
	_assert(controller.inventory_ui != null, "Player inventory must create icon UI")
	_assert(controller.get_container(controller.player_hotbar_id).slot_count == 10, "Hotbar must expose ten slots mapped to 1-0")
	_assert(not controller.inventory_open, "Inventory starts closed")
	controller.toggle_inventory()
	_assert(controller.inventory_open and controller.inventory_ui.is_inventory_visible(), "Tab command path must open inventory")
	_assert(controller.inventory_ui.external_container_id.is_empty() and not controller.inventory_ui.external_section.visible, "Plain Tab inventory must not show a stale or imaginary external container")
	_assert(controller.inventory_ui.get_external_visible_cell_count() == 0, "Closed external section must not render placeholder slots")
	controller.toggle_inventory()

	var starter: Variant = _find_item(controller, "survey_beacon", Relations.CONTAINER, controller.player_inventory_id)
	_assert(starter != null and starter.quantity == 3, "Lunar/player spawn must receive three stacked beacons")
	var inventory_mass: float = float(controller.domain.mass.container_mass_kg(controller.player_inventory_id))
	_assert(is_equal_approx(inventory_mass, 41.5), "Backpack mass must include child hotbar and starter contents")

	controller.inventory_ui._on_drop_requested(starter.instance_id, controller.player_hotbar_id, 0)
	_assert(controller.get_container(controller.player_hotbar_id).get_item_at_slot(0) == starter.instance_id, "Drag/drop must place beacon stack in hotbar slot 1")
	_assert_success(controller.select_hotbar(0), "Hotbar slot 1 must be selectable")
	var drop_result: Dictionary = controller.drop_selected_item()
	_assert_success(drop_result, "Selected beacon must drop into WORLD")
	var world_beacon_id := String(drop_result.get("new_item_id", drop_result.get("result_item_id", "")))
	var world_beacon: Variant = controller.get_item(world_beacon_id)
	_assert(world_beacon != null and Relations.kind_of(world_beacon.relation) == Relations.WORLD, "Dropped split must create one WORLD beacon")
	_assert(Relations.is_entity_world_relation(world_beacon.relation), "Dropped WORLD item must reference canonical entity aggregate")
	_assert(world_beacon.relation.keys().size() == 2 and not world_beacon.relation.has("spatial_ref"), "WORLD item relation must not duplicate spatial state")
	var world_beacon_aggregate = controller.get_world_item_aggregate(world_beacon_id)
	_assert(world_beacon_aggregate != null and world_beacon_aggregate.item_instance_id == world_beacon_id, "Dropped WORLD item must own one aggregate")
	_assert(controller.get_item(starter.instance_id).quantity == 2, "Dropping one from stack must leave two in hotbar")
	_assert(controller.presenter.get_world_node(world_beacon_id) is RigidBody3D, "WORLD beacon must have physics body")

	var world_body: RigidBody3D = controller.presenter.get_world_node(world_beacon_id)
	var first_live_transform := Transform3D(Basis.IDENTITY, Vector3(8.0, 1.25, -3.0))
	var first_live_velocity := Vector3(1.5, 0.25, -0.75)
	world_body.transform = first_live_transform
	world_body.linear_velocity = first_live_velocity

	# A non-spatial aggregate revision (for example quantity or another domain
	# component) must not replay the persisted pose over a live physics body.
	_assert_success(world_beacon_aggregate.apply_domain_components({"diagnostic_tag": "live-body"}), "WORLD aggregate domain components must update")
	controller.presenter.synchronize_all()
	_assert(world_body.transform.is_equal_approx(first_live_transform), "Domain-only aggregate revision must not teleport live WORLD body")
	_assert(world_body.linear_velocity.is_equal_approx(first_live_velocity), "Domain-only aggregate revision must not replay stored velocity")

	# Dropping another item from the same source stack must not replay the
	# first WORLD relation onto its already live physics body.
	var second_drop_result: Dictionary = controller.drop_selected_item()
	_assert_success(second_drop_result, "Second beacon from the same stack must drop")
	var second_world_id := String(second_drop_result.get("new_item_id", second_drop_result.get("result_item_id", "")))
	_assert(second_world_id != world_beacon_id, "Each split drop must create an independent item UUID")
	_assert(controller.get_item(starter.instance_id).quantity == 1, "Two drops must leave exactly one beacon in hotbar")
	_assert(world_body.transform.is_equal_approx(first_live_transform), "Dropping a second item must not teleport the first WORLD body")
	_assert(world_body.linear_velocity.is_equal_approx(first_live_velocity), "Dropping a second item must not reapply velocity to the first WORLD body")
	_assert(Relations.kind_of(controller.get_item(world_beacon_id).relation) == Relations.WORLD, "First dropped item must remain detached from every container")

	var interactor = WorldInteractor.new()
	fixture.world_root.add_child(interactor)
	interactor.setup(null)
	interactor.set_enabled(true)
	interactor.current_target = world_body
	interactor.current_hit_position = world_body.global_position
	interactor.current_distance_m = 1.0
	var pickup_result: Dictionary = interactor.perform_interaction()
	_assert_success(pickup_result, "WorldInteractor E path must pick beacon up")
	_assert(controller.presenter.get_world_node(world_beacon_id) == null, "Container item must lose physical body")
	_assert(Relations.kind_of(controller.get_item(world_beacon_id).relation) == Relations.CONTAINER, "Picked beacon must enter backpack")
	_assert(controller.get_world_item_aggregate(world_beacon_id) == null, "Picked item must release WORLD aggregate")

	var crate: Variant = _find_item(controller, "portable_crate", Relations.WORLD)
	_assert(crate != null, "Playground must spawn external beacon crate")
	var crate_body = controller.presenter.get_world_node(crate.instance_id)
	_assert(crate_body != null, "World crate must have interaction body")
	_assert_success(crate_body.interact(), "E interaction must open world container")
	_assert(controller.inventory_open and controller.inventory_ui.external_container_id == crate.get_owned_container_id(), "Opened crate must appear beside player inventory")
	_assert(controller.inventory_ui.external_section.visible, "External container section must become visible only after E interaction")
	_assert(controller.inventory_ui.get_external_visible_cell_count() == 12, "Twelve-entry BULK crate must render its own capacity instead of fixed generic placeholders")
	_assert(controller.inventory_ui.external_title.text.contains("2/12"), "BULK container title must expose used and available stack entries")
	var crate_beacons: Variant = _find_item(controller, "survey_beacon", Relations.CONTAINER, crate.get_owned_container_id())
	_assert(crate_beacons != null and crate_beacons.quantity == 4, "Demo crate must contain four beacons")
	controller.inventory_ui._on_drop_requested(crate_beacons.instance_id, controller.player_inventory_id, -1)
	var merged: Variant = controller.get_item(world_beacon_id)
	_assert(merged != null and merged.quantity == 5, "Drag from crate must stack four beacons with picked beacon up to max 5")
	_assert(controller.get_item(crate_beacons.instance_id) == null, "Merged source stack must be removed, not duplicated")

	var rack: Variant = _find_item(controller, "battery_rack", Relations.WORLD)
	var rack_id: String = String(rack.get_owned_container_id())
	var rack_body = controller.presenter.get_world_node(rack.instance_id)
	_assert_success(rack_body.interact(), "E interaction must switch inventory context to battery rack")
	_assert(controller.inventory_ui.external_container_id == rack_id and controller.inventory_ui.get_external_visible_cell_count() == 4, "Four-slot rack must render exactly four fixed slots")
	var reject_result: Dictionary = controller.move_item_to_container(merged.instance_id, rack_id, 1)
	_assert(not bool(reject_result.get("success", false)), "Battery-only slot must reject beacon")
	_assert(String(reject_result.get("error_code", "")) == "SLOT_ITEM_REJECTED", "Restricted slot must return precise rejection")
	_assert(String(controller.get_item(merged.instance_id).relation.get("container_id", "")) == controller.player_inventory_id, "Rejected transfer must not move item")
	var player_battery: Variant = _find_item(controller, "battery_pack", Relations.CONTAINER, controller.player_inventory_id)
	_assert_success(controller.move_item_to_container(player_battery.instance_id, rack_id, 1), "Battery-only slot must accept battery")
	_assert(controller.get_container(rack_id).get_item_at_slot(1) == player_battery.instance_id, "Accepted battery must occupy requested fixed slot")

	_assert_success(controller.move_item_to_container(merged.instance_id, controller.player_hotbar_id, 1), "Beacon stack must move into hotbar slot 2")
	controller.select_hotbar(1)
	var anchor := Node3D.new()
	fixture.attachment_root.add_child(anchor)
	controller.register_mount_anchor("demo_mount", "beacon_socket", anchor)
	var socket_node = MountSocket.new()
	fixture.attachment_root.add_child(socket_node)
	socket_node.setup_socket(controller, "demo_mount", "beacon_socket")
	var mount_result: Dictionary = socket_node.interact()
	_assert_success(mount_result, "Active hotbar beacon must mount through E interaction")
	var mounted_id := String(mount_result.get("new_item_id", mount_result.get("result_item_id", "")))
	var mounted: Variant = controller.get_item(mounted_id)
	_assert(mounted != null and Relations.kind_of(mounted.relation) == Relations.ATTACHMENT, "Mounting stack must split one attached beacon")
	_assert(controller.get_item(merged.instance_id).quantity == 4, "Mounted split must leave four beacons in hotbar")
	_assert(controller.presenter.get_attached_node(mounted_id) != null, "Attached beacon must have mounted presentation")
	_assert_success(socket_node.interact(), "Occupied socket interaction must detach beacon")
	_assert(Relations.kind_of(controller.get_item(mounted_id).relation) == Relations.CONTAINER, "Detached beacon must return to backpack")
	_assert(String(controller.get_socket_state("demo_mount", "beacon_socket").get("item_id", "")).is_empty(), "Detach must clear socket state")

	_assert_success(controller.move_item_to_container(crate.instance_id, controller.player_inventory_id), "Physical crate must move into backpack as nested container item")
	_assert(controller.presenter.get_world_node(crate.instance_id) == null, "Crate inside inventory must lose physics body")
	_assert_success(controller.drop_item(crate.instance_id, Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))), "Crate must be droppable back to WORLD")
	_assert(controller.presenter.get_world_node(crate.instance_id) is RigidBody3D, "Dropped crate must regain physics body")
	_assert(controller.presenter.get_world_physical_mass_kg(crate.instance_id) > 4.0, "Dropped crate physics mass must include recursive contents")

	_assert_success(controller.domain.validator.validate_graph(), "All R2 moves must leave graph valid")
	_assert_success(controller.domain.world_entities.validate_item_bindings(controller.domain.items), "All WORLD relations must have exactly one aggregate binding")
	_assert(_all_world_relations_are_entity_references(controller), "No live WORLD item may persist duplicate spatial state")
	_assert(_memberships_are_unique(controller), "No item may be lost or duplicated across containers")
	var total_before := _total_quantity(controller)
	_assert_success(controller.save_graph(), "R2 graph must save after all movement types")
	fixture.controller.queue_free()
	await process_frame

	var restored_fixture := await _create_controller(true)
	var restored = restored_fixture.controller
	_assert(bool(restored_fixture.setup.loaded), "Second runtime must load saved player graph")
	_assert(_total_quantity(restored) == total_before, "Restart must preserve total item quantity")
	_assert_success(restored.domain.validator.validate_graph(), "Reloaded player graph must remain valid")
	_assert_success(restored.domain.world_entities.validate_item_bindings(restored.domain.items), "Reloaded WORLD aggregate bindings must validate")
	_assert(_all_world_relations_are_entity_references(restored), "Reloaded WORLD relations must remain canonical")
	_assert(String(restored.get_socket_state("demo_mount", "beacon_socket").get("item_id", "")).is_empty(), "Restart must preserve detached socket")

	var loaded: Dictionary = store.load_state(STATE_KEY)
	var corrupt: Dictionary = Dictionary(loaded.get("state", {})).duplicate(true)
	var rows: Array = corrupt.get("items", {}).get("items", [])
	# Remove a deterministically referenced item. Removing rows[0] was flaky once
	# multiple independent WORLD items existed because that row could be a valid
	# unreferenced world aggregate and the graph would remain consistent.
	var referenced_item_id := ""
	for container in restored.domain.containers.all_containers():
		if not container.item_ids.is_empty():
			referenced_item_id = String(container.item_ids[0])
			break
	var removed_referenced_row := false
	for row_index in range(rows.size()):
		if String(rows[row_index].get("instance_id", "")) == referenced_item_id:
			rows.remove_at(row_index)
			removed_referenced_row = true
			break
	_assert(not referenced_item_id.is_empty() and removed_referenced_row, "Corruption fixture must remove a container-referenced item")
	_assert_success(store.save_state(STATE_KEY, corrupt), "Test must write intentionally corrupt graph")
	restored.queue_free()
	await process_frame
	var blocked_fixture := await _create_controller(true)
	var blocked = blocked_fixture.controller
	_assert(bool(blocked_fixture.setup.persistence_blocked), "Corrupt existing graph must enter fail-closed read-only recovery")
	var blocked_save: Dictionary = blocked.save_graph()
	_assert(String(blocked_save.get("error_code", "")) == "ITEM_GRAPH_PERSISTENCE_BLOCKED", "Recovery runtime must refuse to overwrite corrupt snapshot")
	var preserved: Dictionary = store.load_state(STATE_KEY)
	_assert(JSON.stringify(preserved.get("state", {}), "", true, true) == JSON.stringify(corrupt, "", true, true), "Read-only recovery must preserve original corrupt file")

	store.delete_state(STATE_KEY)
	blocked.queue_free()
	await process_frame
	_finish()


func _create_controller(enable_ui: bool) -> Dictionary:
	var world_root := Node3D.new()
	world_root.name = "WorldRoot"
	get_root().add_child(world_root)
	var attachment_root := Node3D.new()
	attachment_root.name = "AttachmentRoot"
	get_root().add_child(attachment_root)
	var controller = Gameplay.new()
	controller.name = "ItemGameplayController"
	get_root().add_child(controller)
	var setup: Dictionary = controller.setup_runtime(null, world_root, attachment_root, null, "scenario/local", "", STATE_KEY, "playground", enable_ui)
	await process_frame
	return {"controller": controller, "world_root": world_root, "attachment_root": attachment_root, "setup": setup}


func _find_item(controller, definition_id: String, relation_kind: String = "", container_id: String = ""):
	for item in controller.domain.items.all_items():
		if item.definition_id != definition_id:
			continue
		if not relation_kind.is_empty() and Relations.kind_of(item.relation) != relation_kind:
			continue
		if not container_id.is_empty() and String(item.relation.get("container_id", "")) != container_id:
			continue
		return item
	return null


func _all_world_relations_are_entity_references(controller) -> bool:
	for item in controller.domain.items.all_items():
		if Relations.kind_of(item.relation) != Relations.WORLD:
			continue
		if not Relations.is_entity_world_relation(item.relation):
			return false
		if item.relation.has("spatial_ref") or item.relation.has("transform"):
			return false
		if controller.get_world_item_aggregate(item.instance_id) == null:
			return false
	return true


func _memberships_are_unique(controller) -> bool:
	var seen: Dictionary = {}
	for container in controller.domain.containers.all_containers():
		for item_id in container.item_ids:
			if seen.has(item_id):
				return false
			seen[item_id] = container.container_id
	for item in controller.domain.items.all_items():
		if Relations.kind_of(item.relation) == Relations.CONTAINER:
			if String(seen.get(item.instance_id, "")) != String(item.relation.get("container_id", "")):
				return false
	return true


func _total_quantity(controller) -> int:
	var total := 0
	for item in controller.domain.items.all_items():
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
		print("Player inventory flow: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Player inventory flow: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
