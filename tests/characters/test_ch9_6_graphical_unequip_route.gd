extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_playable_network_equipment_lab.tscn")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")

const READY_TIMEOUT_MS := 20000
const CONVERGENCE_TIMEOUT_MS := 12000
const PERSISTENCE_USER_PATH := "user://ch9-6-playable-network-equipment-lab"
const BACKPACK_DROP_SLOT := 10

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var persistence_root: String = ProjectSettings.globalize_path(PERSISTENCE_USER_PATH)
	_remove_tree(persistence_root)

	var lab = LabScene.instantiate()
	root.add_child(lab)
	var ready := await _wait_until(func() -> bool:
		return bool(lab.ch9_setup_result.get("success", false)) or not lab.network_setup_in_progress
	, READY_TIMEOUT_MS)
	_assert(ready, "CH9.6 graphical unequip route lab did not finish bootstrap")
	_assert(bool(lab.ch9_setup_result.get("success", false)), "CH9.6 graphical unequip route setup failed: %s" % JSON.stringify(lab.ch9_setup_result))
	if not ready or not bool(lab.ch9_setup_result.get("success", false)):
		lab.queue_free()
		_remove_tree(persistence_root)
		_finish()
		return

	var controller = lab.character_gameplay_controller
	var screen = lab.character_inventory_ui.active_screen
	var equipment_id: String = controller.get_character_equipment_container_id()
	var replica_id: String = lab.get_wearable_item_id(EquipmentCatalog.SLOT_LOWER)
	var canonical_id: String = lab.get_canonical_wearable_item_id(EquipmentCatalog.SLOT_LOWER)
	_assert(not replica_id.is_empty(), "CH9.6 graphical unequip route lower wearable replica is missing")

	var equip_preview: Dictionary = screen.call(
		"_preview_equipment_drop",
		replica_id,
		1,
		equipment_id,
		EquipmentCatalog.SLOT_LOWER,
		""
	)
	_assert(bool(equip_preview.get("success", false)), "CH9.6 graphical unequip route could not preview initial equip")
	screen.call("_on_drop_requested", replica_id, equipment_id, EquipmentCatalog.SLOT_LOWER, 1, "")
	var equipped := await _wait_until(func() -> bool:
		var replica = controller.get_item(replica_id)
		return (
			replica != null
			and String(replica.relation.get("container_id", "")) == equipment_id
			and lab.equipment_presenter.get_visual(replica_id) != null
		)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(equipped, "CH9.6 graphical unequip route initial equip did not converge")

	# Reproduce the real GUI route that the previous focused test skipped:
	# InventoryItemCell asks the screen preview first. Only if preview accepts the
	# target does Godot dispatch _drop_data -> _on_drop_requested. A network-backed
	# equipment source must therefore be previewable when dragged onto a normal
	# backpack cell, even though it is not a generic open container source.
	var unequip_preview: Dictionary = screen.call(
		"_preview_equipment_drop",
		replica_id,
		1,
		controller.player_inventory_id,
		BACKPACK_DROP_SLOT,
		""
	)
	_assert(bool(unequip_preview.get("success", false)), "CH9.6 GUI preview rejected equipped -> backpack drag: %s" % JSON.stringify(unequip_preview))
	_assert(String(unequip_preview.get("mode", "")) == "NETWORK_UNEQUIP_TO_BACKPACK", "CH9.6 GUI preview did not select network unequip route")
	_assert(int(unequip_preview.get("maximum_quantity", 0)) == 1, "CH9.6 GUI unequip preview must remain one physical item")

	screen.call("_on_drop_requested", replica_id, controller.player_inventory_id, BACKPACK_DROP_SLOT, 1, "")
	var unequipped := await _wait_until(func() -> bool:
		var canonical_item: Dictionary = _find_item(lab.network_client.get_item_graph_snapshot(), canonical_id)
		var canonical_location: Dictionary = Dictionary(canonical_item.get("location", {}))
		var replica = controller.get_item(replica_id)
		return (
			String(canonical_location.get("kind", "")) == "INVENTORY"
			and replica != null
			and String(replica.relation.get("container_id", "")) == controller.player_inventory_id
			and lab.equipment_presenter.get_visual(replica_id) == null
		)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(unequipped, "CH9.6 graphical equipped -> backpack drag did not converge through equipment.unequip")
	var bridge: Dictionary = lab.network_bridge.get_report()
	_assert(int(bridge.get("submitted", 0)) >= 2, "CH9.6 graphical unequip route did not submit equip + unequip through network bridge")
	_assert(int(bridge.get("rejected", 0)) == 0, "CH9.6 graphical unequip route produced a network bridge rejection")

	lab.queue_free()
	for _frame in range(6):
		await process_frame
	_remove_tree(persistence_root)
	_finish()


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value).duplicate(true)
	return {}


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var started_ms := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_ms <= timeout_ms:
		if bool(predicate.call()):
			return true
		await process_frame
	return false


func _remove_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry_name := directory.get_next()
		if entry_name.is_empty():
			break
		if entry_name in [".", ".."]:
			continue
		var child_path := path.path_join(entry_name)
		if directory.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.6 graphical unequip route: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.6 graphical unequip route: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
