extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_item_graph_equipment_lab.tscn")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const ItemIdGenerator = preload("res://scripts/items/services/item_id_generator.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame
	await process_frame

	_assert(bool(lab.ch9_setup_result.get("success", false)), "CH9.2 lab setup failed: %s" % JSON.stringify(lab.ch9_setup_result))
	_assert(lab.character_gameplay_controller != null, "CH9.2 gameplay controller missing")
	_assert(lab.item_graph_equipment_source != null, "CH9.2 Item Graph equipment source missing")
	_assert(lab.equipment_operation_service != null, "CH9.2 equipment operation service missing")
	_assert(lab.character_inventory_ui != null, "CH9.2 inventory UI missing")
	_assert(lab.equipment_presenter != null, "CH9.2 character equipment presenter missing")
	if not bool(lab.ch9_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var controller = lab.character_gameplay_controller
	var equipment_id: String = controller.get_character_equipment_container_id()
	_assert(equipment_id == lab.EQUIPMENT_CONTAINER_ID, "CH9.2 gameplay controller equipment container id mismatch")
	var equipment_container = controller.get_container(equipment_id)
	_assert(equipment_container != null and equipment_container.is_slot_container(), "CH9.2 equipment container missing or not slotted")
	_assert(int(equipment_container.slot_count) == 5, "CH9.2 equipment slot count mismatch")
	_assert(equipment_container.item_ids.is_empty(), "CH9.2 equipment must start empty")

	var screen = lab.character_inventory_ui.active_screen
	_assert(screen is CharacterEquipmentInventoryScreen, "CH9.2 did not instantiate equipment-aware component inventory screen")
	_assert(screen.equipment_panel != null, "CH9.2 equipment panel missing")
	_assert(screen.equipment_panel.visible, "CH9.2 equipment panel is not visible")
	_assert(String(screen.equipment_panel.container_id) == equipment_id, "CH9.2 equipment panel bound to wrong container")
	_assert(int(screen.equipment_panel.current_model.get("physical_cell_count", 0)) == 5, "CH9.2 equipment panel did not render five canonical slots")
	_assert(bool(controller.inventory_open), "CH9.2 inventory should open on lab startup")
	_assert(lab.player.process_mode == Node.PROCESS_MODE_DISABLED, "CH9.2 open inventory must disable the gameplay CharacterBody3D")

	# Keep inventory open across additional physics frames. The CH9.2 parent lab
	# must not call move_and_slide() while the disabled CharacterBody3D has been
	# removed from the physics space. The PowerShell runner treats any engine
	# ERROR emitted here as a gate failure.
	await physics_frame
	await physics_frame
	_assert(bool(controller.inventory_open), "CH9.2 inventory unexpectedly changed state during frozen movement gate")

	for slot_index in range(5):
		var item_id: String = lab.get_wearable_item_id(slot_index)
		_assert(ItemIdGenerator.is_global_id(item_id), "CH9.2 wearable does not use canonical global Item UUID in slot %d" % slot_index)
		var item = controller.get_item(item_id)
		_assert(item != null, "CH9.2 wearable item missing from ItemRegistry in slot %d" % slot_index)
		_assert(Relations.kind_of(item.relation) == Relations.CONTAINER, "CH9.2 wearable must start in a canonical container")
		_assert(String(item.relation.get("container_id", "")) == controller.player_inventory_id, "CH9.2 wearable did not start in backpack")

	var lower_item_id: String = lab.get_wearable_item_id(lab.SLOT_LOWER)
	var lower_before = controller.get_item(lower_item_id)
	var lower_revision_before: int = int(lower_before.revision)
	var equip_result: Dictionary = lab.equip_slot_for_test(lab.SLOT_LOWER)
	_assert(bool(equip_result.get("success", false)), "CH9.2 real equip failed: %s" % JSON.stringify(equip_result))
	await process_frame
	var lower_after = controller.get_item(lower_item_id)
	_assert(int(lower_after.revision) > lower_revision_before, "CH9.2 real equip did not advance canonical item revision")
	_assert(String(lower_after.relation.get("container_id", "")) == equipment_id, "CH9.2 real equip did not move item into equipment container")
	_assert(int(lower_after.relation.get("slot_index", -1)) == lab.SLOT_LOWER, "CH9.2 real equip relation slot mismatch")
	_assert(String(equipment_container.get_item_at_slot(lab.SLOT_LOWER)) == lower_item_id, "CH9.2 equipment container membership mismatch after equip")
	_assert(lab.item_graph_equipment_source.get_snapshot().find_item(lower_item_id) != null, "CH9.2 source did not project equipped lower item")
	_assert(lab.equipment_presenter.get_visual(lower_item_id) != null, "CH9.2 presenter did not create lower garment from Item Graph state")
	_assert(bool(controller.domain.validator.validate_graph().get("success", false)), "CH9.2 Item Graph invalid after equip")

	screen.refresh()
	_assert(String(screen.equipment_panel.current_model.get("container_id", "")) == equipment_id, "CH9.2 equipment panel lost canonical binding after equip")
	var rendered_equipped := false
	for cell_value in screen.equipment_panel.current_model.get("cells", []):
		var cell: Dictionary = Dictionary(cell_value)
		if String(cell.get("item_id", "")) == lower_item_id:
			rendered_equipped = true
	_assert(rendered_equipped, "CH9.2 equipment UI did not render canonical equipped lower item")

	var unequip_result: Dictionary = lab.unequip_slot_for_test(lab.SLOT_LOWER)
	_assert(bool(unequip_result.get("success", false)), "CH9.2 real unequip failed: %s" % JSON.stringify(unequip_result))
	await process_frame
	var lower_unequipped = controller.get_item(lower_item_id)
	_assert(String(lower_unequipped.relation.get("container_id", "")) == controller.player_inventory_id, "CH9.2 unequip did not return item to backpack")
	_assert(lab.item_graph_equipment_source.get_snapshot().find_item(lower_item_id) == null, "CH9.2 source retained item after canonical unequip")
	_assert(lab.equipment_presenter.get_visual(lower_item_id) == null, "CH9.2 presenter retained garment after canonical unequip")
	_assert(bool(controller.domain.validator.validate_graph().get("success", false)), "CH9.2 Item Graph invalid after unequip")

	var debug: Dictionary = controller.create_character_equipment_debug_snapshot()
	_assert(String(debug.get("schema", "")) == "planet_simulator.character_equipment_gameplay_controller.v1", "CH9.2 gameplay debug schema drift")
	_assert(not bool(debug.get("network_mutation_enabled", true)), "CH9.2 must not silently enable network equipment mutation before CH9.3")

	# Closing inventory must restore the CharacterBody3D to normal processing and
	# allow the inherited movement loop to run again without PhysicsServer errors.
	var close_result: Dictionary = controller.toggle_inventory()
	_assert(bool(close_result.get("success", false)), "CH9.2 inventory close failed")
	_assert(not bool(controller.inventory_open), "CH9.2 inventory did not close")
	_assert(lab.player.process_mode == Node.PROCESS_MODE_INHERIT, "CH9.2 closing inventory did not restore gameplay CharacterBody3D processing")
	await process_frame
	await physics_frame
	_assert(not bool(controller.inventory_open), "CH9.2 inventory reopened unexpectedly during movement resume gate")

	lab.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.2 inventory + character Item Graph composition: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.2 inventory + character Item Graph composition: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
