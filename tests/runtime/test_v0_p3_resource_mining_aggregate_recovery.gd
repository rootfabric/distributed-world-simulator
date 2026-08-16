extends SceneTree

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P3GameplayService = preload(
	"res://scripts/runtime/networked_gameplay/p3/networked_gameplay_service_p3.gd"
)
const EarthResourceSpatialResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)

const AUTHORITY_ID := "authority/v0-p3/aggregate-test"
const NODE_ID := "resource/earth/ore-demo/1"
const PLAYER_ID := "a"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_resource_state_is_inside_gameplay_aggregate()
	_finish()


func _test_resource_state_is_inside_gameplay_aggregate() -> void:
	var service = P3GameplayService.new()
	var setup: Dictionary = service.setup(AUTHORITY_ID, 1, 0, {
		"profile": "MULTIPLAYER_CORE",
		"topology_adapter": "ENET",
		"region_id": "region/v0-p3/earth",
		"playable_sandbox": true,
	})
	_assert(bool(setup.get("success", false)), "P3 aggregate gameplay service configures")
	if not bool(setup.get("success", false)):
		return
	var session_a := "transport-session/v0-p3/a/1"
	var joined: Dictionary = service.join(PLAYER_ID, session_a, "operation/v0-p3/aggregate/join-a")
	_assert(bool(joined.get("success", false)), "P3 aggregate player joins")
	if not bool(joined.get("success", false)):
		return
	var player: Dictionary = service.get_player(PLAYER_ID)
	var ownership_epoch := int(player.get("ownership_epoch", 0))
	_assert(ownership_epoch >= 1, "P3 aggregate join establishes ownership epoch")

	var resolver = EarthResourceSpatialResolver.new()
	_assert(bool(resolver.setup().get("success", false)), "aggregate test Earth resolver configures")
	var node := _resource_node(service.create_resource_mining_snapshot(), NODE_ID)
	var resolved: Dictionary = resolver.resolve_planar(Dictionary(node.get("spatial", {})))
	_assert(bool(resolved.get("success", false)), "aggregate test resolves canonical resource position")
	if not bool(resolved.get("success", false)):
		return
	var target: Dictionary = Dictionary(resolved.get("details", {}).get("planar_position", {}))
	_assert(_move_to(service, session_a, ownership_epoch, target), "authoritative player moves into resource range")

	var mine_operation := "operation/v0-p3/aggregate/mine-1"
	var mine_payload := {"resource_node_id": NODE_ID, "requested_units": 1}
	var before_resource: Dictionary = service.create_resource_mining_snapshot()
	var before_item: Dictionary = service.create_canonical_item_graph_snapshot()
	var mined: Dictionary = service.handle_resource_mine(
		PLAYER_ID,
		session_a,
		ownership_epoch,
		mine_operation,
		mine_payload
	)
	_assert(bool(mined.get("success", false)), "aggregate resource.mine succeeds")
	if not bool(mined.get("success", false)):
		return
	var output_item_id := String(mined.get("details", {}).get("output_item_id", ""))
	var after_resource: Dictionary = service.create_resource_mining_snapshot()
	var after_item: Dictionary = service.create_canonical_item_graph_snapshot()
	_assert(int(_resource_node(after_resource, NODE_ID).get("remaining_units", -1)) == 7, "aggregate mine persists seven remaining resource units")
	_assert(int(after_resource.get("generation", 0)) == int(before_resource.get("generation", 0)) + 1, "aggregate mine advances resource generation once")
	_assert(int(after_item.get("revision", 0)) == int(before_item.get("revision", 0)) + 1, "aggregate mine advances canonical Item Graph once")
	_assert(not output_item_id.is_empty() and not _find_item(after_item, output_item_id).is_empty(), "aggregate mine creates canonical output item")

	var durable: Dictionary = service.export_durable_state()
	var replay_state: Dictionary = service.export_replay_state()
	_assert(durable.has("resource_mining") and replay_state.has("resource_replay"), "resource durable and replay state are sections of the existing gameplay aggregate")
	_assert(bool(service.validate_durable_state(durable).get("success", false)), "P3 gameplay aggregate durable state validates")
	_assert(bool(service.validate_replay_state(replay_state).get("success", false)), "P3 gameplay aggregate replay state validates")
	_assert(service.has_durable_replay_operation(mine_operation), "aggregate replay lookup includes resource mining operations")
	var stored_resource_state: Dictionary = Dictionary(durable.get("resource_mining", {}))
	var stored_resource_snapshot: Dictionary = Dictionary(stored_resource_state.get("snapshot", {}))
	var stored_item_state: Dictionary = Dictionary(durable.get("canonical_item_graph", {}))
	var stored_item_snapshot: Dictionary = Dictionary(stored_item_state.get("snapshot", {}))
	_assert(
		String(stored_resource_snapshot.get("checksum", "")) == String(after_resource.get("checksum", ""))
		and int(stored_resource_snapshot.get("generation", -1)) == int(after_resource.get("generation", -2)),
		"durable export preserves canonical resource checksum and generation across JSON normalization"
	)
	_assert(
		String(stored_item_snapshot.get("checksum", "")) == String(after_item.get("checksum", ""))
		and int(stored_item_snapshot.get("revision", -1)) == int(after_item.get("revision", -2))
		and int(stored_item_snapshot.get("tick", -1)) == int(after_item.get("tick", -2)),
		"durable export preserves canonical Item Graph checksum and clock across JSON normalization"
	)

	var tampered := durable.duplicate(true)
	var tampered_resource: Dictionary = Dictionary(tampered.get("resource_mining", {})).duplicate(true)
	var tampered_snapshot: Dictionary = Dictionary(tampered_resource.get("snapshot", {})).duplicate(true)
	var tampered_nodes: Array = Array(tampered_snapshot.get("nodes", [])).duplicate(true)
	var tampered_node: Dictionary = Dictionary(tampered_nodes[0]).duplicate(true)
	tampered_node["remaining_units"] = 999
	tampered_nodes[0] = tampered_node
	tampered_snapshot["nodes"] = tampered_nodes
	tampered_resource["snapshot"] = tampered_snapshot
	tampered["resource_mining"] = tampered_resource
	tampered["checksum"] = ""
	tampered = NetworkUtils.finalize_json_checksum(tampered)
	_assert(not bool(service.validate_durable_state(tampered).get("success", false)), "outer aggregate checksum cannot bless a tampered resource-owner checksum")

	var stripped_durable := durable.duplicate(true)
	stripped_durable.erase("resource_mining")
	stripped_durable["checksum"] = ""
	stripped_durable = NetworkUtils.finalize_json_checksum(stripped_durable)
	var stripped_durable_validation: Dictionary = service.validate_durable_state(stripped_durable)
	_assert(
		not bool(stripped_durable_validation.get("success", false))
		and String(stripped_durable_validation.get("error_code", "")) == "P3_RESOURCE_STATE_REQUIRED",
		"aggregate cannot masquerade mined P3 Item Graph state as legacy P2 durable state"
	)

	var stripped_replay := replay_state.duplicate(true)
	stripped_replay.erase("resource_replay")
	stripped_replay["checksum"] = ""
	stripped_replay = NetworkUtils.finalize_json_checksum(stripped_replay)
	var stripped_replay_validation: Dictionary = service.validate_replay_state(stripped_replay)
	_assert(
		not bool(stripped_replay_validation.get("success", false))
		and String(stripped_replay_validation.get("error_code", "")) == "P3_RESOURCE_REPLAY_REQUIRED",
		"aggregate cannot drop resource replay ledger after trusted resource output"
	)

	var restored = P3GameplayService.new()
	var restored_durable: Dictionary = restored.restore_durable_state(durable)
	_assert(bool(restored_durable.get("success", false)), "fresh aggregate restores P3 gameplay + Item Graph + resource state")
	if not bool(restored_durable.get("success", false)):
		return
	var restored_replay: Dictionary = restored.restore_replay_state(replay_state)
	_assert(bool(restored_replay.get("success", false)), "fresh aggregate restores P3 replay state")
	if not bool(restored_replay.get("success", false)):
		return
	var restored_resource: Dictionary = restored.create_resource_mining_snapshot()
	var restored_item: Dictionary = restored.create_canonical_item_graph_snapshot()
	_assert(
		String(restored_resource.get("checksum", "")) == String(stored_resource_snapshot.get("checksum", ""))
		and int(restored_resource.get("generation", -1)) == int(stored_resource_snapshot.get("generation", -2))
		and int(_resource_node(restored_resource, NODE_ID).get("remaining_units", -1)) == 7,
		"fresh aggregate reconstructs exact durable resource checksum/generation and depleted node"
	)
	_assert(
		String(restored_item.get("checksum", "")) == String(stored_item_snapshot.get("checksum", ""))
		and int(restored_item.get("revision", -1)) == int(stored_item_snapshot.get("revision", -2))
		and int(restored_item.get("tick", -1)) == int(stored_item_snapshot.get("tick", -2))
		and not _find_item(restored_item, output_item_id).is_empty(),
		"fresh aggregate reconstructs exact durable Item Graph checksum/clock and mined output"
	)
	_assert(restored.has_durable_replay_operation(mine_operation), "fresh aggregate restores resource replay lookup")

	var session_b := "transport-session/v0-p3/a/2"
	var rejoined: Dictionary = restored.join(PLAYER_ID, session_b, "operation/v0-p3/aggregate/rejoin-a")
	_assert(bool(rejoined.get("success", false)), "recovered canonical player rejoins with new transport session")
	if not bool(rejoined.get("success", false)):
		return
	var rejoined_player: Dictionary = restored.get_player(PLAYER_ID)
	var new_epoch := int(rejoined_player.get("ownership_epoch", 0))
	_assert(new_epoch > ownership_epoch, "recovered player ownership epoch advances on reconnect")
	var resource_before_replay: Dictionary = restored.create_resource_mining_snapshot()
	var item_before_replay: Dictionary = restored.create_canonical_item_graph_snapshot()
	var gameplay_before_replay: Dictionary = restored.create_snapshot()
	var replay: Dictionary = restored.handle_resource_mine(
		PLAYER_ID,
		session_b,
		new_epoch,
		mine_operation,
		mine_payload
	)
	_assert(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "post-recovery exact resource operation replays")
	_assert(String(replay.get("details", {}).get("output_item_id", "")) == output_item_id, "post-recovery replay preserves output item identity")
	_assert(restored.create_resource_mining_snapshot() == resource_before_replay, "post-recovery replay does not deplete resource twice")
	_assert(restored.create_canonical_item_graph_snapshot() == item_before_replay, "post-recovery replay does not mint ore twice")
	_assert(restored.create_snapshot() == gameplay_before_replay, "post-recovery replay does not advance outer gameplay canonical state")
	_assert(_count_item_id(restored.create_canonical_item_graph_snapshot(), output_item_id) == 1, "fresh aggregate contains exactly one deterministic mined output item")


func _move_to(service, session_id: String, ownership_epoch: int, target: Dictionary) -> bool:
	var sequence := 0
	for step in range(6):
		var player: Dictionary = service.get_player(PLAYER_ID)
		var position: Dictionary = Dictionary(player.get("position", {}))
		var remaining_x := float(target.get("x", 0.0)) - float(position.get("x", 0.0))
		var remaining_z := float(target.get("z", 0.0)) - float(position.get("z", 0.0))
		if sqrt(remaining_x * remaining_x + remaining_z * remaining_z) <= 0.25:
			return true
		sequence += 1
		var delta_x := clampf(remaining_x, -9.0, 9.0)
		var delta_z := clampf(remaining_z, -9.0, 9.0)
		var moved: Dictionary = service.move_player(
			PLAYER_ID,
			session_id,
			ownership_epoch,
			sequence,
			delta_x,
			delta_z,
			"operation/v0-p3/aggregate/move-%d" % step
		)
		if not bool(moved.get("success", false)):
			return false
	var final_player: Dictionary = service.get_player(PLAYER_ID)
	var final_position: Dictionary = Dictionary(final_player.get("position", {}))
	var final_x := float(target.get("x", 0.0)) - float(final_position.get("x", 0.0))
	var final_z := float(target.get("z", 0.0)) - float(final_position.get("z", 0.0))
	return sqrt(final_x * final_x + final_z * final_z) <= 0.25


func _resource_node(snapshot: Dictionary, resource_node_id: String) -> Dictionary:
	for node_value in snapshot.get("nodes", []):
		if node_value is Dictionary and String(node_value.get("resource_node_id", "")) == resource_node_id:
			return Dictionary(node_value).duplicate(true)
	return {}


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _count_item_id(snapshot: Dictionary, item_id: String) -> int:
	var count := 0
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			count += 1
	return count


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("FAIL: %s" % label)


func _finish() -> void:
	print("V0-P3 aggregate resource recovery: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
