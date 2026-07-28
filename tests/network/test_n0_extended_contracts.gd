extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")
const DeltaScript = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const LeaseScript = preload("res://scripts/network/contracts/authority_lease.gd")
const RouteScript = preload("res://scripts/network/contracts/authority_route.gd")
const SpaceScript = preload("res://scripts/network/contracts/simulation_space_descriptor.gd")
const NodeScript = preload("res://scripts/network/contracts/simulation_node_descriptor.gd")
const RegionScript = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const GhostScript = preload("res://scripts/network/contracts/ghost_replica_state.gd")
const ClientRouteScript = preload("res://scripts/network/contracts/client_route.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var loopback: Dictionary = EndpointScript.create("LOOPBACK", "", 0, "commands")
	var enet: Dictionary = EndpointScript.create("ENET", "127.0.0.1", 19001, "simulation")
	_assert_ok(EndpointScript.validate(loopback), "Valid loopback endpoint rejected")
	_assert_ok(EndpointScript.validate(enet), "Valid ENET endpoint rejected")
	var bad_loopback: Dictionary = loopback.duplicate(true)
	bad_loopback["port"] = 7
	_assert_code(EndpointScript.validate(bad_loopback), "INVALID_ENDPOINT", "Loopback port accepted")
	var extra_endpoint: Dictionary = enet.duplicate(true)
	extra_endpoint["path"] = "/socket"
	_assert_code(EndpointScript.validate(extra_endpoint), "UNEXPECTED_FIELD", "Endpoint extra field accepted")

	var token_hash: String = "lease-token".sha256_text()
	var lease: Dictionary = LeaseScript.create(
		"lease/entity/1", "ENTITY", "entity/probe", "sim-a", 4,
		100, 140, 200, 12, token_hash
	)
	_assert_ok(LeaseScript.validate(lease), "Valid authority lease rejected")
	_assert(LeaseScript.is_active_at_tick(lease, 120), "Active lease was reported inactive")
	_assert(not LeaseScript.can_renew_at_tick(lease, 139), "Lease renewed before renew_after_tick")
	_assert(LeaseScript.can_renew_at_tick(lease, 140), "Lease could not renew at renew_after_tick")
	_assert(not LeaseScript.is_active_at_tick(lease, 200), "Expired lease reported active")
	var bad_window: Dictionary = lease.duplicate(true)
	bad_window["renew_after_tick"] = 200
	_assert_code(LeaseScript.validate(bad_window), "INVALID_LEASE_WINDOW", "Invalid lease window accepted")
	var bad_token: Dictionary = lease.duplicate(true)
	bad_token["lease_token_hash"] = "ABC"
	_assert_code(LeaseScript.validate(bad_token), "INVALID_TOKEN_HASH", "Invalid token hash accepted")
	var unsafe_lease: Dictionary = lease.duplicate(true)
	unsafe_lease["issued_at_tick"] = 9007199254740993
	_assert_code(LeaseScript.validate(unsafe_lease), "INVALID_FIELD_TYPE", "Unsafe lease tick accepted")

	var route: Dictionary = RouteScript.create(
		"route/entity/1", "ENTITY", "entity/probe", "sim-a", 4,
		"lease/entity/1", "region/moon/a", enet, 2, 100, 200
	)
	_assert_ok(RouteScript.validate(route), "Valid authority route rejected")
	_assert(RouteScript.normalize(route) == RouteScript.normalize(RouteScript.normalize(route)), "Route normalization is not idempotent")
	var invalid_route_endpoint: Dictionary = route.duplicate(true)
	invalid_route_endpoint["endpoint"] = {"transport": "ENET"}
	_assert_code(RouteScript.validate(invalid_route_endpoint), "INVALID_ENDPOINT", "Invalid route endpoint accepted")
	var expired_route: Dictionary = route.duplicate(true)
	expired_route["expires_at_tick"] = 100
	_assert_code(RouteScript.validate(expired_route), "INVALID_ROUTE_WINDOW", "Zero-length route window accepted")
	var region_route: Dictionary = RouteScript.create(
		"route/region/1", "REGION", "region/moon/a", "sim-a", 4,
		"lease/region/1", "region/moon/b", enet, 1, 100, 200
	)
	_assert_code(RouteScript.validate(region_route), "REGION_ROUTE_MISMATCH", "Mismatched REGION route accepted")

	var space: Dictionary = SpaceScript.create(
		"moon", "persistent", "main", "body/moon/fixed", "cube_sphere", 1,
		["region/moon/b", "region/moon/a"], 3
	)
	_assert_ok(SpaceScript.validate(space), "Valid space descriptor rejected")
	_assert(SpaceScript.normalize(space)["authority_region_ids"] == ["region/moon/a", "region/moon/b"], "Space region IDs were not canonicalized")
	var duplicate_regions: Dictionary = space.duplicate(true)
	duplicate_regions["authority_region_ids"] = ["region/moon/a", "region/moon/a"]
	_assert_code(SpaceScript.validate(duplicate_regions), "DUPLICATE_VALUE", "Duplicate region IDs accepted")

	var node: Dictionary = NodeScript.create(
		"sim-a", "simulation-server", "build-a", "v16.4.0-foundation-n0",
		"persistent", [space], enet, ["snapshot", "command", "delta"],
		"READY", 10, 20, 2
	)
	_assert_ok(NodeScript.validate(node), "Valid node descriptor rejected")
	_assert(not NodeScript.descriptor_hash(node).is_empty(), "Node descriptor hash is empty")
	_assert(NodeScript.descriptor_hash(node) == NodeScript.descriptor_hash(NodeScript.normalize(node)), "Node descriptor hash changed after normalization")
	var duplicate_capabilities: Dictionary = node.duplicate(true)
	duplicate_capabilities["capabilities"] = ["delta", "delta"]
	_assert_code(NodeScript.validate(duplicate_capabilities), "DUPLICATE_CAPABILITY", "Duplicate capabilities accepted")
	var duplicate_spaces: Dictionary = node.duplicate(true)
	duplicate_spaces["spaces"] = [space, space]
	_assert_code(NodeScript.validate(duplicate_spaces), "DUPLICATE_SPACE", "Duplicate spaces accepted")
	var invalid_role: Dictionary = node.duplicate(true)
	invalid_role["runtime_role"] = "directory"
	_assert_code(NodeScript.validate(invalid_role), "INVALID_ENUM", "Unknown node role accepted")
	var server_without_spaces: Dictionary = node.duplicate(true)
	server_without_spaces["spaces"] = []
	_assert_code(NodeScript.validate(server_without_spaces), "NODE_SPACES_REQUIRED", "Simulation server without spaces accepted")
	var mismatched_space: Dictionary = space.duplicate(true)
	mismatched_space["instance_id"] = "other-instance"
	var node_with_mismatched_space: Dictionary = node.duplicate(true)
	node_with_mismatched_space["spaces"] = [mismatched_space]
	_assert_code(NodeScript.validate(node_with_mismatched_space), "INSTANCE_ID_MISMATCH", "Node accepted space from another instance")

	var prefix_selector: Dictionary = {
		"kind": "PARTITION_PREFIX",
		"partition_prefix": "universe/main/instance/persistent/space/moon/partition/cube_sphere/revision/1/zone/f1",
		"chunk_ids": [],
	}
	var region: Dictionary = RegionScript.create(
		"region/moon/a", "main", "persistent", "moon", "cube_sphere", 1,
		prefix_selector, "sim-a", 4, "ACTIVE", 2
	)
	_assert_ok(RegionScript.validate(region), "Valid authority region rejected")
	var invalid_global: Dictionary = region.duplicate(true)
	invalid_global["selector"] = {"kind": "GLOBAL_SPACE", "partition_prefix": "x", "chunk_ids": []}
	_assert_code(RegionScript.validate(invalid_global), "INVALID_SELECTOR", "Invalid GLOBAL_SPACE selector accepted")
	var duplicate_chunks: Dictionary = region.duplicate(true)
	duplicate_chunks["selector"] = {"kind": "CHUNK_SET", "partition_prefix": "", "chunk_ids": ["chunk/a", "chunk/a"]}
	_assert_code(RegionScript.validate(duplicate_chunks), "INVALID_CHUNK_SET", "Duplicate chunk set accepted")

	var snapshot_hash: String = "snapshot".sha256_text()
	var ghost: Dictionary = GhostScript.create(
		"replica/1", "entity/probe", "sim-a", 4, 12, snapshot_hash,
		"region/moon/interest", 300, 340
	)
	_assert_ok(GhostScript.validate(ghost), "Valid ghost replica rejected")
	var writable_ghost: Dictionary = ghost.duplicate(true)
	writable_ghost["read_only"] = false
	_assert_code(GhostScript.validate(writable_ghost), "GHOST_MUST_BE_READ_ONLY", "Writable ghost accepted")
	var bad_ghost_window: Dictionary = ghost.duplicate(true)
	bad_ghost_window["expires_at_tick"] = 300
	_assert_code(GhostScript.validate(bad_ghost_window), "INVALID_REPLICA_WINDOW", "Invalid ghost expiry accepted")

	var client_route: Dictionary = ClientRouteScript.create(
		"client-route/1", "client/1", "entity/player", "sim-a", "sim-b", 4,
		100, 180, "handoff_overlap", 7, enet,
		EndpointScript.create("ENET", "127.0.0.1", 19002, "simulation")
	)
	_assert_ok(ClientRouteScript.validate(client_route), "Valid client route rejected")
	var same_nodes: Dictionary = client_route.duplicate(true)
	same_nodes["secondary_node_id"] = "sim-a"
	_assert_code(ClientRouteScript.validate(same_nodes), "DUPLICATE_ROUTE_NODE", "Duplicate client route nodes accepted")
	var missing_secondary_endpoint: Dictionary = client_route.duplicate(true)
	missing_secondary_endpoint["secondary_node_id"] = ""
	_assert_code(ClientRouteScript.validate(missing_secondary_endpoint), "INVALID_SECONDARY_ROUTE", "Orphan secondary endpoint accepted")

	var delta: Dictionary = DeltaScript.create(
		"delta/1", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501,
		{
			"physics_state.sleeping": false,
			"domain_components.signal": {"enabled": true},
		},
		["domain_components.legacy_component"]
	)
	_assert_ok(DeltaScript.validate(delta), "Valid entity delta rejected")
	_assert(not String(delta["checksum"]).is_empty(), "Delta checksum is empty")
	_assert(DeltaScript.compute_checksum(delta) == String(delta["checksum"]), "Delta checksum mismatch")
	var base_snapshot: Dictionary = SnapshotScript.create(
		"snapshot/probe/12", "entity/probe", "world_item", 12, "sim-a", 4, 500,
		SpatialRefScript.create("body/moon/fixed", Vector3.ZERO), {}, {"sleeping": false},
		{"legacy_component": {"old": true}}
	)
	var applied: Dictionary = DeltaScript.apply_to_snapshot(base_snapshot, delta)
	_assert_ok(applied, "Valid delta application failed")
	_assert(not applied["snapshot"]["domain_components"].has("legacy_component"), "Replaced domain components retained legacy component")
	_assert(int(applied["snapshot"]["state_revision"]) == 13, "Delta did not advance revision")
	var tampered: Dictionary = delta.duplicate(true)
	tampered["changed_fields"] = {"physics_state": {"sleeping": true}}
	_assert_code(DeltaScript.validate(tampered), "CHECKSUM_MISMATCH", "Tampered delta accepted")
	var empty_delta: Dictionary = DeltaScript.create("delta/2", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501, {}, [])
	_assert_code(DeltaScript.validate(empty_delta), "EMPTY_DELTA", "Empty delta accepted")
	var conflict_delta: Dictionary = DeltaScript.create("delta/3", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501, {"domain_components.x": 1}, ["domain_components.x"])
	_assert_code(DeltaScript.validate(conflict_delta), "DELTA_FIELD_CONFLICT", "Changed/removed field conflict accepted")
	var stale_apply: Dictionary = base_snapshot.duplicate(true)
	stale_apply["state_revision"] = 11
	stale_apply["checksum"] = SnapshotScript.compute_checksum(stale_apply)
	_assert_code(DeltaScript.apply_to_snapshot(stale_apply, delta), "BASE_REVISION_MISMATCH", "Delta applied to wrong base revision")
	var wrong_type_snapshot: Dictionary = base_snapshot.duplicate(true)
	wrong_type_snapshot["entity_type"] = "player"
	wrong_type_snapshot["checksum"] = SnapshotScript.compute_checksum(wrong_type_snapshot)
	_assert_code(DeltaScript.apply_to_snapshot(wrong_type_snapshot, delta), "ENTITY_TYPE_MISMATCH", "Delta applied to wrong entity type")
	var protected_change: Dictionary = DeltaScript.create("delta/protected/1", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501, {"entity_id": "entity/other"}, [])
	_assert_code(DeltaScript.validate(protected_change), "PROTECTED_DELTA_FIELD", "Delta changed protected entity_id")
	var protected_remove: Dictionary = DeltaScript.create("delta/protected/2", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501, {}, ["authority_epoch"])
	_assert_code(DeltaScript.validate(protected_remove), "PROTECTED_DELTA_FIELD", "Delta removed protected authority_epoch")
	var root_remove: Dictionary = DeltaScript.create("delta/protected/root", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501, {}, ["physics_state"])
	_assert_code(DeltaScript.validate(root_remove), "PROTECTED_DELTA_FIELD", "Delta removed required snapshot root")
	var overlapping_paths: Dictionary = DeltaScript.create(
		"delta/overlap/1", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501,
		{"domain_components": {}, "domain_components.item": {}}, []
	)
	_assert_code(DeltaScript.validate(overlapping_paths), "DELTA_FIELD_CONFLICT", "Overlapping delta paths accepted")
	var missing_remove: Dictionary = DeltaScript.create(
		"delta/missing/remove", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501,
		{}, ["domain_components.missing"]
	)
	_assert_code(DeltaScript.apply_to_snapshot(base_snapshot, missing_remove), "DELTA_PATH_NOT_FOUND", "Missing delta removal path accepted")
	var scalar_parent: Dictionary = DeltaScript.create(
		"delta/scalar/parent", "entity/probe", "world_item", 12, 13, "sim-a", 4, 501,
		{"physics_state.sleeping.value": true}, []
	)
	_assert_code(DeltaScript.apply_to_snapshot(base_snapshot, scalar_parent), "INVALID_DELTA_PATH", "Delta traversed scalar parent")
	var unsafe_delta: Dictionary = delta.duplicate(true)
	unsafe_delta["changed_fields"] = {"physics_state.counter": 9007199254740993}
	_assert_code(DeltaScript.validate(unsafe_delta), "NON_CANONICAL_PAYLOAD", "Unsafe nested delta integer accepted")
	var runtime_node := Node.new()
	var runtime_base: Dictionary = base_snapshot.duplicate(true)
	runtime_base["physics_state"] = {"node": runtime_node}
	_assert_code(DeltaScript.apply_to_snapshot(runtime_base, delta), "INVALID_BASE_SNAPSHOT", "Runtime object in base snapshot accepted")
	runtime_node.free()

	_finish()


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_code(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N0 extended contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 extended contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
