extends SceneTree

const ListenHostRuntime = preload("res://scripts/runtime/listen_host/listen_host_runtime.gd")
const PlayableAuthority = preload("res://scripts/runtime/listen_host/playable_listen_host_authority.gd")
const PlayableStateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")
const ItemGameplayController = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const NetworkCommand = preload("res://scripts/network/contracts/network_command_envelope.gd")
const NetworkResult = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const EntityDelta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const LaunchOptions = preload("res://scripts/runtime/launch_options.gd")
const RuntimeRole = preload("res://scripts/runtime/runtime_role.gd")

const CHECKPOINT: String = "v16.9.1-runtime-h1-playable-listen-host"
const BUILD_ID: String = "h1-playable-listen-host"

var failures: Array[String] = []
var assertions: int = 0
var authority_host: Node
var runtime
var client_session
var replica_controller


func _init() -> void:
	authority_host = Node.new()
	authority_host.name = "H1AuthorityHostTest"
	root.add_child(authority_host)
	_test_default_launch_role()
	_test_state_codec_contracts()
	_test_playable_runtime_and_replica_boundary()
	_test_direct_authority_fences()
	_cleanup()
	_finish()


func _test_default_launch_role() -> void:
	var defaults: Dictionary = LaunchOptions.defaults()
	_assert(String(defaults.get("role", "")) == RuntimeRole.LISTEN_HOST, "F5/default role must be listen-host")
	_assert(String(defaults.get("node_id", "")) == "local-listen-host", "Default node id must match listen-host")
	var offline: Dictionary = LaunchOptions.parse(PackedStringArray(["--role=offline"]))
	_assert(bool(offline.get("success", false)), "Explicit offline role was rejected")
	_assert(String(offline.get("options", {}).get("node_id", "")) == "local-offline", "Explicit offline role did not normalize node id")


func _test_state_codec_contracts() -> void:
	var state: Dictionary = _initial_player_state()
	_assert(bool(PlayableStateCodec.validate_player_state(state).get("success", false)), "Valid player state was rejected")
	var round_trip = JSON.parse_string(JSON.stringify(state))
	_assert(round_trip is Dictionary, "Player state did not survive JSON round trip")
	_assert(Dictionary(round_trip) == state, "Player state is not JSON stable")
	var leaked: Dictionary = state.duplicate(true)
	leaked["live_player"] = Node.new()
	_assert(String(PlayableStateCodec.validate_player_state(leaked).get("error_code", "")) == "UNEXPECTED_FIELD", "Runtime object/extra player field was not rejected")
	leaked["live_player"].free()
	var invalid_sequence: Dictionary = state.duplicate(true)
	invalid_sequence["last_input_sequence"] = -1
	_assert(String(PlayableStateCodec.validate_player_state(invalid_sequence).get("error_code", "")) == "INVALID_INPUT_SEQUENCE", "Negative input sequence was accepted")
	var invalid_position: Dictionary = state.duplicate(true)
	invalid_position["interaction_position_m"] = [NAN, 0.0, 0.0]
	_assert(String(PlayableStateCodec.validate_player_state(invalid_position).get("error_code", "")) == "INVALID_INTERACTION_POSITION", "NaN interaction position was accepted")
	var transform_dto: Dictionary = PlayableStateCodec.create_transform_dto(
		Transform3D(Basis(Vector3.UP, 0.25), Vector3(1.0, 2.0, 3.0))
	)
	_assert(bool(PlayableStateCodec.validate_transform_dto(transform_dto).get("success", false)), "Valid transform DTO was rejected")
	_assert(PlayableStateCodec.transform_from_dto(transform_dto).origin.is_equal_approx(Vector3(1.0, 2.0, 3.0)), "Transform DTO round trip changed position")


func _test_playable_runtime_and_replica_boundary() -> void:
	runtime = ListenHostRuntime.new()
	var setup: Dictionary = runtime.setup({
		"authority_host": authority_host,
		"authority_owner_id": "h1-test-host",
		"authority_epoch": 3,
		"server_tick": 10,
		"session_id": "session/h0/compatibility-test",
	})
	_assert(bool(setup.get("success", false)), "ListenHostRuntime compatibility setup failed: %s" % setup)
	var attach: Dictionary = runtime.attach_playable_world({
		"authority_owner_id": "h1-test-host",
		"authority_epoch": 3,
		"server_tick": 10,
		"session_id": "session/h1/contracts/1",
		"universe_id": "main",
		"instance_id": "h1-contracts",
		"space_id": "moon",
		"frame_id": "body/moon/fixed",
		"player_state": _initial_player_state(),
		"item_persistence_enabled": false,
		"item_profile_id": "playground",
		"item_state_key": "h1-contracts-items",
		"include_demo_world": true,
	})
	_assert(bool(attach.get("success", false)), "Playable world attach failed: %s" % attach)
	var player_snapshot: Dictionary = runtime.get_playable_snapshot(PlayableAuthority.PLAYER_ENTITY_ID)
	var item_snapshot: Dictionary = runtime.get_playable_snapshot(PlayableAuthority.ITEM_GRAPH_ENTITY_ID)
	_assert(bool(EntitySnapshot.validate(player_snapshot).get("success", false)), "Initial player snapshot is invalid")
	_assert(bool(EntitySnapshot.validate(item_snapshot).get("success", false)), "Initial item snapshot is invalid")
	_assert(int(player_snapshot.get("state_revision", -1)) == 0, "Initial player revision changed")
	_assert(int(item_snapshot.get("state_revision", -1)) == 0, "Initial item revision changed")

	var report: Dictionary = runtime.get_playable_report()
	client_session = runtime.get_playable_client_session()
	_assert(client_session != null, "Playable client session was not created")
	_assert(not client_session.has_method("attach_playable_world"), "Client session exposes authority attachment")
	_assert(not client_session.has_method("get_playable_authority_world_entity_store_for_kernel"), "Client session exposes authoritative world store")
	_assert(not client_session.has_method("get_item_controller_for_authority_tests"), "Client session exposes authoritative item controller")
	var session_report: Dictionary = client_session.get_report()
	_assert(int(session_report.get("direct_authority_references", -1)) == 0, "Client session reports an authority reference")
	_assert(int(session_report.get("direct_domain_references", -1)) == 0, "Client session reports a domain reference")
	_assert(bool(report.get("attached", false)), "Playable report does not mark attachment")
	_assert(not bool(report.get("direct_client_authority_access", true)), "Client report exposes authority")
	_assert(not bool(report.get("direct_client_domain_access", true)), "Client report exposes authoritative domain")
	_assert(int(report.get("authority", {}).get("presentation_objects", -1)) == 0, "Authority created presentation objects")
	_assert(int(report.get("client_runtime", {}).get("direct_authority_references", -1)) == 0, "ClientRuntime holds authority reference")
	_assert(int(report.get("item_bridge", {}).get("direct_domain_references", -1)) == 0, "Item bridge holds domain reference")

	var graph_value = item_snapshot.get("domain_components", {}).get("item_graph", {})
	replica_controller = ItemGameplayController.new()
	root.add_child(replica_controller)
	var replica_setup: Dictionary = replica_controller.setup_runtime(
		null, null, null, null,
		"body/moon/fixed", "moon-local", "h1-replica", "playground", false,
		{
			"mode": ItemGameplayController.RUNTIME_MODE_REPLICA,
			"initial_graph_snapshot": Dictionary(graph_value),
			"replica_revision": int(item_snapshot["state_revision"]),
			"replica_checksum": String(item_snapshot["checksum"]),
			"network_command_bridge": client_session.get_item_bridge(),
			"persistence_enabled": false,
			"presentation_enabled": false,
		}
	)
	_assert(bool(replica_setup.get("success", false)), "Replica item controller setup failed: %s" % replica_setup)
	_assert(String(replica_controller.runtime_mode) == ItemGameplayController.RUNTIME_MODE_REPLICA, "Item controller did not enter replica mode")
	_assert(replica_controller.presenter == null, "Headless replica test unexpectedly created presenter")
	_assert(int(replica_controller.create_debug_snapshot().get("direct_authority_references", -1)) == 0, "Replica controller reports authority reference")

	var select_result: Dictionary = replica_controller.select_hotbar(4)
	_assert(bool(select_result.get("success", false)), "Network hotbar selection failed: %s" % select_result)
	_assert(replica_controller.selected_hotbar_index == 4, "Replica hotbar selection was not refreshed")
	var selected_snapshot: Dictionary = runtime.get_playable_snapshot(PlayableAuthority.ITEM_GRAPH_ENTITY_ID)
	_assert(int(selected_snapshot.get("state_revision", -1)) == 1, "Hotbar mutation did not advance item revision")
	_assert(int(selected_snapshot.get("domain_components", {}).get("selected_hotbar_index", -1)) == 4, "Authority hotbar selection mismatch")

	var grant_result: Dictionary = replica_controller.grant_debug_item("lunar_rock", 7)
	_assert(bool(grant_result.get("success", false)), "Debug grant through authority failed: %s" % grant_result)
	_assert(_total_definition_quantity(replica_controller, "lunar_rock") >= 7, "Granted items did not reach replica")
	_assert(int(runtime.get_playable_snapshot(PlayableAuthority.ITEM_GRAPH_ENTITY_ID).get("state_revision", -1)) == 2, "Grant did not advance item revision")

	var crate_id: String = _find_world_item_with_container(replica_controller)
	_assert(not crate_id.is_empty(), "Demo external container item was not found")
	var crate = replica_controller.get_item(crate_id)
	var container_id: String = String(crate.get_owned_container_id()) if crate != null else ""
	var open_result: Dictionary = replica_controller.open_container(container_id)
	_assert(bool(open_result.get("success", false)), "Accessible external container was rejected: %s" % open_result)
	_assert(String(runtime.get_playable_report().get("authority", {}).get("open_external_container_id", "")) == container_id, "Authority did not bind opened container")
	var close_result: Dictionary = client_session.get_item_bridge().submit_item_command(
		"container.close", {"container_id": container_id}, "operation/h1/test/close-container"
	)
	_assert(bool(close_result.get("success", false)), "External container close was rejected: %s" % close_result)
	_assert(String(runtime.get_playable_report().get("authority", {}).get("open_external_container_id", "x")).is_empty(), "Authority retained container access after close")

	var moved_state: Dictionary = PlayableStateCodec.create_player_state(
		Vector3(0.75, 1737401.0, 0.0), Basis.IDENTITY, Vector3(3.0, 0.0, 0.0),
		Vector3(0.75, 0.0, 0.0), "lunar_humanoid", "first_person", true, 1,
		"body/moon/fixed", "main", "moon", "h1-contracts", 0.1
	)
	var move_result: Dictionary = client_session.submit_player_state(moved_state, 0.1, "operation/h1/test/player-move/1")
	_assert(bool(move_result.get("success", false)), "Authoritative player movement failed: %s" % move_result)
	var moved_snapshot: Dictionary = runtime.get_playable_snapshot(PlayableAuthority.PLAYER_ENTITY_ID)
	_assert(int(moved_snapshot.get("state_revision", -1)) == 1, "Player revision did not advance")
	_assert(PlayableStateCodec.player_position(Dictionary(moved_snapshot["domain_components"]["player_state"])).is_equal_approx(Vector3(0.75, 1737401.0, 0.0)), "Player replica position mismatch")
	_assert(bool(moved_snapshot["domain_components"]["player_state"]["flashlight_enabled"]), "Player flashlight state was not replicated")

	var detach: Dictionary = runtime.detach_playable_world()
	_assert(bool(detach.get("success", false)), "Playable world detach failed: %s" % detach)
	_assert(not bool(runtime.get_playable_report().get("attached", true)), "Playable runtime remained attached")


func _test_direct_authority_fences() -> void:
	var authority = PlayableAuthority.new()
	root.add_child(authority)
	var setup: Dictionary = authority.setup({
		"authority_owner_id": "h1-fence-authority",
		"authority_epoch": 5,
		"server_tick": 20,
		"session_id": "session/h1/fences/1",
		"universe_id": "main",
		"instance_id": "h1-fences",
		"space_id": "moon",
		"frame_id": "body/moon/fixed",
		"player_state": _initial_player_state("h1-fences"),
		"item_persistence_enabled": false,
		"item_profile_id": "playground",
		"item_state_key": "h1-fence-items",
		"include_demo_world": true,
	})
	_assert(bool(setup.get("success", false)), "Direct authority setup failed: %s" % setup)
	var initial_player: Dictionary = authority.create_snapshot(PlayableAuthority.PLAYER_ENTITY_ID)
	var moved_state: Dictionary = PlayableStateCodec.create_player_state(
		Vector3(1.0, 1737401.0, 0.0), Basis.IDENTITY, Vector3(2.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0), "lunar_humanoid", "third_person", false, 1,
		"body/moon/fixed", "main", "moon", "h1-fences", 0.1
	)
	var command: Dictionary = NetworkCommand.create(
		"message/h1/fence/move/1", "operation/h1/fence/move/1",
		PlayableAuthority.PLAYER_ENTITY_ID, "player.move",
		{"session_id": "session/h1/fences/1", "player_state": moved_state, "delta_seconds": 0.1},
		int(initial_player["state_revision"]), 5, 20, 1
	)
	var accepted: Dictionary = authority.handle_command(command)
	_assert(bool(NetworkResult.validate(accepted).get("success", false)), "Accepted movement result is invalid")
	_assert(String(accepted.get("status", "")) == "SUCCEEDED", "Valid movement was rejected: %s" % accepted)
	var delta: Dictionary = accepted.get("payload", {}).get("replication_delta", {})
	_assert(bool(EntityDelta.validate(delta).get("success", false)), "Movement delta is invalid")

	var replay_command: Dictionary = command.duplicate(true)
	replay_command["message_id"] = "message/h1/fence/move/replay"
	var replay: Dictionary = authority.handle_command(replay_command)
	_assert(String(replay.get("status", "")) == "SUCCEEDED", "Exact operation replay failed")
	var comparable_accepted: Dictionary = accepted.duplicate(true)
	var comparable_replay: Dictionary = replay.duplicate(true)
	comparable_accepted.erase("message_id")
	comparable_replay.erase("message_id")
	_assert(comparable_accepted == comparable_replay, "Exact replay result changed")
	_assert(int(authority.get_report().get("player_revision", -1)) == 1, "Exact replay committed a second movement")

	var collision: Dictionary = command.duplicate(true)
	collision["message_id"] = "message/h1/fence/move/conflict"
	collision["payload"]["delta_seconds"] = 0.2
	var conflict: Dictionary = authority.handle_command(collision)
	_assert(String(conflict.get("error_code", "")) == "OPERATION_REPLAY_CONFLICT", "Operation collision was not fenced")

	var duplicate_state: Dictionary = moved_state.duplicate(true)
	var duplicate_command: Dictionary = NetworkCommand.create(
		"message/h1/fence/duplicate", "operation/h1/fence/duplicate",
		PlayableAuthority.PLAYER_ENTITY_ID, "player.move",
		{"session_id": "session/h1/fences/1", "player_state": duplicate_state, "delta_seconds": 0.1},
		1, 5, 21, 2
	)
	var duplicate: Dictionary = authority.handle_command(duplicate_command)
	_assert(String(duplicate.get("error_code", "")) == "DUPLICATE_INPUT_SEQUENCE", "Duplicate input sequence was accepted")

	var stale: Dictionary = duplicate_command.duplicate(true)
	stale["message_id"] = "message/h1/fence/stale"
	stale["operation_id"] = "operation/h1/fence/stale"
	stale["expected_revision"] = 0
	stale["payload"]["player_state"]["last_input_sequence"] = 2
	var stale_result: Dictionary = authority.handle_command(stale)
	_assert(String(stale_result.get("error_code", "")) == "REVISION_CONFLICT", "Stale player revision was accepted")

	var wrong_session: Dictionary = duplicate_command.duplicate(true)
	wrong_session["message_id"] = "message/h1/fence/session"
	wrong_session["operation_id"] = "operation/h1/fence/session"
	wrong_session["payload"]["session_id"] = "session/other"
	wrong_session["payload"]["player_state"]["last_input_sequence"] = 2
	var session_result: Dictionary = authority.handle_command(wrong_session)
	_assert(String(session_result.get("error_code", "")) == "SESSION_NOT_BOUND", "Unbound session command was accepted")

	var excessive_state: Dictionary = PlayableStateCodec.create_player_state(
		Vector3(10000.0, 1737401.0, 0.0), Basis.IDENTITY, Vector3.ZERO,
		Vector3(10000.0, 0.0, 0.0), "lunar_humanoid", "first_person", false, 2,
		"body/moon/fixed", "main", "moon", "h1-fences", 0.2
	)
	var excessive_command: Dictionary = NetworkCommand.create(
		"message/h1/fence/teleport", "operation/h1/fence/teleport",
		PlayableAuthority.PLAYER_ENTITY_ID, "player.move",
		{"session_id": "session/h1/fences/1", "player_state": excessive_state, "delta_seconds": 0.1},
		1, 5, 21, 3
	)
	var excessive: Dictionary = authority.handle_command(excessive_command)
	_assert(String(excessive.get("error_code", "")) == "PLAYER_MOVEMENT_LIMIT_EXCEEDED", "Impossible teleport was accepted")

	var item_snapshot: Dictionary = authority.create_snapshot(PlayableAuthority.ITEM_GRAPH_ENTITY_ID)
	var item_controller = authority.get_item_controller_for_authority_tests()
	var inventory_item_id: String = _first_container_item(item_controller, item_controller.player_inventory_id)
	_assert(not inventory_item_id.is_empty(), "Authority inventory has no item for negative split test")
	var invalid_split: Dictionary = _item_command(
		"message/h1/fence/split", "operation/h1/fence/split",
		"item.move_to_container",
		{
			"item_id": inventory_item_id,
			"quantity": 999999,
			"target_container_id": item_controller.player_hotbar_id,
			"target_slot_index": 0,
			"target_item_id": "",
		},
		int(item_snapshot["state_revision"]), 5
	)
	var split_result: Dictionary = authority.handle_command(invalid_split)
	_assert(String(split_result.get("status", "")) == "REJECTED", "Invalid split quantity was accepted")
	_assert(int(authority.get_report().get("item_revision", -1)) == 0, "Rejected split mutated item revision")

	var inaccessible: Dictionary = _item_command(
		"message/h1/fence/access", "operation/h1/fence/access",
		"item.move_to_container",
		{
			"item_id": inventory_item_id,
			"quantity": 1,
			"target_container_id": "demo_crate_contents",
			"target_slot_index": -1,
			"target_item_id": "",
		},
		0, 5
	)
	var inaccessible_result: Dictionary = authority.handle_command(inaccessible)
	_assert(String(inaccessible_result.get("error_code", "")) == "TARGET_CONTAINER_ACCESS_DENIED", "Closed external container accepted transfer")
	_assert(int(authority.get_report().get("item_revision", -1)) == 0, "Access rejection mutated item revision")

	var world_item_id: String = _find_first_pickable_world_item(item_controller)
	_assert(not world_item_id.is_empty(), "Demo world has no pickable item")
	var pickup: Dictionary = _item_command(
		"message/h1/fence/pickup", "operation/h1/fence/pickup",
		"item.pickup", {"item_id": world_item_id}, 0, 5
	)
	var pickup_result: Dictionary = authority.handle_command(pickup)
	_assert(String(pickup_result.get("status", "")) == "SUCCEEDED", "First pickup was rejected: %s" % pickup_result)
	var second_pickup: Dictionary = _item_command(
		"message/h1/fence/pickup2", "operation/h1/fence/pickup2",
		"item.pickup", {"item_id": world_item_id}, 1, 5
	)
	var second_pickup_result: Dictionary = authority.handle_command(second_pickup)
	_assert(String(second_pickup_result.get("error_code", "")) == "ITEM_NOT_IN_WORLD", "Repeated pickup was accepted")
	_assert(int(authority.get_report().get("item_revision", -1)) == 1, "Repeated pickup committed a second mutation")

	var invalid_delta_state: Dictionary = moved_state.duplicate(true)
	invalid_delta_state["last_input_sequence"] = 2
	var bad_epoch: Dictionary = NetworkCommand.create(
		"message/h1/fence/epoch", "operation/h1/fence/epoch",
		PlayableAuthority.PLAYER_ENTITY_ID, "player.move",
		{"session_id": "session/h1/fences/1", "player_state": invalid_delta_state, "delta_seconds": 0.1},
		1, 4, 21, 4
	)
	var epoch_result: Dictionary = authority.handle_command(bad_epoch)
	_assert(String(epoch_result.get("error_code", "")) == "STALE_AUTHORITY_EPOCH", "Stale authority epoch was accepted")

	var authority_report: Dictionary = authority.get_report()
	_assert(int(authority_report.get("presentation_objects", -1)) == 0, "Authority created presentation nodes")
	_assert(bool(authority_report.get("item_graph_valid", false)), "Authority item graph became invalid")
	authority.shutdown()
	authority.queue_free()


func _initial_player_state(instance_id: String = "h1-contracts") -> Dictionary:
	return PlayableStateCodec.create_player_state(
		Vector3(0.0, 1737401.0, 0.0), Basis.IDENTITY, Vector3.ZERO,
		Vector3.ZERO, "lunar_humanoid", "first_person", false, 0,
		"body/moon/fixed", "main", "moon", instance_id, 0.0
	)


func _item_command(
	message_id: String,
	operation_id: String,
	command_type: String,
	payload: Dictionary,
	revision: int,
	epoch: int
) -> Dictionary:
	var command_payload: Dictionary = payload.duplicate(true)
	command_payload["session_id"] = "session/h1/fences/1"
	return NetworkCommand.create(
		message_id, operation_id, PlayableAuthority.ITEM_GRAPH_ENTITY_ID,
		command_type, command_payload, revision, epoch, 20, 1
	)


func _find_world_item_with_container(controller) -> String:
	for item in controller.domain.items.all_items():
		if item.owns_container() and String(item.relation.get("kind", "")) in ["WORLD", "WORLD_ENTITY"]:
			return String(item.instance_id)
	return ""


func _find_first_pickable_world_item(controller) -> String:
	for item in controller.domain.items.all_items():
		if not item.owns_container() and String(item.relation.get("kind", "")) in ["WORLD", "WORLD_ENTITY"]:
			return String(item.instance_id)
	return ""


func _first_container_item(controller, container_id: String) -> String:
	var container = controller.get_container(container_id)
	if container == null or container.item_ids.is_empty():
		return ""
	return String(container.item_ids[0])


func _total_definition_quantity(controller, definition_id: String) -> int:
	var total: int = 0
	for item in controller.domain.items.all_items():
		if String(item.definition_id) == definition_id:
			total += int(item.quantity)
	return total


func _cleanup() -> void:
	if runtime != null:
		runtime.detach_playable_world()
		runtime = null
	client_session = null
	if replica_controller != null and is_instance_valid(replica_controller):
		replica_controller.queue_free()
	if authority_host != null and is_instance_valid(authority_host):
		authority_host.queue_free()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("H1 playable listen-host contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("H1 playable listen-host contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
