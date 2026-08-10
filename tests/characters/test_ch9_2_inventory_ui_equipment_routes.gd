extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_item_graph_equipment_lab.tscn")
const Relations = preload("res://scripts/items/domain/item_relations.gd")

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
	_assert(bool(lab.ch9_setup_result.get("success", false)), "CH9.2 UI route lab setup failed")
	if not bool(lab.ch9_setup_result.get("success", false)):
		lab.queue_free()
		_finish()
		return

	var controller = lab.character_gameplay_controller
	var screen = lab.character_inventory_ui.active_screen
	var equipment_id: String = controller.get_character_equipment_container_id()
	var upper_item_id: String = lab.get_wearable_item_id(lab.SLOT_UPPER)

	var preview: Dictionary = screen.call(
		"_preview_equipment_drop",
		upper_item_id,
		1,
		equipment_id,
		lab.SLOT_UPPER,
		""
	)
	_assert(bool(preview.get("success", false)), "CH9.2 equipment panel preview rejected valid upper item: %s" % JSON.stringify(preview))
	_assert(int(preview.get("maximum_quantity", 0)) == 1, "CH9.2 equipment preview must accept exactly one physical item")

	screen.call("_on_drop_requested", upper_item_id, equipment_id, lab.SLOT_UPPER, 1, "")
	await process_frame
	var upper = controller.get_item(upper_item_id)
	_assert(String(upper.relation.get("container_id", "")) == equipment_id, "CH9.2 inventory UI did not route equip into canonical equipment container")
	_assert(lab.equipment_presenter.get_visual(upper_item_id) != null, "CH9.2 inventory UI equip did not update character presentation")

	var inventory = controller.get_container(controller.player_inventory_id)
	var replacement = controller.domain.items.create_item(
		"ch9_wearable_upper",
		1,
		{},
		Relations.container(controller.player_inventory_id)
	)
	_assert(replacement != null, "CH9.2 failed to create replacement upper item")
	if replacement != null:
		inventory.assign_item(replacement.instance_id)
		var swap_preview: Dictionary = screen.call(
			"_preview_equipment_drop",
			String(replacement.instance_id),
			1,
			equipment_id,
			lab.SLOT_UPPER,
			upper_item_id
		)
		_assert(bool(swap_preview.get("success", false)), "CH9.2 UI did not preview one-item atomic equipment replacement")
		_assert(String(swap_preview.get("mode", "")) == "SWAP", "CH9.2 occupied equipment slot did not plan canonical swap")
		screen.call("_on_drop_requested", String(replacement.instance_id), equipment_id, lab.SLOT_UPPER, 1, upper_item_id)
		await process_frame
		_assert(String(controller.get_container(equipment_id).get_item_at_slot(lab.SLOT_UPPER)) == String(replacement.instance_id), "CH9.2 UI swap did not install replacement item")
		_assert(String(controller.get_item(upper_item_id).relation.get("container_id", "")) == controller.player_inventory_id, "CH9.2 UI swap did not return replaced item to backpack")
		_assert(lab.equipment_presenter.get_visual(String(replacement.instance_id)) != null, "CH9.2 UI swap did not present replacement garment")
		_assert(lab.equipment_presenter.get_visual(upper_item_id) == null, "CH9.2 UI swap retained replaced garment visual")

		# Drag from equipment panel back to the normal backpack. The UI must use
		# CH9.1 unequip rather than bypassing character equipment semantics.
		screen.call("_on_drop_requested", String(replacement.instance_id), controller.player_inventory_id, -1, 1, "")
		await process_frame
		_assert(String(replacement.relation.get("container_id", "")) == controller.player_inventory_id, "CH9.2 UI unequip did not return replacement to backpack")
		_assert(lab.equipment_presenter.get_visual(String(replacement.instance_id)) == null, "CH9.2 UI unequip retained garment visual")

	_assert(bool(controller.domain.validator.validate_graph().get("success", false)), "CH9.2 UI equipment routes left Item Graph invalid")
	var ui_debug: Dictionary = screen.create_debug_snapshot()
	_assert(String(Dictionary(ui_debug.get("character_equipment", {})).get("container_id", "")) == equipment_id, "CH9.2 inventory debug snapshot lost equipment panel binding")

	lab.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.2 inventory UI equipment routes: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.2 inventory UI equipment routes: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
