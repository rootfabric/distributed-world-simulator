extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_playable_network_equipment_lab.tscn")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")

const READY_TIMEOUT_MS := 20000
const CONVERGENCE_TIMEOUT_MS := 12000
const PERSISTENCE_USER_PATH := "user://ch9-6-playable-network-equipment-lab"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var persistence_root: String = ProjectSettings.globalize_path(PERSISTENCE_USER_PATH)
	_remove_tree(persistence_root)

	var lab = LabScene.instantiate()
	root.add_child(lab)
	var ready: bool = await _wait_until(func() -> bool:
		return bool(lab.ch9_setup_result.get("success", false)) or (
			not lab.network_setup_in_progress
			and String(lab.ch9_setup_result.get("code", "")) != "CH9_6_NETWORK_BOOTSTRAP_PENDING"
		)
	, READY_TIMEOUT_MS)
	_assert(ready, "CH9.6 generation 1 lab did not finish network bootstrap")
	_assert(bool(lab.ch9_setup_result.get("success", false)), "CH9.6 generation 1 setup failed: %s" % JSON.stringify(lab.ch9_setup_result))
	if not ready or not bool(lab.ch9_setup_result.get("success", false)):
		lab.queue_free()
		_remove_tree(persistence_root)
		_finish()
		return

	var controller = lab.character_gameplay_controller
	var screen = lab.character_inventory_ui.active_screen
	var equipment_id: String = controller.get_character_equipment_container_id()
	var lower_replica_id: String = lab.get_wearable_item_id(EquipmentCatalog.SLOT_LOWER)
	var lower_canonical_id: String = lab.get_canonical_wearable_item_id(EquipmentCatalog.SLOT_LOWER)
	_assert(not lower_replica_id.is_empty(), "CH9.6 lower wearable replica ID missing")
	_assert(lower_canonical_id == "item/player/a/wearable/lower", "CH9.6 lower wearable canonical mapping changed")
	_assert(bool(controller.create_character_equipment_debug_snapshot().get("network_mutation_enabled", false)), "CH9.6 controller is not using network mutation")

	var preview_value = screen.call(
		"_preview_equipment_drop",
		lower_replica_id,
		1,
		equipment_id,
		EquipmentCatalog.SLOT_LOWER,
		""
	)
	var preview: Dictionary = Dictionary(preview_value) if preview_value is Dictionary else {}
	_assert(bool(preview.get("success", false)), "CH9.6 UI preview rejected network lower wearable: %s" % JSON.stringify(preview))
	_assert(int(preview.get("maximum_quantity", 0)) == 1, "CH9.6 UI preview did not preserve one-physical-item equipment rule")

	screen.call(
		"_on_drop_requested",
		lower_replica_id,
		equipment_id,
		EquipmentCatalog.SLOT_LOWER,
		1,
		""
	)
	var equipped: bool = await _wait_until(func() -> bool:
		var canonical: Dictionary = lab.network_client.get_item_graph_snapshot()
		var canonical_item: Dictionary = _find_item(canonical, lower_canonical_id)
		var canonical_location: Dictionary = Dictionary(canonical_item.get("location", {}))
		var replica_item = controller.get_item(lower_replica_id)
		return (
			String(canonical_location.get("kind", "")) == "CONTAINER"
			and String(canonical_location.get("container_id", "")) == EquipmentCatalog.equipment_container_id("a")
			and int(canonical_location.get("slot_index", -1)) == EquipmentCatalog.SLOT_LOWER
			and replica_item != null
			and String(replica_item.relation.get("container_id", "")) == equipment_id
			and lab.equipment_presenter.get_visual(lower_replica_id) != null
		)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(equipped, "CH9.6 UI -> network -> canonical Item Graph -> real presenter equip did not converge")
	_assert(_item_count(lab.network_client.get_item_graph_snapshot(), lower_canonical_id) == 1, "CH9.6 equip duplicated canonical wearable UUID")
	_assert(not JSON.stringify(lab.network_client.get_snapshot()).contains(lower_canonical_id), "CH9.6 equipment UUID leaked into movement/gameplay snapshot")
	var bridge_after_equip: Dictionary = lab.network_bridge.get_report()
	_assert(int(bridge_after_equip.get("submitted", 0)) >= 1, "CH9.6 UI equip did not submit through network bridge")
	_assert(int(bridge_after_equip.get("rejected", 0)) == 0, "CH9.6 network bridge rejected valid UI equip")

	# Exercise the exact UI unequip route and then equip again so shutdown writes
	# a checkpoint containing equipped state. This makes generation 2 prove that
	# the playable graphical composition is rebuilt from durable canonical truth.
	screen.call(
		"_on_drop_requested",
		lower_replica_id,
		controller.player_inventory_id,
		-1,
		1,
		""
	)
	var unequipped: bool = await _wait_until(func() -> bool:
		var canonical_item: Dictionary = _find_item(lab.network_client.get_item_graph_snapshot(), lower_canonical_id)
		var location: Dictionary = Dictionary(canonical_item.get("location", {}))
		return String(location.get("kind", "")) == "INVENTORY" and lab.equipment_presenter.get_visual(lower_replica_id) == null
	, CONVERGENCE_TIMEOUT_MS)
	_assert(unequipped, "CH9.6 UI network unequip did not converge")

	screen.call(
		"_on_drop_requested",
		lower_replica_id,
		equipment_id,
		EquipmentCatalog.SLOT_LOWER,
		1,
		""
	)
	var reequipped: bool = await _wait_until(func() -> bool:
		var canonical_item: Dictionary = _find_item(lab.network_client.get_item_graph_snapshot(), lower_canonical_id)
		var location: Dictionary = Dictionary(canonical_item.get("location", {}))
		return String(location.get("kind", "")) == "CONTAINER" and lab.equipment_presenter.get_visual(lower_replica_id) != null
	, CONVERGENCE_TIMEOUT_MS)
	_assert(reequipped, "CH9.6 second UI equip did not converge before restart")
	var generation_1_persistence: Dictionary = Dictionary(lab.network_server.get_report().get("persistence", {}))
	_assert(int(generation_1_persistence.get("checkpoint_generation", 0)) >= 1, "CH9.6 UI equipment mutations produced no durable checkpoint")

	lab.queue_free()
	for _frame in range(6):
		await process_frame

	var recovered_lab = LabScene.instantiate()
	root.add_child(recovered_lab)
	var recovered_ready: bool = await _wait_until(func() -> bool:
		return bool(recovered_lab.ch9_setup_result.get("success", false)) or (
			not recovered_lab.network_setup_in_progress
			and String(recovered_lab.ch9_setup_result.get("code", "")) != "CH9_6_NETWORK_BOOTSTRAP_PENDING"
		)
	, READY_TIMEOUT_MS)
	_assert(recovered_ready, "CH9.6 generation 2 lab did not finish network bootstrap")
	_assert(bool(recovered_lab.ch9_setup_result.get("success", false)), "CH9.6 generation 2 setup failed: %s" % JSON.stringify(recovered_lab.ch9_setup_result))
	if recovered_ready and bool(recovered_lab.ch9_setup_result.get("success", false)):
		_assert(bool(recovered_lab.ch9_setup_result.get("recovered", false)), "CH9.6 generation 2 server did not report recovery")
		var recovered_replica_id: String = recovered_lab.get_wearable_item_id(EquipmentCatalog.SLOT_LOWER)
		var recovered_controller = recovered_lab.character_gameplay_controller
		var recovered_equipment_id: String = recovered_controller.get_character_equipment_container_id()
		var recovered_presented: bool = await _wait_until(func() -> bool:
			var replica_item = recovered_controller.get_item(recovered_replica_id)
			return (
				replica_item != null
				and String(replica_item.relation.get("container_id", "")) == recovered_equipment_id
				and int(replica_item.relation.get("slot_index", -1)) == EquipmentCatalog.SLOT_LOWER
				and recovered_lab.equipment_presenter.get_visual(recovered_replica_id) != null
			)
		, CONVERGENCE_TIMEOUT_MS)
		_assert(recovered_presented, "CH9.6 recovered canonical equipment did not rebuild real Quaternius presentation")
		_assert(recovered_lab.get_canonical_wearable_item_id(EquipmentCatalog.SLOT_LOWER) == lower_canonical_id, "CH9.6 restart changed canonical wearable identity")
		_assert(_item_count(recovered_lab.network_client.get_item_graph_snapshot(), lower_canonical_id) == 1, "CH9.6 restart duplicated canonical wearable UUID")
		var ui_debug: Dictionary = recovered_lab.character_inventory_ui.active_screen.create_debug_snapshot()
		_assert(String(Dictionary(ui_debug.get("character_equipment", {})).get("container_id", "")) == recovered_equipment_id, "CH9.6 recovered Inventory UI lost equipment panel binding")

	recovered_lab.queue_free()
	for _frame in range(6):
		await process_frame
	_remove_tree(persistence_root)
	_finish()


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value).duplicate(true)
	return {}


func _item_count(snapshot: Dictionary, item_id: String) -> int:
	var count: int = 0
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			count += 1
	return count


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var started_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_ms <= timeout_ms:
		if bool(predicate.call()):
			return true
		await process_frame
	return false


func _remove_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry_name: String = directory.get_next()
		if entry_name.is_empty():
			break
		if entry_name in [".", ".."]:
			continue
		var child_path: String = path.path_join(entry_name)
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
		print("CH9.6 playable network equipment UI: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.6 playable network equipment UI: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
