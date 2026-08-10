extends SceneTree

const EquipmentDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const ItemGraphEquipmentSource = preload("res://scripts/characters/equipment/item_graph_equipment_source.gd")
const ItemRegistryScript = preload("res://scripts/items/services/item_registry.gd")
const ContainerRegistryScript = preload("res://scripts/containers/container_registry.gd")
const ContainerStateScript = preload("res://scripts/containers/container_state.gd")
const ItemDefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemInstanceScript = preload("res://scripts/items/domain/item_instance.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")

const OWNER_ID := "entity.player.ch9.roundtrip"
const CONTAINER_ID := "container/equipment/ch9-roundtrip"
const HELMET_ID := "item/10000000-0000-4000-8000-000000000001"
const FEET_ID := "item/10000000-0000-4000-8000-000000000002"
const PROFILE_HELMET := "equipment.helmet.mk1"
const PROFILE_FEET := "equipment.layer.feet.peasant"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_item_registry = ItemRegistryScript.new()
	var original_container_registry = ContainerRegistryScript.new()
	original_item_registry.register_definition(ItemDefinitionScript.new({
		"id": "wearable.helmet.roundtrip",
		"display_name": "Helmet",
		"max_stack": 1,
		"tags": ["equipment", "equipment.slot.head"],
	}))
	original_item_registry.register_definition(ItemDefinitionScript.new({
		"id": "wearable.feet.roundtrip",
		"display_name": "Boots",
		"max_stack": 1,
		"tags": ["equipment", "equipment.slot.feet"],
	}))

	var container = ContainerStateScript.new({
		"container_id": CONTAINER_ID,
		"owner_kind": "WORLD_ENTITY",
		"owner_id": OWNER_ID,
		"storage_mode": ContainerStateScript.STORAGE_SLOTS,
		"slot_count": 2,
		"slot_rules": [
			{"accepted_tags": ["equipment.slot.head"]},
			{"accepted_tags": ["equipment.slot.feet"]},
		],
		"revision": 27,
	})
	_assert(original_container_registry.add_container(container), "CH9 roundtrip source container registration failed")

	var helmet = ItemInstanceScript.new({
		"instance_id": HELMET_ID,
		"definition_id": "wearable.helmet.roundtrip",
		"display_name": "Helmet",
		"quantity": 1,
		"relation": Relations.container(CONTAINER_ID, 0),
		"revision": 8,
	})
	var feet = ItemInstanceScript.new({
		"instance_id": FEET_ID,
		"definition_id": "wearable.feet.roundtrip",
		"display_name": "Boots",
		"quantity": 1,
		"relation": Relations.container(CONTAINER_ID, 1),
		"revision": 11,
	})
	_assert(original_item_registry.add_item(helmet), "CH9 roundtrip helmet add failed")
	_assert(original_item_registry.add_item(feet), "CH9 roundtrip footwear add failed")
	_assert(container.assign_item(HELMET_ID, 0) == 0, "CH9 roundtrip helmet slot assignment failed")
	_assert(container.assign_item(FEET_ID, 1) == 1, "CH9 roundtrip footwear slot assignment failed")

	var layout := EquipmentDomain.Layout.new(
		"humanoid.standard",
		["character", "humanoid"],
		["equipment.headwear", "equipment.clothing"],
		["body.head.outer", "body.feet"],
		["body.head", "body.root"],
		[]
	)
	var profiles: Array = [
		EquipmentDomain.Profile.new(PROFILE_HELMET, "wearable.helmet.mk1", "body.head", ["body.head.outer"], [], [], ["equipment.headwear"]),
		EquipmentDomain.Profile.new(PROFILE_FEET, "wearable.layer.feet.peasant", "body.root", ["body.feet"], [], [], ["equipment.clothing"]),
	]
	var mapping := {0: PROFILE_HELMET, 1: PROFILE_FEET}

	var source_before = ItemGraphEquipmentSource.new()
	var before_setup: Dictionary = source_before.setup(OWNER_ID, CONTAINER_ID, layout, original_item_registry, original_container_registry, mapping, profiles)
	_assert(bool(before_setup.get("success", false)), "CH9 roundtrip source-before setup failed: %s" % JSON.stringify(before_setup))
	var snapshot_before: EquipmentDomain.Snapshot = source_before.get_snapshot()
	_assert(snapshot_before.entries().size() == 2, "CH9 roundtrip source-before item count mismatch")
	_assert(snapshot_before.revision == 27, "CH9 roundtrip source-before revision mismatch")

	var bundle := {
		"item_registry": original_item_registry.to_dict(),
		"container_registry": original_container_registry.to_dict(),
		"slot_profile_ids": mapping,
	}
	var encoded := JSON.stringify(bundle, "", true, true)
	var decoded = JSON.parse_string(encoded)
	_assert(decoded is Dictionary, "CH9 roundtrip JSON decode failed")
	if not decoded is Dictionary:
		_finish()
		return
	var decoded_bundle: Dictionary = decoded

	var restored_item_registry = ItemRegistryScript.new()
	var restored_container_registry = ContainerRegistryScript.new()
	var item_load: Dictionary = restored_item_registry.load_dict(Dictionary(decoded_bundle.get("item_registry", {})))
	var container_load: Dictionary = restored_container_registry.load_dict(Dictionary(decoded_bundle.get("container_registry", {})))
	_assert(bool(item_load.get("success", false)), "CH9 roundtrip ItemRegistry load failed: %s" % JSON.stringify(item_load))
	_assert(bool(container_load.get("success", false)), "CH9 roundtrip ContainerRegistry load failed: %s" % JSON.stringify(container_load))

	var decoded_mapping_value = decoded_bundle.get("slot_profile_ids", {})
	_assert(decoded_mapping_value is Dictionary, "CH9 roundtrip slot mapping did not survive as Dictionary")
	var restored_source = ItemGraphEquipmentSource.new()
	var restored_setup: Dictionary = restored_source.setup(
		OWNER_ID,
		CONTAINER_ID,
		layout,
		restored_item_registry,
		restored_container_registry,
		Dictionary(decoded_mapping_value),
		profiles
	)
	_assert(bool(restored_setup.get("success", false)), "CH9 roundtrip restored source setup failed: %s" % JSON.stringify(restored_setup))
	var snapshot_after: EquipmentDomain.Snapshot = restored_source.get_snapshot()
	_assert(snapshot_after.revision == snapshot_before.revision, "CH9 roundtrip equipment revision changed")
	_assert(snapshot_after.state_fingerprint() == snapshot_before.state_fingerprint(), "CH9 roundtrip equipment projection fingerprint changed")
	_assert(snapshot_after.find_item(HELMET_ID) != null, "CH9 roundtrip helmet projection missing")
	_assert(snapshot_after.find_item(FEET_ID) != null, "CH9 roundtrip footwear projection missing")
	_assert(String(snapshot_after.find_item(HELMET_ID).profile_id) == PROFILE_HELMET, "CH9 roundtrip helmet profile drift")
	_assert(String(snapshot_after.find_item(FEET_ID).profile_id) == PROFILE_FEET, "CH9 roundtrip footwear profile drift")

	var restored_container = restored_container_registry.get_container(CONTAINER_ID)
	_assert(restored_container != null, "CH9 roundtrip restored equipment container missing")
	_assert(String(restored_container.owner_id) == OWNER_ID, "CH9 roundtrip equipment owner drift")
	_assert(int(restored_container.revision) == 27, "CH9 roundtrip container revision drift")
	_assert(String(restored_container.get_item_at_slot(0)) == HELMET_ID, "CH9 roundtrip helmet slot drift")
	_assert(String(restored_container.get_item_at_slot(1)) == FEET_ID, "CH9 roundtrip footwear slot drift")
	_assert(Relations.kind_of(restored_item_registry.get_item(HELMET_ID).relation) == Relations.CONTAINER, "CH9 roundtrip helmet relation kind drift")
	_assert(String(restored_item_registry.get_item(HELMET_ID).relation.get("container_id", "")) == CONTAINER_ID, "CH9 roundtrip helmet relation target drift")

	var report: Dictionary = restored_source.create_report()
	_assert(bool(report.get("last_success", false)), "CH9 roundtrip restored source report is not successful")
	_assert(int(report.get("snapshot_revision", -1)) == 27, "CH9 roundtrip restored report revision drift")
	_assert(int(report.get("equipped_item_count", -1)) == 2, "CH9 roundtrip restored report item count drift")
	_assert(String(report.get("state_fingerprint", "")) == snapshot_before.state_fingerprint(), "CH9 roundtrip restored report fingerprint drift")

	var unrestricted_container = ContainerStateScript.new({
		"container_id": "container/equipment/ch9-unrestricted",
		"owner_kind": "WORLD_ENTITY",
		"owner_id": OWNER_ID,
		"storage_mode": ContainerStateScript.STORAGE_SLOTS,
		"slot_count": 1,
		"slot_rules": [{}],
	})
	_assert(restored_container_registry.add_container(unrestricted_container), "CH9 unrestricted fixture container add failed")
	var unrestricted_source = ItemGraphEquipmentSource.new()
	var unrestricted_result: Dictionary = unrestricted_source.setup(
		OWNER_ID,
		"container/equipment/ch9-unrestricted",
		layout,
		restored_item_registry,
		restored_container_registry,
		{0: PROFILE_HELMET},
		profiles
	)
	_assert(not bool(unrestricted_result.get("success", true)), "CH9 accepted an unrestricted canonical equipment slot")
	_assert(String(unrestricted_result.get("code", "")) == ItemGraphEquipmentSource.RESULT_EQUIPMENT_SLOT_UNRESTRICTED, "CH9 unrestricted equipment slot error code drift")

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9 Item Graph equipment source roundtrip: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9 Item Graph equipment source roundtrip: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
