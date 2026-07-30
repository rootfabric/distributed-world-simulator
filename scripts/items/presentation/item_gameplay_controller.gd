extends Node

signal inventory_visibility_changed(visible: bool)
signal gameplay_state_changed()

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Presenter = preload("res://scripts/items/presentation/item_representation_system.gd")
const InventoryUI = preload("res://scripts/items/presentation/item_inventory_ui.gd")
const GraphPersistence = preload("res://scripts/items/persistence/item_graph_persistence.gd")
const PlacementContract = preload("res://scripts/items/placement/item_placement_contract.gd")
const PlacementService = preload("res://scripts/items/placement/item_placement_service.gd")
const PlayableStateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

const RUNTIME_MODE_LEGACY: String = "legacy"
const RUNTIME_MODE_AUTHORITY: String = "authority"
const RUNTIME_MODE_REPLICA: String = "replica"

const DEFAULT_DROP_DISTANCE_M: float = 1.6
const DEFAULT_DROP_HEIGHT_M: float = 0.8
const DEFAULT_DROP_SPEED_MPS: float = 2.5

var domain: Dictionary = {}
var presenter
var graph_persistence
var inventory_ui
var placement_service
var player
var world_root: Node3D
var attachment_root: Node3D
var physics_frame_id: String = "scenario/local"
var gravity_reference_body_id: String = ""
var profile_id: String = "playground"
var state_key: String = "playground-items"
var player_inventory_id: String = "player_inventory"
var player_hotbar_id: String = "player_hotbar"
var selected_hotbar_index: int = 0
var operation_counter: int = 1
var operation_session_id: String = ""
var inventory_open: bool = false
var persistence_blocked: bool = false
var persistence_error: Dictionary = {}
var last_result: Dictionary = {"success": true, "message": "Готово"}
var starter_pack_revision: int = 0
var runtime_mode: String = RUNTIME_MODE_LEGACY
var network_command_bridge
var network_replica_revision: int = -1
var network_replica_checksum: String = ""
var persistence_enabled: bool = true
var presentation_enabled: bool = true
var transient_inventory_cursor_ids: Dictionary = {}


func setup_runtime(
	player_reference,
	world_root_reference: Node3D,
	attachment_root_reference: Node3D,
	gravity_field = null,
	configured_frame_id: String = "scenario/local",
	configured_reference_body_id: String = "",
	configured_state_key: String = "playground-items",
	configured_profile_id: String = "playground",
	enable_ui: bool = true,
	runtime_options: Dictionary = {}
) -> Dictionary:
	player = player_reference
	world_root = world_root_reference
	attachment_root = attachment_root_reference
	physics_frame_id = configured_frame_id
	gravity_reference_body_id = configured_reference_body_id
	state_key = configured_state_key
	profile_id = configured_profile_id
	runtime_mode = String(runtime_options.get("mode", RUNTIME_MODE_LEGACY)).strip_edges().to_lower()
	if runtime_mode not in [RUNTIME_MODE_LEGACY, RUNTIME_MODE_AUTHORITY, RUNTIME_MODE_REPLICA]:
		return {"success": false, "error_code": "INVALID_ITEM_RUNTIME_MODE"}
	persistence_enabled = bool(runtime_options.get("persistence_enabled", runtime_mode != RUNTIME_MODE_REPLICA))
	presentation_enabled = bool(runtime_options.get("presentation_enabled", runtime_mode != RUNTIME_MODE_AUTHORITY))
	network_command_bridge = runtime_options.get("network_command_bridge")
	operation_counter = 1
	operation_session_id = _create_operation_session_id()
	transient_inventory_cursor_ids.clear()
	domain = Factory.create()
	domain.world_entities.setup({
		"authority_owner_id": String(runtime_options.get("authority_owner_id", "local-process")),
		"authority_epoch": int(runtime_options.get("authority_epoch", 1)),
	})
	_register_default_definitions()
	graph_persistence = GraphPersistence.new()
	var store = null
	if persistence_enabled:
		store = Factory.create_json_state_store(String(runtime_options.get("persistence_root", "user://planet_simulator/item_graphs")))
	graph_persistence.setup(domain, store, state_key)
	var loaded := false
	persistence_blocked = false
	persistence_error = {}
	if runtime_mode == RUNTIME_MODE_REPLICA:
		var initial_snapshot_value = runtime_options.get("initial_graph_snapshot", {})
		if not initial_snapshot_value is Dictionary or Dictionary(initial_snapshot_value).is_empty():
			return {"success": false, "error_code": "REPLICA_GRAPH_SNAPSHOT_REQUIRED"}
		var replica_load: Dictionary = graph_persistence.load_snapshot(Dictionary(initial_snapshot_value))
		if not bool(replica_load.get("success", false)):
			return replica_load
		loaded = true
		var replica_metadata: Dictionary = Dictionary(replica_load.get("metadata", {}))
		selected_hotbar_index = clampi(int(replica_metadata.get("selected_hotbar_index", 0)), 0, 9)
		starter_pack_revision = int(replica_metadata.get("starter_pack_revision", 0))
		network_replica_revision = int(runtime_options.get("replica_revision", -1))
		network_replica_checksum = String(runtime_options.get("replica_checksum", ""))
	else:
		if graph_persistence.has_state():
			var load_result: Dictionary = graph_persistence.load()
			loaded = bool(load_result.get("success", false))
			if loaded:
				var loaded_metadata: Dictionary = Dictionary(load_result.get("metadata", {}))
				selected_hotbar_index = clampi(int(loaded_metadata.get("selected_hotbar_index", 0)), 0, 9)
				starter_pack_revision = int(loaded_metadata.get("starter_pack_revision", 0))
			else:
				persistence_blocked = true
				persistence_error = load_result.duplicate(true)
		if not loaded:
			_seed_default_graph(bool(runtime_options.get("include_demo_world", profile_id == "playground")))
	# A snapshot stores definitions as well. Re-register runtime definitions after
	# loading so non-destructive metadata upgrades remain available to old saves.
	_register_default_definitions()
	_upgrade_legacy_mount_fixture()
	_ensure_starter_pack()
	var migration_result: Dictionary = _migrate_all_world_items_to_aggregates()
	if not bool(migration_result.get("success", false)):
		persistence_blocked = true
		persistence_error = migration_result.duplicate(true)
	_connect_domain_signals()
	if presentation_enabled:
		presenter = Presenter.new()
		presenter.name = "ItemRepresentationSystem"
		add_child(presenter)
		presenter.setup(domain.items, world_root, attachment_root, false, domain.mass, gravity_field, physics_frame_id, gravity_reference_body_id, domain.world_entities)
		presenter.set_interaction_controller(self)
		placement_service = PlacementService.new()
		placement_service.name = "ItemPlacementService"
		add_child(placement_service)
		placement_service.setup(self, player, world_root)
		presenter.synchronize_all()
		placement_service.synchronize_all()
	if enable_ui and presentation_enabled:
		inventory_ui = InventoryUI.new()
		inventory_ui.name = "ItemInventoryUI"
		add_child(inventory_ui)
		inventory_ui.setup(self)
		inventory_ui.refresh("Сохранение повреждено: runtime только для чтения" if persistence_blocked else "")
	return {
		"success": true,
		"loaded": loaded,
		"runtime_mode": runtime_mode,
		"network_replica": runtime_mode == RUNTIME_MODE_REPLICA,
		"persistence_enabled": persistence_enabled,
		"presentation_enabled": presentation_enabled,
		"persistence_blocked": persistence_blocked,
		"persistence_error": persistence_error.duplicate(true),
		"item_count": domain.items.items.size(),
		"container_count": domain.containers.containers.size(),
		"world_entity_count": domain.world_entities.size(),
		"inventory_ui_implementation": inventory_ui.get_implementation_id() if inventory_ui != null else "disabled",
	}


func register_mount_anchor(assembly_id: String, socket_id: String, anchor: Node3D) -> void:
	if presenter != null:
		presenter.register_attachment_anchor(assembly_id, socket_id, anchor)
		presenter.synchronize_all()


func toggle_inventory() -> Dictionary:
	if inventory_open:
		set_inventory_visible(false)
	else:
		if inventory_ui != null:
			inventory_ui.close_external_container(false)
		set_inventory_visible(true)
	return {"success": true, "visible": inventory_open, "output": "Инвентарь: %s" % ("открыт" if inventory_open else "закрыт")}


func set_inventory_visible(value: bool) -> void:
	if not value and inventory_ui != null and not String(inventory_ui.external_container_id).is_empty():
		close_external_container()
	inventory_open = value
	if inventory_ui != null:
		if not value:
			inventory_ui.close_external_container(false)
		inventory_ui.set_inventory_visible(value)
		if value:
			inventory_ui.refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	if player != null and is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	inventory_visibility_changed.emit(value)


func select_hotbar(index: int) -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation(
			"inventory.select_hotbar",
			{"selected_hotbar_index": posmod(index, 10)},
			"select_hotbar"
		)
	selected_hotbar_index = posmod(index, 10)
	_refresh_ui()
	save_graph()
	return {"success": true, "selected_hotbar_index": selected_hotbar_index, "output": "Быстрый слот: %d" % (selected_hotbar_index + 1)}


func get_selected_hotbar_item_id() -> String:
	var hotbar = get_container(player_hotbar_id)
	return hotbar.get_item_at_slot(selected_hotbar_index) if hotbar != null else ""


func move_item_to_container(
	item_id: String,
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	return move_item_quantity_to_container(
		item_id,
		-1,
		target_container_id,
		target_slot_index,
		target_item_id
	)




func preview_item_quantity_to_container(
	item_id: String,
	requested_quantity: int,
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	var item = get_item(item_id)
	if item == null:
		return {"success": false, "error_code": "ITEM_NOT_FOUND"}
	var container = get_container(target_container_id)
	if container == null:
		return {"success": false, "error_code": "CONTAINER_NOT_FOUND"}
	var quantity_to_move := int(item.quantity) if requested_quantity < 0 else clampi(requested_quantity, 1, int(item.quantity))
	if quantity_to_move < int(item.quantity) and item.owns_container():
		return {"success": false, "error_code": "CONTAINER_ITEM_CANNOT_SPLIT", "message": "Контейнер нельзя разделить"}
	var resolved_target_item_id := target_item_id
	if resolved_target_item_id.is_empty() and container.is_slot_container() and target_slot_index >= 0:
		resolved_target_item_id = String(container.get_item_at_slot(target_slot_index))
	if not resolved_target_item_id.is_empty():
		if resolved_target_item_id == item_id:
			return {"success": false, "error_code": "STACK_TARGET_IS_SOURCE", "message": "Стак уже находится здесь"}
		var target_item = get_item(resolved_target_item_id)
		if target_item == null:
			return {"success": false, "error_code": "STACK_TARGET_NOT_FOUND"}
		if Relations.kind_of(target_item.relation) != Relations.CONTAINER or String(target_item.relation.get("container_id", "")) != target_container_id:
			return {"success": false, "error_code": "STACK_TARGET_CONTAINER_MISMATCH"}
		if not item.is_stack_compatible(target_item):
			return {"success": false, "error_code": "STACK_INCOMPATIBLE", "message": "Эти предметы нельзя объединить"}
		var definition = get_definition(target_item.definition_id)
		if definition == null or int(target_item.quantity) >= int(definition.max_stack):
			return {"success": false, "error_code": "STACK_FULL", "message": "Целевой стак заполнен"}
		return {"success": true, "mode": "STACK", "maximum_quantity": mini(quantity_to_move, int(definition.max_stack) - int(target_item.quantity))}
	if container.is_slot_container():
		if target_slot_index < 0 or target_slot_index >= int(container.slot_count):
			return {"success": false, "error_code": "SLOT_REQUIRED"}
		var definition = get_definition(item.definition_id)
		if not container.can_accept_definition_in_slot(definition, target_slot_index):
			return {"success": false, "error_code": "SLOT_ITEM_REJECTED", "message": "Этот предмет нельзя поместить в выбранный слот"}
	var source_same_bulk: bool = (
		not container.is_slot_container()
		and Relations.kind_of(item.relation) == Relations.CONTAINER
		and String(item.relation.get("container_id", "")) == target_container_id
	)
	if source_same_bulk:
		return {"success": false, "error_code": "SAME_BULK_NO_TARGET", "message": "В BULK-контейнере перетащите предмет на конкретный стак или в другой контейнер"}
	if not container.is_slot_container():
		var compatible_headroom: int = 0
		for existing_id in container.item_ids:
			if String(existing_id) == item_id:
				continue
			var existing = get_item(String(existing_id))
			if existing == null or not item.is_stack_compatible(existing):
				continue
			var existing_definition = get_definition(existing.definition_id)
			if existing_definition != null:
				compatible_headroom += maxi(0, int(existing_definition.max_stack) - int(existing.quantity))
		if compatible_headroom > 0:
			if container.has_free_slot():
				return {"success": true, "mode": "BULK_AUTO_STACK", "maximum_quantity": quantity_to_move}
			return {"success": true, "mode": "BULK_AUTO_STACK", "maximum_quantity": mini(quantity_to_move, compatible_headroom)}
	if not container.has_free_slot():
		return {"success": false, "error_code": "CONTAINER_ENTRY_LIMIT", "message": "В контейнере нет свободного места для нового стака"}
	return {"success": true, "mode": "MOVE", "maximum_quantity": quantity_to_move}


func move_item_quantity_to_container(
	item_id: String,
	requested_quantity: int,
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation(
			"item.move_to_container",
			{
				"item_id": item_id,
				"quantity": requested_quantity,
				"target_container_id": target_container_id,
				"target_slot_index": target_slot_index,
				"target_item_id": target_item_id,
			},
			"move_to_container"
		)
	var item = get_item(item_id)
	if item == null:
		return _remember({"success": false, "error_code": "ITEM_NOT_FOUND"})
	var container = get_container(target_container_id)
	if container == null:
		return _remember({"success": false, "error_code": "CONTAINER_NOT_FOUND"})

	var original_quantity: int = int(item.quantity)
	var quantity_to_move: int = original_quantity if requested_quantity < 0 else clampi(requested_quantity, 1, original_quantity)
	var resolved_target_item_id := target_item_id
	if resolved_target_item_id.is_empty() and container.is_slot_container() and target_slot_index >= 0:
		resolved_target_item_id = String(container.get_item_at_slot(target_slot_index))

	var source_already_in_target_bulk: bool = (
		not container.is_slot_container()
		and Relations.kind_of(item.relation) == Relations.CONTAINER
		and String(item.relation.get("container_id", "")) == target_container_id
	)
	if resolved_target_item_id.is_empty() and source_already_in_target_bulk and quantity_to_move < original_quantity:
		return _remember({
			"success": true,
			"item_id": item_id,
			"result_item_id": item_id,
			"moved_quantity": 0,
			"no_change": true,
			"message": "BULK-контейнер автоматически стакает предметы. Для отдельного стака перенесите часть в пустой фиксированный слот.",
		})

	if not resolved_target_item_id.is_empty():
		if resolved_target_item_id == item_id:
			return _remember({
				"success": true,
				"item_id": item_id,
				"result_item_id": item_id,
				"moved_quantity": 0,
				"no_change": true,
				"message": "Стак уже находится здесь",
			})
		var target_item = get_item(resolved_target_item_id)
		if target_item == null:
			return _remember({"success": false, "error_code": "STACK_TARGET_NOT_FOUND"})
		if Relations.kind_of(target_item.relation) != Relations.CONTAINER:
			return _remember({"success": false, "error_code": "STACK_TARGET_NOT_IN_CONTAINER"})
		if String(target_item.relation.get("container_id", "")) != target_container_id:
			return _remember({"success": false, "error_code": "STACK_TARGET_CONTAINER_MISMATCH"})
		if container.is_slot_container() and int(target_item.relation.get("slot_index", -1)) != target_slot_index:
			return _remember({"success": false, "error_code": "STACK_TARGET_SLOT_MISMATCH"})
		var stack_result: Dictionary = domain.transfer.stack_items(
			item_id,
			resolved_target_item_id,
			quantity_to_move,
			_operation("ui_stack"),
			int(item.revision),
			int(target_item.revision)
		)
		if bool(stack_result.get("success", false)):
			stack_result["requested_quantity"] = requested_quantity if requested_quantity >= 0 else original_quantity
			stack_result["message"] = "Стаки объединены: %d" % int(stack_result.get("moved_quantity", 0))
		elif String(stack_result.get("error_code", "")) == "STACK_FULL":
			stack_result["message"] = "Целевой стак заполнен"
		elif String(stack_result.get("error_code", "")) == "STACK_INCOMPATIBLE":
			stack_result["message"] = "Эти предметы нельзя объединить в один стак"
		return _after_operation(stack_result)

	var relation := Relations.container(target_container_id, target_slot_index)
	var result: Dictionary
	if quantity_to_move >= original_quantity:
		result = domain.transfer.move_item(
			item_id,
			relation,
			_operation("ui_move"),
			int(item.revision)
		)
	else:
		if item.owns_container():
			return _remember({
				"success": false,
				"error_code": "CONTAINER_ITEM_CANNOT_SPLIT",
				"message": "Контейнер нельзя разделить",
			})
		result = domain.transfer.split_and_move(
			item_id,
			quantity_to_move,
			relation,
			_operation("ui_split_move"),
			int(item.revision)
		)
	if bool(result.get("success", false)):
		result["requested_quantity"] = requested_quantity if requested_quantity >= 0 else quantity_to_move
		result["moved_quantity"] = int(result.get("moved_quantity", result.get("split_quantity", quantity_to_move)))
		if bool(result.get("merged", false)):
			result["message"] = "Перемещено и объединено: %d" % int(result.get("moved_quantity", quantity_to_move))
		elif quantity_to_move < original_quantity:
			result["message"] = "Перемещена часть стака: %d" % quantity_to_move
		else:
			result["message"] = "Предмет перемещён"
	return _after_operation(result)


func begin_inventory_cursor_carry(
	item_id: String,
	requested_quantity: int,
	cursor_container_id: String
) -> Dictionary:
	if item_id.is_empty() or cursor_container_id.is_empty():
		return _remember({"success": false, "error_code": "CURSOR_CARRY_ARGUMENT_INVALID"})
	var item = get_item(item_id)
	if item == null:
		return _remember({"success": false, "error_code": "ITEM_NOT_FOUND"})
	var cursor_result := _ensure_transient_inventory_cursor(cursor_container_id)
	if not bool(cursor_result.get("success", false)):
		return _remember(cursor_result)
	var cursor = get_container(cursor_container_id)
	if cursor == null or not cursor.item_ids.is_empty():
		return _remember({"success": false, "error_code": "CURSOR_ALREADY_OCCUPIED"})
	var quantity := clampi(requested_quantity, 1, int(item.quantity))
	var result: Dictionary
	if quantity >= int(item.quantity):
		result = domain.transfer.move_item(
			item_id,
			Relations.container(cursor_container_id, 0),
			_operation("inventory_cursor_pick_all"),
			int(item.revision)
		)
	else:
		if item.owns_container():
			return _remember({
				"success": false,
				"error_code": "CONTAINER_ITEM_CANNOT_SPLIT",
				"message": "Контейнер нельзя разделить",
			})
		result = domain.transfer.split_and_move(
			item_id,
			quantity,
			Relations.container(cursor_container_id, 0),
			_operation("inventory_cursor_pick_split"),
			int(item.revision)
		)
	if bool(result.get("success", false)):
		var carried_item_id := String(result.get("new_item_id", result.get("result_item_id", item_id)))
		result["carried_item_id"] = carried_item_id
		result["cursor_container_id"] = cursor_container_id
		result["requested_quantity"] = quantity
		result["moved_quantity"] = quantity
	return _after_operation(result)


func swap_inventory_cursor_item(carried_item_id: String, target_item_id: String) -> Dictionary:
	var carried = get_item(carried_item_id)
	var target = get_item(target_item_id)
	if carried == null or target == null:
		return _remember({"success": false, "error_code": "ITEM_NOT_FOUND"})
	var result: Dictionary = domain.transfer.swap_items(
		carried_item_id,
		target_item_id,
		_operation("inventory_cursor_swap"),
		int(carried.revision),
		int(target.revision)
	)
	if bool(result.get("success", false)):
		result["message"] = "Предметы поменяны местами"
	return _after_operation(result)


func finalize_inventory_cursor(cursor_container_id: String) -> Dictionary:
	if cursor_container_id.is_empty():
		return {"success": true, "no_change": true}
	var cursor = get_container(cursor_container_id)
	if cursor != null and not cursor.item_ids.is_empty():
		return _remember({
			"success": false,
			"error_code": "CURSOR_NOT_EMPTY",
			"remaining_item_ids": cursor.item_ids.duplicate(),
		})
	if cursor != null and not domain.containers.remove_container(cursor_container_id):
		return _remember({"success": false, "error_code": "CURSOR_CONTAINER_REMOVE_FAILED"})
	transient_inventory_cursor_ids.erase(cursor_container_id)
	var save_result := save_graph()
	if not bool(save_result.get("success", false)):
		return _remember(save_result)
	_refresh_ui()
	gameplay_state_changed.emit()
	return _remember({"success": true, "cursor_container_id": cursor_container_id, "saved": true})


func is_transient_inventory_cursor_active() -> bool:
	return not transient_inventory_cursor_ids.is_empty()


func _ensure_transient_inventory_cursor(cursor_container_id: String) -> Dictionary:
	var existing = get_container(cursor_container_id)
	if existing != null:
		if not bool(transient_inventory_cursor_ids.get(cursor_container_id, false)):
			return {"success": false, "error_code": "CURSOR_CONTAINER_ID_CONFLICT"}
		return {"success": true, "container_id": cursor_container_id}
	var cursor := ContainerState.new({
		"container_id": cursor_container_id,
		"owner_kind": "UI_TRANSIENT",
		"owner_id": profile_id,
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": 1,
		"slot_rules": [{"accepted_tags": []}],
		"maximum_mass_kg": -1.0,
		"maximum_volume_l": -1.0,
		"allow_nested_containers": true,
		"maximum_nested_depth": 32,
	})
	if not domain.containers.add_container(cursor):
		return {"success": false, "error_code": "CURSOR_CONTAINER_CREATE_FAILED"}
	transient_inventory_cursor_ids[cursor_container_id] = true
	return {"success": true, "container_id": cursor_container_id}


func interact_world_item(item_id: String) -> Dictionary:
	var item = get_item(item_id)
	if item == null:
		return _remember({"success": false, "message": "Предмет уже недоступен"})
	if item.owns_container():
		return open_container(String(item.get_owned_container_id()))
	return pickup_world_item(item_id)


func get_world_item_aggregate(item_id: String):
	return domain.world_entities.get_for_item(item_id) if not domain.is_empty() else null


func get_world_item_spatial_ref(item_id: String) -> Dictionary:
	var aggregate = get_world_item_aggregate(item_id)
	if aggregate != null:
		return aggregate.spatial_ref.duplicate(true)
	var item = get_item(item_id)
	if item != null and Relations.kind_of(item.relation) == Relations.WORLD:
		return Relations.spatial_ref_from_relation(item.relation)
	return {}


func get_world_item_transform(item_id: String) -> Transform3D:
	var spatial_ref: Dictionary = get_world_item_spatial_ref(item_id)
	if spatial_ref.is_empty():
		return Transform3D.IDENTITY
	var SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")
	return Transform3D(
		SpatialRefScript.get_basis(spatial_ref),
		SpatialRefScript.get_position(spatial_ref)
	)


func pickup_world_item(item_id: String) -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation("item.pickup", {"item_id": item_id}, "pickup")
	var item = get_item(item_id)
	if item == null:
		return _remember({"success": false, "error_code": "ITEM_NOT_FOUND"})
	if Relations.kind_of(item.relation) != Relations.WORLD:
		return _remember({"success": false, "error_code": "ITEM_NOT_IN_WORLD"})
	var result: Dictionary = domain.transfer.move_item(item_id, Relations.container(player_inventory_id), _operation("pickup"), int(item.revision))
	return _after_operation(result, "Предмет подобран")


func drop_selected_item() -> Dictionary:
	var item_id := get_selected_hotbar_item_id()
	if item_id.is_empty():
		return _remember({"success": false, "error_code": "HOTBAR_SLOT_EMPTY", "message": "Выбранный быстрый слот пуст"})
	return drop_item(item_id)


func drop_item(item_id: String, override_transform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	return drop_item_quantity(item_id, 1, override_transform)


func drop_item_stack(item_id: String, override_transform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	return drop_item_quantity(item_id, -1, override_transform)


func drop_item_quantity(
	item_id: String,
	quantity: int,
	override_transform: Transform3D = Transform3D.IDENTITY
) -> Dictionary:
	if _uses_network_commands():
		var network_transform := override_transform
		if network_transform == Transform3D.IDENTITY:
			network_transform = _default_drop_transform()
		return _submit_network_operation(
			"item.drop",
			{
				"item_id": item_id,
				"quantity": quantity,
				"transform": PlayableStateCodec.create_transform_dto(network_transform),
			},
			"drop"
		)
	var item = get_item(item_id)
	if item == null:
		return _remember({"success": false, "error_code": "ITEM_NOT_FOUND"})
	var requested_quantity := int(item.quantity) if quantity < 0 else quantity
	if requested_quantity <= 0 or requested_quantity > int(item.quantity):
		return _remember({
			"success": false,
			"error_code": "INVALID_SPLIT_QUANTITY",
			"requested_quantity": requested_quantity,
			"available_quantity": int(item.quantity),
		})
	if requested_quantity < int(item.quantity) and item.owns_container():
		return _remember({
			"success": false,
			"error_code": "CONTAINER_ITEM_CANNOT_SPLIT",
			"message": "Предмет-контейнер нельзя разделить",
		})
	var transform := override_transform
	var linear_velocity := Vector3.ZERO
	if transform == Transform3D.IDENTITY:
		transform = _default_drop_transform()
		linear_velocity = _default_drop_linear_velocity()
	var relation := Relations.world(transform, linear_velocity, physics_frame_id)
	var result: Dictionary
	if requested_quantity < int(item.quantity):
		result = domain.transfer.split_and_move(
			item_id,
			requested_quantity,
			relation,
			_operation("drop_one" if requested_quantity == 1 else "drop_quantity"),
			int(item.revision)
		)
	else:
		result = domain.transfer.move_item(
			item_id,
			relation,
			_operation("drop" if requested_quantity == 1 else "drop_stack"),
			int(item.revision)
		)
	var message := "Предмет выброшен" if requested_quantity == 1 else "Стак выброшен: ×%d" % requested_quantity
	return _after_operation(result, message)


func mount_selected_item(assembly_id: String, socket_id: String) -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation(
			"item.mount",
			{"assembly_id": assembly_id, "socket_id": socket_id},
			"mount"
		)
	var item_id := get_selected_hotbar_item_id()
	if item_id.is_empty():
		return _remember({"success": false, "error_code": "HOTBAR_SLOT_EMPTY", "message": "Поместите маяк в выбранный быстрый слот"})
	var item = get_item(item_id)
	var socket: Dictionary = domain.attachments.get_socket_state(assembly_id, socket_id)
	if socket.is_empty():
		return _remember({"success": false, "error_code": "SOCKET_NOT_FOUND"})
	if not String(socket.get("item_id", "")).is_empty():
		return _remember({"success": false, "error_code": "SOCKET_OCCUPIED"})
	var definition = get_definition(item.definition_id)
	var accepted := PackedStringArray(socket.get("accepted_tags", []))
	if not accepted.is_empty():
		var matches := false
		for tag in accepted:
			if definition.has_tag(String(tag)):
				matches = true
				break
		if not matches:
			return _remember({"success": false, "error_code": "SOCKET_TAG_REJECTED", "message": "Этот предмет нельзя установить в гнездо"})
	var result: Dictionary
	if int(item.quantity) > 1:
		result = domain.transfer.split_and_move(item_id, 1, Relations.attachment(assembly_id, String(socket.get("parent_item_id", "")), socket_id), _operation("mount_one"), int(item.revision))
	else:
		result = domain.attachments.attach(item_id, assembly_id, socket_id, _operation("mount"), int(item.revision))
	return _after_operation(result, "Маяк установлен")


func detach_socket_to_inventory(assembly_id: String, socket_id: String) -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation(
			"item.detach",
			{"assembly_id": assembly_id, "socket_id": socket_id},
			"detach"
		)
	var socket: Dictionary = domain.attachments.get_socket_state(assembly_id, socket_id)
	var item_id := String(socket.get("item_id", ""))
	if item_id.is_empty():
		return _remember({"success": false, "error_code": "SOCKET_EMPTY"})
	var item = get_item(item_id)
	var result: Dictionary = domain.attachments.detach_to_container(item_id, player_inventory_id, _operation("detach"), int(item.revision))
	return _after_operation(result, "Маяк снят в рюкзак")


func open_container(container_id: String) -> Dictionary:
	if _uses_network_commands():
		var network_result: Dictionary = _submit_network_operation(
			"container.open",
			{"container_id": container_id},
			"open_container"
		)
		if not bool(network_result.get("success", false)):
			return network_result
		if inventory_ui != null:
			inventory_ui.open_external_container(container_id)
		set_inventory_visible(true)
		return _remember(network_result)
	if get_container(container_id) == null:
		return _remember({"success": false, "error_code": "CONTAINER_NOT_FOUND"})
	if inventory_ui != null:
		inventory_ui.open_external_container(container_id)
	set_inventory_visible(true)
	return _remember({"success": true, "container_id": container_id, "message": "Контейнер открыт"})


func close_external_container() -> Dictionary:
	var container_id: String = (
		String(inventory_ui.external_container_id)
		if inventory_ui != null
		else ""
	)
	var result: Dictionary = {"success": true, "container_id": container_id}
	if _uses_network_commands() and not container_id.is_empty():
		result = _submit_network_operation(
			"container.close",
			{"container_id": container_id},
			"close_container"
		)
	if inventory_ui != null:
		inventory_ui.close_external_container(false)
	return _remember(result)


func save_graph() -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation("item.save", {}, "save")
	if not transient_inventory_cursor_ids.is_empty():
		return {
			"success": true,
			"skipped": true,
			"reason": "TRANSIENT_INVENTORY_CURSOR_ACTIVE",
			"cursor_container_ids": transient_inventory_cursor_ids.keys(),
		}
	if graph_persistence == null:
		return {"success": false, "error_code": "PERSISTENCE_NOT_READY"}
	if persistence_blocked:
		return {"success": false, "error_code": "ITEM_GRAPH_PERSISTENCE_BLOCKED", "cause": persistence_error.duplicate(true)}
	if presenter != null:
		presenter.capture_all_world_states()
	return graph_persistence.save({
		"profile_id": profile_id,
		"selected_hotbar_index": selected_hotbar_index,
		"player_inventory_id": player_inventory_id,
		"player_hotbar_id": player_hotbar_id,
		"starter_pack_revision": starter_pack_revision,
	})


func reload_graph() -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation("item.reload", {}, "reload")
	var result: Dictionary = graph_persistence.load()
	if bool(result.get("success", false)):
		persistence_blocked = false
		persistence_error = {}
		var loaded_metadata: Dictionary = Dictionary(result.get("metadata", {}))
		selected_hotbar_index = clampi(int(loaded_metadata.get("selected_hotbar_index", selected_hotbar_index)), 0, 9)
		starter_pack_revision = int(loaded_metadata.get("starter_pack_revision", starter_pack_revision))
		_register_default_definitions()
		_upgrade_legacy_mount_fixture()
		if presenter != null:
			presenter.synchronize_all()
		if placement_service != null:
			placement_service.synchronize_all()
		_refresh_ui()
	else:
		persistence_blocked = true
		persistence_error = result.duplicate(true)
	return result


func get_item(item_id: String):
	return domain.items.get_item(item_id) if not domain.is_empty() else null


func get_definition(definition_id: String):
	return domain.items.get_definition(definition_id) if not domain.is_empty() else null


func get_container(container_id: String):
	return domain.containers.get_container(container_id) if not domain.is_empty() else null


func get_item_mass_kg(item_id: String) -> float:
	return domain.mass.item_recursive_mass_kg(item_id) if not domain.is_empty() else 0.0


func get_socket_state(assembly_id: String, socket_id: String) -> Dictionary:
	return domain.attachments.get_socket_state(assembly_id, socket_id) if not domain.is_empty() else {}


func get_container_display_name(container_id: String) -> String:
	var container = get_container(container_id)
	if container == null:
		return container_id
	if container.owner_kind == "ITEM_INSTANCE":
		var owner = get_item(container.owner_id)
		if owner != null:
			return owner.display_name
	if container_id == player_inventory_id:
		return "Рюкзак игрока"
	if container_id == player_hotbar_id:
		return "Быстрая панель"
	return container_id


func result_message(result: Dictionary) -> String:
	if bool(result.get("success", false)):
		return String(result.get("message", result.get("output", "Готово")))
	if result.has("message") and not String(result.get("message", "")).is_empty():
		return String(result.get("message", ""))
	var code := String(result.get("error_code", "UNKNOWN"))
	var messages := {
		"REVISION_CONFLICT": "Состояние предмета изменилось. Обновите инвентарь и повторите перенос.",
		"INVALID_SPLIT_QUANTITY": "Выбранное количество больше не соответствует размеру стака.",
		"SLOT_OCCUPIED": "Целевой слот уже занят.",
		"SLOT_REQUIRED": "Выберите конкретный слот контейнера.",
		"MAXIMUM_MASS_EXCEEDED": "Недостаточно допустимой массы контейнера.",
		"MAXIMUM_VOLUME_EXCEEDED": "Недостаточно объёма контейнера.",
		"STACK_TARGET_NOT_FOUND": "Целевой стак уже изменился. Обновите меню.",
		"ITEM_NOT_FOUND": "Исходный стак уже изменился или был перемещён.",
	}
	return String(messages.get(code, "Ошибка: %s" % code))


func create_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.item_gameplay_snapshot.v1",
		"profile_id": profile_id,
		"inventory_open": inventory_open,
		"selected_hotbar_index": selected_hotbar_index,
		"selected_item_id": get_selected_hotbar_item_id(),
		"operation_session_id": operation_session_id,
		"persistence_blocked": persistence_blocked,
		"persistence_error": persistence_error.duplicate(true),
		"runtime_mode": runtime_mode,
		"network_replica_revision": network_replica_revision,
		"network_replica_checksum": network_replica_checksum,
		"direct_authority_references": 0,
		"items": domain.items.to_dict(),
		"containers": domain.containers.to_dict(),
		"attachments": domain.attachments.to_dict(),
		"placed_fixture_count": placement_service.fixture_nodes.size() if placement_service != null else 0,
		"graph_valid": bool(domain.validator.validate_graph().get("success", false)),
	}


func _register_default_definitions() -> void:
	for data in [
		{"id": "survey_beacon", "display_name": "Полевой маяк", "max_stack": 5, "unit_mass_kg": 2.5, "external_volume_l": 3.0, "tags": ["beacon", "mountable", "electronic"], "metadata": {"size": [0.32, 0.58, 0.32], "icon_color": [1.0, 0.34, 0.05]}},
		{"id": "battery_pack", "display_name": "Аккумулятор", "max_stack": 4, "unit_mass_kg": 8.0, "external_volume_l": 6.0, "tags": ["battery", "power"], "metadata": {"size": [0.42, 0.28, 0.30], "icon_color": [0.20, 0.82, 0.32]}},
		{"id": "lunar_rock", "display_name": "Лунный камень", "max_stack": 50, "unit_mass_kg": 2.0, "external_volume_l": 0.8, "tags": ["rock", "resource"], "metadata": {"size": [0.34, 0.26, 0.36], "icon_color": [0.65, 0.65, 0.70]}},
		{"id": "portable_crate", "display_name": "Универсальный ящик", "max_stack": 1, "unit_mass_kg": 4.0, "external_volume_l": 30.0, "tags": ["container"], "metadata": {"size": [0.95, 0.65, 0.72], "icon_color": [0.62, 0.38, 0.14], "freeze_world_body": true}},
		{"id": "battery_rack", "display_name": "Батарейный шкаф", "max_stack": 1, "unit_mass_kg": 18.0, "external_volume_l": 80.0, "tags": ["container", "rack"], "metadata": {"size": [1.2, 1.4, 0.65], "icon_color": [0.20, 0.28, 0.34], "freeze_world_body": true}},
		{
			"id": "beacon_mount_base",
			"display_name": "Монтажное гнездо маяка",
			"max_stack": 10,
			"unit_mass_kg": 6.0,
			"external_volume_l": 12.0,
			"tags": ["assembly_root", "placeable", "mount_socket"],
			"metadata": {
				"presentation_mode": "EXTERNAL",
				"icon_color": [0.18, 0.48, 0.60],
				"debug_grantable": true,
				"placement": {
					"schema": PlacementContract.SCHEMA,
					"kind": PlacementContract.KIND_MOUNT_SOCKET,
					"max_distance_m": 8.0,
					"collision_mask": 1,
					"surface_offset_m": 0.17,
					"socket": {"socket_id": "beacon_socket", "accepted_tags": ["beacon"]},
				},
			},
		},
	]:
		domain.items.register_definition(Definition.new(data))


func _seed_default_graph(include_demo_world: bool) -> void:
	var inventory := ContainerState.new({
		"container_id": player_inventory_id,
		"owner_kind": "ACTOR",
		"owner_id": "player",
		"storage_mode": ContainerState.STORAGE_BULK,
		"slot_count": 18,
		"maximum_mass_kg": 180.0,
		"maximum_volume_l": 220.0,
		"allow_nested_containers": true,
		"maximum_nested_depth": 3,
	})
	var hotbar_rules: Array = []
	for _index in range(10):
		hotbar_rules.append({"accepted_tags": []})
	var hotbar := ContainerState.new({
		"container_id": player_hotbar_id,
		"owner_kind": "ACTOR",
		"owner_id": "player",
		"parent_container_id": player_inventory_id,
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": 10,
		"slot_rules": hotbar_rules,
		"maximum_mass_kg": 120.0,
		"maximum_volume_l": 120.0,
	})
	domain.containers.add_container(inventory)
	domain.containers.add_container(hotbar)
	var starter_beacons = domain.items.create_item("survey_beacon", 3, {}, Relations.container(player_inventory_id))
	inventory.assign_item(starter_beacons.instance_id)
	var batteries = domain.items.create_item("battery_pack", 2, {}, Relations.container(player_inventory_id))
	inventory.assign_item(batteries.instance_id)
	var starter_mounts = domain.items.create_item("beacon_mount_base", 3, {}, Relations.container(player_inventory_id))
	inventory.assign_item(starter_mounts.instance_id)
	starter_pack_revision = 2
	if not include_demo_world:
		return
	var crate = domain.items.create_item("portable_crate", 1, {"container": {"container_id": "demo_crate_contents"}}, Relations.world(Transform3D(Basis.IDENTITY, Vector3(3.0, 0.8, -2.0)), Vector3.ZERO, physics_frame_id))
	var crate_contents := ContainerState.new({
		"container_id": "demo_crate_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": crate.instance_id,
		"storage_mode": ContainerState.STORAGE_BULK, "slot_count": 12,
		"maximum_mass_kg": 120.0, "maximum_volume_l": 90.0, "allow_nested_containers": true,
	})
	domain.containers.add_container(crate_contents)
	var crate_beacons = domain.items.create_item("survey_beacon", 4, {}, Relations.container(crate_contents.container_id))
	crate_contents.assign_item(crate_beacons.instance_id)
	var crate_rocks = domain.items.create_item("lunar_rock", 6, {}, Relations.container(crate_contents.container_id))
	crate_contents.assign_item(crate_rocks.instance_id)
	var rack = domain.items.create_item("battery_rack", 1, {"container": {"container_id": "battery_rack_slots"}}, Relations.world(Transform3D(Basis.IDENTITY, Vector3(-3.5, 0.75, -2.0)), Vector3.ZERO, physics_frame_id))
	var rack_slots := ContainerState.new({
		"container_id": "battery_rack_slots", "owner_kind": "ITEM_INSTANCE", "owner_id": rack.instance_id,
		"storage_mode": ContainerState.STORAGE_SLOTS, "slot_count": 4,
		"slot_rules": [{"accepted_tags": ["battery"]}, {"accepted_tags": ["battery"]}, {"accepted_tags": ["battery"]}, {"accepted_tags": ["battery"]}],
		"maximum_mass_kg": 80.0, "maximum_volume_l": 40.0, "allow_nested_containers": false,
	})
	domain.containers.add_container(rack_slots)
	var rack_battery = domain.items.create_item("battery_pack", 1, {}, Relations.container(rack_slots.container_id, 0))
	rack_slots.assign_item(rack_battery.instance_id, 0)
	var mount_base = domain.items.create_item(
		"beacon_mount_base",
		1,
		{"placement": {
			"installed": true,
			"kind": PlacementContract.KIND_MOUNT_SOCKET,
			"assembly_id": "demo_mount",
			"socket_id": "beacon_socket",
		}},
		Relations.world(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.16, -5.0)), Vector3.ZERO, physics_frame_id)
	)
	domain.attachments.ensure_socket("demo_mount", mount_base.instance_id, "beacon_socket", ["beacon"])


func place_selected_item_from_view() -> Dictionary:
	var item_id := get_selected_hotbar_item_id()
	if item_id.is_empty():
		return _remember({"success": false, "error_code": "HOTBAR_SLOT_EMPTY", "message": "Выберите монтажное гнездо в панели 1–0"})
	var item = get_item(item_id)
	var definition = get_definition(item.definition_id) if item != null else null
	if placement_service == null or not placement_service.can_place_definition(definition):
		return _remember({"success": false, "error_code": "ITEM_NOT_PLACEABLE", "message": "Выбранный предмет нельзя установить на поверхность"})
	var query: Dictionary = placement_service.query_surface_from_actor(definition)
	if not bool(query.get("success", false)):
		return _remember(query)
	return place_selected_item_at_transform(query.get("transform", Transform3D.IDENTITY))


func place_selected_item_at_transform(target_transform: Transform3D) -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation(
			"item.place",
			{"transform": PlayableStateCodec.create_transform_dto(target_transform)},
			"place"
		)
	var source_item_id := get_selected_hotbar_item_id()
	var source = get_item(source_item_id)
	if source == null:
		return _remember({"success": false, "error_code": "HOTBAR_SLOT_EMPTY", "message": "Выберите устанавливаемый предмет в панели 1–0"})
	var definition = get_definition(source.definition_id)
	var profile := PlacementContract.get_profile(definition)
	if profile.is_empty() or (placement_service != null and not placement_service.can_place_definition(definition)):
		return _remember({"success": false, "error_code": "ITEM_NOT_PLACEABLE", "message": "Этот предмет не поддерживает установку"})
	var relation := Relations.world(target_transform, Vector3.ZERO, physics_frame_id)
	var transfer_result: Dictionary
	if int(source.quantity) > 1 and not source.owns_container():
		transfer_result = domain.transfer.split_and_move(source_item_id, 1, relation, _operation("place_one"), int(source.revision))
	else:
		transfer_result = domain.transfer.move_item(source_item_id, relation, _operation("place"), int(source.revision))
	if not bool(transfer_result.get("success", false)):
		return _after_operation(transfer_result)
	var placed_item_id := String(transfer_result.get("new_item_id", transfer_result.get("result_item_id", source_item_id)))
	var placed = get_item(placed_item_id)
	if placed == null:
		return _remember({"success": false, "error_code": "PLACED_ITEM_NOT_FOUND", "message": "Не удалось завершить установку"})
	var socket_profile: Dictionary = Dictionary(profile.get("socket", {}))
	var assembly_id := "fixture/%s" % placed_item_id
	var socket_id := String(socket_profile.get("socket_id", "primary"))
	var components: Dictionary = Dictionary(placed.components).duplicate(true)
	components["placement"] = {
		"installed": true,
		"kind": String(profile.get("kind", "")),
		"assembly_id": assembly_id,
		"socket_id": socket_id,
	}
	placed.components = components
	placed.revision += 1
	domain.attachments.ensure_socket(assembly_id, placed_item_id, socket_id, socket_profile.get("accepted_tags", []))
	if presenter != null:
		presenter.synchronize_item(placed_item_id)
	if placement_service != null:
		placement_service.synchronize_item(placed_item_id)
	_refresh_ui()
	save_graph()
	gameplay_state_changed.emit()
	return _remember({
		"success": true,
		"item_id": placed_item_id,
		"assembly_id": assembly_id,
		"socket_id": socket_id,
		"message": "%s установлено" % String(definition.display_name),
	})


func list_debug_item_catalog() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ids: Array = domain.items.definitions.keys()
	ids.sort()
	for definition_id_value in ids:
		var definition = get_definition(String(definition_id_value))
		if definition == null or not bool(definition.metadata.get("debug_grantable", true)):
			continue
		rows.append({
			"definition_id": String(definition.id),
			"display_name": String(definition.display_name),
			"max_stack": int(definition.max_stack),
			"tags": Array(definition.tags),
			"icon_color": definition.metadata.get("icon_color", []).duplicate(),
		})
	return rows


func grant_debug_item(definition_id: String, total_quantity: int) -> Dictionary:
	if _uses_network_commands():
		return _submit_network_operation(
			"item.grant_debug",
			{"definition_id": definition_id, "quantity": total_quantity},
			"grant_debug"
		)
	var definition = get_definition(definition_id)
	if definition == null:
		return _remember({"success": false, "error_code": "ITEM_DEFINITION_NOT_FOUND", "message": "Неизвестный предмет: %s" % definition_id})
	var remaining := maxi(1, total_quantity)
	var inventory = get_container(player_inventory_id)
	if inventory == null:
		return _remember({"success": false, "error_code": "CONTAINER_NOT_FOUND"})
	# Admin delivery deliberately bypasses gameplay capacity, but preserves stack
	# compatibility, max_stack and globally unique aggregate IDs.
	for existing_id in inventory.item_ids.duplicate():
		if remaining <= 0:
			break
		var existing = get_item(String(existing_id))
		if existing == null or existing.definition_id != definition_id:
			continue
		var probe = domain.items.create_item(definition_id, 1, existing.components, Relations.destroyed(), existing.display_name)
		if probe == null:
			continue
		var compatible: bool = bool(existing.is_stack_compatible(probe))
		domain.items.remove_item(probe.instance_id)
		if not compatible:
			continue
		var available := maxi(0, int(definition.max_stack) - int(existing.quantity))
		var moved := mini(available, remaining)
		if moved <= 0:
			continue
		existing.quantity += moved
		existing.revision += 1
		remaining -= moved
	while remaining > 0:
		var chunk := mini(remaining, int(definition.max_stack))
		var created = domain.items.create_item(definition_id, chunk, {"debug_grant": true}, Relations.container(player_inventory_id))
		if created == null:
			return _remember({"success": false, "error_code": "DEBUG_GRANT_CREATE_FAILED", "granted_quantity": total_quantity - remaining})
		inventory.assign_item(created.instance_id)
		remaining -= chunk
	inventory.revision += 1
	if presenter != null:
		presenter.synchronize_all()
	if placement_service != null:
		placement_service.synchronize_all()
	_refresh_ui()
	save_graph()
	gameplay_state_changed.emit()
	return _remember({"success": true, "definition_id": definition_id, "granted_quantity": total_quantity, "message": "Выдано: %s ×%d" % [definition.display_name, total_quantity]})


func _upgrade_legacy_mount_fixture() -> void:
	for item in domain.items.all_items():
		if item.definition_id != "beacon_mount_base" or Relations.kind_of(item.relation) != Relations.WORLD:
			continue
		var placement = item.components.get("placement", {})
		if placement is Dictionary and bool(placement.get("installed", false)):
			continue
		var components: Dictionary = Dictionary(item.components).duplicate(true)
		components["placement"] = {
			"installed": true,
			"kind": PlacementContract.KIND_MOUNT_SOCKET,
			"assembly_id": "demo_mount" if not domain.attachments.get_socket_state("demo_mount", "beacon_socket").is_empty() else "fixture/%s" % item.instance_id,
			"socket_id": "beacon_socket",
		}
		item.components = components
		item.revision += 1
		var assembly_id := String(components["placement"]["assembly_id"])
		domain.attachments.ensure_socket(assembly_id, item.instance_id, "beacon_socket", ["beacon"])


func _ensure_starter_pack() -> void:
	if starter_pack_revision >= 2:
		return
	var inventory = get_container(player_inventory_id)
	if inventory == null:
		return
	var mounts = domain.items.create_item("beacon_mount_base", 3, {}, Relations.container(player_inventory_id))
	if mounts != null:
		inventory.assign_item(mounts.instance_id)
		starter_pack_revision = 2


func _migrate_all_world_items_to_aggregates() -> Dictionary:
	var result: Dictionary = domain.world_entities.migrate_legacy_item_relations(domain.items)
	if not bool(result.get("success", false)):
		return result
	return domain.world_entities.validate_item_bindings(domain.items)


func _reconcile_world_entity_binding(item_id: String, old_relation: Dictionary) -> Dictionary:
	var item = get_item(item_id)
	var old_entity_id: String = Relations.world_entity_id(old_relation)
	if item == null:
		if not old_entity_id.is_empty():
			domain.world_entities.remove_entity(old_entity_id)
		else:
			domain.world_entities.remove_for_item(item_id)
		return {"success": true}
	if Relations.kind_of(item.relation) != Relations.WORLD:
		domain.world_entities.remove_for_item(item_id)
		return {"success": true}
	var current_entity_id: String = Relations.world_entity_id(item.relation)
	if not current_entity_id.is_empty():
		var bound = domain.world_entities.get_entity(current_entity_id)
		if bound == null or bound.item_instance_id != item_id:
			return {"success": false, "error_code": "WORLD_ENTITY_BINDING_INVALID"}
		return {"success": true, "entity_id": current_entity_id}
	var spatial_ref: Dictionary = Relations.spatial_ref_from_relation(item.relation)
	var aggregate = null
	if not old_entity_id.is_empty():
		aggregate = domain.world_entities.get_entity(old_entity_id)
	if aggregate != null:
		var update_result: Dictionary = aggregate.apply_spatial_state(
			spatial_ref,
			aggregate.physics_state,
			aggregate.partition_address,
			-1,
			aggregate.authority_epoch
		)
		if not bool(update_result.get("success", false)):
			return update_result
	else:
		aggregate = domain.world_entities.create_for_item(item_id, spatial_ref, {
			"state_revision": int(item.revision),
			"domain_components": {
				"definition_id": item.definition_id,
				"quantity": int(item.quantity),
			},
		})
		if aggregate == null:
			return {"success": false, "error_code": "WORLD_ENTITY_CREATE_FAILED"}
	item.set_relation(Relations.world_entity(aggregate.entity_id))
	return {"success": true, "entity_id": aggregate.entity_id}


func _connect_domain_signals() -> void:
	domain.transfer.relation_changed.connect(_on_relation_changed)
	domain.transfer.item_removed.connect(_on_item_removed)
	domain.transfer.item_created.connect(_on_item_created)
	domain.transfer.quantity_changed.connect(_on_quantity_changed)


func _on_relation_changed(item_id: String, old_relation: Dictionary, _new: Dictionary) -> void:
	var reconcile_result: Dictionary = _reconcile_world_entity_binding(item_id, old_relation)
	if not bool(reconcile_result.get("success", false)):
		persistence_blocked = true
		persistence_error = reconcile_result.duplicate(true)
	if presenter != null:
		presenter.synchronize_item(item_id)
	if placement_service != null:
		placement_service.synchronize_item(item_id)
	_refresh_ui()


func _on_item_removed(item_id: String) -> void:
	domain.world_entities.remove_for_item(item_id)
	if presenter != null:
		presenter.synchronize_item(item_id)
	if placement_service != null:
		placement_service.synchronize_item(item_id)
	_refresh_ui()


func _on_item_created(item_id: String) -> void:
	if presenter != null:
		presenter.synchronize_item(item_id)
	if placement_service != null:
		placement_service.synchronize_item(item_id)
	_refresh_ui()


func _on_quantity_changed(item_id: String, _old: int, new_quantity: int) -> void:
	var aggregate = domain.world_entities.get_for_item(item_id)
	if aggregate != null:
		aggregate.apply_domain_components({"quantity": new_quantity})
	if presenter != null:
		presenter.synchronize_all()
	if placement_service != null:
		placement_service.synchronize_all()
	_refresh_ui()


func create_network_graph_snapshot() -> Dictionary:
	if graph_persistence == null:
		return {}
	var result: Dictionary = graph_persistence.create_snapshot_result({
		"profile_id": profile_id,
		"selected_hotbar_index": selected_hotbar_index,
		"player_inventory_id": player_inventory_id,
		"player_hotbar_id": player_hotbar_id,
		"starter_pack_revision": starter_pack_revision,
	})
	return (
		Dictionary(result.get("snapshot", {})).duplicate(true)
		if bool(result.get("success", false))
		else {}
	)


func apply_network_graph_snapshot(
	graph_snapshot: Dictionary,
	replica_revision: int = -1,
	replica_checksum: String = ""
) -> Dictionary:
	if runtime_mode != RUNTIME_MODE_REPLICA or graph_persistence == null:
		return {"success": false, "error_code": "ITEM_CONTROLLER_NOT_REPLICA"}
	var load_result: Dictionary = graph_persistence.load_snapshot(graph_snapshot)
	if not bool(load_result.get("success", false)):
		return load_result
	_register_default_definitions()
	var loaded_metadata: Dictionary = Dictionary(load_result.get("metadata", {}))
	selected_hotbar_index = clampi(
		int(loaded_metadata.get("selected_hotbar_index", selected_hotbar_index)),
		0,
		9
	)
	starter_pack_revision = int(
		loaded_metadata.get("starter_pack_revision", starter_pack_revision)
	)
	network_replica_revision = replica_revision
	network_replica_checksum = replica_checksum
	if presenter != null:
		presenter.synchronize_all()
	if placement_service != null:
		placement_service.synchronize_all()
	_refresh_ui()
	gameplay_state_changed.emit()
	return {
		"success": true,
		"item_count": domain.items.items.size(),
		"container_count": domain.containers.containers.size(),
		"replica_revision": network_replica_revision,
		"replica_checksum": network_replica_checksum,
	}


func _uses_network_commands() -> bool:
	return runtime_mode == RUNTIME_MODE_REPLICA and network_command_bridge != null


func _submit_network_operation(
	command_type: String,
	payload: Dictionary,
	operation_prefix: String
) -> Dictionary:
	if not _uses_network_commands():
		return _remember({
			"success": false,
			"error_code": "NETWORK_COMMAND_BRIDGE_REQUIRED",
		})
	if not network_command_bridge.has_method("submit_item_command"):
		return _remember({
			"success": false,
			"error_code": "INVALID_NETWORK_COMMAND_BRIDGE",
		})
	var result_value = network_command_bridge.call(
		"submit_item_command",
		command_type,
		payload.duplicate(true),
		_operation(operation_prefix)
	)
	if not result_value is Dictionary:
		return _remember({
			"success": false,
			"error_code": "INVALID_NETWORK_COMMAND_RESULT",
		})
	var result: Dictionary = Dictionary(result_value).duplicate(true)
	var snapshot_value = result.get("replica_snapshot", {})
	if snapshot_value is Dictionary and not Dictionary(snapshot_value).is_empty():
		var components_value = Dictionary(snapshot_value).get("domain_components", {})
		var graph_value = (
			Dictionary(components_value).get("item_graph", {})
			if components_value is Dictionary
			else {}
		)
		if graph_value is Dictionary and not Dictionary(graph_value).is_empty():
			var apply_result: Dictionary = apply_network_graph_snapshot(
				Dictionary(graph_value),
				int(Dictionary(snapshot_value).get("state_revision", -1)),
				String(Dictionary(snapshot_value).get("checksum", ""))
			)
			if not bool(apply_result.get("success", false)):
				return _remember({
					"success": false,
					"error_code": "REPLICA_GRAPH_APPLY_FAILED",
					"cause": apply_result,
				})
	result.erase("replica_snapshot")
	result.erase("network_result")
	return _remember(result)


func _after_operation(result: Dictionary, success_message: String = "") -> Dictionary:
	if bool(result.get("success", false)):
		if not success_message.is_empty():
			result["message"] = success_message
		if presenter != null:
			presenter.synchronize_all()
		if placement_service != null:
			placement_service.synchronize_all()
		_refresh_ui()
		save_graph()
		gameplay_state_changed.emit()
	return _remember(result)


func _remember(result: Dictionary) -> Dictionary:
	last_result = result.duplicate(true)
	return result


func _refresh_ui() -> void:
	if inventory_ui != null:
		inventory_ui.refresh()


func _operation(prefix: String) -> String:
	var value := "%s-%s-%s-%d" % [profile_id, operation_session_id, prefix, operation_counter]
	operation_counter += 1
	return value


func _create_operation_session_id() -> String:
	var random_bytes := Crypto.new().generate_random_bytes(12)
	var hex_value := ""
	for byte_value in random_bytes:
		hex_value += "%02x" % int(byte_value)
	if hex_value.is_empty():
		hex_value = "%x-%x" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	return hex_value


func _default_drop_transform() -> Transform3D:
	if player is Node3D and world_root != null:
		var player_node := player as Node3D
		var forward := _drop_view_forward_global(player_node)
		var up := player_node.global_basis.y.normalized()
		if up.length_squared() < 0.000001:
			up = Vector3.UP
		var target_global := Transform3D(
			Basis.IDENTITY,
			player_node.global_position
				+ up * DEFAULT_DROP_HEIGHT_M
				+ forward * DEFAULT_DROP_DISTANCE_M
		)
		return world_root.global_transform.affine_inverse() * target_global
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, -1.5))


func _default_drop_linear_velocity() -> Vector3:
	if not player is Node3D or world_root == null:
		return Vector3.ZERO
	var forward_global := _drop_view_forward_global(player as Node3D)
	return world_root.global_basis.inverse() * (forward_global * DEFAULT_DROP_SPEED_MPS)


func _drop_view_forward_global(player_node: Node3D) -> Vector3:
	var forward := Vector3.ZERO
	if player_node.has_method("get_view_basis"):
		var view_basis_value: Variant = player_node.call("get_view_basis")
		if view_basis_value is Basis:
			var view_basis: Basis = view_basis_value
			forward = -view_basis.z
	if forward.length_squared() < 0.000001:
		forward = -player_node.global_basis.z
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD
	return forward.normalized()
