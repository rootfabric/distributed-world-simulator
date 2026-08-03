extends SceneTree

const PlaygroundRuntime = preload("res://scripts/world/testing/playground_runtime.gd")
const GameplayService = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const SimulatorApp = preload("res://scripts/app/simulator_app.gd")

var assertions := 0
var failures: Array[String] = []


class ServiceBackedClient:
	extends RefCounted

	signal replica_updated(snapshot: Dictionary)
	signal item_graph_updated(snapshot: Dictionary)
	signal prediction_updated(predicted_state: Dictionary, presentation_state: Dictionary, report: Dictionary)

	var service
	var logical_player_id := "a"
	var transport_session_id := "transport-session/m7/contracts/a"
	var ownership_epoch := 1
	var input_sequence := 0
	var operation_sequence := 0

	func setup() -> Dictionary:
		service = GameplayService.new()
		var configured: Dictionary = service.setup("authority/m7/playground", 1, 0, {
			"profile": GameplayService.PROFILE_MULTIPLAYER_CORE,
			"topology_adapter": "ENET",
			"region_id": "region/m7/playground",
			"playable_sandbox": true,
		})
		if not bool(configured.get("success", false)):
			return configured
		var joined: Dictionary = service.join(logical_player_id, transport_session_id, "operation/m7/contracts/join")
		if not bool(joined.get("success", false)):
			return joined
		ownership_epoch = int(joined.get("details", {}).get("player", {}).get("ownership_epoch", 1))
		return {"success": true, "error_code": ""}

	func get_snapshot() -> Dictionary:
		return service.create_snapshot()

	func get_item_graph_snapshot() -> Dictionary:
		return service.create_canonical_item_graph_snapshot()

	func get_local_player_id() -> String:
		return logical_player_id

	func move_blocking(delta_x: float, delta_z: float) -> Dictionary:
		input_sequence += 1
		operation_sequence += 1
		var result: Dictionary = service.move_player(
			logical_player_id, transport_session_id, ownership_epoch, input_sequence,
			delta_x, delta_z, "operation/m7/contracts/move/%d" % operation_sequence
		)
		if bool(result.get("success", false)):
			replica_updated.emit(service.create_snapshot())
		return result

	func move_nonblocking(delta_x: float, delta_z: float) -> Dictionary:
		return move_blocking(delta_x, delta_z)

	func submit_movement_intent_nonblocking(intent: Dictionary, _client_tick: int = 0) -> Dictionary:
		return submit_movement_intent_blocking(intent)

	func advance_local_prediction(intent: Dictionary, _frame_delta_seconds: float) -> Dictionary:
		var result: Dictionary = submit_movement_intent_blocking(intent)
		var player: Dictionary = service.get_player(logical_player_id)
		prediction_updated.emit(player, player, {
			"configured": true,
			"reconciliations": 0,
			"history_size": 1,
		})
		return {
			"success": bool(result.get("success", false)),
			"error_code": String(result.get("error_code", "")),
			"details": {
				"predicted_state": player,
				"presentation_state": player,
			},
		}

	func is_prediction_ready() -> bool:
		return true

	func submit_movement_intent_blocking(intent: Dictionary) -> Dictionary:
		input_sequence += 1
		operation_sequence += 1
		var result: Dictionary = service.submit_movement_intent(
			logical_player_id, transport_session_id, ownership_epoch, input_sequence,
			intent, "operation/m7/contracts/input/%d" % operation_sequence
		)
		if bool(result.get("success", false)):
			replica_updated.emit(service.create_snapshot())
		return result

	func submit_player_state_nonblocking(player_state: Dictionary, delta_seconds: float) -> Dictionary:
		input_sequence += 1
		operation_sequence += 1
		var candidate := player_state.duplicate(true)
		candidate["last_input_sequence"] = input_sequence
		return service.submit_player_state(
			logical_player_id, transport_session_id, ownership_epoch, input_sequence,
			candidate, delta_seconds, "operation/m7/contracts/forbidden-state/%d" % operation_sequence
		)

	func execute_item_command_blocking(command_type: String, payload: Dictionary, operation_id: String = "") -> Dictionary:
		operation_sequence += 1
		var resolved_operation := operation_id
		if resolved_operation.is_empty():
			resolved_operation = "operation/m7/contracts/item/%d" % operation_sequence
		var result: Dictionary = service.handle_canonical_item_command(
			logical_player_id, transport_session_id, ownership_epoch,
			resolved_operation, command_type, payload
		)
		if bool(result.get("success", false)):
			item_graph_updated.emit(service.create_canonical_item_graph_snapshot())
		return result

	func is_automated_acceptance() -> bool:
		return false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest_value = JSON.parse_string(
		FileAccess.get_file_as_string("res://config/network/playable-networked-playground.v1.json")
	)
	_assert(manifest_value is Dictionary, "M7 playable manifest is valid JSON")
	var manifest: Dictionary = Dictionary(manifest_value) if manifest_value is Dictionary else {}
	_assert(String(manifest.get("checkpoint", "")) == "v16.10.6.1-testing-m7-playable-networked-playground", "M7 manifest checkpoint is current")
	_assert(String(manifest.get("base_checkpoint", "")) == "v16.10.6-architecture-a3-single-server-multiplayer", "M7 manifest preserves accepted A3 base")
	_assert(String(manifest.get("world_id", "")) == "playground", "M7 manifest selects playground")
	_assert(SimulatorApp.M7_CHECKPOINT == String(manifest.get("checkpoint", "")), "M7 runtime identity matches manifest")
	for required_path in [
		"res://PLAY_M7_NETWORKED_PLAYGROUND.ps1",
		"res://START_M7_NETWORK_SERVER.ps1",
		"res://START_M7_NETWORK_CLIENT.ps1",
		"res://WATCH_M7_NETWORK_LOG.ps1",
		"res://STOP_M7_NETWORK_DEBUG.ps1",
		"res://STOP_M7_NETWORKED_PLAYGROUND.ps1",
		"res://PLAY_M7_NETWORKED_PLAYGROUND.sh",
		"res://STOP_M7_NETWORKED_PLAYGROUND.sh",
		"res://RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.ps1",
		"res://RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.sh",
	]:
		_assert(FileAccess.file_exists(required_path), "M7 delivery includes %s" % required_path.get_file())

	var debug_client_launcher := FileAccess.get_file_as_string("res://START_M7_NETWORK_CLIENT.ps1")
	_assert(debug_client_launcher.contains("Get-Process -Id $ServerPid"), "debug client rejects stale server process descriptors")
	_assert(debug_client_launcher.contains("--network-debug-stay-open"), "debug client remains open after disconnect")
	_assert(debug_client_launcher.contains("server/process.json"), "debug client validates the matching server process descriptor")
	var debug_server_launcher := FileAccess.get_file_as_string("res://START_M7_NETWORK_SERVER.ps1")
	_assert(debug_server_launcher.contains("server-state.json"), "debug server exposes a machine-readable state file")
	_assert(debug_server_launcher.contains("godot.log"), "debug server persists its dedicated log")

	var client := ServiceBackedClient.new()
	var client_setup: Dictionary = client.setup()
	_assert(bool(client_setup.get("success", false)), "M7 service-backed client configured")
	if not bool(client_setup.get("success", false)):
		_finish()
		return
	var runtime = PlaygroundRuntime.new()
	runtime.configure_runtime({
		"runtime_role": "game-client",
		"presentation_enabled": true,
		"local_input_enabled": true,
		"universe_id": "main",
		"instance_id": "m7-contract-playground",
		"launch_options": {"network_playground": true},
		"world_definition": {
			"id": "playground",
			"options": {"spawn": [0.0, 1.2, 6.0]},
		},
	})
	root.add_child(runtime)
	await process_frame
	await process_frame
	var attached: Dictionary = runtime.attach_m3_multiplayer_client(client)
	_assert(bool(attached.get("success", false)), "M7 playable network runtime attached")
	if not bool(attached.get("success", false)):
		runtime.queue_free()
		await process_frame
		_finish()
		return
	await process_frame
	await process_frame
	var report: Dictionary = runtime.create_m3_graphical_client_report()
	_assert(bool(report.get("network_playground_enabled", false)), "M7 network playground profile enabled")
	_assert(bool(report.get("network_prediction_mode", false)), "client-side movement prediction is enabled")
	_assert(String(report.get("m7_interpolation_mode", "")) == "CLIENT_PREDICTION_RECONCILIATION", "prediction/reconciliation presentation is enabled")
	_assert(bool(report.get("seven_days_inventory_active", false)), "Seven Days inventory profile active")
	_assert(runtime.item_gameplay != null, "real ItemGameplayController is attached")
	_assert(runtime.m5_networked_inventory_shell == null, "legacy M5 inventory shell is not used")
	_assert(runtime.world_interactor != null and runtime.world_interactor.is_enabled(), "3D world interaction is enabled")
	_assert(runtime.item_gameplay.inventory_ui != null, "Seven Days inventory UI exists")
	_assert(runtime.item_gameplay.presenter != null, "3D item presentation exists")

	var before_player: Dictionary = client.service.get_player("a")
	var forbidden_state: Dictionary = client.submit_player_state_nonblocking(runtime._create_m7_player_state(), 0.06)
	_assert(not bool(forbidden_state.get("success", true)) and String(forbidden_state.get("error_code", "")) == "CLIENT_AUTHORITATIVE_STATE_FORBIDDEN", "client-authored position is rejected")
	var after_forbidden: Dictionary = client.service.get_player("a")
	_assert(Dictionary(after_forbidden.get("position", {})) == Dictionary(before_player.get("position", {})), "rejected client state cannot move authority")
	var far_pickup: Dictionary = client.service.handle_canonical_item_command(
		"a", client.transport_session_id, client.ownership_epoch,
		"operation/m7/contracts/far-pickup", "item.pickup", {"item_id":"item/shared/beacon/1"}
	)
	_assert(not bool(far_pickup.get("success", true)) and String(far_pickup.get("error_code", "")) in ["ITEM_INTERACTION_OUT_OF_RANGE", "ITEM_NOT_VISIBLE_TO_PLAYER", "ITEM_INTERACTION_OCCLUDED"], "server rejects remote pickup before movement")
	var bridge_rejection: Dictionary = runtime._m7_item_bridge.submit_item_command(
		"item.pickup", {"item_id": "item/shared/beacon/1"}, "operation/m7/contracts/bridge-far-pickup"
	)
	_assert(not bool(bridge_rejection.get("success", true)), "item bridge preserves the server-side pickup rejection")
	_assert(not String(bridge_rejection.get("message", "")).is_empty(), "item bridge exposes a human-readable pickup rejection")
	_assert(String(bridge_rejection.get("output", "")) == String(bridge_rejection.get("message", "")), "item rejection is visible through legacy gameplay output")

	var beacon_target := Vector3(1.2, 0.4, -3.4)
	var movement: Dictionary = _move_service_client_toward(runtime, client, beacon_target, 2)
	_assert(bool(movement.get("success", false)), "movement intent accepted")
	var authoritative_player: Dictionary = client.service.get_player("a")
	_assert(int(authoritative_player.get("last_input_sequence", 0)) >= 2, "authoritative input sequence advanced")
	_assert(_record_position(authoritative_player).distance_to(Vector3(-2.0, 0.0, 0.0)) > 0.5, "server simulated player movement")

	var adapter = runtime._m7_item_adapter
	var shared_beacon_replica_id: String = adapter.to_replica_item_id("item/shared/beacon/1")
	var pickup: Dictionary = runtime.item_gameplay.pickup_world_item(shared_beacon_replica_id)
	_assert(bool(pickup.get("success", false)), "3D world beacon pickup routed through network")
	_assert(_item_location(client.get_item_graph_snapshot(), "item/shared/beacon/1") == "INVENTORY", "server owns picked-up beacon")
	_assert(runtime.item_gameplay.get_item(shared_beacon_replica_id) != null, "picked-up beacon remains in replica graph")

	var drop: Dictionary = runtime.item_gameplay.drop_selected_item()
	_assert(bool(drop.get("success", false)), "selected hotbar item drops through network")
	_assert(_count_world_definition(client.get_item_graph_snapshot(), "item/beacon") >= 1, "server contains network-dropped beacon")

	var select_mount_base: Dictionary = runtime.item_gameplay.select_hotbar(1)
	_assert(bool(select_mount_base.get("success", false)), "mount-base hotbar selection replicated")
	var place_transform := Transform3D(Basis.IDENTITY, Vector3(9000.0, 9000.0, 9000.0))
	var placed: Dictionary = runtime.item_gameplay.place_selected_item_at_transform(place_transform)
	_assert(bool(placed.get("success", false)), "mount base placement routed through network")
	var placed_position := _item_position(client.get_item_graph_snapshot(), String(placed.get("item_id", placed.get("details", {}).get("item_id", ""))))
	_assert(placed_position.length() < 100.0, "server ignored malicious client placement transform")
	var item_snapshot: Dictionary = client.get_item_graph_snapshot()
	var placed_mount_id := _latest_fixture_mount(item_snapshot)
	_assert(not placed_mount_id.is_empty(), "server created mount fixture for placed base")

	var select_beacon: Dictionary = runtime.item_gameplay.select_hotbar(0)
	_assert(bool(select_beacon.get("success", false)), "beacon hotbar selection replicated")
	var mounted: Dictionary = runtime.item_gameplay.mount_selected_item(placed_mount_id, "beacon_socket")
	_assert(bool(mounted.get("success", false)), "beacon installation routed through network")
	_assert(not _mount_item(client.get_item_graph_snapshot(), placed_mount_id).is_empty(), "server mount contains installed beacon")
	var detached: Dictionary = runtime.item_gameplay.detach_socket_to_inventory(placed_mount_id, "beacon_socket")
	_assert(bool(detached.get("success", false)), "beacon detach routed through network")
	_assert(_mount_item(client.get_item_graph_snapshot(), placed_mount_id).is_empty(), "server mount is empty after detach")

	var crate_target := Vector3(3.0, 0.8, -2.0)
	var crate_move: Dictionary = _move_service_client_toward(runtime, client, crate_target, 1)
	_assert(bool(crate_move.get("success", false)), "server moved player into crate interaction range")
	var crate_replica_id: String = adapter.to_replica_item_id("item/shared/crate/1")
	var opened: Dictionary = runtime.item_gameplay.interact_world_item(crate_replica_id)
	_assert(bool(opened.get("success", false)), "shared 3D crate opens through network")
	_assert(runtime.item_gameplay.inventory_open, "inventory automatically opens for shared crate")
	_assert(String(runtime.item_gameplay.inventory_ui.external_container_id) == "container/shared/crate/1", "shared external container is displayed")

	var final_report: Dictionary = runtime.create_m3_graphical_client_report()
	_assert(int(final_report.get("m7_state_submissions", 0)) >= 0, "M7 movement submission counter is available")
	_assert(String(client.service.get_report().get("movement_service", {}).get("playground_authority", "")) == "SERVER_SIMULATED_INPUT_INTENT", "M7 movement authority is server-side")
	_assert(String(final_report.get("m7_last_sync_error", "")).is_empty(), "M7 replica has no synchronization error")
	_assert(int(final_report.get("m7_item_bridge", {}).get("accepted", 0)) >= 7, "M7 item bridge accepted gameplay commands")
	_assert(String(client.get_item_graph_snapshot().get("checksum", "")).length() == 64, "canonical Item Graph checksum remains valid")

	runtime.prepare_for_unload()
	runtime.queue_free()
	await process_frame
	_finish()


func _move_service_client_toward(runtime, client, target: Vector3, steps: int) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": ""}
	for _index in range(steps):
		var record: Dictionary = client.service.get_player("a")
		var position := _record_position(record)
		var direction := (target - position).slide(Vector3.UP)
		if direction.length_squared() <= 0.000001:
			break
		direction = direction.normalized()
		runtime.player.camera_yaw = atan2(-direction.x, -direction.z)
		result = client.submit_movement_intent_blocking(runtime._create_m7_movement_intent(0.25, Vector2(0.0, -1.0), 0, 0))
		if not bool(result.get("success", false)):
			return result
	# Send a zero-axis intent to update the authoritative view toward the exact target.
	var final_record: Dictionary = client.service.get_player("a")
	var final_direction := (target - _record_position(final_record)).slide(Vector3.UP)
	if final_direction.length_squared() > 0.000001:
		final_direction = final_direction.normalized()
		runtime.player.camera_yaw = atan2(-final_direction.x, -final_direction.z)
		result = client.submit_movement_intent_blocking(runtime._create_m7_movement_intent(0.05, Vector2.ZERO, 0, 0))
	return result

func _record_position(record: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(record.get("position", {}))
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))

func _item_position(snapshot: Dictionary, item_id: String) -> Vector3:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return preload("res://scripts/runtime/listen_host/playable_state_codec.gd").transform_from_dto(Dictionary(item_value.get("transform", {}))).origin
	return Vector3.ZERO


func _item_location(snapshot: Dictionary, item_id: String) -> String:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return String(item_value.get("location", {}).get("kind", ""))
	return ""


func _count_world_definition(snapshot: Dictionary, definition_id: String) -> int:
	var count := 0
	for item_value in snapshot.get("items", []):
		if (
			item_value is Dictionary
			and String(item_value.get("definition_id", "")) == definition_id
			and String(item_value.get("location", {}).get("kind", "")) == "WORLD"
		):
			count += 1
	return count


func _latest_fixture_mount(snapshot: Dictionary) -> String:
	var result := ""
	for mount_value in snapshot.get("mounts", []):
		if mount_value is Dictionary:
			var mount_id := String(mount_value.get("mount_id", ""))
			if mount_id.begins_with("fixture/item/player/"):
				result = mount_id
	return result


func _mount_item(snapshot: Dictionary, mount_id: String) -> String:
	for mount_value in snapshot.get("mounts", []):
		if mount_value is Dictionary and String(mount_value.get("mount_id", "")) == mount_id:
			return String(mount_value.get("item_id", ""))
	return ""


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("M7 playable networked playground: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
