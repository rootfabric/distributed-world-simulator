extends SceneTree

const EarthAppScript = preload("res://scripts/app/earth_mvp_app.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var failures: Array[String] = []
var assertions: int = 0


class FakeM3Client:
	extends Node
	const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

	signal replica_updated(snapshot: Dictionary)
	signal item_graph_updated(snapshot: Dictionary)
	signal prediction_updated(
		predicted_state: Dictionary,
		presentation_state: Dictionary,
		report: Dictionary
	)
	signal construction_updated(bundle: Dictionary)

	var snapshot: Dictionary = {}
	var item_graph_snapshot: Dictionary = {}
	var moves: Array[Vector2] = []
	var prediction_calls: int = 0

	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func get_local_player_id() -> String:
		return "a"

	func get_item_graph_snapshot() -> Dictionary:
		return item_graph_snapshot.duplicate(true)

	func get_construction_session() -> Dictionary:
		return {}

	func get_construction_bundle() -> Dictionary:
		return {}

	func execute_construction_command_blocking(_command: Dictionary) -> Dictionary:
		return {"success": false, "error_code": "TEST_CONSTRUCTION_NOT_CONFIGURED"}

	func move_blocking(x: float, z: float) -> Dictionary:
		moves.append(Vector2(x, z))
		return {"success": true, "error_code": ""}

	func move_nonblocking(x: float, z: float) -> Dictionary:
		moves.append(Vector2(x, z))
		return {"success": true, "error_code": ""}

	func advance_local_prediction(intent: Dictionary, delta: float) -> Dictionary:
		prediction_calls += 1
		var local_player: Dictionary = {}
		for player_value in snapshot.get("players", []):
			if (
				player_value is Dictionary
				and String(player_value.get("logical_player_id", "")) == "a"
			):
				local_player = Dictionary(player_value).duplicate(true)
				break
		if local_player.is_empty():
			return {"success": false, "error_code": "TEST_PLAYER_MISSING"}
		var position: Dictionary = Dictionary(local_player.get("position", {})).duplicate(true)
		position["x"] = float(position.get("x", 0.0)) + float(intent.get("move_x", 0.0)) * delta
		position["z"] = float(position.get("z", 0.0)) - float(intent.get("move_z", 0.0)) * delta
		local_player["position"] = position
		prediction_updated.emit(local_player, local_player, {"test": true})
		return {
			"success": true,
			"error_code": "",
			"details": {"presentation_state": local_player},
		}

	func is_automated_acceptance() -> bool:
		return true

	func execute_item_command_blocking(
		command_type: String, _payload: Dictionary, _operation_id: String = ""
	) -> Dictionary:
		item_graph_snapshot["revision"] = int(item_graph_snapshot.get("revision", 0)) + 1
		item_graph_snapshot["tick"] = int(item_graph_snapshot.get("tick", 0)) + 1
		var canonical := item_graph_snapshot.duplicate(true)
		canonical.erase("checksum")
		item_graph_snapshot["checksum"] = Utils.payload_hash(canonical)
		item_graph_updated.emit(get_item_graph_snapshot())
		return {
			"success": command_type == "item.pickup",
			"error_code": "" if command_type == "item.pickup" else "TEST_UNSUPPORTED_COMMAND",
		}


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
	_assert(bool(earth.initialized), "Earth procedural MVP initialized")

	var client := FakeM3Client.new()
	client.snapshot = _snapshot(0.0, 0.0, true)
	client.item_graph_snapshot = _item_graph_snapshot(0)
	root.add_child(client)
	var attached: Dictionary = earth.attach_m3_multiplayer_client(client)
	_assert(bool(attached.get("success", false)), "M3 client attached to playable Earth MVP")
	_assert(not earth.earth_explorer.is_physics_processing(), "authoritative replica owns translation physics")
	_assert(earth.earth_explorer.is_processing_unhandled_input(), "network MVP keeps local mouse-look input")

	var initial: Vector3 = earth.earth_explorer.get_frame_position()
	var initial_orientation: Basis = earth.earth_explorer.orientation
	var local_yaw := Basis(initial_orientation.y.normalized(), 0.25)
	earth.earth_explorer.orientation = (local_yaw * initial_orientation).orthonormalized()
	earth.earth_explorer.global_transform = Transform3D(
		earth.earth_explorer.orientation,
		Vector3.ZERO
	)
	# Network-replica presentation preserves the cached Earth-relative view.
	# The old fixture changed orientation directly but never synchronized that
	# cache, so it did not model a real local mouse-look update.
	earth.earth_explorer._sync_network_surface_view_from_orientation()
	var looked_yaw: float = earth.earth_explorer.get_surface_relative_yaw()

	# Raw authoritative snapshots reconcile the NX4 runtime but must not snap the
	# Earth presentation after the initial seed.
	client.snapshot = _snapshot(12.0, -8.0, true)
	client.replica_updated.emit(client.get_snapshot())
	await process_frame
	var after_raw_snapshot: Vector3 = earth.earth_explorer.get_frame_position()
	_assert(
		after_raw_snapshot.distance_to(initial) < 0.01,
		"raw authoritative snapshot does not snap predicted Earth presentation"
	)

	var presentation_player: Dictionary = _player("a", 12.0, -8.0, true)
	client.prediction_updated.emit(
		presentation_player,
		presentation_player,
		{"correction_mode": "SMOOTH"}
	)
	await process_frame
	var moved: Vector3 = earth.earth_explorer.get_frame_position()
	_assert(moved.distance_to(initial) > 1.0, "NX4 presentation state moves Earth player")
	var after_prediction_yaw: float = earth.earth_explorer.get_surface_relative_yaw()
	_assert(
		absf(wrapf(after_prediction_yaw - looked_yaw, -PI, PI)) < 0.001,
		"predicted Earth movement preserves Earth-relative camera look"
	)

	var report: Dictionary = earth.create_m3_graphical_client_report()
	var playable_altitude := float(report.get("playable_surface_eye_altitude_m", -1.0))
	_assert(
		absf(earth.earth_world.get_altitude(moved) - playable_altitude) < 0.1,
		"playable player stays at terrain eye height"
	)
	_assert(String(report.get("world_id", "")) == "earth", "Earth report identifies world")
	_assert(bool(report.get("spectator_ready", false)), "Earth MVP player is active")
	_assert(bool(report.get("network_replica_mode", false)), "Earth MVP remains replica-driven")
	_assert(bool(report.get("prediction_enabled", false)), "Earth MVP consumes NX4 prediction")
	_assert(
		String(report.get("presentation_mode", "")) == "NX4_PREDICTED_EARTH_SURFACE",
		"Earth MVP reports predicted surface presentation"
	)
	_assert(
		String(report.get("playable_surface_biome", "ocean")) != "ocean",
		"Earth MVP selects a deterministic land biome"
	)
	_assert(int(report.get("m4_item_graph_revision", -1)) == 0, "Earth received canonical M4 item graph")
	_assert(int(report.get("remote_presenter_count", 0)) == 1, "remote M3 participant has presenter")

	var remote: Dictionary = Dictionary(report.get("remote_presenters", {}).get("b", {}))
	_assert(not bool(remote.get("input_authority", true)), "remote presenter has no input authority")
	var remote_earth_position: Array = remote.get("earth_mapped_position", [])
	_assert(remote_earth_position.size() == 3, "remote presenter reports Earth-mapped position")
	if remote_earth_position.size() == 3:
		var remote_position := Vector3(
			float(remote_earth_position[0]),
			float(remote_earth_position[1]),
			float(remote_earth_position[2])
		)
		_assert(
			absf(earth.earth_world.get_altitude(remote_position) - playable_altitude) < 0.1,
			"remote presenter is mapped to playable surface height"
		)
		var remote_presenter = earth._m3_remote_presenters.get("b")
		_assert(
			remote_presenter != null
			and remote_presenter.basis.y.normalized().dot(remote_position.normalized()) > 0.999,
			"remote capsule local Y follows Earth surface normal"
		)

	var move_result: Dictionary = earth.m3_apply_test_input_offset(
		Vector3(1.0, 0.0, 2.0)
	)
	_assert(
		bool(move_result.get("success", false)) and client.moves.size() == 1,
		"Earth routes explicit test movement to M3 client"
	)
	var pickup: Dictionary = earth.m4_execute_item_command(
		"item.pickup",
		{"item_id": "item/shared/beacon/1"},
		"operation/test/earth/pickup/1"
	)
	_assert(bool(pickup.get("success", false)), "Earth routes pickup to canonical M4 authority")
	report = earth.create_m3_graphical_client_report()
	_assert(int(report.get("m4_item_graph_revision", -1)) == 1, "Earth receives canonical item mutation")
	_assert(
		int(report.get("m4_item_commands", 0)) == 1
		and int(report.get("m4_item_rejections", -1)) == 0,
		"Earth has no private item authority"
	)

	earth.queue_free()
	client.queue_free()
	await process_frame
	print("MVP Earth M3 spectator: %d assertions, %d failures" % [
		assertions,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)


func _item_graph_snapshot(revision: int) -> Dictionary:
	var snapshot := {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "authority/test/earth-m3",
		"authority_epoch": 1,
		"revision": revision,
		"tick": revision,
		"items": [],
		"inventories": {
			"a": {
				"inventory": [],
				"hotbar": ["", "", "", "", "", "", "", ""],
				"selected_hotbar_index": 0,
			},
		},
		"containers": [],
		"mounts": [],
		"open_containers": {},
		"checksum": "",
	}
	snapshot["checksum"] = _snapshot_checksum(snapshot)
	return snapshot


func _snapshot_checksum(snapshot: Dictionary) -> String:
	var canonical := snapshot.duplicate(true)
	canonical.erase("checksum")
	return NetworkUtils.payload_hash(canonical)


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
