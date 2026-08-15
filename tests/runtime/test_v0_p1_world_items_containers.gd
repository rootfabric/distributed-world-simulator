extends SceneTree

const CanonicalItemGraph = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
)
const WorldItemRuntime = preload(
	"res://scripts/runtime/networked_gameplay/i2s/canonical_world_item_runtime.gd"
)
const PlayableStateCodec = preload(
	"res://scripts/runtime/listen_host/playable_state_codec.gd"
)

const BEACON_ID := "item/shared/beacon/1"
const CRATE_ID := "item/shared/crate/1"
const CONTAINER_ID := "container/shared/crate/1"

var assertions: int = 0
var failures: Array[String] = []
var canonical
var operation_sequence: Dictionary = {"a": 0, "b": 0}


func _init() -> void:
	_run()


func _run() -> void:
	canonical = CanonicalItemGraph.new()
	_assert(
		_ok(canonical.setup("authority/v0-p1", 1, {"playable_sandbox": true})),
		"canonical Item Graph sandbox configures"
	)
	canonical.ensure_player("a")
	canonical.ensure_player("b")

	var host := Node3D.new()
	host.name = "V0P1TestHost"
	get_root().add_child(host)
	var world_a := Node3D.new()
	world_a.name = "WorldA"
	host.add_child(world_a)
	var world_b := Node3D.new()
	world_b.name = "WorldB"
	host.add_child(world_b)

	var runtime_a = WorldItemRuntime.new()
	runtime_a.name = "RuntimeA"
	host.add_child(runtime_a)
	var runtime_b = WorldItemRuntime.new()
	runtime_b.name = "RuntimeB"
	host.add_child(runtime_b)
	_assert(
		_ok(runtime_a.setup(world_a, "a", Callable(self, "_submit_canonical").bind("a"))),
		"client A I2S runtime configures"
	)
	_assert(
		_ok(runtime_b.setup(world_b, "b", Callable(self, "_submit_canonical").bind("b"))),
		"client B I2S runtime configures"
	)

	var initial_snapshot: Dictionary = canonical.create_snapshot()
	_assert(_ok(runtime_a.accept_snapshot(initial_snapshot)), "client A accepts canonical Item Graph snapshot")
	_assert(_ok(runtime_b.accept_snapshot(initial_snapshot)), "client B accepts canonical Item Graph snapshot")
	_assert(runtime_a.has_presentation(BEACON_ID), "canonical WORLD beacon creates presentation")
	_assert(runtime_b.has_presentation(BEACON_ID), "second client derives presentation from same canonical WORLD beacon")
	_assert(runtime_a.has_presentation(CRATE_ID), "canonical WORLD crate creates presentation")
	var crate_target = runtime_a.get_presentation(CRATE_ID)
	_assert(crate_target != null, "crate presentation target exists")
	_assert(crate_target.is_in_group(&"world_interactable"), "crate participates in world interaction group")
	_assert(
		String(crate_target.get_external_container_id()) == CONTAINER_ID,
		"world crate resolves canonical external container identity"
	)

	var pickup: Dictionary = runtime_a.interact_world_item(BEACON_ID)
	_assert(_ok(pickup), "pickup succeeds through canonical Item Graph")
	var after_pickup := runtime_a.get_canonical_snapshot()
	_assert(_item_location_kind(after_pickup, BEACON_ID) == "INVENTORY", "pickup moves canonical identity to INVENTORY")
	_assert(_item_player(after_pickup, BEACON_ID) == "a", "picked identity belongs to player A")
	_assert(not runtime_a.has_presentation(BEACON_ID), "presentation disappears only after canonical pickup snapshot")

	var stale_b_pickup: Dictionary = runtime_b.interact_world_item(BEACON_ID)
	_assert(
		String(stale_b_pickup.get("error_code", "")) == "ITEM_ALREADY_CLAIMED",
		"stale second-client pickup is fenced by server"
	)
	_assert(runtime_b.has_presentation(BEACON_ID), "stale client keeps old presentation until canonical convergence")
	_assert(_ok(runtime_b.accept_snapshot(canonical.create_snapshot())), "client B accepts authoritative post-pickup snapshot")
	_assert(not runtime_b.has_presentation(BEACON_ID), "client B removes picked presentation after convergence")
	var duplicate_local: Dictionary = runtime_a.interact_world_item(BEACON_ID)
	_assert(
		String(duplicate_local.get("error_code", "")) == "I2S_STALE_WORLD_INTERACTION",
		"already-consumed local interaction fails closed"
	)

	var opened: Dictionary = runtime_a.open_external_container(CONTAINER_ID)
	_assert(_ok(opened), "external container opens canonically")
	var container_screen: Dictionary = runtime_a.build_player_container_screen()
	_assert(bool(container_screen.get("success", false)), "Player | Container screen projects from canonical snapshot")
	_assert(
		String(container_screen.get("external_container_id", "")) == CONTAINER_ID,
		"external container context comes from authoritative open_containers"
	)
	_assert(not Dictionary(container_screen.get("external", {})).is_empty(), "external container view is present")

	var moved_to_container: Dictionary = runtime_a.transfer_item(BEACON_ID, -1, CONTAINER_ID)
	_assert(_ok(moved_to_container), "inventory to external-container transfer succeeds")
	var after_container_transfer := runtime_a.get_canonical_snapshot()
	_assert(_item_location_kind(after_container_transfer, BEACON_ID) == "CONTAINER", "canonical item location becomes CONTAINER")
	_assert(_item_container(after_container_transfer, BEACON_ID) == CONTAINER_ID, "canonical item records exact container identity")
	_assert(_container_has(after_container_transfer, CONTAINER_ID, BEACON_ID), "canonical container slots contain transferred identity")
	_assert(_ok(runtime_b.accept_snapshot(canonical.create_snapshot())), "client B accepts authoritative container transfer")
	_assert(_container_has(runtime_b.get_canonical_snapshot(), CONTAINER_ID, BEACON_ID), "client B converges on container contents")

	var moved_back: Dictionary = runtime_a.transfer_item(BEACON_ID)
	_assert(_ok(moved_back), "external container item transfers back to inventory")
	_assert(_item_location_kind(runtime_a.get_canonical_snapshot(), BEACON_ID) == "INVENTORY", "transfer back restores INVENTORY")

	var dropped: Dictionary = runtime_a.drop_item(BEACON_ID)
	_assert(_ok(dropped), "drop succeeds through canonical Item Graph")
	var after_drop := runtime_a.get_canonical_snapshot()
	_assert(_item_location_kind(after_drop, BEACON_ID) == "WORLD", "drop restores canonical WORLD state")
	_assert(_item_has_valid_transform(after_drop, BEACON_ID), "dropped WORLD identity has authoritative transform")
	_assert(runtime_a.has_presentation(BEACON_ID), "drop recreates local world presentation")
	_assert(_ok(runtime_b.accept_snapshot(canonical.create_snapshot())), "client B accepts authoritative drop snapshot")
	_assert(runtime_b.has_presentation(BEACON_ID), "client B recreates dropped presentation")
	_assert(
		runtime_a.get_presentation_item_ids().size() == _renderable_world_count(after_drop),
		"no duplicate or orphan world presentations remain"
	)

	# Reconnect gate: leave a canonical item inside an open container, destroy the
	# original presentation runtime conceptually, then reconstruct a fresh client
	# from the server snapshot only.
	_assert(_ok(runtime_a.interact_world_item(BEACON_ID)), "player A can pick dropped beacon again")
	_assert(_ok(runtime_a.open_external_container(CONTAINER_ID)), "player A reopens crate before reconnect")
	_assert(_ok(runtime_a.transfer_item(BEACON_ID, -1, CONTAINER_ID)), "beacon is canonical inside crate before reconnect")
	var reconnect_snapshot := canonical.create_snapshot()
	var reconnect_world := Node3D.new()
	reconnect_world.name = "ReconnectWorldA"
	host.add_child(reconnect_world)
	var reconnect_runtime = WorldItemRuntime.new()
	reconnect_runtime.name = "ReconnectRuntimeA"
	host.add_child(reconnect_runtime)
	_assert(
		_ok(reconnect_runtime.setup(reconnect_world, "a", Callable(self, "_submit_canonical").bind("a"))),
		"fresh reconnect runtime configures"
	)
	_assert(_ok(reconnect_runtime.accept_snapshot(reconnect_snapshot)), "fresh reconnect runtime accepts only canonical snapshot")
	_assert(not reconnect_runtime.has_presentation(BEACON_ID), "reconnect does not invent world beacon while it is in container")
	_assert(reconnect_runtime.has_presentation(CRATE_ID), "reconnect reconstructs canonical world crate")
	var reconnect_screen := reconnect_runtime.build_player_container_screen()
	_assert(String(reconnect_screen.get("external_container_id", "")) == CONTAINER_ID, "reconnect reconstructs open external-container context")
	_assert(_container_has(reconnect_runtime.get_canonical_snapshot(), CONTAINER_ID, BEACON_ID), "reconnect reconstructs same canonical container contents")
	_assert(_ok(reconnect_runtime.close_external_container()), "reconnected client can close canonical container")

	var non_spatial = CanonicalItemGraph.new()
	_assert(_ok(non_spatial.setup("authority/v0-p1/non-spatial", 1, {"playable_sandbox": false})), "non-sandbox Item Graph configures")
	non_spatial.ensure_player("a")
	var non_spatial_world := Node3D.new()
	host.add_child(non_spatial_world)
	var non_spatial_runtime = WorldItemRuntime.new()
	host.add_child(non_spatial_runtime)
	_assert(
		_ok(non_spatial_runtime.setup(non_spatial_world, "a", Callable(self, "_reject_unexpected_command"))),
		"non-spatial I2S runtime configures"
	)
	var non_spatial_sync: Dictionary = non_spatial_runtime.accept_snapshot(non_spatial.create_snapshot())
	_assert(
		String(non_spatial_sync.get("error_code", "")) == "I2S_WORLD_SPATIAL_STATE_INCOMPLETE",
		"WORLD records without canonical transform fail closed"
	)
	_assert(non_spatial_runtime.get_presentation_item_ids().is_empty(), "I2S never invents presentation-only positions")

	non_spatial_runtime.clear_presentations()
	reconnect_runtime.clear_presentations()
	runtime_a.clear_presentations()
	runtime_b.clear_presentations()
	host.queue_free()
	_finish()


func _submit_canonical(
	command_type: String,
	payload: Dictionary,
	operation_id: String,
	player_id: String
) -> Dictionary:
	var sequence := int(operation_sequence.get(player_id, 0)) + 1
	operation_sequence[player_id] = sequence
	var resolved_operation_id := operation_id.strip_edges()
	if resolved_operation_id.is_empty():
		resolved_operation_id = "operation/v0-p1/%s/%d" % [player_id, sequence]
	return canonical.execute(
		player_id,
		1,
		resolved_operation_id,
		command_type,
		payload,
		_authority_context(command_type, payload)
	)


func _authority_context(command_type: String, payload: Dictionary) -> Dictionary:
	var player_position := Vector3(0.0, 0.4, 0.0)
	var target := player_position + Vector3(0.0, 0.0, -2.0)
	if command_type == "item.pickup":
		target = _canonical_item_position(String(payload.get("item_id", "")), target)
	elif command_type == "container.open":
		var container_id := String(payload.get("container_id", ""))
		var owner_item_id := _container_owner(canonical.create_snapshot(), container_id)
		target = _canonical_item_position(owner_item_id, target)
	var view := target - player_position
	if view.length_squared() <= 0.000001:
		view = Vector3(0.0, 0.0, -1.0)
	view = view.normalized()
	return {
		"player_position": _vector_dto(player_position),
		"interaction_origin": _vector_dto(player_position),
		"view_direction": _vector_dto(view),
		"orientation_yaw": 0.0,
	}


func _canonical_item_position(item_id: String, fallback: Vector3) -> Vector3:
	var item := _item_by_id(canonical.create_snapshot(), item_id)
	var transform_value = item.get("transform", {})
	if transform_value is Dictionary and bool(
		PlayableStateCodec.validate_transform_dto(Dictionary(transform_value)).get("success", false)
	):
		return PlayableStateCodec.transform_from_dto(Dictionary(transform_value)).origin
	return fallback


func _reject_unexpected_command(_command_type: String, _payload: Dictionary, _operation_id: String) -> Dictionary:
	return {"success": false, "error_code": "UNEXPECTED_TEST_COMMAND"}


func _item_by_id(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value)
	return {}


func _item_location_kind(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_by_id(snapshot, item_id).get("location", {}).get("kind", ""))


func _item_player(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_by_id(snapshot, item_id).get("location", {}).get("player_id", ""))


func _item_container(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_by_id(snapshot, item_id).get("location", {}).get("container_id", ""))


func _item_has_valid_transform(snapshot: Dictionary, item_id: String) -> bool:
	var transform_value = _item_by_id(snapshot, item_id).get("transform", {})
	return transform_value is Dictionary and bool(
		PlayableStateCodec.validate_transform_dto(Dictionary(transform_value)).get("success", false)
	)


func _container_has(snapshot: Dictionary, container_id: String, item_id: String) -> bool:
	for container_value in snapshot.get("containers", []):
		if (
			container_value is Dictionary
			and String(container_value.get("container_id", "")) == container_id
		):
			return item_id in Array(container_value.get("slots", []))
	return false


func _container_owner(snapshot: Dictionary, container_id: String) -> String:
	for container_value in snapshot.get("containers", []):
		if (
			container_value is Dictionary
			and String(container_value.get("container_id", "")) == container_id
		):
			return String(container_value.get("owner_item_id", ""))
	return ""


func _renderable_world_count(snapshot: Dictionary) -> int:
	var count := 0
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		if String(item_value.get("location", {}).get("kind", "")) != "WORLD":
			continue
		var transform_value = item_value.get("transform", {})
		if transform_value is Dictionary and bool(
			PlayableStateCodec.validate_transform_dto(Dictionary(transform_value)).get("success", false)
		):
			count += 1
	return count


func _vector_dto(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("V0-P1 canonical world items + containers: %d assertions, %d failures" % [
		assertions,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)
