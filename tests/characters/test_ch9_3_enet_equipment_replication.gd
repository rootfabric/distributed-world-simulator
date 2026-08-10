extends SceneTree

const ServerRuntime = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_dedicated_server_runtime.gd")
const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_graphical_client_runtime.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")
const EquipmentProjection = preload("res://scripts/characters/equipment/network_character_equipment_projection.gd")

const READY_TIMEOUT_MS := 15000
const CONVERGENCE_TIMEOUT_MS := 10000

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := 38000 + (OS.get_process_id() % 1200)
	var server = ServerRuntime.new()
	root.add_child(server)
	var server_setup: Dictionary = server.setup({
		"host": "127.0.0.1",
		"port": port,
		"authority_owner_id": "simulation/ch9-3/enet",
		"authority_epoch": 1,
		"playable_sandbox": true,
		"automated_acceptance": true,
	})
	_assert(bool(server_setup.get("success", false)), "CH9.3 ENet server setup failed: %s" % JSON.stringify(server_setup))
	if not bool(server_setup.get("success", false)):
		_finish()
		return

	var client_a = _create_client("a", port)
	var client_b = _create_client("b", port)
	_assert(client_a != null and client_b != null, "CH9.3 ENet client setup failed")
	if client_a == null or client_b == null:
		_finish()
		return

	var both_ready := await _wait_until(func() -> bool:
		return client_a.is_ready() and client_b.is_ready()
	, READY_TIMEOUT_MS)
	_assert(both_ready, "CH9.3 ENet clients did not become ready")
	if not both_ready:
		_finish()
		return

	var initial_converged := await _wait_until(func() -> bool:
		var a: Dictionary = client_a.get_item_graph_snapshot()
		var b: Dictionary = client_b.get_item_graph_snapshot()
		return (
			not a.is_empty()
			and not b.is_empty()
			and String(a.get("checksum", "")) == String(b.get("checksum", ""))
			and not _find_item(a, "item/player/a/wearable/lower").is_empty()
		)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(initial_converged, "CH9.3 ENet initial Item Graph did not converge")

	var lower_id := "item/player/a/wearable/lower"
	var sent: Dictionary = client_a.submit_equipment_command_nonblocking(
		"equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER},
		"operation/ch9-3/enet/a/equip-lower"
	)
	_assert(bool(sent.get("success", false)), "CH9.3 ENet equipment command send failed: %s" % JSON.stringify(sent))

	var equip_converged := await _wait_until(func() -> bool:
		return _clients_converged_on_equipment(client_a, client_b, lower_id, true)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(equip_converged, "CH9.3 ENet equip did not converge on A and B")
	if equip_converged:
		var snapshot_a: Dictionary = client_a.get_item_graph_snapshot()
		var snapshot_b: Dictionary = client_b.get_item_graph_snapshot()
		_assert(String(snapshot_a.get("checksum", "")) == String(snapshot_b.get("checksum", "")), "CH9.3 ENet clients disagree on equipped Item Graph checksum")
		_assert(not JSON.stringify(client_b.get_snapshot()).contains(lower_id), "CH9.3 remote gameplay/movement snapshot leaked equipment Item ID")
		var projection = EquipmentProjection.new()
		var projected: Dictionary = projection.project(snapshot_b, "a")
		_assert(bool(projected.get("success", false)), "CH9.3 B could not project A equipment after ENet replication")
		var character_snapshot = projected.get("details", {}).get("snapshot")
		_assert(character_snapshot is CharacterEquipmentDomain.Snapshot and character_snapshot.find_item(lower_id) != null, "CH9.3 B character projection missing A lower wearable")

	# Late join must receive the same authoritative equipment in JOIN_ACK's full
	# Item Graph snapshot without waiting for a new movement/equipment command.
	var client_c = _create_client("c", port)
	_assert(client_c != null, "CH9.3 late client C setup failed")
	if client_c != null:
		var late_ready := await _wait_until(func() -> bool:
			return client_c.is_ready()
		, READY_TIMEOUT_MS)
		_assert(late_ready, "CH9.3 late client C did not become ready")
		if late_ready:
			var late_converged := await _wait_until(func() -> bool:
				var c: Dictionary = client_c.get_item_graph_snapshot()
				return (
					String(c.get("checksum", "")) == String(client_a.get_item_graph_snapshot().get("checksum", ""))
					and _item_is_equipped(c, lower_id)
				)
			, CONVERGENCE_TIMEOUT_MS)
			_assert(late_converged, "CH9.3 late join did not receive A equipment")
			if late_converged:
				var late_projection = EquipmentProjection.new()
				var late_projected: Dictionary = late_projection.project(client_c.get_item_graph_snapshot(), "a")
				_assert(bool(late_projected.get("success", false)), "CH9.3 late client could not project A equipment")

	var unequip_sent: Dictionary = client_a.submit_equipment_command_nonblocking(
		"equipment.unequip",
		{"item_id": lower_id},
		"operation/ch9-3/enet/a/unequip-lower"
	)
	_assert(bool(unequip_sent.get("success", false)), "CH9.3 ENet unequip command send failed")
	var unequip_converged := await _wait_until(func() -> bool:
		return _clients_converged_on_equipment(client_a, client_b, lower_id, false)
	, CONVERGENCE_TIMEOUT_MS)
	_assert(unequip_converged, "CH9.3 ENet unequip did not converge on A and B")

	var report_a: Dictionary = client_a.get_report()
	var report_b: Dictionary = client_b.get_report()
	_assert(int(report_a.get("item_snapshot_updates", 0)) + int(report_a.get("item_delta_updates", 0)) > 0, "CH9.3 origin client recorded no Item Graph updates")
	_assert(int(report_b.get("item_snapshot_updates", 0)) + int(report_b.get("item_delta_updates", 0)) > 0, "CH9.3 remote client recorded no Item Graph updates")
	_assert(String(report_a.get("last_error_code", "")) == "", "CH9.3 origin client ended with network error: %s" % String(report_a.get("last_error_code", "")))
	_assert(String(report_b.get("last_error_code", "")) == "", "CH9.3 remote client ended with network error: %s" % String(report_b.get("last_error_code", "")))
	_finish()


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


func _clients_converged_on_equipment(client_a, client_b, item_id: String, equipped: bool) -> bool:
	var a: Dictionary = client_a.get_item_graph_snapshot()
	var b: Dictionary = client_b.get_item_graph_snapshot()
	if a.is_empty() or b.is_empty() or String(a.get("checksum", "")) != String(b.get("checksum", "")):
		return false
	return _item_is_equipped(a, item_id) == equipped and _item_is_equipped(b, item_id) == equipped


func _item_is_equipped(snapshot: Dictionary, item_id: String) -> bool:
	var item := _find_item(snapshot, item_id)
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


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		if bool(predicate.call()):
			return true
		await process_frame
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.3 ENet multiplayer equipment replication: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.3 ENet multiplayer equipment replication: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
