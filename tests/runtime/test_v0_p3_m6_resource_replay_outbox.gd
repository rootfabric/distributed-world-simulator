extends SceneTree

const P3GameplayService = preload(
	"res://scripts/runtime/networked_gameplay/p3/networked_gameplay_service_p3.gd"
)
const M6ReplayOutbox = preload(
	"res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd"
)
const EarthResourceSpatialResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)

const AUTHORITY_ID := "authority/v0-p3/m6-replay-test"
const PLAYER_ID := "a"
const NODE_ID := "resource/earth/ore-demo/1"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_m6_outbox_round_trip_with_resource_replay()
	_finish()


func _test_m6_outbox_round_trip_with_resource_replay() -> void:
	var service = P3GameplayService.new()
	var setup: Dictionary = service.setup(AUTHORITY_ID, 1, 0, {
		"profile": "MULTIPLAYER_CORE",
		"topology_adapter": "ENET",
		"region_id": "region/v0-p3/m6-replay",
		"playable_sandbox": true,
	})
	_assert(bool(setup.get("success", false)), "P3 gameplay service configures for M6 replay test")
	if not bool(setup.get("success", false)):
		return
	var session_id := "transport-session/v0-p3/m6/a/1"
	var joined: Dictionary = service.join(PLAYER_ID, session_id, "operation/v0-p3/m6/join-a")
	_assert(bool(joined.get("success", false)), "P3 M6 replay player joins")
	if not bool(joined.get("success", false)):
		return
	var ownership_epoch := int(service.get_player(PLAYER_ID).get("ownership_epoch", 0))
	var target := _target_position(service)
	_assert(not target.is_empty(), "P3 M6 replay resource target resolves")
	if target.is_empty():
		return
	var moved: Dictionary = service.move_player(
		PLAYER_ID,
		session_id,
		ownership_epoch,
		1,
		clampf(float(target.get("x", 0.0)) + 5.0, -10.0, 10.0),
		clampf(float(target.get("z", 0.0)), -10.0, 10.0),
		"operation/v0-p3/m6/move-a"
	)
	_assert(bool(moved.get("success", false)), "P3 M6 replay player moves into mining range")
	if not bool(moved.get("success", false)):
		return

	var mine_operation := "operation/v0-p3/m6/mine-1"
	var mine_payload := {"resource_node_id": NODE_ID, "requested_units": 1}
	var mined: Dictionary = service.handle_resource_mine(
		PLAYER_ID,
		session_id,
		ownership_epoch,
		mine_operation,
		mine_payload
	)
	_assert(bool(mined.get("success", false)), "P3 M6 replay source mine succeeds")
	if not bool(mined.get("success", false)):
		return
	_assert(service.has_durable_replay_operation(mine_operation), "P3 resource mine is visible through durable replay lookup")

	var outbox = M6ReplayOutbox.new()
	var outbox_setup: Dictionary = outbox.setup(service)
	_assert(bool(outbox_setup.get("success", false)), "M6 replay outbox configures against P3 gameplay service")
	if not bool(outbox_setup.get("success", false)):
		return
	var staged: Dictionary = outbox.stage_committed(mine_operation, "resource.mine", {
		"logical_player_id": PLAYER_ID,
		"success": true,
		"error_code": "",
		"result": mined.duplicate(true),
	})
	_assert(bool(staged.get("success", false)), "M6 outbox stages outer resource.mine operation")
	if not bool(staged.get("success", false)):
		return
	var outbox_state: Dictionary = outbox.to_dict()
	_assert(bool(outbox.validate(outbox_state).get("success", false)), "M6 outbox serialized state validates with resource_replay records")
	var gameplay_replay: Dictionary = Dictionary(outbox_state.get("gameplay_replay", {}))
	var resource_replay: Dictionary = Dictionary(gameplay_replay.get("resource_replay", {}))
	var resource_records: Dictionary = Dictionary(resource_replay.get("records", {}))
	_assert(resource_records.has(mine_operation), "serialized M6 gameplay replay contains outer resource.mine operation")

	var durable: Dictionary = service.export_durable_state()
	var resource_before: Dictionary = service.create_resource_mining_snapshot()
	var item_before: Dictionary = service.create_canonical_item_graph_snapshot()
	var output_item_id := String(mined.get("details", {}).get("output_item_id", ""))

	var restored = P3GameplayService.new()
	var restored_durable: Dictionary = restored.restore_durable_state(durable)
	_assert(bool(restored_durable.get("success", false)), "fresh P3 gameplay service restores M6 source durable state")
	if not bool(restored_durable.get("success", false)):
		return
	var restored_outbox = M6ReplayOutbox.new()
	_assert(bool(restored_outbox.setup(restored).get("success", false)), "fresh M6 outbox configures after P3 durable restore")
	var loaded: Dictionary = restored_outbox.load_dict(outbox_state)
	_assert(bool(loaded.get("success", false)), "fresh M6 outbox restores resource replay aggregate")
	if not bool(loaded.get("success", false)):
		return
	_assert(restored.has_durable_replay_operation(mine_operation), "fresh P3 gameplay service exposes restored resource replay operation")
	_assert(restored.create_resource_mining_snapshot() == resource_before, "M6 replay load does not alter canonical resource state")
	_assert(restored.create_canonical_item_graph_snapshot() == item_before, "M6 replay load does not alter canonical Item Graph state")

	var previous_player: Dictionary = restored.get_player(PLAYER_ID)
	var previous_epoch := int(previous_player.get("ownership_epoch", 0))
	var new_session := "transport-session/v0-p3/m6/a/2"
	var rejoined: Dictionary = restored.join(PLAYER_ID, new_session, "operation/v0-p3/m6/rejoin-a")
	_assert(bool(rejoined.get("success", false)), "fresh P3 gameplay player rejoins after M6 recovery")
	if not bool(rejoined.get("success", false)):
		return
	var new_epoch := int(restored.get_player(PLAYER_ID).get("ownership_epoch", 0))
	_assert(new_epoch > previous_epoch, "fresh P3 gameplay reconnect advances ownership epoch after M6 recovery")
	var replay_resource_before := restored.create_resource_mining_snapshot()
	var replay_item_before := restored.create_canonical_item_graph_snapshot()
	var replay: Dictionary = restored.handle_resource_mine(
		PLAYER_ID,
		new_session,
		new_epoch,
		mine_operation,
		mine_payload
	)
	_assert(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "M6-restored exact resource.mine operation replays")
	_assert(String(replay.get("details", {}).get("output_item_id", "")) == output_item_id, "M6-restored replay preserves mined output identity")
	_assert(restored.create_resource_mining_snapshot() == replay_resource_before, "M6-restored replay does not deplete resource twice")
	_assert(restored.create_canonical_item_graph_snapshot() == replay_item_before, "M6-restored replay does not mint ore twice")


func _target_position(service) -> Dictionary:
	var snapshot: Dictionary = service.create_resource_mining_snapshot()
	var node: Dictionary = {}
	for node_value in snapshot.get("nodes", []):
		if node_value is Dictionary and String(node_value.get("resource_node_id", "")) == NODE_ID:
			node = Dictionary(node_value).duplicate(true)
			break
	if node.is_empty():
		return {}
	var resolver = EarthResourceSpatialResolver.new()
	if not bool(resolver.setup().get("success", false)):
		return {}
	var resolved: Dictionary = resolver.resolve_planar(Dictionary(node.get("spatial", {})))
	return Dictionary(resolved.get("details", {}).get("planar_position", {})).duplicate(true) if bool(resolved.get("success", false)) else {}


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("FAIL: %s" % label)


func _finish() -> void:
	print("V0-P3 M6 resource replay: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
