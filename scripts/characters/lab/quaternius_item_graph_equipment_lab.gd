class_name QuaterniusItemGraphEquipmentLab
extends "res://scripts/characters/lab/quaternius_layered_equipment_lab.gd"

const GameplayControllerType = preload("res://scripts/characters/equipment/character_equipment_gameplay_controller.gd")
const EquipmentInventoryUIType = preload("res://scripts/items/presentation/character_equipment_inventory_ui.gd")
const ItemGraphSourceType = preload("res://scripts/characters/equipment/item_graph_equipment_source.gd")
const EquipmentOperationsType = preload("res://scripts/characters/equipment/character_equipment_operation_service.gd")
const ItemDefinitionType = preload("res://scripts/items/domain/item_definition.gd")
const ContainerStateType = preload("res://scripts/containers/container_state.gd")
const ItemRelations = preload("res://scripts/items/domain/item_relations.gd")

const OWNER_ENTITY_ID := "entity.player.ch9.2.lab"
const EQUIPMENT_CONTAINER_ID := "container/equipment/ch9-2-player"

const SLOT_HEAD := 0
const SLOT_BACK := 1
const SLOT_UPPER := 2
const SLOT_LOWER := 3
const SLOT_FEET := 4

var character_gameplay_controller: CharacterEquipmentGameplayController
var character_inventory_ui: CharacterEquipmentInventoryUI
var item_graph_equipment_source: ItemGraphEquipmentSource
var equipment_operation_service: CharacterEquipmentOperationService
var equipment_item_ids_by_slot: Dictionary = {}
var ch9_setup_result: Dictionary = {}


func _ready() -> void:
	super._ready()
	_setup_item_graph_inventory_composition()
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			if character_gameplay_controller != null:
				character_gameplay_controller.toggle_inventory()
				_refresh_status()
			get_viewport().set_input_as_handled()
			return
		# CH9.2 deliberately disables the old lab-owned equipment mutations.
		# Equipment state must now change through Item Graph + Inventory UI only.
		if event.keycode in [KEY_U, KEY_L, KEY_K, KEY_H, KEY_B]:
			if status_label != null:
				status_label.text += "\nCH9.2: U/L/K/H/B disabled — use inventory equipment slots"
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func _setup_item_graph_inventory_composition() -> void:
	if equipment_presenter == null or wearable_catalog == null or equipment_layout == null:
		ch9_setup_result = {"success": false, "code": "CH8_PRESENTATION_NOT_READY"}
		push_error("CH9.2 requires the CH8 presentation lab to be ready")
		return

	character_gameplay_controller = GameplayControllerType.new()
	character_gameplay_controller.name = "CH9CharacterEquipmentGameplayController"
	add_child(character_gameplay_controller)
	var runtime_result: Dictionary = character_gameplay_controller.setup_runtime(
		player,
		self,
		self,
		null,
		"scenario/local",
		"",
		"ch9-2-character-equipment-lab",
		"ch9-2-character-equipment-lab",
		false,
		{
			"persistence_enabled": false,
			"presentation_enabled": false,
			"include_demo_world": false,
		}
	)
	if not bool(runtime_result.get("success", false)):
		ch9_setup_result = runtime_result
		push_error("CH9.2 item gameplay controller setup failed: %s" % JSON.stringify(runtime_result))
		return

	_register_wearable_item_definitions()
	var equipment_container := ContainerStateType.new({
		"container_id": EQUIPMENT_CONTAINER_ID,
		"owner_kind": "WORLD_ENTITY",
		"owner_id": OWNER_ENTITY_ID,
		"storage_mode": ContainerStateType.STORAGE_SLOTS,
		"slot_count": 5,
		"slot_rules": [
			{"accepted_tags": ["equipment.slot.head"]},
			{"accepted_tags": ["equipment.slot.back"]},
			{"accepted_tags": ["equipment.slot.upper"]},
			{"accepted_tags": ["equipment.slot.lower"]},
			{"accepted_tags": ["equipment.slot.feet"]},
		],
		"maximum_mass_kg": 100.0,
		"maximum_volume_l": 180.0,
	})
	if not character_gameplay_controller.domain.containers.add_container(equipment_container):
		ch9_setup_result = {"success": false, "code": "EQUIPMENT_CONTAINER_ADD_FAILED"}
		return

	_seed_wearables_to_backpack()
	var profiles: Array = _equipment_profiles()
	var mapping: Dictionary = {
		SLOT_HEAD: HELMET_PROFILE_ID,
		SLOT_BACK: BACKPACK_PROFILE_ID,
		SLOT_UPPER: UPPER_PROFILE_ID,
		SLOT_LOWER: LOWER_PROFILE_ID,
		SLOT_FEET: FEET_PROFILE_ID,
	}
	item_graph_equipment_source = ItemGraphSourceType.new()
	ch9_setup_result = item_graph_equipment_source.setup(
		OWNER_ENTITY_ID,
		EQUIPMENT_CONTAINER_ID,
		equipment_layout,
		character_gameplay_controller.domain.items,
		character_gameplay_controller.domain.containers,
		mapping,
		profiles
	)
	if not bool(ch9_setup_result.get("success", false)):
		push_error("CH9.2 Item Graph equipment source setup failed: %s" % JSON.stringify(ch9_setup_result))
		return

	equipment_operation_service = EquipmentOperationsType.new()
	ch9_setup_result = equipment_operation_service.setup(
		OWNER_ENTITY_ID,
		EQUIPMENT_CONTAINER_ID,
		item_graph_equipment_source,
		character_gameplay_controller.domain.items,
		character_gameplay_controller.domain.containers,
		character_gameplay_controller.domain.transfer
	)
	if not bool(ch9_setup_result.get("success", false)):
		push_error("CH9.2 equipment operation service setup failed: %s" % JSON.stringify(ch9_setup_result))
		return

	# From this point the inherited lab/presenter reads canonical Item Graph state.
	equipment_source = item_graph_equipment_source
	ch9_setup_result = character_gameplay_controller.configure_character_equipment(
		EQUIPMENT_CONTAINER_ID,
		item_graph_equipment_source,
		equipment_operation_service,
		equipment_presenter,
		body_suppression_coordinator,
		body_topology_coordinator
	)
	if not bool(ch9_setup_result.get("success", false)):
		push_error("CH9.2 character equipment gameplay binding failed: %s" % JSON.stringify(ch9_setup_result))
		return

	character_inventory_ui = EquipmentInventoryUIType.new()
	character_inventory_ui.name = "CH9CharacterEquipmentInventoryUI"
	character_gameplay_controller.add_child(character_inventory_ui)
	character_gameplay_controller.inventory_ui = character_inventory_ui
	character_inventory_ui.setup(character_gameplay_controller, "component", "planet_default")
	character_gameplay_controller.set_inventory_visible(true)
	ch9_setup_result = {
		"success": true,
		"code": "OK",
		"equipment_container_id": EQUIPMENT_CONTAINER_ID,
		"wearable_item_ids_by_slot": equipment_item_ids_by_slot.duplicate(true),
	}


func _register_wearable_item_definitions() -> void:
	for data in [
		{"id": "ch9_wearable_helmet", "display_name": "Шлем", "tag": "equipment.slot.head", "mass": 1.6, "volume": 4.0, "color": [0.36, 0.52, 0.70]},
		{"id": "ch9_wearable_backpack", "display_name": "Рюкзак", "tag": "equipment.slot.back", "mass": 2.4, "volume": 18.0, "color": [0.32, 0.44, 0.24]},
		{"id": "ch9_wearable_upper", "display_name": "Peasant Upper", "tag": "equipment.slot.upper", "mass": 1.1, "volume": 5.0, "color": [0.46, 0.25, 0.18]},
		{"id": "ch9_wearable_lower", "display_name": "Peasant Trousers", "tag": "equipment.slot.lower", "mass": 1.0, "volume": 4.5, "color": [0.28, 0.22, 0.17]},
		{"id": "ch9_wearable_feet", "display_name": "Peasant Boots", "tag": "equipment.slot.feet", "mass": 1.4, "volume": 5.5, "color": [0.20, 0.16, 0.12]},
	]:
		character_gameplay_controller.domain.items.register_definition(ItemDefinitionType.new({
			"id": String(data["id"]),
			"display_name": String(data["display_name"]),
			"max_stack": 1,
			"unit_mass_kg": float(data["mass"]),
			"external_volume_l": float(data["volume"]),
			"tags": ["equipment", String(data["tag"])],
			"metadata": {"icon_color": data["color"]},
		}))


func _seed_wearables_to_backpack() -> void:
	var inventory = character_gameplay_controller.get_container(character_gameplay_controller.player_inventory_id)
	var rows := [
		[SLOT_HEAD, "ch9_wearable_helmet"],
		[SLOT_BACK, "ch9_wearable_backpack"],
		[SLOT_UPPER, "ch9_wearable_upper"],
		[SLOT_LOWER, "ch9_wearable_lower"],
		[SLOT_FEET, "ch9_wearable_feet"],
	]
	for row in rows:
		var item = character_gameplay_controller.domain.items.create_item(
			String(row[1]),
			1,
			{},
			ItemRelations.container(character_gameplay_controller.player_inventory_id)
		)
		if item == null:
			continue
		inventory.assign_item(item.instance_id)
		equipment_item_ids_by_slot[int(row[0])] = String(item.instance_id)


func _equipment_profiles() -> Array:
	return [
		LayerDomain.Profile.new(HELMET_PROFILE_ID, "wearable.helmet.mk1", "body.head", ["body.head.outer"], [], [], ["equipment.headwear"]),
		LayerDomain.Profile.new(BACKPACK_PROFILE_ID, "wearable.backpack.mk1", "gear.back", ["gear.back"], [], [], ["equipment.backpack"]),
		LayerDomain.Profile.new(UPPER_PROFILE_ID, UPPER_PRESENTATION_ID, "body.root", ["body.torso.outer", "body.arms.outer"], [], [], ["equipment.clothing"]),
		LayerDomain.Profile.new(LOWER_PROFILE_ID, LOWER_PRESENTATION_ID, "body.root", ["body.legs.outer"], [], [], ["equipment.clothing"]),
		LayerDomain.Profile.new(FEET_PROFILE_ID, FEET_PRESENTATION_ID, "body.root", ["body.feet"], [], [], ["equipment.clothing"]),
	]


func get_wearable_item_id(slot_index: int) -> String:
	return String(equipment_item_ids_by_slot.get(slot_index, ""))


func equip_slot_for_test(slot_index: int) -> Dictionary:
	if character_gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	return character_gameplay_controller.equip_character_item(get_wearable_item_id(slot_index), slot_index, 1)


func unequip_slot_for_test(slot_index: int) -> Dictionary:
	if character_gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	var item_id: String = String(character_gameplay_controller.get_container(EQUIPMENT_CONTAINER_ID).get_item_at_slot(slot_index))
	if item_id.is_empty():
		return {"success": false, "error_code": "EQUIPMENT_SLOT_EMPTY"}
	return character_gameplay_controller.unequip_character_item(
		item_id,
		character_gameplay_controller.player_inventory_id,
		-1
	)


func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var inventory_state := "NOT READY"
	var equipment_count := 0
	if character_gameplay_controller != null and character_gameplay_controller.has_character_equipment():
		inventory_state = "OPEN" if character_gameplay_controller.inventory_open else "CLOSED"
		var equipment_container = character_gameplay_controller.get_container(EQUIPMENT_CONTAINER_ID)
		if equipment_container != null:
			equipment_count = equipment_container.item_ids.size()
	status_label.text += (
		"\n\nCH9.2 — Real Item Graph + Inventory Composition\n"
		+ "Tab — inventory | drag backpack item -> equipment slot | drag back to unequip\n"
		+ "slots: 1 head | 2 back | 3 upper | 4 lower | 5 feet\n"
		+ "U/L/K/H/B mutations disabled: Item Graph is the only equipment source\n"
		+ "inventory: %s | equipped canonical items: %d"
	) % [inventory_state, equipment_count]
