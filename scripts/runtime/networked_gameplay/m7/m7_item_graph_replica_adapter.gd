extends RefCounted

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ItemInstance = preload("res://scripts/items/domain/item_instance.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const GraphPersistence = preload("res://scripts/items/persistence/item_graph_persistence.gd")
const PlacementContract = preload("res://scripts/items/placement/item_placement_contract.gd")
const PlayableStateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

const SCHEMA := "planet_simulator.m7_item_graph_replica_adapter.v1"
const LOCAL_INVENTORY_ID := "player_inventory"
const LOCAL_HOTBAR_ID := "player_hotbar"
const HOTBAR_SIZE := 10
const INVENTORY_SIZE := 18

var _local_player_id := ""
var _canonical_to_replica: Dictionary = {}
var _replica_to_canonical: Dictionary = {}


func setup(local_player_id: String) -> Dictionary:
	_local_player_id = local_player_id.strip_edges().to_lower()
	_canonical_to_replica.clear()
	_replica_to_canonical.clear()
	if _local_player_id.is_empty():
		return _failure("M7_LOCAL_PLAYER_ID_REQUIRED")
	return _success()


func convert(canonical_snapshot: Dictionary) -> Dictionary:
	if _local_player_id.is_empty():
		return _failure("M7_ITEM_ADAPTER_NOT_CONFIGURED")
	if String(canonical_snapshot.get("schema", "")) != "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1":
		return _failure("M7_CANONICAL_ITEM_GRAPH_REQUIRED")
	var domain: Dictionary = Factory.create()
	domain.world_entities.setup({
		"authority_owner_id": String(canonical_snapshot.get("authority_owner_id", "network-authority")),
		"authority_epoch": int(canonical_snapshot.get("authority_epoch", 1)),
	})
	_register_definitions(domain)
	var container_map: Dictionary = _build_containers(domain, canonical_snapshot)
	var mount_map: Dictionary = _mount_map(canonical_snapshot)
	var inventory_map: Dictionary = Dictionary(canonical_snapshot.get("inventories", {}))
	var item_rows: Array = Array(canonical_snapshot.get("items", []))
	for item_value in item_rows:
		if not item_value is Dictionary:
			return _failure("M7_INVALID_CANONICAL_ITEM")
		var add_result := _add_item(domain, Dictionary(item_value), inventory_map, container_map, mount_map)
		if not bool(add_result.get("success", false)):
			return add_result
	var socket_result := _add_mount_sockets(domain, mount_map)
	if not bool(socket_result.get("success", false)):
		return socket_result
	var graph_validation: Dictionary = domain.validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		return _failure("M7_REPLICA_GRAPH_INVALID", graph_validation)
	var persistence = GraphPersistence.new()
	persistence.setup(domain, null, "m7-network-replica")
	var local_inventory: Dictionary = Dictionary(inventory_map.get(_local_player_id, {}))
	var snapshot_result: Dictionary = persistence.create_snapshot_result({
		"profile_id": "playground",
		"selected_hotbar_index": clampi(int(local_inventory.get("selected_hotbar_index", 0)), 0, HOTBAR_SIZE - 1),
		"player_inventory_id": LOCAL_INVENTORY_ID,
		"player_hotbar_id": LOCAL_HOTBAR_ID,
		"starter_pack_revision": 2,
		"source_schema": String(canonical_snapshot.get("schema", "")),
		"source_revision": int(canonical_snapshot.get("revision", -1)),
		"source_checksum": String(canonical_snapshot.get("checksum", "")),
		"network_profile": "seven_days_like",
	})
	if not bool(snapshot_result.get("success", false)):
		return snapshot_result
	return _success({
		"graph_snapshot": Dictionary(snapshot_result.get("snapshot", {})).duplicate(true),
		"canonical_revision": int(canonical_snapshot.get("revision", -1)),
		"canonical_checksum": String(canonical_snapshot.get("checksum", "")),
		"item_count": item_rows.size(),
		"container_count": domain.containers.containers.size(),
		"world_entity_count": domain.world_entities.size(),
	})


func create_replica_snapshot(canonical_snapshot: Dictionary) -> Dictionary:
	var converted: Dictionary = self.convert(canonical_snapshot)
	if not bool(converted.get("success", false)):
		return converted
	var details: Dictionary = Dictionary(converted.get("details", {}))
	return _success({
		"replica_snapshot": {
			"domain_components": {"item_graph": details.get("graph_snapshot", {})},
			"state_revision": int(details.get("canonical_revision", -1)),
			"checksum": String(details.get("canonical_checksum", "")),
		},
		"graph_snapshot": details.get("graph_snapshot", {}),
		"canonical_revision": int(details.get("canonical_revision", -1)),
		"canonical_checksum": String(details.get("canonical_checksum", "")),
	})


func _build_containers(domain: Dictionary, snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var local_inventory := ContainerState.new({
		"container_id": LOCAL_INVENTORY_ID,
		"owner_kind": "ACTOR",
		"owner_id": "player/%s" % _local_player_id,
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": INVENTORY_SIZE,
		"maximum_mass_kg": 180.0,
		"maximum_volume_l": 220.0,
		"allow_nested_containers": true,
		"maximum_nested_depth": 3,
	})
	domain.containers.add_container(local_inventory)
	result[LOCAL_INVENTORY_ID] = local_inventory
	var local_hotbar := ContainerState.new({
		"container_id": LOCAL_HOTBAR_ID,
		"owner_kind": "ACTOR",
		"owner_id": "player/%s" % _local_player_id,
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": HOTBAR_SIZE,
		"maximum_mass_kg": 80.0,
		"maximum_volume_l": 100.0,
		"allow_nested_containers": true,
		"maximum_nested_depth": 2,
	})
	domain.containers.add_container(local_hotbar)
	result[LOCAL_HOTBAR_ID] = local_hotbar
	for player_id_value in Dictionary(snapshot.get("inventories", {})).keys():
		var player_id := String(player_id_value)
		if player_id == _local_player_id:
			continue
		var hidden_id := _remote_inventory_id(player_id)
		var hidden := ContainerState.new({
			"container_id": hidden_id,
			"owner_kind": "ACTOR",
			"owner_id": "player/%s" % player_id,
			"storage_mode": ContainerState.STORAGE_BULK,
			"slot_count": 64,
			"allow_nested_containers": true,
		})
		domain.containers.add_container(hidden)
		result[hidden_id] = hidden
	for container_value in snapshot.get("containers", []):
		if not container_value is Dictionary:
			continue
		var row: Dictionary = container_value
		var container_id := String(row.get("container_id", ""))
		if container_id.is_empty():
			continue
		var state := ContainerState.new({
			"container_id": container_id,
			"owner_kind": "ITEM_INSTANCE",
			"owner_id": _replica_item_id(String(row.get("owner_item_id", ""))),
			"storage_mode": ContainerState.STORAGE_SLOTS,
			"slot_count": maxi(1, int(row.get("capacity", 1))),
			"maximum_mass_kg": 500.0,
			"maximum_volume_l": 500.0,
			"allow_nested_containers": true,
		})
		domain.containers.add_container(state)
		result[container_id] = state
	return result


func _add_item(
	domain: Dictionary,
	row: Dictionary,
	inventory_map: Dictionary,
	container_map: Dictionary,
	mount_map: Dictionary
) -> Dictionary:
	var canonical_item_id := String(row.get("item_id", ""))
	var item_id := _replica_item_id(canonical_item_id)
	var definition_id := _definition_id(String(row.get("definition_id", "")))
	if canonical_item_id.is_empty() or item_id.is_empty() or definition_id.is_empty():
		return _failure("M7_INVALID_CANONICAL_ITEM_IDENTITY")
	var location: Dictionary = Dictionary(row.get("location", {}))
	var relation_result: Dictionary = _relation_for_item(row, location, inventory_map, mount_map)
	if not bool(relation_result.get("success", false)):
		return relation_result
	var components: Dictionary = {}
	if definition_id == "portable_crate":
		var owned_container_id := _owned_container_id(item_id, container_map)
		if not owned_container_id.is_empty():
			components["container"] = {"container_id": owned_container_id}
	if definition_id == "beacon_mount_base" and String(location.get("kind", "")) == "WORLD":
		var mount_id := String(row.get("mount_id", "fixture/%s" % item_id))
		components["placement"] = {
			"installed": true,
			"kind": PlacementContract.KIND_MOUNT_SOCKET,
			"assembly_id": mount_id,
			"socket_id": "beacon_socket",
		}
	var item := ItemInstance.new({
		"instance_id": item_id,
		"definition_id": definition_id,
		"display_name": String(domain.items.get_definition(definition_id).display_name),
		"quantity": int(row.get("quantity", 1)),
		"relation": relation_result.get("details", {}).get("relation", {}),
		"components": components,
		"revision": int(row.get("revision", 0)),
	})
	if not domain.items.add_item(item):
		return _failure("M7_REPLICA_ITEM_ADD_FAILED", {"item_id": item_id})
	var relation: Dictionary = item.relation
	if Relations.kind_of(relation) == Relations.CONTAINER:
		var container_id := String(relation.get("container_id", ""))
		var container = container_map.get(container_id)
		if container == null:
			return _failure("M7_REPLICA_CONTAINER_MISSING", {"container_id": container_id})
		var assigned: int = container.assign_item(item_id, int(relation.get("slot_index", -1)))
		if container.is_slot_container() and assigned < 0:
			return _failure("M7_REPLICA_SLOT_ASSIGNMENT_FAILED", {"item_id": item_id, "container_id": container_id})
	return _success()


func _relation_for_item(
	row: Dictionary,
	location: Dictionary,
	inventory_map: Dictionary,
	mount_map: Dictionary
) -> Dictionary:
	var item_id := String(row.get("item_id", ""))
	match String(location.get("kind", "")):
		"WORLD":
			var transform := _world_transform(row)
			return _success({"relation": Relations.world(transform, Vector3.ZERO, "scenario/playground/local")})
		"INVENTORY":
			var player_id := String(location.get("player_id", ""))
			if player_id == _local_player_id:
				var inventory: Dictionary = Dictionary(inventory_map.get(player_id, {}))
				var hotbar: Array = Array(inventory.get("hotbar", []))
				var hotbar_index := hotbar.find(item_id)
				if hotbar_index >= 0:
					return _success({"relation": Relations.container(LOCAL_HOTBAR_ID, hotbar_index)})
				var inventory_items: Array = Array(inventory.get("inventory", []))
				var inventory_index := inventory_items.find(item_id)
				if inventory_index < 0:
					inventory_index = 0
				return _success({"relation": Relations.container(LOCAL_INVENTORY_ID, mini(inventory_index, INVENTORY_SIZE - 1))})
			return _success({"relation": Relations.container(_remote_inventory_id(player_id))})
		"CONTAINER":
			var container_id := String(location.get("container_id", ""))
			return _success({"relation": Relations.container(container_id, int(location.get("slot_index", -1)))})
		"MOUNT":
			var mount_id := String(location.get("mount_id", ""))
			var mount: Dictionary = Dictionary(mount_map.get(mount_id, {}))
			var parent_item_id := _replica_item_id(String(mount.get("parent_item_id", "")))
			if parent_item_id.is_empty():
				return _failure("M7_MOUNT_PARENT_REQUIRED", {"mount_id": mount_id})
			return _success({"relation": Relations.attachment(mount_id, parent_item_id, String(mount.get("socket_id", "beacon_socket")))})
	return _failure("M7_UNSUPPORTED_ITEM_LOCATION", {"item_id": item_id, "location": location})


func _add_mount_sockets(domain: Dictionary, mount_map: Dictionary) -> Dictionary:
	for mount_id_value in mount_map.keys():
		var mount_id := String(mount_id_value)
		var mount: Dictionary = mount_map[mount_id]
		var parent_item_id := _replica_item_id(String(mount.get("parent_item_id", "")))
		if parent_item_id.is_empty() or domain.items.get_item(parent_item_id) == null:
			return _failure("M7_MOUNT_PARENT_NOT_FOUND", {"mount_id": mount_id, "parent_item_id": parent_item_id})
		domain.attachments.ensure_socket(
			mount_id,
			parent_item_id,
			String(mount.get("socket_id", "beacon_socket")),
			["beacon"]
		)
	return _success()


func _mount_map(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for mount_value in snapshot.get("mounts", []):
		if mount_value is Dictionary:
			var mount: Dictionary = Dictionary(mount_value).duplicate(true)
			result[String(mount.get("mount_id", ""))] = mount
	return result


func _owned_container_id(item_id: String, container_map: Dictionary) -> String:
	for container_id_value in container_map.keys():
		var container = container_map[container_id_value]
		if container != null and String(container.owner_id) == item_id:
			return String(container_id_value)
	return ""


func _world_transform(row: Dictionary) -> Transform3D:
	var transform_value = row.get("transform", {})
	if transform_value is Dictionary:
		var transform: Dictionary = transform_value
		if bool(PlayableStateCodec.validate_transform_dto(transform).get("success", false)):
			return PlayableStateCodec.transform_from_dto(transform)
	var item_id := String(row.get("item_id", ""))
	if item_id.contains("crate"):
		return Transform3D(Basis.IDENTITY, Vector3(3.0, 0.8, -2.0))
	if item_id.contains("mount"):
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.17, -5.0))
	if item_id.contains("ore"):
		return Transform3D(Basis.IDENTITY, Vector3(-1.5, 0.35, -2.8))
	return Transform3D(Basis.IDENTITY, Vector3(1.2, 0.4, -3.4))


func to_canonical_item_id(replica_item_id: String) -> String:
	return String(_replica_to_canonical.get(replica_item_id, replica_item_id))


func to_replica_item_id(canonical_item_id: String) -> String:
	return _replica_item_id(canonical_item_id)


func _replica_item_id(canonical_item_id: String) -> String:
	var normalized := canonical_item_id.strip_edges()
	if normalized.is_empty():
		return ""
	if _canonical_to_replica.has(normalized):
		return String(_canonical_to_replica[normalized])
	var digest := normalized.sha256_text()
	var uuid := "%s-%s-4%s-8%s-%s" % [
		digest.substr(0, 8),
		digest.substr(8, 4),
		digest.substr(13, 3),
		digest.substr(17, 3),
		digest.substr(20, 12),
	]
	var replica_id := "item/%s" % uuid
	_canonical_to_replica[normalized] = replica_id
	_replica_to_canonical[replica_id] = normalized
	return replica_id


func _definition_id(canonical_id: String) -> String:
	match canonical_id:
		"item/beacon": return "survey_beacon"
		"item/ore": return "lunar_rock"
		"item/crate": return "portable_crate"
		"item/mount-base": return "beacon_mount_base"
		"item/battery": return "battery_pack"
	return ""


func _remote_inventory_id(player_id: String) -> String:
	return "network_remote_inventory_%s" % player_id.replace("/", "_")


func _register_definitions(domain: Dictionary) -> void:
	for data in [
		{"id":"survey_beacon","display_name":"Полевой маяк","max_stack":5,"unit_mass_kg":2.5,"external_volume_l":3.0,"tags":["beacon","mountable","electronic"],"metadata":{"size":[0.32,0.58,0.32],"icon_color":[1.0,0.34,0.05]}},
		{"id":"battery_pack","display_name":"Аккумулятор","max_stack":4,"unit_mass_kg":8.0,"external_volume_l":6.0,"tags":["battery","power"],"metadata":{"size":[0.42,0.28,0.30],"icon_color":[0.20,0.82,0.32]}},
		{"id":"lunar_rock","display_name":"Лунный камень","max_stack":50,"unit_mass_kg":2.0,"external_volume_l":0.8,"tags":["rock","resource"],"metadata":{"size":[0.34,0.26,0.36],"icon_color":[0.65,0.65,0.70]}},
		{"id":"portable_crate","display_name":"Универсальный ящик","max_stack":1,"unit_mass_kg":4.0,"external_volume_l":30.0,"tags":["container"],"metadata":{"size":[0.95,0.65,0.72],"icon_color":[0.62,0.38,0.14],"freeze_world_body":true}},
		{
			"id":"beacon_mount_base","display_name":"Монтажное гнездо маяка","max_stack":10,
			"unit_mass_kg":6.0,"external_volume_l":12.0,"tags":["assembly_root","placeable","mount_socket"],
			"metadata":{"presentation_mode":"EXTERNAL","icon_color":[0.18,0.48,0.60],"debug_grantable":true,"placement":{
				"schema":PlacementContract.SCHEMA,"kind":PlacementContract.KIND_MOUNT_SOCKET,"max_distance_m":8.0,
				"collision_mask":1,"surface_offset_m":0.17,"socket":{"socket_id":"beacon_socket","accepted_tags":["beacon"]}
			}}
		},
	]:
		domain.items.register_definition(Definition.new(data))


func get_report() -> Dictionary:
	return {"schema": SCHEMA, "local_player_id": _local_player_id}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
