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

const OWNER_ID := "entity.player.ch9.1.001"
const EQUIPMENT_ID := "container/equipment/ch9-1-player-001"
const BACKPACK_ID := "container/backpack/ch9-1-player-001"

const UPPER_A := "item/10000000-0000-4000-8000-000000000001"
const UPPER_B := "item/10000000-0000-4000-8000-000000000002"
const LOWER_OLD := "item/10000000-0000-4000-8000-000000000003"
const LOWER_NEW := "item/10000000-0000-4000-8000-000000000004"
const LOWER_THIRD := "item/10000000-0000-4000-8000-000000000005"
const FEET_A := "item/10000000-0000-4000-8000-000000000006"

const PROFILE_UPPER := "equipment.layer.upper.peasant"
const PROFILE_LOWER := "equipment.layer.lower.peasant"
const PROFILE_FEET := "equipment.layer.feet.peasant"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture: Dictionary = _fixture()
	var item_registry = fixture["item_registry"]
	var container_registry = fixture["container_registry"]
	var equipment_container = fixture["equipment_container"]
	var backpack = fixture["backpack"]
	var source: ItemGraphEquipmentSource = fixture["source"]
	var service: CharacterEquipmentOperationService = fixture["service"]

	_assert(source.get_snapshot().find_item(LOWER_OLD) != null, "CH9.1 initial lower item is not projected")
	_assert(source.get_snapshot().entries().size() == 1, "CH9.1 initial equipment count drift")

	var upper_plan: Dictionary = service.plan_equip_from_container(UPPER_A, 0)
	_assert_ok(upper_plan, "CH9.1 upper plan failed")
	_assert(String(upper_plan.get("details", {}).get("mode", "")) == EquipmentOperations.MODE_MOVE, "CH9.1 empty slot should plan MOVE")
	_assert(Array(upper_plan.get("details", {}).get("replacement_item_ids", [])).is_empty(), "CH9.1 empty upper slot unexpectedly requires replacement")
	var upper_before_revision := int(item_registry.get_item(UPPER_A).revision)
	var equipment_revision_before_upper := int(equipment_container.revision)
	var backpack_revision_before_upper := int(backpack.revision)
	var equip_upper: Dictionary = service.equip_strict(UPPER_A, 0, "ch9.1/equip-upper", upper_before_revision)
	_assert_ok(equip_upper, "CH9.1 strict upper equip failed")
	_assert(_is_in_slot(item_registry, UPPER_A, EQUIPMENT_ID, 0), "CH9.1 upper canonical relation did not move to equipment slot")
	_assert(equipment_container.get_item_at_slot(0) == UPPER_A, "CH9.1 equipment membership did not receive upper item")
	_assert(not backpack.item_ids.has(UPPER_A), "CH9.1 backpack retained equipped upper item")
	_assert(source.get_snapshot().find_item(UPPER_A) != null, "CH9.1 source did not project equipped upper item")
	_assert(int(equipment_container.revision) == equipment_revision_before_upper + 1, "CH9.1 equipment container revision did not advance once")
	_assert(int(backpack.revision) == backpack_revision_before_upper + 1, "CH9.1 backpack revision did not advance once")
	_assert(int(item_registry.get_item(UPPER_A).revision) == upper_before_revision + 1, "CH9.1 equipped item revision did not advance once")

	var replay_upper: Dictionary = service.equip_strict(UPPER_A, 0, "ch9.1/equip-upper", upper_before_revision)
	_assert_ok(replay_upper, "CH9.1 exact strict-equip replay failed")
	_assert(_is_in_slot(item_registry, UPPER_A, EQUIPMENT_ID, 0), "CH9.1 strict-equip replay changed desired state")
	_assert(int(item_registry.get_item(UPPER_A).revision) == upper_before_revision + 1, "CH9.1 strict-equip replay mutated item revision")
	_assert(int(equipment_container.revision) == equipment_revision_before_upper + 1, "CH9.1 strict-equip replay mutated equipment revision")

	var upper_equipped_revision := int(item_registry.get_item(UPPER_A).revision)
	var unequip_upper: Dictionary = service.unequip_to_container(UPPER_A, BACKPACK_ID, 0, "ch9.1/unequip-upper", upper_equipped_revision)
	_assert_ok(unequip_upper, "CH9.1 unequip upper failed")
	_assert(_is_in_slot(item_registry, UPPER_A, BACKPACK_ID, 0), "CH9.1 unequipped upper did not return to requested backpack slot")
	_assert(source.get_snapshot().find_item(UPPER_A) == null, "CH9.1 source retained unequipped upper")
	var upper_after_unequip_revision := int(item_registry.get_item(UPPER_A).revision)
	var replay_unequip: Dictionary = service.unequip_to_container(UPPER_A, BACKPACK_ID, 0, "ch9.1/unequip-upper", upper_equipped_revision)
	_assert_ok(replay_unequip, "CH9.1 desired-state unequip replay failed")
	_assert(bool(replay_unequip.get("details", {}).get("no_change", false)), "CH9.1 unequip replay should report no_change")
	_assert(int(item_registry.get_item(UPPER_A).revision) == upper_after_unequip_revision, "CH9.1 unequip replay mutated revision")

	var replace_plan: Dictionary = service.plan_equip_from_container(LOWER_NEW, 1)
	_assert_ok(replace_plan, "CH9.1 lower replacement plan failed")
	_assert(String(replace_plan.get("details", {}).get("mode", "")) == EquipmentOperations.MODE_SWAP, "CH9.1 occupied compatible lower slot should plan SWAP")
	_assert(String(replace_plan.get("details", {}).get("replacement_item_id", "")) == LOWER_OLD, "CH9.1 replacement plan identified wrong old lower item")
	var lower_new_before_relation: Dictionary = Relations.canonicalize(item_registry.get_item(LOWER_NEW).relation)
	var lower_new_before_revision := int(item_registry.get_item(LOWER_NEW).revision)
	var lower_old_before_revision := int(item_registry.get_item(LOWER_OLD).revision)
	var replace_lower: Dictionary = service.replace_one_from_container(
		LOWER_NEW,
		1,
		LOWER_OLD,
		"ch9.1/replace-lower",
		lower_new_before_revision,
		lower_old_before_revision
	)
	_assert_ok(replace_lower, "CH9.1 atomic lower replacement failed")
	_assert(_is_in_slot(item_registry, LOWER_NEW, EQUIPMENT_ID, 1), "CH9.1 new lower item did not occupy equipment slot")
	_assert(Relations.canonicalize(item_registry.get_item(LOWER_OLD).relation) == lower_new_before_relation, "CH9.1 replaced lower item did not atomically move to incoming item's old relation")
	_assert(backpack.get_item_at_slot(1) == LOWER_OLD, "CH9.1 backpack did not receive replaced lower item in incoming slot")
	_assert(source.get_snapshot().find_item(LOWER_NEW) != null, "CH9.1 source did not project replacement lower item")
	_assert(source.get_snapshot().find_item(LOWER_OLD) == null, "CH9.1 source retained replaced lower item")
	_assert(int(item_registry.get_item(LOWER_NEW).revision) == lower_new_before_revision + 1, "CH9.1 incoming replacement item revision drift")
	_assert(int(item_registry.get_item(LOWER_OLD).revision) == lower_old_before_revision + 1, "CH9.1 replaced item revision drift")

	var replace_replay_incoming_revision := int(item_registry.get_item(LOWER_NEW).revision)
	var replace_replay_old_revision := int(item_registry.get_item(LOWER_OLD).revision)
	var replay_replace: Dictionary = service.replace_one_from_container(
		LOWER_NEW,
		1,
		LOWER_OLD,
		"ch9.1/replace-lower",
		lower_new_before_revision,
		lower_old_before_revision
	)
	_assert_ok(replay_replace, "CH9.1 desired-state replacement replay failed")
	_assert(bool(replay_replace.get("details", {}).get("no_change", false)), "CH9.1 replacement replay should be no_change")
	_assert(int(item_registry.get_item(LOWER_NEW).revision) == replace_replay_incoming_revision, "CH9.1 replacement replay mutated incoming revision")
	_assert(int(item_registry.get_item(LOWER_OLD).revision) == replace_replay_old_revision, "CH9.1 replacement replay mutated old item revision")
	_assert(_is_in_slot(item_registry, LOWER_NEW, EQUIPMENT_ID, 1), "CH9.1 replacement replay swapped items back")

	var third_before_relation: Dictionary = Relations.canonicalize(item_registry.get_item(LOWER_THIRD).relation)
	var current_lower_before_relation: Dictionary = Relations.canonicalize(item_registry.get_item(LOWER_NEW).relation)
	var wrong_replace: Dictionary = service.replace_one_from_container(
		LOWER_THIRD,
		1,
		LOWER_OLD,
		"ch9.1/wrong-replaced-id",
		int(item_registry.get_item(LOWER_THIRD).revision),
		int(item_registry.get_item(LOWER_OLD).revision)
	)
	_assert(not bool(wrong_replace.get("success", true)), "CH9.1 accepted stale replaced_item_id")
	_assert(String(wrong_replace.get("code", "")) == EquipmentOperations.RESULT_REPLACEMENT_TARGET_MISMATCH, "CH9.1 stale replacement target error code drift")
	_assert(Relations.canonicalize(item_registry.get_item(LOWER_THIRD).relation) == third_before_relation, "CH9.1 stale replacement request moved incoming item")
	_assert(Relations.canonicalize(item_registry.get_item(LOWER_NEW).relation) == current_lower_before_relation, "CH9.1 stale replacement request changed equipped item")

	var upper_b_before_relation: Dictionary = Relations.canonicalize(item_registry.get_item(UPPER_B).relation)
	var stale_revision_result: Dictionary = service.equip_strict(UPPER_B, 0, "ch9.1/stale-upper", 999)
	_assert(not bool(stale_revision_result.get("success", true)), "CH9.1 accepted stale item revision")
	_assert(String(stale_revision_result.get("code", "")) == EquipmentOperations.RESULT_TRANSFER_REJECTED, "CH9.1 stale revision should be rejected by canonical transfer service")
	_assert(String(stale_revision_result.get("details", {}).get("transfer_error_code", "")) == "REVISION_CONFLICT", "CH9.1 stale revision lost canonical transfer error")
	_assert(Relations.canonicalize(item_registry.get_item(UPPER_B).relation) == upper_b_before_relation, "CH9.1 stale revision mutated Item Graph")

	var wrong_slot_plan: Dictionary = service.plan_equip_from_container(UPPER_B, 2)
	_assert(not bool(wrong_slot_plan.get("success", true)), "CH9.1 allowed upper item in footwear slot")
	_assert(String(wrong_slot_plan.get("code", "")) == ItemGraphEquipmentSource.RESULT_EQUIPMENT_ITEM_REJECTED_BY_SLOT, "CH9.1 wrong physical slot rejection code drift")
	_assert(Relations.canonicalize(item_registry.get_item(UPPER_B).relation) == upper_b_before_relation, "CH9.1 planning wrong slot mutated Item Graph")

	var feet_item = item_registry.get_item(FEET_A)
	feet_item.quantity = 2
	var quantity_plan: Dictionary = service.plan_equip_from_container(FEET_A, 2)
	_assert(not bool(quantity_plan.get("success", true)), "CH9.1 allowed stacked equipped candidate")
	_assert(String(quantity_plan.get("code", "")) == ItemGraphEquipmentSource.RESULT_EQUIPMENT_ITEM_QUANTITY_INVALID, "CH9.1 stacked candidate rejection code drift")
	feet_item.quantity = 1

	var report: Dictionary = service.create_report()
	_assert(String(report.get("mutation_owner", "")) == "ITEM_TRANSFER_SERVICE", "CH9.1 operation service claimed wrong mutation owner")
	_assert(not bool(report.get("owns_operation_ledger", true)), "CH9.1 operation facade must not own a second operation ledger")
	_assert(not bool(report.get("owns_item_registry", true)), "CH9.1 operation facade must not own ItemRegistry")
	_assert(not bool(report.get("owns_container_registry", true)), "CH9.1 operation facade must not own ContainerRegistry")
	_assert(bool(report.get("supports_single_atomic_swap", false)), "CH9.1 report lost atomic single-swap support")
	_assert(not bool(report.get("supports_multi_item_replacement", true)), "CH9.1 must not claim unsupported multi-item atomicity")

	var graph_result: Dictionary = fixture["validator"].validate_graph()
	_assert(bool(graph_result.get("success", false)), "CH9.1 final Item Graph validation failed: %s" % JSON.stringify(graph_result))
	_finish()


func _fixture() -> Dictionary:
	var item_registry = ItemRegistryScript.new()
	var container_registry = ContainerRegistryScript.new()
	for definition in [
		_definition("wearable.upper.test", "equipment.slot.upper"),
		_definition("wearable.lower.test", "equipment.slot.lower"),
		_definition("wearable.feet.test", "equipment.slot.feet"),
	]:
		item_registry.register_definition(definition)

	var equipment_container = ContainerStateScript.new({
		"container_id": EQUIPMENT_ID,
		"owner_kind": "WORLD_ENTITY",
		"owner_id": OWNER_ID,
		"storage_mode": ContainerStateScript.STORAGE_SLOTS,
		"slot_count": 3,
		"slot_rules": [
			{"accepted_tags": ["equipment.slot.upper"]},
			{"accepted_tags": ["equipment.slot.lower"]},
			{"accepted_tags": ["equipment.slot.feet"]},
		],
		"revision": 10,
	})
	var backpack = ContainerStateScript.new({
		"container_id": BACKPACK_ID,
		"owner_kind": "WORLD_ENTITY",
		"owner_id": OWNER_ID,
		"storage_mode": ContainerStateScript.STORAGE_SLOTS,
		"slot_count": 8,
		"slot_rules": [
			{"accepted_tags": ["equipment"]}, {"accepted_tags": ["equipment"]},
			{"accepted_tags": ["equipment"]}, {"accepted_tags": ["equipment"]},
			{"accepted_tags": ["equipment"]}, {"accepted_tags": ["equipment"]},
			{"accepted_tags": ["equipment"]}, {"accepted_tags": ["equipment"]},
		],
		"revision": 20,
	})
	_assert(container_registry.add_container(equipment_container), "CH9.1 equipment container registration failed")
	_assert(container_registry.add_container(backpack), "CH9.1 backpack registration failed")

	_add_item(item_registry, backpack, UPPER_A, "wearable.upper.test", 0, 2)
	_add_item(item_registry, backpack, LOWER_NEW, "wearable.lower.test", 1, 4)
	_add_item(item_registry, backpack, LOWER_THIRD, "wearable.lower.test", 2, 1)
	_add_item(item_registry, backpack, UPPER_B, "wearable.upper.test", 3, 7)
	_add_item(item_registry, backpack, FEET_A, "wearable.feet.test", 4, 2)
	_add_item(item_registry, equipment_container, LOWER_OLD, "wearable.lower.test", 1, 5)

	var validator = RelationshipValidatorScript.new()
	validator.setup(item_registry, container_registry)
	var mass_service = MassServiceScript.new()
	mass_service.setup(item_registry, container_registry)
	var transfer_service = TransferServiceScript.new()
	transfer_service.setup(item_registry, container_registry, validator, mass_service)
	_assert(bool(validator.validate_graph().get("success", false)), "CH9.1 fixture Item Graph invalid before source setup")

	var layout := EquipmentDomain.Layout.new(
		"humanoid.standard",
		["character", "biological", "humanoid", "biped"],
		["equipment.clothing"],
		["body.torso.outer", "body.arms.outer", "body.legs.outer", "body.feet"],
		["body.root"],
		[]
	)
	var profiles: Array = [
		EquipmentDomain.Profile.new(PROFILE_UPPER, "wearable.layer.upper.peasant", "body.root", ["body.torso.outer", "body.arms.outer"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_LOWER, "wearable.layer.lower.peasant", "body.root", ["body.legs.outer"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_FEET, "wearable.layer.feet.peasant", "body.root", ["body.feet"], [], [], ["equipment.clothing"]),
	]
	var mapping := {0: PROFILE_UPPER, 1: PROFILE_LOWER, 2: PROFILE_FEET}
	var source = ItemGraphEquipmentSource.new()
	var source_setup: Dictionary = source.setup(OWNER_ID, EQUIPMENT_ID, layout, item_registry, container_registry, mapping, profiles)
	_assert_ok(source_setup, "CH9.1 ItemGraphEquipmentSource setup failed")
	var service = EquipmentOperations.new()
	var service_setup: Dictionary = service.setup(OWNER_ID, EQUIPMENT_ID, source, item_registry, container_registry, transfer_service)
	_assert_ok(service_setup, "CH9.1 operation service setup failed")
	return {
		"item_registry": item_registry,
		"container_registry": container_registry,
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
		"unit_mass_kg": 1.0,
		"external_volume_l": 1.0,
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
	_assert(item_registry.add_item(item), "CH9.1 fixture add item failed: %s" % item_id)
	_assert(container.assign_item(item_id, slot_index) == slot_index, "CH9.1 fixture slot assignment failed: %s" % item_id)


func _is_in_slot(item_registry, item_id: String, container_id: String, slot_index: int) -> bool:
	var item = item_registry.get_item(item_id)
	if item == null:
		return false
	var relation: Dictionary = Relations.canonicalize(item.relation)
	return (
		Relations.kind_of(relation) == Relations.CONTAINER
		and String(relation.get("container_id", "")) == container_id
		and int(relation.get("slot_index", -1)) == slot_index
	)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, JSON.stringify(result)])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.1 authoritative equipment operations: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.1 authoritative equipment operations: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
