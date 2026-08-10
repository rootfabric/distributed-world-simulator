extends SceneTree

const EquipmentDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const ItemGraphEquipmentSource = preload("res://scripts/characters/equipment/item_graph_equipment_source.gd")
const LabEquipmentSource = preload("res://scripts/characters/equipment/lab_equipment_source.gd")
const ItemRegistryScript = preload("res://scripts/items/services/item_registry.gd")
const ContainerRegistryScript = preload("res://scripts/containers/container_registry.gd")
const ContainerStateScript = preload("res://scripts/containers/container_state.gd")
const ItemDefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemInstanceScript = preload("res://scripts/items/domain/item_instance.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")

const OWNER_ID := "entity.player.ch9.001"
const EQUIPMENT_CONTAINER_ID := "container/equipment/ch9-player-001"

const HELMET_ID := "item/00000000-0000-4000-8000-000000000001"
const BACKPACK_ID := "item/00000000-0000-4000-8000-000000000002"
const UPPER_ID := "item/00000000-0000-4000-8000-000000000003"
const LOWER_ID := "item/00000000-0000-4000-8000-000000000004"
const FEET_ID := "item/00000000-0000-4000-8000-000000000005"

const PROFILE_HELMET := "equipment.helmet.mk1"
const PROFILE_BACKPACK := "equipment.backpack.mk1"
const PROFILE_UPPER := "equipment.layer.upper.peasant"
const PROFILE_LOWER := "equipment.layer.lower.peasant"
const PROFILE_FEET := "equipment.layer.feet.peasant"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture: Dictionary = _create_fixture()
	var item_registry = fixture["item_registry"]
	var container_registry = fixture["container_registry"]
	var equipment_container = fixture["equipment_container"]
	var layout: EquipmentDomain.Layout = fixture["layout"]
	var profiles: Array = fixture["profiles"]
	var mapping: Dictionary = fixture["mapping"]

	var source = ItemGraphEquipmentSource.new()
	var setup_result: Dictionary = source.setup(
		OWNER_ID,
		EQUIPMENT_CONTAINER_ID,
		layout,
		item_registry,
		container_registry,
		mapping,
		profiles
	)
	_assert(bool(setup_result.get("success", false)), "CH9 Item Graph source setup failed: %s" % JSON.stringify(setup_result))
	_assert(source is EquipmentDomain.Source, "CH9 Item Graph source does not implement CharacterEquipmentDomain.Source")
	_assert(not source.has_method("equip"), "CH9 Item Graph source must not own equip mutation")
	_assert(not source.has_method("unequip"), "CH9 Item Graph source must not own unequip mutation")

	var snapshot: EquipmentDomain.Snapshot = source.get_snapshot()
	_assert(snapshot.owner_entity_id == OWNER_ID, "CH9 projected owner mismatch")
	_assert(snapshot.layout_id == layout.layout_id, "CH9 projected layout mismatch")
	_assert(snapshot.revision == int(equipment_container.revision), "CH9 snapshot revision must follow canonical equipment container revision")
	_assert(snapshot.entries().size() == 5, "CH9 expected five projected equipment entries")
	for item_id in [HELMET_ID, BACKPACK_ID, UPPER_ID, LOWER_ID, FEET_ID]:
		_assert(snapshot.find_item(item_id) != null, "CH9 projected item missing: %s" % item_id)

	_assert(String(snapshot.find_item(HELMET_ID).profile_id) == PROFILE_HELMET, "CH9 helmet profile projection mismatch")
	_assert(String(snapshot.find_item(BACKPACK_ID).profile_id) == PROFILE_BACKPACK, "CH9 backpack profile projection mismatch")
	_assert(String(snapshot.find_item(UPPER_ID).profile_id) == PROFILE_UPPER, "CH9 upper profile projection mismatch")
	_assert(String(snapshot.find_item(LOWER_ID).profile_id) == PROFILE_LOWER, "CH9 lower profile projection mismatch")
	_assert(String(snapshot.find_item(FEET_ID).profile_id) == PROFILE_FEET, "CH9 feet profile projection mismatch")

	var lab_source = LabEquipmentSource.new()
	var lab_setup: Dictionary = lab_source.setup(OWNER_ID, layout, profiles)
	_assert(bool(lab_setup.get("success", false)), "CH9 comparison lab source setup failed")
	for pair in [
		[HELMET_ID, PROFILE_HELMET],
		[BACKPACK_ID, PROFILE_BACKPACK],
		[UPPER_ID, PROFILE_UPPER],
		[LOWER_ID, PROFILE_LOWER],
		[FEET_ID, PROFILE_FEET],
	]:
		var equip_result: Dictionary = lab_source.equip(String(pair[0]), String(pair[1]))
		_assert(bool(equip_result.get("success", false)), "CH9 comparison lab equip failed: %s" % String(pair[0]))
	_assert(snapshot.state_fingerprint() == lab_source.get_snapshot().state_fingerprint(), "CH9 Item Graph source is not snapshot-compatible with accepted equipment source contract")

	var initial_revision := snapshot.revision
	var feet_item = item_registry.get_item(FEET_ID)
	_assert(equipment_container.remove_item(FEET_ID), "CH9 failed to remove footwear from canonical equipment container fixture")
	feet_item.set_relation(Relations.world_entity(OWNER_ID))
	equipment_container.revision += 1
	var removal_result: Dictionary = source.refresh()
	_assert(bool(removal_result.get("success", false)), "CH9 source refresh after canonical removal failed")
	var without_feet: EquipmentDomain.Snapshot = source.get_snapshot()
	_assert(without_feet.find_item(FEET_ID) == null, "CH9 source retained item removed from canonical equipment container")
	_assert(without_feet.entries().size() == 4, "CH9 source removal projection count mismatch")
	_assert(without_feet.revision > initial_revision, "CH9 source did not advance with equipment container revision")

	feet_item.set_relation(Relations.container(EQUIPMENT_CONTAINER_ID, 4))
	_assert(equipment_container.assign_item(FEET_ID, 4) == 4, "CH9 failed to restore footwear to equipment slot")
	equipment_container.revision += 1
	var restore_result: Dictionary = source.refresh()
	_assert(bool(restore_result.get("success", false)), "CH9 source refresh after canonical restore failed")
	_assert(source.get_snapshot().find_item(FEET_ID) != null, "CH9 source did not restore canonical footwear projection")

	var lower_item = item_registry.get_item(LOWER_ID)
	var valid_snapshot_before_failure: EquipmentDomain.Snapshot = source.get_snapshot()
	lower_item.set_relation(Relations.container(EQUIPMENT_CONTAINER_ID, 4))
	var mismatch_result: Dictionary = source.refresh()
	_assert(not bool(mismatch_result.get("success", true)), "CH9 source accepted slot/relation mismatch")
	_assert(String(mismatch_result.get("code", "")) == ItemGraphEquipmentSource.RESULT_EQUIPMENT_ITEM_RELATION_MISMATCH, "CH9 relation mismatch error code drift")
	_assert(source.get_snapshot().state_fingerprint() == valid_snapshot_before_failure.state_fingerprint(), "CH9 failed refresh must preserve last valid presentation snapshot")
	lower_item.set_relation(Relations.container(EQUIPMENT_CONTAINER_ID, 3))
	_assert(bool(source.refresh().get("success", false)), "CH9 source did not recover after relation repair")

	var lower_definition = item_registry.get_definition(lower_item.definition_id)
	var saved_tags: PackedStringArray = lower_definition.tags.duplicate()
	lower_definition.tags = PackedStringArray(["equipment.slot.wrong"])
	var slot_reject_result: Dictionary = source.refresh()
	_assert(not bool(slot_reject_result.get("success", true)), "CH9 source accepted definition rejected by canonical equipment slot")
	_assert(String(slot_reject_result.get("code", "")) == ItemGraphEquipmentSource.RESULT_EQUIPMENT_ITEM_REJECTED_BY_SLOT, "CH9 slot rejection error code drift")
	lower_definition.tags = saved_tags
	_assert(bool(source.refresh().get("success", false)), "CH9 source did not recover after slot definition repair")

	lower_item.quantity = 2
	var quantity_result: Dictionary = source.refresh()
	_assert(not bool(quantity_result.get("success", true)), "CH9 source accepted stacked equipped item")
	_assert(String(quantity_result.get("code", "")) == ItemGraphEquipmentSource.RESULT_EQUIPMENT_ITEM_QUANTITY_INVALID, "CH9 quantity rejection error code drift")
	lower_item.quantity = 1
	_assert(bool(source.refresh().get("success", false)), "CH9 source did not recover after quantity repair")

	var wrong_owner_source = ItemGraphEquipmentSource.new()
	var wrong_owner_result: Dictionary = wrong_owner_source.setup(
		"entity.player.other",
		EQUIPMENT_CONTAINER_ID,
		layout,
		item_registry,
		container_registry,
		mapping,
		profiles
	)
	_assert(not bool(wrong_owner_result.get("success", true)), "CH9 source accepted equipment container owned by another entity")
	_assert(String(wrong_owner_result.get("code", "")) == ItemGraphEquipmentSource.RESULT_EQUIPMENT_CONTAINER_OWNER_MISMATCH, "CH9 owner mismatch error code drift")

	var report: Dictionary = source.create_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.item_graph_equipment_source_report.v1", "CH9 source report schema drift")
	_assert(bool(report.get("read_only", false)), "CH9 source report must declare read-only projection")
	_assert(not bool(report.get("owns_item_mutation", true)), "CH9 source must not own Item Graph mutation")
	_assert(not bool(report.get("owns_network_state", true)), "CH9 source must not own network state")
	_assert(not bool(report.get("owns_persistence", true)), "CH9 source must not own persistence")
	_assert(String(report.get("canonical_source", "")) == "ITEM_REGISTRY_PLUS_EQUIPMENT_CONTAINER", "CH9 canonical source report drift")

	_finish()


func _create_fixture() -> Dictionary:
	var item_registry = ItemRegistryScript.new()
	var container_registry = ContainerRegistryScript.new()
	var definitions := [
		_definition("wearable.helmet.test", "equipment.slot.head"),
		_definition("wearable.backpack.test", "equipment.slot.back"),
		_definition("wearable.upper.test", "equipment.slot.upper"),
		_definition("wearable.lower.test", "equipment.slot.lower"),
		_definition("wearable.feet.test", "equipment.slot.feet"),
	]
	for definition in definitions:
		item_registry.register_definition(definition)

	var equipment_container = ContainerStateScript.new({
		"container_id": EQUIPMENT_CONTAINER_ID,
		"owner_kind": "WORLD_ENTITY",
		"owner_id": OWNER_ID,
		"storage_mode": ContainerStateScript.STORAGE_SLOTS,
		"slot_count": 5,
		"slot_rules": [
			{"accepted_tags": ["equipment.slot.head"]},
			{"accepted_tags": ["equipment.slot.back"]},
			{"accepted_tags": ["equipment.slot.upper"]},
			{"accepted_tags": ["equipment.slot.lower"]},
			{"accepted_tags": ["equipment.slot.feet"]},
		],
		"revision": 12,
	})
	_assert(container_registry.add_container(equipment_container), "CH9 fixture equipment container registration failed")

	var item_rows := [
		[HELMET_ID, "wearable.helmet.test", 0],
		[BACKPACK_ID, "wearable.backpack.test", 1],
		[UPPER_ID, "wearable.upper.test", 2],
		[LOWER_ID, "wearable.lower.test", 3],
		[FEET_ID, "wearable.feet.test", 4],
	]
	for row in item_rows:
		var item = ItemInstanceScript.new({
			"instance_id": String(row[0]),
			"definition_id": String(row[1]),
			"display_name": String(row[1]),
			"quantity": 1,
			"relation": Relations.container(EQUIPMENT_CONTAINER_ID, int(row[2])),
			"revision": 3,
		})
		_assert(item_registry.add_item(item), "CH9 fixture item registry add failed: %s" % String(row[0]))
		_assert(equipment_container.assign_item(String(row[0]), int(row[2])) == int(row[2]), "CH9 fixture slot assignment failed: %s" % String(row[0]))

	var layout := EquipmentDomain.Layout.new(
		"humanoid.standard",
		["character", "biological", "humanoid", "biped"],
		["equipment.headwear", "equipment.backpack", "equipment.clothing"],
		[
			"body.head.outer",
			"body.torso.outer", "body.arms.outer",
			"body.legs.outer", "body.feet",
			"gear.back",
		],
		["body.head", "body.root", "gear.back"],
		[]
	)
	var profiles: Array = [
		EquipmentDomain.Profile.new(PROFILE_HELMET, "wearable.helmet.mk1", "body.head", ["body.head.outer"], [], [], ["equipment.headwear"]),
		EquipmentDomain.Profile.new(PROFILE_BACKPACK, "wearable.backpack.mk1", "gear.back", ["gear.back"], [], [], ["equipment.backpack"]),
		EquipmentDomain.Profile.new(PROFILE_UPPER, "wearable.layer.upper.peasant", "body.root", ["body.torso.outer", "body.arms.outer"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_LOWER, "wearable.layer.lower.peasant", "body.root", ["body.legs.outer"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_FEET, "wearable.layer.feet.peasant", "body.root", ["body.feet"], [], [], ["equipment.clothing"]),
	]
	var mapping := {
		0: PROFILE_HELMET,
		1: PROFILE_BACKPACK,
		2: PROFILE_UPPER,
		3: PROFILE_LOWER,
		4: PROFILE_FEET,
	}
	return {
		"item_registry": item_registry,
		"container_registry": container_registry,
		"equipment_container": equipment_container,
		"layout": layout,
		"profiles": profiles,
		"mapping": mapping,
	}


func _definition(definition_id: String, slot_tag: String):
	return ItemDefinitionScript.new({
		"id": definition_id,
		"display_name": definition_id,
		"max_stack": 1,
		"unit_mass_kg": 1.0,
		"external_volume_l": 1.0,
		"tags": ["equipment", slot_tag],
		"metadata": {},
	})


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9 Item Graph equipment source: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9 Item Graph equipment source: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
