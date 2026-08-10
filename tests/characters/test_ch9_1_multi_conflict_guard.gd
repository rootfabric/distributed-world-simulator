extends SceneTree

const EquipmentDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const ItemGraphEquipmentSource = preload("res://scripts/characters/equipment/item_graph_equipment_source.gd")
const EquipmentOperations = preload("res://scripts/characters/equipment/character_equipment_operation_service.gd")
const ItemRegistryScript = preload("res://scripts/items/services/item_registry.gd")
const ContainerRegistryScript = preload("res://scripts/containers/container_registry.gd")
const ContainerStateScript = preload("res://scripts/containers/container_state.gd")
const ItemDefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemInstanceScript = preload("res://scripts/items/domain/item_instance.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const TransferServiceScript = preload("res://scripts/items/services/item_transfer_service.gd")
const RelationshipValidatorScript = preload("res://scripts/items/services/item_relationship_validator.gd")
const MassServiceScript = preload("res://scripts/items/services/item_mass_service.gd")

const OWNER_ID := "entity.player.ch9.1.guard"
const EQUIPMENT_ID := "container/equipment/ch9-1-guard"
const BACKPACK_ID := "container/backpack/ch9-1-guard"

const UPPER_ID := "item/20000000-0000-4000-8000-000000000001"
const LOWER_ID := "item/20000000-0000-4000-8000-000000000002"
const FEET_ID := "item/20000000-0000-4000-8000-000000000003"
const EVA_ID := "item/20000000-0000-4000-8000-000000000004"

const PROFILE_UPPER := "equipment.layer.upper.guard"
const PROFILE_LOWER := "equipment.layer.lower.guard"
const PROFILE_FEET := "equipment.layer.feet.guard"
const PROFILE_EVA := "equipment.eva.guard"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture: Dictionary = _fixture()
	var item_registry = fixture["item_registry"]
	var equipment_container = fixture["equipment_container"]
	var backpack = fixture["backpack"]
	var source: ItemGraphEquipmentSource = fixture["source"]
	var service: CharacterEquipmentOperationService = fixture["service"]
	var validator = fixture["validator"]

	var before_fingerprint := source.get_snapshot().state_fingerprint()
	var before_equipment_revision := int(equipment_container.revision)
	var before_backpack_revision := int(backpack.revision)
	var before_eva_revision := int(item_registry.get_item(EVA_ID).revision)
	var before_eva_relation: Dictionary = Relations.canonicalize(item_registry.get_item(EVA_ID).relation)
	var before_upper_relation: Dictionary = Relations.canonicalize(item_registry.get_item(UPPER_ID).relation)
	var before_lower_relation: Dictionary = Relations.canonicalize(item_registry.get_item(LOWER_ID).relation)
	var before_feet_relation: Dictionary = Relations.canonicalize(item_registry.get_item(FEET_ID).relation)

	var plan: Dictionary = service.plan_equip_from_container(EVA_ID, 3)
	_assert_ok(plan, "CH9.1 EVA multi-conflict plan should be a valid non-mutating plan")
	_assert(String(plan.get("code", "")) == EquipmentOperations.RESULT_MULTI_ITEM_TRANSACTION_REQUIRED, "CH9.1 EVA plan did not declare multi-item transaction requirement")
	_assert(String(plan.get("details", {}).get("mode", "")) == EquipmentOperations.MODE_MULTI_ITEM_TRANSACTION_REQUIRED, "CH9.1 EVA plan mode drift")
	var replacement_ids: Array = Array(plan.get("details", {}).get("replacement_item_ids", []))
	_assert(replacement_ids.size() == 3, "CH9.1 EVA plan should conflict with exactly upper/lower/feet")
	_assert(replacement_ids.has(UPPER_ID), "CH9.1 EVA plan lost upper conflict")
	_assert(replacement_ids.has(LOWER_ID), "CH9.1 EVA plan lost lower conflict")
	_assert(replacement_ids.has(FEET_ID), "CH9.1 EVA plan lost feet conflict")
	_assert(String(plan.get("details", {}).get("physical_target_occupant_item_id", "")).is_empty(), "CH9.1 EVA target slot should be physically empty")
	_assert(not bool(plan.get("details", {}).get("mutation_performed", true)), "CH9.1 planning must not mutate canonical state")

	var strict_result: Dictionary = service.equip_strict(
		EVA_ID,
		3,
		"ch9.1/eva-strict",
		before_eva_revision
	)
	_assert(not bool(strict_result.get("success", true)), "CH9.1 strict equip unexpectedly committed a multi-conflict EVA")
	_assert(String(strict_result.get("code", "")) == EquipmentOperations.RESULT_EQUIPMENT_REPLACEMENT_REQUIRED, "CH9.1 strict multi-conflict rejection code drift")

	var replace_one_result: Dictionary = service.replace_one_from_container(
		EVA_ID,
		3,
		UPPER_ID,
		"ch9.1/eva-replace-one",
		before_eva_revision,
		int(item_registry.get_item(UPPER_ID).revision)
	)
	_assert(not bool(replace_one_result.get("success", true)), "CH9.1 single-swap API unexpectedly accepted multi-conflict EVA")
	_assert(String(replace_one_result.get("code", "")) == EquipmentOperations.RESULT_MULTI_ITEM_TRANSACTION_REQUIRED, "CH9.1 multi-conflict single-swap rejection code drift")

	_assert(source.get_snapshot().state_fingerprint() == before_fingerprint, "CH9.1 rejected EVA operation changed projected equipment state")
	_assert(int(equipment_container.revision) == before_equipment_revision, "CH9.1 rejected EVA operation changed equipment container revision")
	_assert(int(backpack.revision) == before_backpack_revision, "CH9.1 rejected EVA operation changed backpack revision")
	_assert(int(item_registry.get_item(EVA_ID).revision) == before_eva_revision, "CH9.1 rejected EVA operation changed incoming item revision")
	_assert(Relations.canonicalize(item_registry.get_item(EVA_ID).relation) == before_eva_relation, "CH9.1 rejected EVA operation moved incoming item")
	_assert(Relations.canonicalize(item_registry.get_item(UPPER_ID).relation) == before_upper_relation, "CH9.1 rejected EVA operation moved upper item")
	_assert(Relations.canonicalize(item_registry.get_item(LOWER_ID).relation) == before_lower_relation, "CH9.1 rejected EVA operation moved lower item")
	_assert(Relations.canonicalize(item_registry.get_item(FEET_ID).relation) == before_feet_relation, "CH9.1 rejected EVA operation moved feet item")
	_assert(equipment_container.get_item_at_slot(0) == UPPER_ID, "CH9.1 rejected EVA operation damaged upper membership")
	_assert(equipment_container.get_item_at_slot(1) == LOWER_ID, "CH9.1 rejected EVA operation damaged lower membership")
	_assert(equipment_container.get_item_at_slot(2) == FEET_ID, "CH9.1 rejected EVA operation damaged feet membership")
	_assert(String(equipment_container.get_item_at_slot(3)).is_empty(), "CH9.1 rejected EVA operation populated reserved EVA slot")
	_assert(backpack.get_item_at_slot(0) == EVA_ID, "CH9.1 rejected EVA operation removed EVA from backpack")
	_assert(bool(validator.validate_graph().get("success", false)), "CH9.1 Item Graph invalid after rejected multi-conflict operations")

	var report: Dictionary = service.create_report()
	_assert(String(report.get("multi_item_policy", "")) == "FAIL_CLOSED_REQUIRES_EXISTING_MULTI_ITEM_TRANSACTION_PATH", "CH9.1 multi-item policy report drift")
	_assert(not bool(report.get("supports_multi_item_replacement", true)), "CH9.1 must not claim a multi-item transaction implementation")
	_finish()


func _fixture() -> Dictionary:
	var item_registry = ItemRegistryScript.new()
	var container_registry = ContainerRegistryScript.new()
	for definition in [
		_definition("wearable.upper.guard", "equipment.slot.upper"),
		_definition("wearable.lower.guard", "equipment.slot.lower"),
		_definition("wearable.feet.guard", "equipment.slot.feet"),
		_definition("wearable.eva.guard", "equipment.slot.eva"),
	]:
		item_registry.register_definition(definition)

	var equipment_container = ContainerStateScript.new({
		"container_id": EQUIPMENT_ID,
		"owner_kind": "WORLD_ENTITY",
		"owner_id": OWNER_ID,
		"storage_mode": ContainerStateScript.STORAGE_SLOTS,
		"slot_count": 4,
		"slot_rules": [
			{"accepted_tags": ["equipment.slot.upper"]},
			{"accepted_tags": ["equipment.slot.lower"]},
			{"accepted_tags": ["equipment.slot.feet"]},
			{"accepted_tags": ["equipment.slot.eva"]},
		],
		"revision": 30,
	})
	var backpack = ContainerStateScript.new({
		"container_id": BACKPACK_ID,
		"owner_kind": "WORLD_ENTITY",
		"owner_id": OWNER_ID,
		"storage_mode": ContainerStateScript.STORAGE_SLOTS,
		"slot_count": 4,
		"slot_rules": [
			{"accepted_tags": ["equipment"]}, {"accepted_tags": ["equipment"]},
			{"accepted_tags": ["equipment"]}, {"accepted_tags": ["equipment"]},
		],
		"revision": 40,
	})
	_assert(container_registry.add_container(equipment_container), "CH9.1 guard equipment container registration failed")
	_assert(container_registry.add_container(backpack), "CH9.1 guard backpack registration failed")

	_add_item(item_registry, equipment_container, UPPER_ID, "wearable.upper.guard", 0, 1)
	_add_item(item_registry, equipment_container, LOWER_ID, "wearable.lower.guard", 1, 1)
	_add_item(item_registry, equipment_container, FEET_ID, "wearable.feet.guard", 2, 1)
	_add_item(item_registry, backpack, EVA_ID, "wearable.eva.guard", 0, 6)

	var validator = RelationshipValidatorScript.new()
	validator.setup(item_registry, container_registry)
	var mass_service = MassServiceScript.new()
	mass_service.setup(item_registry, container_registry)
	var transfer_service = TransferServiceScript.new()
	transfer_service.setup(item_registry, container_registry, validator, mass_service)
	_assert(bool(validator.validate_graph().get("success", false)), "CH9.1 guard fixture Item Graph invalid")

	var layout := EquipmentDomain.Layout.new(
		"humanoid.standard",
		["character", "biological", "humanoid", "biped"],
		["equipment.clothing", "equipment.eva"],
		["body.torso.outer", "body.arms.outer", "body.legs.outer", "body.feet"],
		["body.root"],
		[]
	)
	var profiles: Array = [
		EquipmentDomain.Profile.new(PROFILE_UPPER, "wearable.layer.upper.guard", "body.root", ["body.torso.outer", "body.arms.outer"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_LOWER, "wearable.layer.lower.guard", "body.root", ["body.legs.outer"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_FEET, "wearable.layer.feet.guard", "body.root", ["body.feet"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_EVA, "wearable.eva.guard", "body.root", ["body.torso.outer", "body.arms.outer", "body.legs.outer", "body.feet"], [], [], ["equipment.eva"]),
	]
	var mapping := {0: PROFILE_UPPER, 1: PROFILE_LOWER, 2: PROFILE_FEET, 3: PROFILE_EVA}
	var source = ItemGraphEquipmentSource.new()
	var source_setup: Dictionary = source.setup(OWNER_ID, EQUIPMENT_ID, layout, item_registry, container_registry, mapping, profiles)
	_assert_ok(source_setup, "CH9.1 guard source setup failed")
	var service = EquipmentOperations.new()
	var service_setup: Dictionary = service.setup(OWNER_ID, EQUIPMENT_ID, source, item_registry, container_registry, transfer_service)
	_assert_ok(service_setup, "CH9.1 guard operation service setup failed")
	return {
		"item_registry": item_registry,
		"equipment_container": equipment_container,
		"backpack": backpack,
		"validator": validator,
		"source": source,
		"service": service,
	}


func _definition(definition_id: String, slot_tag: String):
	return ItemDefinitionScript.new({
		"id": definition_id,
		"display_name": definition_id,
		"max_stack": 1,
		"unit_mass_kg": 2.0,
		"external_volume_l": 2.0,
		"tags": ["equipment", slot_tag],
		"metadata": {},
	})


func _add_item(item_registry, container, item_id: String, definition_id: String, slot_index: int, revision: int) -> void:
	var item = ItemInstanceScript.new({
		"instance_id": item_id,
		"definition_id": definition_id,
		"display_name": definition_id,
		"quantity": 1,
		"relation": Relations.container(container.container_id, slot_index),
		"revision": revision,
	})
	_assert(item_registry.add_item(item), "CH9.1 guard add item failed: %s" % item_id)
	_assert(container.assign_item(item_id, slot_index) == slot_index, "CH9.1 guard slot assignment failed: %s" % item_id)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, JSON.stringify(result)])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.1 multi-conflict equipment guard: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.1 multi-conflict equipment guard: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
