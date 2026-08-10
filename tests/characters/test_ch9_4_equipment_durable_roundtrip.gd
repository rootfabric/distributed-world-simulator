extends SceneTree

const Service = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_4_equipment_recovery_service.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")
const EquipmentProjection = preload("res://scripts/characters/equipment/network_character_equipment_projection.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = _new_service()
	if service == null:
		_finish()
		return
	var join: Dictionary = service.join("a", "transport-session/ch9-4/a/1", "operation/ch9-4/join/a/1")
	_assert_ok(join, "initial join")
	var epoch := int(join.get("details", {}).get("player", {}).get("ownership_epoch", 0))
	var lower_id := "item/player/a/wearable/lower"
	var helmet_id := "item/player/a/wearable/helmet"
	var equip_lower := service.handle_canonical_item_command(
		"a", "transport-session/ch9-4/a/1", epoch,
		"operation/ch9-4/equip/a/lower", "equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER}
	)
	var equip_helmet := service.handle_canonical_item_command(
		"a", "transport-session/ch9-4/a/1", epoch,
		"operation/ch9-4/equip/a/helmet", "equipment.equip",
		{"item_id": helmet_id, "slot_index": EquipmentCatalog.SLOT_HEAD}
	)
	_assert_ok(equip_lower, "equip lower before durable export")
	_assert_ok(equip_helmet, "equip helmet before durable export")

	var canonical_before: Dictionary = service.create_canonical_item_graph_snapshot()
	var durable: Dictionary = service.export_durable_state()
	var replay: Dictionary = service.export_replay_state()
	_assert(not durable.is_empty(), "durable export is empty")
	_assert_ok(service.validate_durable_state(durable), "equipment durable state validates")
	_assert_ok(service.validate_replay_state(replay), "equipment replay state validates")
	_assert(_equipment_item(canonical_before, "a", EquipmentCatalog.SLOT_LOWER) == lower_id, "lower missing before restore")
	_assert(_equipment_item(canonical_before, "a", EquipmentCatalog.SLOT_HEAD) == helmet_id, "helmet missing before restore")

	var corrupted := durable.duplicate(true)
	var item_state: Dictionary = Dictionary(corrupted.get("canonical_item_graph", {})).duplicate(true)
	var item_snapshot: Dictionary = Dictionary(item_state.get("snapshot", {})).duplicate(true)
	var containers: Array = Array(item_snapshot.get("containers", [])).duplicate(true)
	for index in range(containers.size()):
		if not containers[index] is Dictionary:
			continue
		var container: Dictionary = Dictionary(containers[index]).duplicate(true)
		if String(container.get("container_id", "")) != EquipmentCatalog.equipment_container_id("a"):
			continue
		var slots: Dictionary = Dictionary(container.get("equipment_slots", {})).duplicate(true)
		slots.erase(str(EquipmentCatalog.SLOT_LOWER))
		container["equipment_slots"] = slots
		containers[index] = container
		break
	item_snapshot["containers"] = containers
	item_snapshot = Utils.finalize_json_checksum(item_snapshot)
	item_state["snapshot"] = item_snapshot
	item_state = Utils.finalize_json_checksum(item_state)
	corrupted["canonical_item_graph"] = item_state
	corrupted = Utils.finalize_json_checksum(corrupted)
	var corrupt_validation: Dictionary = service.validate_durable_state(corrupted)
	_assert(not bool(corrupt_validation.get("success", false)), "semantic equipment corruption was accepted")
	_assert(String(corrupt_validation.get("error_code", "")) == Service.RESULT_EQUIPMENT_DURABLE_STATE_INVALID, "semantic corruption error code drift")

	service.shutdown()
	var restored = _new_service()
	if restored == null:
		_finish()
		return
	var restore_result: Dictionary = restored.restore_durable_state(durable)
	_assert_ok(restore_result, "durable equipment restore")
	_assert(bool(restore_result.get("details", {}).get("character_equipment_recovered", false)), "restore did not report equipment-aware graph")
	_assert(int(restore_result.get("details", {}).get("equipped_item_count", 0)) == 2, "restore equipped item count mismatch")
	_assert_ok(restored.restore_replay_state(replay), "replay state restore")

	var canonical_after: Dictionary = restored.create_canonical_item_graph_snapshot()
	_assert(String(canonical_after.get("checksum", "")) == String(canonical_before.get("checksum", "")), "canonical Item Graph checksum changed across restore")
	_assert(_equipment_item(canonical_after, "a", EquipmentCatalog.SLOT_LOWER) == lower_id, "lower Item UUID changed across restore")
	_assert(_equipment_item(canonical_after, "a", EquipmentCatalog.SLOT_HEAD) == helmet_id, "helmet Item UUID changed across restore")
	_assert(_item_count(canonical_after, lower_id) == 1, "lower duplicated during restore")
	_assert(_item_count(canonical_after, helmet_id) == 1, "helmet duplicated during restore")
	_assert(restored.has_durable_replay_operation("operation/ch9-4/equip/a/lower"), "equipment replay ledger did not survive restore")

	var projected: Dictionary = EquipmentProjection.new().project(canonical_after, "a")
	_assert_ok(projected, "recovered equipment projection")
	var character_snapshot = projected.get("details", {}).get("snapshot")
	_assert(character_snapshot is CharacterEquipmentDomain.Snapshot, "recovered projection did not produce equipment snapshot")
	if character_snapshot is CharacterEquipmentDomain.Snapshot:
		_assert(character_snapshot.find_item(lower_id) != null, "recovered lower missing from character snapshot")
		_assert(character_snapshot.find_item(helmet_id) != null, "recovered helmet missing from character snapshot")

	var reconnect: Dictionary = restored.join("a", "transport-session/ch9-4/a/2", "operation/ch9-4/join/a/2")
	_assert_ok(reconnect, "reconnect after durable restore")
	var reconnect_epoch := int(reconnect.get("details", {}).get("player", {}).get("ownership_epoch", 0))
	_assert(reconnect_epoch > epoch, "reconnect did not advance ownership epoch")
	_assert(_equipment_item(restored.create_canonical_item_graph_snapshot(), "a", EquipmentCatalog.SLOT_LOWER) == lower_id, "reconnect changed recovered equipment")

	var checksum_before_replay := String(restored.create_canonical_item_graph_snapshot().get("checksum", ""))
	var old_replay: Dictionary = restored.handle_canonical_item_command(
		"a", "transport-session/ch9-4/a/1", epoch,
		"operation/ch9-4/equip/a/lower", "equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER}
	)
	_assert(bool(old_replay.get("success", false)) and bool(old_replay.get("replay", false)), "pre-restart equipment operation did not replay idempotently")
	_assert(String(restored.create_canonical_item_graph_snapshot().get("checksum", "")) == checksum_before_replay, "replay mutated recovered Item Graph")

	var unequip: Dictionary = restored.handle_canonical_item_command(
		"a", "transport-session/ch9-4/a/2", reconnect_epoch,
		"operation/ch9-4/unequip/a/lower", "equipment.unequip",
		{"item_id": lower_id}
	)
	_assert_ok(unequip, "post-recovery unequip")
	var after_unequip := restored.create_canonical_item_graph_snapshot()
	_assert(_equipment_item(after_unequip, "a", EquipmentCatalog.SLOT_LOWER).is_empty(), "post-recovery unequip left slot occupied")
	_assert(String(_find_item(after_unequip, lower_id).get("location", {}).get("kind", "")) == "INVENTORY", "post-recovery unequip did not return same Item UUID to inventory")

	restored.shutdown()
	_finish()


func _new_service():
	var service = Service.new()
	var setup: Dictionary = service.setup("simulation/ch9-4/test", 1, 0, {
		"profile": "MULTIPLAYER_CORE",
		"topology_adapter": "LOOPBACK",
		"region_id": "region/ch9-4/test",
		"playable_sandbox": true,
	})
	_assert_ok(setup, "service setup")
	return service if bool(setup.get("success", false)) else null


func _equipment_item(snapshot: Dictionary, player_id: String, slot_index: int) -> String:
	for value in snapshot.get("containers", []):
		if value is Dictionary and String(value.get("container_id", "")) == EquipmentCatalog.equipment_container_id(player_id):
			return String(Dictionary(value.get("equipment_slots", {})).get(str(slot_index), ""))
	return ""


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value)
	return {}


func _item_count(snapshot: Dictionary, item_id: String) -> int:
	var count := 0
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			count += 1
	return count


func _assert_ok(result: Dictionary, label: String) -> void:
	_assert(bool(result.get("success", false)), "%s failed: %s" % [label, JSON.stringify(result)])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.4 equipment durable roundtrip: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.4 equipment durable roundtrip: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
