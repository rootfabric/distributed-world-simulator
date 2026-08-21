extends SceneTree

const FrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const WorldDescriptorScript = preload("res://scripts/network/gateway/world_descriptor.gd")
const WorldRelationScript = preload("res://scripts/network/gateway/world_relation.gd")
const WorldGraphScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")
const ClientWorldViewScript = preload("res://scripts/network/gateway/client_world_view.gd")
const InterestPlanScript = preload("res://scripts/network/gateway/aggregated_interest_plan.gd")
const ConnectGateScript = preload("res://scripts/network/gateway/gateway_connect_gate.gd")
const CollisionProofScript = preload("res://scripts/network/gateway/collision_proof.gd")
const CollisionQueryScript = preload("res://scripts/network/gateway/collision_query.gd")

var assertions: int = 0
var failures: Array[String] = []

func _init() -> void:
	_test_client_surface_topology_fence()
	_test_world_graph_nested_topology_fence()
	_test_graph_revision_provenance()
	_test_connect_gate_evidence_correlation()
	_test_collision_proof_provenance()
	_finish()

func _test_client_surface_topology_fence() -> void:
	var frame := FrameScript.create(
		"frame/test/snapshot-r6", "gateway-session/test/a", "WORLD_TO_CLIENT",
		"AUTHORITATIVE_SNAPSHOT", 10, "planet_simulator.test_snapshot.v1",
		{"revision": 1, "nested": [{"simulation_server_endpoint": "10.0.0.2:7777"}]},
	)
	_assert_error(FrameScript.validate(frame), "CLIENT_TOPOLOGY_METADATA_FORBIDDEN", "Client frame leaked simulation endpoint")
	frame["payload"] = {"revision": 1, "nested": {"peer_id": 42}}
	_assert_error(FrameScript.validate(frame), "CLIENT_TOPOLOGY_METADATA_FORBIDDEN", "Client frame leaked peer_id")
	frame["payload"] = {"revision": 1, "backend_link_id": "backend-link/test/leak"}
	_assert_error(FrameScript.validate(frame), "CLIENT_TOPOLOGY_METADATA_FORBIDDEN", "Client frame leaked backend link")

func _world(world_id: String, revision: int) -> Dictionary:
	return WorldDescriptorScript.create(
		world_id, "planet_surface", "reference-frame/test/sol",
		{"kind": "bounded", "partition": 0}, {"kind": "sphere", "radius": 1000},
		"authority-subject/test/a", ["fine"], {"read_only": true, "allows_mutation": false},
		["fine"], {"neighbor_depth": 1}, {"max_projection_neighbors": 4}, revision,
	)

func _relation(revision: int) -> Dictionary:
	return WorldRelationScript.create(
		"world-relation/test/a-b", "world/test/a", "world/test/b", "NEIGHBOR",
		{"kind": "seam"}, {"kind": "shared_parent"}, {"read_only": true, "allows_mutation": false}, revision,
	)

func _test_world_graph_nested_topology_fence() -> void:
	var world := _world("world/test/a", 3)
	world["projection_policy"]["backend_link_id"] = "backend-link/test/leak"
	_assert_error(WorldDescriptorScript.validate(world), "WORLD_GRAPH_RUNTIME_METADATA_FORBIDDEN", "WorldDescriptor projection policy leaked backend link")
	world = _world("world/test/a", 3)
	world["spatial_domain"]["peer_id"] = 42
	_assert_error(WorldDescriptorScript.validate(world), "WORLD_GRAPH_RUNTIME_METADATA_FORBIDDEN", "WorldDescriptor spatial domain leaked peer_id")
	var relation := _relation(7)
	relation["reference_frame_relation"]["backend_connection_id"] = "backend-connection/test/leak"
	_assert_error(WorldRelationScript.validate(relation), "WORLD_GRAPH_RUNTIME_METADATA_FORBIDDEN", "WorldRelation leaked backend connection")
	var plan := InterestPlanScript.create(
		"interest-plan/test/b", "world/test/b", "PROJECTION", "fine", ["gateway-session/test/a"], 1,
		{"bytes_per_second": 1000, "backend_link_id": "backend-link/test/leak"}, 9, 6, true,
	)
	_assert_error(InterestPlanScript.validate(plan), "DERIVED_ROUTING_RUNTIME_METADATA_FORBIDDEN", "Interest budget leaked backend link")
	var duplicate_plan := InterestPlanScript.create(
		"interest-plan/test/b", "world/test/b", "PROJECTION", "fine", ["gateway-session/test/a", "gateway-session/test/a"], 1,
		{"bytes_per_second": 1000}, 9, 6, true,
	)
	_assert_error(InterestPlanScript.validate(duplicate_plan), "DUPLICATE_SUBSCRIBER_SESSION", "Duplicate interest subscriber accepted")

func _test_graph_revision_provenance() -> void:
	var worlds := [_world("world/test/a", 3), _world("world/test/b", 4)]
	var relations := [_relation(7)]
	var current := WorldGraphScript.reconstruct_from_directory("world-graph/test/ab", 11, 9, worlds, relations)
	_assert_ok(WorldGraphScript.validate(current), "Current WorldGraph fixture invalid")
	var stale_world := current.duplicate(true)
	stale_world["graph_revision"] = 10
	stale_world["worlds"][0]["world_revision"] = 2
	_assert_error(WorldGraphScript.validate_newer(stale_world, current), "STALE_NESTED_WORLD_REVISION", "New graph accepted stale nested world")
	var stale_relation := current.duplicate(true)
	stale_relation["graph_revision"] = 10
	stale_relation["relations"][0]["relation_revision"] = 6
	_assert_error(WorldGraphScript.validate_newer(stale_relation, current), "STALE_NESTED_RELATION_REVISION", "New graph accepted stale nested relation")
	var reused_revision := current.duplicate(true)
	reused_revision["graph_revision"] = 10
	reused_revision["worlds"][0]["coverage"]["radius"] = 1001
	_assert_error(WorldGraphScript.validate_newer(reused_revision, current), "WORLD_REVISION_REUSED_WITH_DIFFERENT_CONTENT", "Equal world revision accepted changed content")

	var view := ClientWorldViewScript.create(
		"world-view/test/a", "gateway-session/test/a", "world/test/a", "reference-frame/test/sol", "world/test/a", [], [], [], 9, 5, 6, true,
	)
	var stale_view := view.duplicate(true)
	stale_view["graph_revision"] = 8
	stale_view["view_revision"] = 6
	_assert_error(ClientWorldViewScript.validate_newer(stale_view, view), "STALE_GRAPH_REVISION", "New view accepted older graph revision")

	var plan := InterestPlanScript.create(
		"interest-plan/test/b", "world/test/b", "PROJECTION", "fine", ["gateway-session/test/a"], 1,
		{"bytes_per_second": 1000}, 9, 6, true,
	)
	var stale_plan := plan.duplicate(true)
	stale_plan["graph_revision"] = 8
	stale_plan["interest_revision"] = 7
	_assert_error(InterestPlanScript.validate_newer(stale_plan, plan), "STALE_GRAPH_REVISION", "New interest plan accepted older graph revision")

func _valid_gate() -> Dictionary:
	var session := {
		"schema": "planet_simulator.gateway_session_binding.v1", "protocol_version": 1,
		"gateway_session_id": "gateway-session/test/a", "client_session_id": "client-session/test/a",
		"logical_player_id": "player/test/alice", "player_entity_id": "entity/test/player-alice",
		"world_id": "world/test/b", "binding_revision": 5, "state": "ATTACHED",
	}
	var placement := {
		"placement_evidence_id": "placement-evidence/test/a", "source_owner": "SESSION_PLACEMENT",
		"client_session_id": "client-session/test/a", "logical_player_id": "player/test/alice",
		"player_entity_id": "entity/test/player-alice", "world_id": "world/test/b", "placement_revision": 6,
	}
	var directory := {
		"authority_resolution_id": "authority-resolution/test/b", "source_owner": "WORLD_DIRECTORY",
		"player_entity_id": "entity/test/player-alice", "world_id": "world/test/b",
		"authority_id": "authority/test/b", "server_instance_id": "server-instance/test/b-1",
		"directory_generation": 20, "authority_epoch": 52,
	}
	var route := {
		"schema": "planet_simulator.gateway_route_binding.v1", "protocol_version": 1,
		"route_binding_id": "gateway-route/test/b", "gateway_session_id": "gateway-session/test/a",
		"player_entity_id": "entity/test/player-alice", "authority_id": "authority/test/b",
		"server_instance_id": "server-instance/test/b-1", "observed_authority_epoch": 52,
		"route_revision": 52, "route_role": "ACTIVE",
	}
	var ready := {
		"ready_snapshot_id": "ready-snapshot/test/a", "source_owner": "AUTHORITY",
		"gateway_session_id": "gateway-session/test/a", "player_entity_id": "entity/test/player-alice",
		"world_id": "world/test/b", "authority_id": "authority/test/b", "authority_epoch": 52,
		"snapshot_revision": 7,
	}
	return ConnectGateScript.create(
		"connect-attempt/test/a", "transport-connection/test/a", "gateway/test/g1", 3, 4,
		true, true, true, true, true, true, true, true, 8,
		session, placement, directory, route, ready,
	)

func _test_connect_gate_evidence_correlation() -> void:
	var gate := _valid_gate()
	_assert_ok(ConnectGateScript.validate(gate), "Valid evidence-bound ConnectGate rejected")
	_assert(int(gate["route_revision"]) == int(gate["authority_epoch"]), "Fixture must prove numeric equality is legal")
	var session_world_mismatch := gate.duplicate(true)
	session_world_mismatch["session_binding"]["world_id"] = "world/test/a"
	_assert_error(ConnectGateScript.validate(session_world_mismatch), "CONNECT_PLACEMENT_EVIDENCE_MISMATCH", "ConnectGate accepted session/placement world mismatch")
	var route_authority_mismatch := gate.duplicate(true)
	route_authority_mismatch["route_binding"]["authority_id"] = "authority/test/a"
	_assert_error(ConnectGateScript.validate(route_authority_mismatch), "CONNECT_ROUTE_EVIDENCE_MISMATCH", "ConnectGate accepted route authority mismatch")
	var directory_world_mismatch := gate.duplicate(true)
	directory_world_mismatch["directory_authority_evidence"]["world_id"] = "world/test/a"
	_assert_error(ConnectGateScript.validate(directory_world_mismatch), "CONNECT_DIRECTORY_EVIDENCE_MISMATCH", "ConnectGate accepted Directory world mismatch")
	var ready_epoch_mismatch := gate.duplicate(true)
	ready_epoch_mismatch["ready_snapshot_evidence"]["authority_epoch"] = 51
	_assert_error(ConnectGateScript.validate(ready_epoch_mismatch), "CONNECT_READY_EVIDENCE_MISMATCH", "ConnectGate accepted ready snapshot epoch mismatch")
	var session_not_attached := gate.duplicate(true)
	session_not_attached["session_binding"]["state"] = "RESUMING"
	_assert_error(ConnectGateScript.validate(session_not_attached), "CONNECT_SESSION_NOT_ATTACHED", "ConnectGate accepted non-ATTACHED session")
	var warm_route := gate.duplicate(true)
	warm_route["route_binding"]["route_role"] = "WARM"
	_assert_error(ConnectGateScript.validate(warm_route), "CONNECT_ROUTE_NOT_ACTIVE", "ConnectGate accepted non-ACTIVE route")

func _time(mapping_revision: int = 9) -> Dictionary:
	return {"schema": "planet_simulator.interaction_time.v1", "protocol_version": 1, "simulation_epoch": 4, "canonical_time": 1234.5, "source_local_tick": 74067, "time_mapping_revision": mapping_revision}

func _query() -> Dictionary:
	var evidence := {"schema": "planet_simulator.reference_frame_evidence.v1", "protocol_version": 1, "source_reference_frame_id": "reference-frame/test/world-b", "target_reference_frame_id": "reference-frame/test/world-a", "transform_revision": 17, "world_graph_revision": 31}
	var segment := {"schema": "planet_simulator.interaction_domain_segment.v1", "protocol_version": 1, "world_id": "world/test/a", "authority_ref": "authority/test/a", "path_t_start": 0.2, "path_t_end": 0.8, "reference_frame_evidence": evidence, "relation_revision": 22}
	return CollisionQueryScript.create("interaction/test/shot-1", _time(), segment, 31, 61, 2)

func _proof() -> Dictionary:
	return CollisionProofScript.create(
		"interaction/test/shot-1", 2, "world/test/a", "authority/test/a", 61, 0.2, 0.8,
		0.44, "entity/test/player-bob", "ENTITY", "torso", _time(), 45, 17, 3,
	)

func _test_collision_proof_provenance() -> void:
	var query := _query()
	var proof := _proof()
	_assert_ok(CollisionProofScript.validate_against_query(proof, query), "Valid proof/query provenance rejected")
	var wrong_query := proof.duplicate(true)
	wrong_query["query_revision"] = 3
	_assert_error(CollisionProofScript.validate_against_query(wrong_query, query), "PROOF_QUERY_MISMATCH", "Proof accepted wrong query revision")
	var stale_epoch := proof.duplicate(true)
	stale_epoch["authority_epoch"] = 60
	_assert_error(CollisionProofScript.validate_against_query(stale_epoch, query), "STALE_AUTHORITY_EPOCH_EVIDENCE", "Proof accepted stale authority epoch")
	var stale_transform := proof.duplicate(true)
	stale_transform["transform_revision"] = 16
	_assert_error(CollisionProofScript.validate_against_query(stale_transform, query), "STALE_TRANSFORM_EVIDENCE", "Proof accepted stale transform")
	var stale_time := proof.duplicate(true)
	stale_time["interaction_time"]["time_mapping_revision"] = 8
	_assert_error(CollisionProofScript.validate_against_query(stale_time, query), "STALE_INTERACTION_TIME_EVIDENCE", "Proof accepted stale interaction time")
	var newer_bad := proof.duplicate(true)
	newer_bad["proof_revision"] = 4
	newer_bad["authority_epoch"] = 60
	_assert_error(CollisionProofScript.validate_newer(newer_bad, proof), "PROOF_LINEAGE_CHANGED", "Higher proof revision hid stale authority epoch")
	var newer_good := proof.duplicate(true)
	newer_good["proof_revision"] = 4
	_assert_ok(CollisionProofScript.validate_newer(newer_good, proof), "Valid newer proof rejected")

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("EG0 R6 review repairs: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("EG0 R6 review repairs: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
