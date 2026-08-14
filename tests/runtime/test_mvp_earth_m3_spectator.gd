extends SceneTree

const EarthAppScript = preload("res://scripts/app/earth_app.gd")

var failures: Array[String] = []
var assertions: int = 0


class FakeM3Client:
	extends Node

	signal replica_updated(snapshot: Dictionary)
	signal item_graph_updated(snapshot: Dictionary)

	var snapshot: Dictionary = {}
	var item_graph_snapshot: Dictionary = {}
	var moves: Array[Vector2] = []

	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func get_local_player_id() -> String:
		return "a"

	func get_item_graph_snapshot() -> Dictionary:
		return item_graph_snapshot.duplicate(true)

	func move_blocking(x: float, z: float) -> Dictionary:
		moves.append(Vector2(x, z))
		return {"success": true, "error_code": ""}

	func move_nonblocking(x: float, z: float) -> Dictionary:
		moves.append(Vector2(x, z))
		return {"success": true, "error_code": ""}

	func is_automated_acceptance() -> bool:
		return true

	func execute_item_command_blocking(
		command_type: String, _payload: Dictionary, _operation_id: String = ""
	) -> Dictionary:
		item_graph_snapshot["revision"] = int(item_graph_snapshot.get("revision", 0)) + 1
		item_graph_updated.emit(get_item_graph_snapshot())
		return {"success": command_type == "item.pickup", "error_code": "" if command_type == "item.pickup" else "TEST_UNSUPPORTED_COMMAND"}


func _init() -> void:
	_run()


func _run() -> void:
	var earth = EarthAppScript.new()
	earth.configure_runtime({
		"runtime_role": "game-client",
		"presentation_enabled": true,
		"local_input_enabled": true,
		"world_definition": {"id": "earth", "display_name": "Earth"},
	})
	root.add_child(earth)
	await process_frame
	await process_frame
	_assert(bool(earth.initialized), "Earth procedural spectator initialized")
	var client := FakeM3Client.new()
	client.snapshot = _snapshot(0.0, 0.0, true)
	client.item_graph_snapshot = {"revision": 0, "checksum": "earth-item-0"}
	root.add_child(client)
	var attached: Dictionary = earth.attach_m3_multiplayer_client(client)
	_assert(bool(attached.get("success", false)), "M3 client attached to Earth spectator")
	_assert(not earth.earth_explorer.is_physics_processing(), "authoritative replica owns translation physics")
	_assert(earth.earth_explorer.is_processing_unhandled_input(), "network spectator keeps local mouse-look input")

	var initial: Vector3 = earth.earth_explorer.get_frame_position()
	var initial_orientation: Basis = earth.earth_explorer.orientation
	var local_yaw := Basis(initial_orientation.y.normalized(), 0.25)
	earth.earth_explorer.orientation = (local_yaw * initial_orientation).orthonormalized()
	earth.earth_explorer.global_transform = Transform3D(earth.earth_explorer.orientation, Vector3.ZERO)
	var looked_forward: Vector3 = (-earth.earth_explorer.orientation.z).normalized()

	client.snapshot = _snapshot(12.0, -8.0, true)
	client.replica_updated.emit(client.get_snapshot())
	await process_frame
	var moved: Vector3 = earth.earth_explorer.get_frame_position()
	_assert(moved.distance_to(initial) > 1.0, "authoritative M3 x/z moves Earth spectator")
	var after_snapshot_forward: Vector3 = (-earth.earth_explorer.orientation.z).normalized()
	_assert(after_snapshot_forward.dot(looked_forward) > 0.99, "authoritative snapshot preserves local camera look")
	var altitude: float = earth.earth_world.get_canonical_spawn_altitude_m()
	_assert(absf(earth.earth_world.get_altitude(moved) - altitude) < 0.1, "mapped spectator retains canonical altitude")
	var report: Dictionary = earth.create_m3_graphical_client_report()
	_assert(String(report.get("world_id", "")) == "earth", "Earth report identifies world")
	_assert(bool(report.get("spectator_ready", false)), "Earth spectator is active")
	_assert(bool(report.get("network_replica_mode", false)), "Earth spectator is replica-driven")
	_assert(int(report.get("m4_item_graph_revision", -1)) == 0, "Earth received canonical M4 item graph")
	_assert(int(report.get("remote_presenter_count", 0)) == 1, "remote M3 participant has presenter")
	var remote: Dictionary = Dictionary(report.get("remote_presenters", {}).get("b", {}))
	_assert(not bool(remote.get("input_authority", true)), "remote presenter has no input authority")
	var remote_earth_position: Array = remote.get("earth_mapped_position", [])
	_assert(remote_earth_position.size() == 3, "remote presenter reports Earth-mapped position")
	if remote_earth_position.size() == 3:
		var remote_position := Vector3(
			float(remote_earth_position[0]), float(remote_earth_position[1]), float(remote_earth_position[2])
		)
		_assert(absf(earth.earth_world.get_altitude(remote_position) - altitude) < 0.1, "remote spectator retains canonical altitude")
	var move_result: Dictionary = earth.m3_apply_test_input_offset(Vector3(1.0, 0.0, 2.0))
	_assert(bool(move_result.get("success", false)) and client.moves.size() == 1, "Earth routes test movement to M3 client")
	var pickup: Dictionary = earth.m4_execute_item_command("item.pickup", {"item_id": "item/shared/beacon/1"}, "operation/test/earth/pickup/1")
	_assert(bool(pickup.get("success", false)), "Earth routes pickup to canonical M4 authority")
	report = earth.create_m3_graphical_client_report()
	_assert(int(report.get("m4_item_graph_revision", -1)) == 1, "Earth receives canonical item mutation")
	_assert(int(report.get("m4_item_commands", 0)) == 1 and int(report.get("m4_item_rejections", -1)) == 0, "Earth has no private item authority")
	earth.queue_free()
	client.queue_free()
	await process_frame
	print("MVP Earth M3 spectator: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _snapshot(x: float, z: float, remote_connected: bool) -> Dictionary:
	return {
		"authority_epoch": 1,
		"server_tick": 10,
		"revision": 10,
		"checksum": "earth-m3-test",
		"players": [
			_player("a", x, z, true),
			_player("b", -2.0, 3.0, remote_connected),
		],
	}


func _player(logical_id: String, x: float, z: float, connected: bool) -> Dictionary:
	return {
		"logical_player_id": logical_id,
		"player_entity_id": "player/%s" % logical_id,
		"transport_session_id": "transport-session/test/%s" % logical_id,
		"ownership_epoch": 1,
		"connected": connected,
		"position": {"x": x, "y": 0.0, "z": z},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"inventory": [],
		"last_input_sequence": 0,
		"state_revision": 10,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)
