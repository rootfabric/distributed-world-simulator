extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Gameplay = preload("res://scripts/items/presentation/item_gameplay_controller.gd")

const STORE_ROOT := "user://planet_simulator/item_graphs"
const STATE_KEY := "test-item-placement-admin"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store = Factory.create_json_state_store(STORE_ROOT)
	store.delete_state(STATE_KEY)
	var fixture: Dictionary = await _create_controller()
	var controller = fixture.controller
	var backpack = controller.get_container(controller.player_inventory_id)
	var hotbar = controller.get_container(controller.player_hotbar_id)
	var mount_stack = _find_item(controller, "beacon_mount_base", controller.player_inventory_id)
	var beacon_stack = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	_assert(mount_stack != null and mount_stack.quantity == 3, "Starter pack must contain three placeable mount sockets")
	_assert(beacon_stack != null and beacon_stack.quantity == 3, "Starter pack must contain three beacons")
	_assert_success(controller.move_item_to_container(mount_stack.instance_id, controller.player_hotbar_id, 0), "Mount stack must move to hotbar")
	controller.select_hotbar(0)
	var place_result: Dictionary = controller.place_selected_item_at_transform(Transform3D(Basis.IDENTITY, Vector3(1.0, 0.16, -2.0)))
	_assert_success(place_result, "Selected mount socket must be placeable through high-level placement service")
	var placed_id := String(place_result.get("item_id", ""))
	var placed = controller.get_item(placed_id)
	_assert(placed != null and Relations.kind_of(placed.relation) == Relations.WORLD, "Placed socket must become a WORLD item")
	_assert(Relations.is_entity_world_relation(placed.relation) and not placed.relation.has("spatial_ref"), "Placed socket must reference canonical WORLD aggregate")
	var placed_aggregate = controller.get_world_item_aggregate(placed_id)
	_assert(placed_aggregate != null and placed_aggregate.item_instance_id == placed_id, "Placed fixture must own aggregate spatial state")
	_assert(controller.get_world_item_transform(placed_id).origin.is_equal_approx(Vector3(1.0, 0.16, -2.0)), "Placed fixture transform must resolve through aggregate")
	_assert(bool(Dictionary(placed.components.get("placement", {})).get("installed", false)), "Placed item must carry installed placement component")
	_assert(mount_stack.quantity == 2 and hotbar.get_item_at_slot(0) == mount_stack.instance_id, "Placing one unit must leave the remainder linked to hotbar")
	var fixture_node = controller.placement_service.get_fixture_node(placed_id)
	_assert(fixture_node != null and fixture_node.fixture_item_id == placed_id, "Placement service must create fixture presentation owned by item")
	var socket: Dictionary = controller.get_socket_state(String(place_result.get("assembly_id", "")), String(place_result.get("socket_id", "")))
	_assert(String(socket.get("parent_item_id", "")) == placed_id, "Installed socket must use placed item as parent aggregate")

	_assert_success(controller.move_item_to_container(beacon_stack.instance_id, controller.player_hotbar_id, 1), "Beacon stack must move to second hotbar slot")
	controller.select_hotbar(1)
	var mount_result: Dictionary = fixture_node.interact()
	_assert_success(mount_result, "Placed socket must mount selected compatible beacon")
	var mounted_socket: Dictionary = controller.get_socket_state(String(place_result.assembly_id), String(place_result.socket_id))
	_assert(not String(mounted_socket.get("item_id", "")).is_empty(), "Socket must retain mounted item identity")
	var detach_result: Dictionary = fixture_node.interact()
	_assert_success(detach_result, "Occupied socket must detach beacon back to inventory")
	_assert(controller.get_item(placed_id) != null, "Interacting with socket must not remove its fixture item")

	var before_admin := _total_quantity(controller, "survey_beacon")
	var grant_result: Dictionary = controller.grant_debug_item("survey_beacon", 100)
	_assert_success(grant_result, "Admin grant ×100 must succeed")
	_assert(_total_quantity(controller, "survey_beacon") == before_admin + 100, "Admin grant must conserve exact requested quantity")
	for item in controller.domain.items.all_items():
		if item.definition_id == "survey_beacon":
			_assert(item.quantity <= 5, "Admin grant must respect definition max_stack")
	var catalog: Array[Dictionary] = controller.list_debug_item_catalog()
	_assert(_catalog_has(catalog, "beacon_mount_base"), "Debug catalog must expose placeable mount socket")
	_assert(_catalog_has(catalog, "survey_beacon"), "Debug catalog must expose beacon")
	_assert_success(controller.domain.validator.validate_graph(), "Placement and admin grant must keep item graph valid")
	_assert_success(controller.save_graph(), "Placed fixture graph must save")
	controller.queue_free()
	await process_frame

	var restored_fixture: Dictionary = await _create_controller()
	var restored = restored_fixture.controller
	_assert(bool(restored_fixture.setup.get("loaded", false)), "Item graph must load after restart")
	_assert(restored.get_item(placed_id) != null, "Placed fixture item must survive restart")
	_assert(Relations.is_entity_world_relation(restored.get_item(placed_id).relation), "Restored fixture must keep aggregate relation")
	_assert(restored.get_world_item_aggregate(placed_id) != null, "Restored fixture aggregate must survive restart")
	_assert(restored.placement_service.get_fixture_node(placed_id) != null, "Placed fixture presentation must be reconstructed after restart")
	_assert_success(restored.domain.validator.validate_graph(), "Restored placement graph must validate")
	store.delete_state(STATE_KEY)
	restored.queue_free()
	await process_frame
	_finish()


func _create_controller() -> Dictionary:
	var world_root := Node3D.new()
	world_root.name = "PlacementWorldRoot"
	get_root().add_child(world_root)
	var attachment_root := Node3D.new()
	attachment_root.name = "PlacementAttachmentRoot"
	get_root().add_child(attachment_root)
	var controller = Gameplay.new()
	controller.name = "PlacementGameplayController"
	get_root().add_child(controller)
	var setup: Dictionary = controller.setup_runtime(null, world_root, attachment_root, null, "scenario/local", "", STATE_KEY, "playground", true)
	await process_frame
	return {"controller": controller, "setup": setup}


func _find_item(controller, definition_id: String, container_id: String):
	for item in controller.domain.items.all_items():
		if item.definition_id == definition_id and Relations.kind_of(item.relation) == Relations.CONTAINER and String(item.relation.get("container_id", "")) == container_id:
			return item
	return null


func _total_quantity(controller, definition_id: String) -> int:
	var total := 0
	for item in controller.domain.items.all_items():
		if item.definition_id == definition_id:
			total += int(item.quantity)
	return total


func _catalog_has(catalog: Array[Dictionary], definition_id: String) -> bool:
	for row in catalog:
		if String(row.get("definition_id", "")) == definition_id:
			return true
	return false


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Item placement and admin tools: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Item placement and admin tools: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
