class_name Ch9EquipmentItemGraphReplicaAdapter
extends "res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter.gd"

const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")


func _build_containers(domain: Dictionary, snapshot: Dictionary) -> Dictionary:
	# The accepted M7 adapter treats all canonical containers as item-owned storage.
	# Filter character-equipment rows before calling it, then add them as ACTOR
	# slot containers without changing the canonical item relation model.
	var filtered := snapshot.duplicate(true)
	var normal_containers: Array = []
	var equipment_containers: Array = []
	for value in snapshot.get("containers", []):
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		if String(row.get("container_kind", "")) == EquipmentCatalog.EQUIPMENT_CONTAINER_KIND:
			equipment_containers.append(row.duplicate(true))
		else:
			normal_containers.append(row.duplicate(true))
	filtered["containers"] = normal_containers
	var result: Dictionary = super._build_containers(domain, filtered)
	for row_value in equipment_containers:
		var row: Dictionary = row_value
		var container_id := String(row.get("container_id", ""))
		var owner_entity_id := String(row.get("owner_entity_id", ""))
		if container_id.is_empty() or owner_entity_id.is_empty():
			continue
		var slot_rules: Array = []
		for slot_index in range(EquipmentCatalog.EQUIPMENT_SLOT_COUNT):
			slot_rules.append({"accepted_tags": [EquipmentCatalog.slot_tag(slot_index)]})
		var state := ContainerState.new({
			"container_id": container_id,
			"owner_kind": "ACTOR",
			"owner_id": owner_entity_id,
			"storage_mode": ContainerState.STORAGE_SLOTS,
			"slot_count": EquipmentCatalog.EQUIPMENT_SLOT_COUNT,
			"slot_rules": slot_rules,
			"maximum_mass_kg": 100.0,
			"maximum_volume_l": 180.0,
			"allow_nested_containers": false,
		})
		domain.containers.add_container(state)
		result[container_id] = state
	return result


func _definition_id(canonical_id: String) -> String:
	var wearable_id := EquipmentCatalog.replica_definition_id(canonical_id)
	if not wearable_id.is_empty():
		return wearable_id
	return super._definition_id(canonical_id)


func _register_definitions(domain: Dictionary) -> void:
	super._register_definitions(domain)
	for data in [
		{"id": EquipmentCatalog.REPLICA_DEFINITION_HELMET, "display_name": "Helmet", "tag": EquipmentCatalog.slot_tag(EquipmentCatalog.SLOT_HEAD), "mass": 1.6, "volume": 4.0},
		{"id": EquipmentCatalog.REPLICA_DEFINITION_BACKPACK, "display_name": "Backpack", "tag": EquipmentCatalog.slot_tag(EquipmentCatalog.SLOT_BACK), "mass": 2.4, "volume": 18.0},
		{"id": EquipmentCatalog.REPLICA_DEFINITION_UPPER, "display_name": "Peasant Upper", "tag": EquipmentCatalog.slot_tag(EquipmentCatalog.SLOT_UPPER), "mass": 1.1, "volume": 5.0},
		{"id": EquipmentCatalog.REPLICA_DEFINITION_LOWER, "display_name": "Peasant Trousers", "tag": EquipmentCatalog.slot_tag(EquipmentCatalog.SLOT_LOWER), "mass": 1.0, "volume": 4.5},
		{"id": EquipmentCatalog.REPLICA_DEFINITION_FEET, "display_name": "Peasant Boots", "tag": EquipmentCatalog.slot_tag(EquipmentCatalog.SLOT_FEET), "mass": 1.4, "volume": 5.5},
	]:
		domain.items.register_definition(Definition.new({
			"id": String(data["id"]),
			"display_name": String(data["display_name"]),
			"max_stack": 1,
			"unit_mass_kg": float(data["mass"]),
			"external_volume_l": float(data["volume"]),
			"tags": ["equipment", String(data["tag"])],
			"metadata": {},
		}))
