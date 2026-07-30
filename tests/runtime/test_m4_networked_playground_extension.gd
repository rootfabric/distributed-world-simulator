extends SceneTree

const PlaygroundRuntime = preload(
	"res://scripts/world/testing/playground_runtime.gd"
)
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var failures: Array[String] = []
var assertions := 0


class FakeM4ClientRuntime:
	extends RefCounted

	signal replica_updated(snapshot: Dictionary)
	signal item_graph_updated(snapshot: Dictionary)

	var gameplay_snapshot: Dictionary = {
		"checksum": "gameplay-checksum-initial",
		"players": [
			{
				"logical_player_id": "a",
				"player_entity_id": "player/a",
				"connected": true,
				"position": {"x": -2.0, "y": 0.0, "z": 0.0},
				"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
				"state_revision": 1,
			},
			{
				"logical_player_id": "b",
				"player_entity_id": "player/b",
				"connected": true,
				"position": {"x": 2.0, "y": 0.0, "z": 0.0},
				"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
				"state_revision": 1,
			},
		],
	}
	var item_snapshot: Dictionary = {}
	var commands: Array[Dictionary] = []
	var movement_deltas: Array[Vector2] = []
	var automated_acceptance := true

	func get_snapshot() -> Dictionary:
		return gameplay_snapshot.duplicate(true)

	func get_item_graph_snapshot() -> Dictionary:
		return item_snapshot.duplicate(true)

	func get_local_player_id() -> String:
		return "a"

	func move_blocking(delta_x: float, delta_z: float) -> Dictionary:
		return {
			"success": true,
			"delta_x": delta_x,
			"delta_z": delta_z,
		}

	func move_nonblocking(delta_x: float, delta_z: float) -> Dictionary:
		movement_deltas.append(Vector2(delta_x, delta_z))
		return {"success": true, "delta_x": delta_x, "delta_z": delta_z}

	func execute_item_command_blocking(
		command_type: String,
		payload: Dictionary,
		operation_id: String = ""
	) -> Dictionary:
		commands.append({
			"command_type": command_type,
			"payload": payload.duplicate(true),
			"operation_id": operation_id,
		})
		item_snapshot["revision"] = int(item_snapshot.get("revision", 0)) + 1
		item_snapshot["tick"] = int(item_snapshot.get("tick", 0)) + 1
		var body := item_snapshot.duplicate(true)
		body.erase("checksum")
		item_snapshot["checksum"] = NetworkUtils.payload_hash(body)
		item_graph_updated.emit(item_snapshot.duplicate(true))
		return {"success": true, "error_code": ""}

	func is_automated_acceptance() -> bool:
		return automated_acceptance


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var runtime = PlaygroundRuntime.new()
	runtime.configure_runtime({
		"runtime_role": "game-client",
		"presentation_enabled": true,
		"local_input_enabled": true,
		"world_definition": {
			"id": "playground",
			"options": {"spawn": [0.0, 1.2, 6.0]},
		},
	})
	root.add_child(runtime)
	await process_frame
	await process_frame
	_assert(
		Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"graphical client starts with a visible cursor for native window movement"
	)

	var invalid_attach: Dictionary = runtime.attach_m3_multiplayer_client(null)
	_assert(
		String(invalid_attach.get("error_code", "")) == "INVALID_M3_CLIENT_RUNTIME",
		"null M3 runtime rejected"
	)

	var client := FakeM4ClientRuntime.new()
	client.item_snapshot = _create_item_snapshot()
	var initial_item_checksum := String(client.item_snapshot.get("checksum", ""))
	var attached: Dictionary = runtime.attach_m3_multiplayer_client(client)
	_assert(bool(attached.get("success", false)), "M4 playground client attached")
	var initial: Dictionary = runtime.create_m3_graphical_client_report()
	_assert(String(initial.get("world_id", "")) == "playground", "playground report identity")
	_assert(bool(initial.get("network_replica_mode", false)), "local player is replica-driven")
	_assert(int(initial.get("remote_presenter_count", 0)) == 1, "remote player presenter spawned")
	_assert(
		String(initial.get("m4_item_graph_checksum", "")) == initial_item_checksum,
		"initial M4 Item Graph replica applied"
	)
	client.automated_acceptance = false
	var camera_yaw := runtime.player.get_node_or_null("CameraAnchor/CameraYaw") as Node3D
	_assert(camera_yaw != null, "playground camera yaw node is available")
	if camera_yaw != null:
		camera_yaw.rotation.y = PI * 0.5
		Input.action_press("move_forward")
		runtime._apply_m3_network_input(0.06)
		Input.action_release("move_forward")
		_assert(client.movement_deltas.size() == 1, "forward input reached M3 client runtime")
		if client.movement_deltas.size() == 1:
			var forward_delta: Vector2 = client.movement_deltas[0]
			_assert(
				absf(forward_delta.x) > absf(forward_delta.y),
				"forward input follows camera direction instead of fixed world Z"
			)
	client.automated_acceptance = true

	var move: Dictionary = runtime.m3_apply_test_input_offset(Vector3(0.5, 0.0, -0.25))
	_assert(bool(move.get("success", false)), "authoritative playground movement routed")

	var item_result: Dictionary = runtime.m4_execute_item_command(
		"item.pickup",
		{"item_id": "item/shared/beacon/1"},
		"operation/test/playground/pickup"
	)
	_assert(bool(item_result.get("success", false)), "M4 item command routed")
	_assert(client.commands.size() == 1, "one M4 command reached client runtime")
	_assert(
		String(client.commands[0].get("command_type", "")) == "item.pickup",
		"M4 command type preserved"
	)
	var after_item: Dictionary = runtime.create_m3_graphical_client_report()
	_assert(int(after_item.get("m4_item_graph_revision", 0)) == 1, "M4 revision updated")
	_assert(
		String(after_item.get("m4_item_graph_checksum", "")) == String(client.item_snapshot.get("checksum", "")),
		"M4 checksum updated"
	)

	client.gameplay_snapshot["players"] = [client.gameplay_snapshot["players"][0]]
	client.gameplay_snapshot["checksum"] = "gameplay-checksum-after-leave"
	client.replica_updated.emit(client.gameplay_snapshot.duplicate(true))
	await process_frame
	var after_leave: Dictionary = runtime.create_m3_graphical_client_report()
	_assert(int(after_leave.get("remote_presenter_count", -1)) == 0, "remote player despawned")
	_assert(int(after_leave.get("remote_despawn_count", 0)) == 1, "remote despawn counted")

	runtime.prepare_for_unload()
	runtime.queue_free()
	await process_frame
	_finish()


func _create_item_snapshot() -> Dictionary:
	var snapshot := {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "authority/test/playground",
		"authority_epoch": 1,
		"revision": 0,
		"tick": 0,
		"items": [],
		"inventories": {
			"a": {"inventory": [], "hotbar": [], "selected_hotbar_index": 0},
			"b": {"inventory": [], "hotbar": [], "selected_hotbar_index": 0},
		},
		"containers": [],
		"mounts": [],
		"open_containers": {},
	}
	snapshot["checksum"] = NetworkUtils.payload_hash(snapshot)
	return snapshot


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print(
		"M4 networked playground extension: %d assertions, %d failures"
		% [assertions, failures.size()]
	)
	quit(0 if failures.is_empty() else 1)
