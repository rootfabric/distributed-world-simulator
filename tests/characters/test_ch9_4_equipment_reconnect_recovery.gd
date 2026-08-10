extends SceneTree

const Service = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_4_equipment_recovery_service.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")
const EquipmentProjection = preload("res://scripts/characters/equipment/network_character_equipment_projection.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Coordinator = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")
const AuthorityAdapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const ReplayOutbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")

const OWNER := "simulation/ch9-4/recovery"
const SESSION_1 := "transport-session/ch9-4/recovery/a/1"
const EQUIP_LOWER_OP := "operation/ch9-4/recovery/equip/lower"
const EQUIP_HELMET_OP := "operation/ch9-4/recovery/equip/helmet"

var failures: Array[String] = []
var assertions := 0
var root_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root_path = ProjectSettings.globalize_path("user://ch9-4-equipment-recovery-%d" % Time.get_ticks_usec())
	_remove_tree(root_path)
	var live = _new_service()
	if live == null:
		_finish()
		return
	var join: Dictionary = live.join("a", SESSION_1, "operation/ch9-4/recovery/join/a/1")
	_assert_ok(join, "initial A join")
	var epoch := int(join.get("details", {}).get("player", {}).get("ownership_epoch", 0))
	var lower_id := "item/player/a/wearable/lower"
	var helmet_id := "item/player/a/wearable/helmet"
	var lower_result: Dictionary = live.handle_canonical_item_command(
		"a", SESSION_1, epoch, EQUIP_LOWER_OP, "equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER}
	)
	var helmet_result: Dictionary = live.handle_canonical_item_command(
		"a", SESSION_1, epoch, EQUIP_HELMET_OP, "equipment.equip",
		{"item_id": helmet_id, "slot_index": EquipmentCatalog.SLOT_HEAD}
	)
	_assert_ok(lower_result, "equip lower before checkpoint")
	_assert_ok(helmet_result, "equip helmet before checkpoint")
	var checksum_generation_1 := String(live.create_canonical_item_graph_snapshot().get("checksum", ""))

	var repo = Repository.new()
	_assert_ok(repo.configure(root_path), "checkpoint repository setup")
	var authority = AuthorityAdapter.new()
	_assert_ok(authority.setup(live, "session/ch9-4/recovery"), "authority adapter setup")
	var outbox = ReplayOutbox.new()
	_assert_ok(outbox.setup(live), "replay outbox setup")
	var staged_lower: Dictionary = outbox.stage_committed(EQUIP_LOWER_OP, "equipment.equip", {
		"logical_player_id": "a", "success": true, "item_graph_checksum": checksum_generation_1,
	})
	var staged_helmet: Dictionary = outbox.stage_committed(EQUIP_HELMET_OP, "equipment.equip", {
		"logical_player_id": "a", "success": true, "item_graph_checksum": checksum_generation_1,
	})
	_assert_ok(staged_lower, "stage lower committed result")
	_assert_ok(staged_helmet, "stage helmet committed result")
	if bool(staged_lower.get("success", false)):
		_assert_ok(outbox.mark_delivered(int(staged_lower.get("details", {}).get("record", {}).get("sequence", 0))), "mark lower delivered")
	var coordinator = Coordinator.new()
	_assert_ok(coordinator.configure(repo, authority, outbox), "recovery coordinator setup")
	var persisted: Dictionary = coordinator.persist_checkpoint("checkpoint/ch9-4/equipment/1", 1, 0, EQUIP_HELMET_OP)
	_assert_ok(persisted, "persist equipment checkpoint generation 1")
	var durable_generation_1: Dictionary = live.export_durable_state()
	live.shutdown()

	var recovered = _new_service()
	if recovered == null:
		_remove_tree(root_path)
		_finish()
		return
	var recovered_authority = AuthorityAdapter.new()
	var recovered_outbox = ReplayOutbox.new()
	var recovered_coordinator = Coordinator.new()
	_assert_ok(recovered_authority.setup(recovered, "session/ch9-4/recovery"), "recovered authority adapter setup")
	_assert_ok(recovered_outbox.setup(recovered), "recovered replay outbox setup")
	_assert_ok(recovered_coordinator.configure(repo, recovered_authority, recovered_outbox), "recovered coordinator setup")
	var recovery: Dictionary = recovered_coordinator.recover_latest()
	_assert_ok(recovery, "recover generation 1")
	_assert(String(recovery.get("details", {}).get("source", "")) == "ACTIVE", "recovery did not use active checkpoint")
	_assert(String(recovered.export_durable_state().get("checksum", "")) == String(durable_generation_1.get("checksum", "")), "durable gameplay checksum changed after checkpoint recovery")
	var snapshot_after_restart: Dictionary = recovered.create_canonical_item_graph_snapshot()
	_assert(String(snapshot_after_restart.get("checksum", "")) == checksum_generation_1, "recovered Item Graph checksum mismatch")
	_assert(_equipment_item(snapshot_after_restart, "a", EquipmentCatalog.SLOT_LOWER) == lower_id, "lower missing after server restart")
	_assert(_equipment_item(snapshot_after_restart, "a", EquipmentCatalog.SLOT_HEAD) == helmet_id, "helmet missing after server restart")
	_assert(_all_item_ids_unique(snapshot_after_restart), "server restart duplicated canonical Item IDs")
	_assert(not bool(recovered.get_player("a").get("connected", true)), "recovered A retained transient connected state")
	_assert(String(recovered.get_player("a").get("transport_session_id", "")).is_empty(), "recovered A retained stale transport session")
	_assert(recovered_outbox.get_records().size() == 2, "equipment outbox records did not recover")
	_assert(recovered_outbox.get_pending_records().size() == 1, "equipment outbox pending/delivered state changed")

	var reconnect: Dictionary = recovered.join("a", "transport-session/ch9-4/recovery/a/2", "operation/ch9-4/recovery/join/a/2")
	_assert_ok(reconnect, "A reconnect after restart")
	var epoch_2 := int(reconnect.get("details", {}).get("player", {}).get("ownership_epoch", 0))
	_assert(epoch_2 > epoch, "reconnect did not advance ownership epoch")
	_assert(_equipment_item(recovered.create_canonical_item_graph_snapshot(), "a", EquipmentCatalog.SLOT_LOWER) == lower_id, "reconnect changed lower equipment")

	var late_join: Dictionary = recovered.join("b", "transport-session/ch9-4/recovery/b/1", "operation/ch9-4/recovery/join/b/1")
	_assert_ok(late_join, "late client B join")
	var late_snapshot: Dictionary = recovered.create_canonical_item_graph_snapshot()
	_assert(_equipment_item(late_snapshot, "a", EquipmentCatalog.SLOT_LOWER) == lower_id, "late join snapshot lost recovered lower")
	_assert(_equipment_item(late_snapshot, "a", EquipmentCatalog.SLOT_HEAD) == helmet_id, "late join snapshot lost recovered helmet")
	var projected: Dictionary = EquipmentProjection.new().project(late_snapshot, "a")
	_assert_ok(projected, "late join projection of recovered A equipment")
	var projected_snapshot = projected.get("details", {}).get("snapshot")
	_assert(projected_snapshot is CharacterEquipmentDomain.Snapshot, "late join projection type mismatch")
	if projected_snapshot is CharacterEquipmentDomain.Snapshot:
		_assert(projected_snapshot.entries().size() == 2, "late join projected duplicate or missing equipment entries")
		_assert(projected_snapshot.find_item(lower_id) != null, "late join projection missing lower")
		_assert(projected_snapshot.find_item(helmet_id) != null, "late join projection missing helmet")

	var old_equip_replay: Dictionary = recovered.handle_canonical_item_command(
		"a", SESSION_1, epoch, EQUIP_LOWER_OP, "equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER}
	)
	_assert(bool(old_equip_replay.get("success", false)) and bool(old_equip_replay.get("replay", false)), "pre-restart equip operation was not replay-idempotent")
	var before_unequip_checksum := String(recovered.create_canonical_item_graph_snapshot().get("checksum", ""))
	var unequip_op := "operation/ch9-4/recovery/unequip/lower"
	var unequip: Dictionary = recovered.handle_canonical_item_command(
		"a", "transport-session/ch9-4/recovery/a/2", epoch_2, unequip_op,
		"equipment.unequip", {"item_id": lower_id}
	)
	_assert_ok(unequip, "post-recovery lower unequip")
	_assert(String(recovered.create_canonical_item_graph_snapshot().get("checksum", "")) != before_unequip_checksum, "post-recovery equipment command did not mutate authority")
	var staged_unequip: Dictionary = recovered_outbox.stage_committed(unequip_op, "equipment.unequip", {
		"logical_player_id": "a", "success": true,
		"item_graph_checksum": String(recovered.create_canonical_item_graph_snapshot().get("checksum", "")),
	})
	_assert_ok(staged_unequip, "stage post-recovery unequip")
	var persisted_2: Dictionary = recovered_coordinator.persist_checkpoint("checkpoint/ch9-4/equipment/2", 2, 1, unequip_op)
	_assert_ok(persisted_2, "persist equipment checkpoint generation 2")
	recovered.shutdown()

	var recovered_again = _new_service()
	if recovered_again == null:
		_remove_tree(root_path)
		_finish()
		return
	var authority_2 = AuthorityAdapter.new()
	var outbox_2 = ReplayOutbox.new()
	var coordinator_2 = Coordinator.new()
	_assert_ok(authority_2.setup(recovered_again, "session/ch9-4/recovery"), "second recovery authority setup")
	_assert_ok(outbox_2.setup(recovered_again), "second recovery outbox setup")
	_assert_ok(coordinator_2.configure(repo, authority_2, outbox_2), "second recovery coordinator setup")
	var recovery_2: Dictionary = coordinator_2.recover_latest()
	_assert_ok(recovery_2, "recover generation 2")
	var final_snapshot: Dictionary = recovered_again.create_canonical_item_graph_snapshot()
	_assert(_equipment_item(final_snapshot, "a", EquipmentCatalog.SLOT_LOWER).is_empty(), "generation 2 restored stale lower equipment")
	_assert(_equipment_item(final_snapshot, "a", EquipmentCatalog.SLOT_HEAD) == helmet_id, "generation 2 lost unchanged helmet")
	_assert(String(_find_item(final_snapshot, lower_id).get("location", {}).get("kind", "")) == "INVENTORY", "generation 2 lower Item UUID not returned to inventory")
	_assert(_item_count(final_snapshot, lower_id) == 1 and _item_count(final_snapshot, helmet_id) == 1, "successive recovery duplicated equipment items")
	_assert(_all_item_ids_unique(final_snapshot), "successive recovery produced duplicate canonical identities")
	recovered_again.shutdown()
	_remove_tree(root_path)
	_finish()


func _new_service():
	var service = Service.new()
	var setup: Dictionary = service.setup(OWNER, 1, 0, {
		"profile": "MULTIPLAYER_CORE",
		"topology_adapter": "LOOPBACK",
		"region_id": "region/ch9-4/recovery",
		"playable_sandbox": true,
	})
	_assert_ok(setup, "recovery service setup")
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


func _all_item_ids_unique(snapshot: Dictionary) -> bool:
	var seen: Dictionary = {}
	for value in snapshot.get("items", []):
		if not value is Dictionary:
			return false
		var item_id := String(value.get("item_id", ""))
		if item_id.is_empty() or seen.has(item_id):
			return false
		seen[item_id] = true
	return true


func _remove_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name in [".", ".."]:
			continue
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _assert_ok(result: Dictionary, label: String) -> void:
	_assert(bool(result.get("success", false)), "%s failed: %s" % [label, JSON.stringify(result)])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.4 equipment checkpoint reconnect recovery: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.4 equipment checkpoint reconnect recovery: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
