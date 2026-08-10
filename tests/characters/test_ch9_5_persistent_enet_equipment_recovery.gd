extends SceneTree

const ServerRuntime = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_5_persistent_dedicated_server_runtime.gd")
const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_graphical_client_runtime.gd")
const PresentationCoordinator = preload("res://scripts/characters/equipment/network_character_equipment_presentation_coordinator.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")

const READY_TIMEOUT_MS := 15000
const CONVERGENCE_TIMEOUT_MS := 10000

var failures: Array[String] = []
var assertions := 0
var persistence_root := ""


class PresenterProbe extends RefCounted:
	var apply_count := 0
	var change_count := 0
	var last_state_fingerprint := ""
	var visible_item_ids: Array[String] = []

	func apply_snapshot(snapshot) -> Dictionary:
		apply_count += 1
		var fingerprint := snapshot.state_fingerprint()
		var changed := fingerprint != last_state_fingerprint
		if changed:
			change_count += 1
		last_state_fingerprint = fingerprint
		visible_item_ids.clear()
		for entry in snapshot.entries():
			visible_item_ids.append(String(entry.item_id))
		visible_item_ids.sort()
		return {
			"success": true,
			"code": "OK",
			"details": {
				"changed": changed,
				"visual_count": visible_item_ids.size(),
				"created": visible_item_ids.size() if changed else 0,
				"removed": 0,
				"reused": visible_item_ids.size() if not changed else 0,
			},
		}

	func clear() -> Dictionary:
		visible_item_ids.clear()
		last_state_fingerprint = ""
		return {"success": true, "code": "OK", "details": {"changed": true}}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	persistence_root = ProjectSettings.globalize_path(
		"user://ch9-5-live-equipment-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_remove_tree(persistence_root)
	var port := 39700 + (OS.get_process_id() % 700)

	var server_1 = _create_server(port)
	if server_1 == null:
		_cleanup_and_finish()
		return
	var first_setup: Dictionary = server_1.get_meta("ch9_5_setup", {})
	_assert(not bool(first_setup.get("details", {}).get("recovered", true)), "fresh CH9.5 server unexpectedly reported recovery")
	_assert(bool(server_1.get_report().get("character_equipment_persistence", false)), "CH9.5 server did not enable equipment persistence")
	_assert(bool(server_1.get_report().get("equipment_recovery_service", false)), "CH9.5 server is not using equipment recovery service")

	var client_a = _create_client("a", port)
	var client_b = _create_client("b", port)
	_assert(client_a != null and client_b != null, "generation 1 clients failed setup")
	if client_a == null or client_b == null:
		_cleanup_and_finish()
		return
	var ready_1 := await _wait_until(func() -> bool:
		return client_a.is_ready() and client_b.is_ready()
	, READY_TIMEOUT_MS)
	_assert(ready_1, "generation 1 clients did not become ready")
	if not ready_1:
		_cleanup_and_finish()
		return

	var initial_converged := await _wait_until(func() -> bool:
		return _same_item_graph(client_a, client_b)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(initial_converged, "generation 1 Item Graph did not converge")

	var coordinator_1 = PresentationCoordinator.new()
	_assert_ok(coordinator_1.setup(client_b), "generation 1 presentation coordinator setup")
	var presenter_1 := PresenterProbe.new()
	_assert_ok(coordinator_1.bind_presenter("a", presenter_1), "generation 1 bind A presenter on B")
	var lower_id := "item/player/a/wearable/lower"
	_assert(presenter_1.visible_item_ids.is_empty(), "A started visually equipped before command")

	var equip_sent: Dictionary = client_a.submit_equipment_command_nonblocking(
		"equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER},
		"operation/ch9-5/live/a/equip-lower"
	)
	_assert_ok(equip_sent, "generation 1 equipment send")
	var equipped_live := await _wait_until(func() -> bool:
		return (
			_same_item_graph(client_a, client_b)
			and _item_is_equipped(client_a.get_item_graph_snapshot(), lower_id)
			and presenter_1.visible_item_ids == [lower_id]
		)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(equipped_live, "generation 1 live equipment/presentation did not converge")
	var generation_1_snapshot: Dictionary = client_a.get_item_graph_snapshot()
	_assert(_item_count(generation_1_snapshot, lower_id) == 1, "generation 1 canonical wearable identity duplicated")
	_assert(not JSON.stringify(client_b.get_snapshot()).contains(lower_id), "movement/gameplay snapshot leaked equipment Item ID")
	var persistence_1: Dictionary = Dictionary(server_1.get_report().get("persistence", {}))
	_assert(int(persistence_1.get("checkpoint_generation", 0)) >= 1, "equipment command produced no M6 checkpoint")
	_assert(not bool(persistence_1.get("fatal_failure", true)), "generation 1 persistence entered fatal state")
	var checkpoint_after_equip := int(persistence_1.get("checkpoint_generation", 0))

	# Stop the authority while clients still exist. They become disconnected, but
	# the server's accepted M6 stop path writes a final checkpoint. Old clients are
	# then frozen and new runtime instances model reconnect after process restart.
	_assert_ok(coordinator_1.stop(false), "generation 1 coordinator stop")
	var stop_1: Dictionary = server_1.stop()
	_assert_ok(stop_1, "generation 1 server stop")
	var disconnected := await _wait_until(func() -> bool:
		return not client_a.is_ready() and not client_b.is_ready()
	, 3000)
	_assert(disconnected, "generation 1 clients did not observe server stop")
	client_a.set_process(false)
	client_b.set_process(false)
	server_1.queue_free()
	for _index in range(4):
		await process_frame

	var server_2 = _create_server(port)
	if server_2 == null:
		_cleanup_and_finish()
		return
	var second_setup: Dictionary = server_2.get_meta("ch9_5_setup", {})
	_assert(bool(second_setup.get("details", {}).get("recovered", false)), "generation 2 server did not recover checkpoint")
	var persistence_2_initial: Dictionary = Dictionary(server_2.get_report().get("persistence", {}))
	_assert(bool(persistence_2_initial.get("recovered", false)), "generation 2 persistence report did not mark recovery")
	_assert(int(persistence_2_initial.get("checkpoint_generation", 0)) >= checkpoint_after_equip, "recovered checkpoint generation regressed")
	_assert(not bool(persistence_2_initial.get("fatal_failure", true)), "generation 2 recovery entered fatal state")

	var client_a2 = _create_client("a", port)
	var client_c = _create_client("c", port)
	_assert(client_a2 != null and client_c != null, "generation 2 reconnect/late client setup failed")
	if client_a2 == null or client_c == null:
		_cleanup_and_finish()
		return
	var ready_2 := await _wait_until(func() -> bool:
		return client_a2.is_ready() and client_c.is_ready()
	, READY_TIMEOUT_MS)
	_assert(ready_2, "generation 2 reconnect/late clients did not become ready")
	if not ready_2:
		_cleanup_and_finish()
		return
	var recovered_live := await _wait_until(func() -> bool:
		return (
			_same_item_graph(client_a2, client_c)
			and _item_is_equipped(client_a2.get_item_graph_snapshot(), lower_id)
			and _item_is_equipped(client_c.get_item_graph_snapshot(), lower_id)
		)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(recovered_live, "reconnect/late join did not receive recovered equipment")
	_assert(_item_count(client_c.get_item_graph_snapshot(), lower_id) == 1, "late join received duplicate wearable identity")

	var coordinator_2 = PresentationCoordinator.new()
	_assert_ok(coordinator_2.setup(client_c), "generation 2 presentation coordinator setup")
	var presenter_2 := PresenterProbe.new()
	_assert_ok(coordinator_2.bind_presenter("a", presenter_2), "generation 2 bind recovered A presenter")
	_assert(presenter_2.visible_item_ids == [lower_id], "recovered equipment did not present immediately on late client")
	var initial_change_count := presenter_2.change_count
	coordinator_2.synchronize(client_c.get_item_graph_snapshot())
	_assert(presenter_2.change_count == initial_change_count, "recovered full snapshot created duplicate presentation state")

	var unequip_sent: Dictionary = client_a2.submit_equipment_command_nonblocking(
		"equipment.unequip",
		{"item_id": lower_id},
		"operation/ch9-5/live/a/unequip-lower-after-recovery"
	)
	_assert_ok(unequip_sent, "post-recovery unequip send")
	var unequipped_live := await _wait_until(func() -> bool:
		return (
			_same_item_graph(client_a2, client_c)
			and not _item_is_equipped(client_a2.get_item_graph_snapshot(), lower_id)
			and presenter_2.visible_item_ids.is_empty()
		)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(unequipped_live, "post-recovery unequip/presentation did not converge")
	var final_snapshot: Dictionary = client_c.get_item_graph_snapshot()
	_assert(_item_count(final_snapshot, lower_id) == 1, "post-recovery unequip duplicated or lost wearable Item UUID")
	_assert(String(_find_item(final_snapshot, lower_id).get("location", {}).get("kind", "")) == "INVENTORY", "post-recovery unequip did not return same UUID to inventory")
	_assert(not JSON.stringify(client_c.get_snapshot()).contains(lower_id), "generation 2 movement/gameplay snapshot leaked equipment Item ID")
	var presentation_report: Dictionary = coordinator_2.create_report()
	_assert(int(presentation_report.get("projection_failures", -1)) == 0, "live presentation coordinator recorded projection failure")
	_assert(int(presentation_report.get("presentation_failures", -1)) == 0, "live presentation coordinator recorded presenter failure")
	var persistence_2_final: Dictionary = Dictionary(server_2.get_report().get("persistence", {}))
	_assert(int(persistence_2_final.get("checkpoint_generation", 0)) > int(persistence_2_initial.get("checkpoint_generation", 0)), "post-recovery equipment mutation was not durably checkpointed")
	_assert(not bool(persistence_2_final.get("fatal_failure", true)), "generation 2 persistence ended fatal")

	coordinator_2.stop(false)
	server_2.stop()
	_cleanup_and_finish()


func _create_server(port: int):
	var server = ServerRuntime.new()
	root.add_child(server)
	var setup: Dictionary = server.setup({
		"host": "127.0.0.1",
		"port": port,
		"authority_owner_id": "simulation/ch9-5/live",
		"authority_epoch": 1,
		"persistence_root": persistence_root,
		"playable_sandbox": true,
		"automated_acceptance": true,
	})
	server.set_meta("ch9_5_setup", setup.duplicate(true))
	_assert_ok(setup, "persistent server setup")
	if not bool(setup.get("success", false)):
		server.queue_free()
		return null
	return server


func _create_client(logical_player_id: String, port: int):
	var client = ClientRuntime.new()
	root.add_child(client)
	var setup: Dictionary = client.setup({
		"host": "127.0.0.1",
		"port": port,
		"logical_player_id": logical_player_id,
		"playable_sandbox": true,
		"automated_acceptance": true,
		"connect_timeout_ms": READY_TIMEOUT_MS,
		"command_timeout_ms": CONVERGENCE_TIMEOUT_MS,
	})
	if not bool(setup.get("success", false)):
		client.queue_free()
		return null
	return client


func _same_item_graph(left, right) -> bool:
	var a: Dictionary = left.get_item_graph_snapshot()
	var b: Dictionary = right.get_item_graph_snapshot()
	return not a.is_empty() and not b.is_empty() and String(a.get("checksum", "")) == String(b.get("checksum", ""))


func _item_is_equipped(snapshot: Dictionary, item_id: String) -> bool:
	var item: Dictionary = _find_item(snapshot, item_id)
	var location: Dictionary = Dictionary(item.get("location", {}))
	return (
		String(location.get("kind", "")) == "CONTAINER"
		and String(location.get("container_id", "")) == EquipmentCatalog.equipment_container_id("a")
		and int(location.get("slot_index", -1)) == EquipmentCatalog.SLOT_LOWER
	)


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value).duplicate(true)
	return {}


func _item_count(snapshot: Dictionary, item_id: String) -> int:
	var count := 0
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			count += 1
	return count


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
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


func _cleanup_and_finish() -> void:
	_remove_tree(persistence_root)
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("CH9.5 persistent ENet equipment recovery composition: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.5 persistent ENet equipment recovery composition: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
