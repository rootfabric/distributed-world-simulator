extends SceneTree

const Service = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_networked_gameplay_service.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_item_graph_replica_adapter.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")
const ItemGraphSource = preload("res://scripts/characters/equipment/item_graph_equipment_source.gd")
const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const GraphPersistence = preload("res://scripts/items/persistence/item_graph_persistence.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = Service.new()
	var setup: Dictionary = service.setup("simulation/ch9-3/replica", 1, 0, {
		"profile": "MULTIPLAYER_CORE",
		"topology_adapter": "LOOPBACK",
		"region_id": "region/ch9-3/replica",
		"playable_sandbox": true,
	})
	_assert(bool(setup.get("success", false)), "CH9.3 replica service setup failed")
	var join_a := service.join("a", "transport-session/ch9-3/replica/a", "operation/ch9-3/replica/join/a")
	var join_b := service.join("b", "transport-session/ch9-3/replica/b", "operation/ch9-3/replica/join/b")
	_assert(bool(join_a.get("success", false)) and bool(join_b.get("success", false)), "CH9.3 replica players failed to join")
	var epoch_a := int(join_a.get("details", {}).get("player", {}).get("ownership_epoch", 0))
	var upper_id := "item/player/a/wearable/upper"
	var feet_id := "item/player/a/wearable/feet"
	for row in [
		[upper_id, EquipmentCatalog.SLOT_UPPER, "upper"],
		[feet_id, EquipmentCatalog.SLOT_FEET, "feet"],
	]:
		var equipped: Dictionary = service.handle_canonical_item_command(
			"a", "transport-session/ch9-3/replica/a", epoch_a,
			"operation/ch9-3/replica/equip/%s" % String(row[2]),
			"equipment.equip",
			{"item_id": String(row[0]), "slot_index": int(row[1])}
		)
		_assert(bool(equipped.get("success", false)), "CH9.3 replica setup equip failed for %s" % String(row[2]))

	var canonical := service.create_canonical_item_graph_snapshot()
	var adapter = Adapter.new()
	var adapter_setup: Dictionary = adapter.setup("b")
	_assert(bool(adapter_setup.get("success", false)), "CH9.3 equipment replica adapter setup failed")
	var converted: Dictionary = adapter.convert(canonical)
	_assert(bool(converted.get("success", false)), "CH9.3 equipment replica conversion failed: %s" % JSON.stringify(converted))
	if not bool(converted.get("success", false)):
		service.shutdown()
		_finish()
		return

	var graph_snapshot: Dictionary = Dictionary(converted.get("details", {}).get("graph_snapshot", {}))
	var domain: Dictionary = Factory.create()
	domain.world_entities.setup({"authority_owner_id": "network-replica-b", "authority_epoch": 1})
	var persistence = GraphPersistence.new()
	persistence.setup(domain, null, "ch9-3-remote-equipment-replica")
	var loaded: Dictionary = persistence.load_snapshot(graph_snapshot)
	_assert(bool(loaded.get("success", false)), "CH9.3 converted production Item Graph failed to load: %s" % JSON.stringify(loaded))
	if not bool(loaded.get("success", false)):
		service.shutdown()
		_finish()
		return

	var equipment_id := EquipmentCatalog.equipment_container_id("a")
	var equipment_container = domain.containers.get_container(equipment_id)
	_assert(equipment_container != null, "CH9.3 remote A equipment container missing from B production replica")
	_assert(equipment_container != null and String(equipment_container.owner_id) == EquipmentCatalog.owner_entity_id("a"), "CH9.3 remote equipment owner identity lost in replica")
	_assert(equipment_container != null and int(equipment_container.slot_count) == EquipmentCatalog.EQUIPMENT_SLOT_COUNT, "CH9.3 remote equipment slot count drift")

	var upper_replica_id := adapter.to_replica_item_id(upper_id)
	var feet_replica_id := adapter.to_replica_item_id(feet_id)
	_assert(not upper_replica_id.is_empty() and not feet_replica_id.is_empty(), "CH9.3 canonical->replica item IDs missing")
	_assert(String(equipment_container.get_item_at_slot(EquipmentCatalog.SLOT_UPPER)) == upper_replica_id, "CH9.3 remote upper slot projection mismatch")
	_assert(String(equipment_container.get_item_at_slot(EquipmentCatalog.SLOT_FEET)) == feet_replica_id, "CH9.3 remote feet slot projection mismatch")
	var upper_item = domain.items.get_item(upper_replica_id)
	var feet_item = domain.items.get_item(feet_replica_id)
	_assert(upper_item != null and String(upper_item.definition_id) == EquipmentCatalog.REPLICA_DEFINITION_UPPER, "CH9.3 upper wearable definition mapping failed")
	_assert(feet_item != null and String(feet_item.definition_id) == EquipmentCatalog.REPLICA_DEFINITION_FEET, "CH9.3 feet wearable definition mapping failed")

	var source = ItemGraphSource.new()
	var source_setup: Dictionary = source.setup(
		EquipmentCatalog.owner_entity_id("a"),
		equipment_id,
		EquipmentCatalog.layout(),
		domain.items,
		domain.containers,
		EquipmentCatalog.slot_profile_ids(),
		EquipmentCatalog.profiles()
	)
	_assert(bool(source_setup.get("success", false)), "CH9.3 CH9.0 source could not bind remote production replica: %s" % JSON.stringify(source_setup))
	var equipment_snapshot = source.get_snapshot()
	_assert(equipment_snapshot.find_item(upper_replica_id) != null, "CH9.3 CH9.0 source lost remote upper item")
	_assert(equipment_snapshot.find_item(feet_replica_id) != null, "CH9.3 CH9.0 source lost remote feet item")
	_assert(equipment_snapshot.entries().size() == 2, "CH9.3 remote production equipment snapshot count mismatch")
	_assert(bool(domain.validator.validate_graph().get("success", false)), "CH9.3 production Item Graph invalid after equipment conversion")

	# Local player B also has an equipment container, but A's items must never be
	# projected into B's character source merely because both live in one replica.
	var local_b_container = domain.containers.get_container(EquipmentCatalog.equipment_container_id("b"))
	_assert(local_b_container != null and local_b_container.item_ids.is_empty(), "CH9.3 remote equipment contaminated local B slots")

	service.shutdown()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.3 multiplayer equipment replica projection: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.3 multiplayer equipment replica projection: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
