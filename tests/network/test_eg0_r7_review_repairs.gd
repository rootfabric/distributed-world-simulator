extends SceneTree

const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const FrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const WorldDescriptorScript = preload("res://scripts/network/gateway/world_descriptor.gd")
const WorldRelationScript = preload("res://scripts/network/gateway/world_relation.gd")
const WorldGraphScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")
const InterestPlanScript = preload("res://scripts/network/gateway/aggregated_interest_plan.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_client_schema_boundary()
	_test_world_graph_semantic_subschemas()
	_test_absence_reintroduction_provenance()
	_finish()


func _test_client_schema_boundary() -> void:
	var valid := FrameScript.create(
		"frame/test/r7-snapshot",
		"gateway-session/test/a",
		"WORLD_TO_CLIENT",
		"AUTHORITATIVE_SNAPSHOT",
		1,
		"planet_simulator.test_snapshot.v1",
		{"revision": 1},
	)
	_assert_ok(FrameScript.validate(valid), "Registered topology-neutral snapshot schema rejected")

	var alias := valid.duplicate(true)
	alias["payload"]["backend_endpoint"] = "10.0.0.2:7777"
	_assert_error(
		FrameScript.validate(alias),
		"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
		"Registered client schema accepted backend_endpoint alias",
	)

	var arbitrary_alias := valid.duplicate(true)
	arbitrary_alias["payload"]["delivery_target"] = "10.0.0.2:7777"
	_assert_error(
		FrameScript.validate(arbitrary_alias),
		"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
		"Registered client schema accepted arbitrary endpoint alias under unrelated spelling",
	)

	var unknown_schema := valid.duplicate(true)
	unknown_schema["payload_schema"] = "planet_simulator.future_snapshot.v1"
	_assert_error(
		FrameScript.validate(unknown_schema),
		"UNREGISTERED_CLIENT_PAYLOAD_SCHEMA",
		"Unregistered client payload schema was exposed to client",
	)

	_assert_ok(
		GatewayUtilsScript.validate_payload({"backend_link_id": "backend-link/test/server-side"}),
		"Generic/server-side payload validation was incorrectly tightened by client schema fence",
	)


func _world(world_id: String, revision: int, radius: int = 1000) -> Dictionary:
	return WorldDescriptorScript.create(
		world_id,
		"planet_surface",
		"reference-frame/test/sol",
		{"kind": "bounded", "partition": 0},
		{"kind": "sphere", "radius": radius},
		"authority-subject/test/%s" % world_id.get_file(),
		["fine"],
		{"read_only": true, "allows_mutation": false},
		["fine"],
		{"neighbor_depth": 1},
		{"max_projection_neighbors": 4},
		revision,
	)


func _relation(revision: int) -> Dictionary:
	return WorldRelationScript.create(
		"world-relation/test/a-b",
		"world/test/a",
		"world/test/b",
		"NEIGHBOR",
		{"kind": "seam", "id": "seam-a-b"},
		{"kind": "shared_parent"},
		{"read_only": true, "allows_mutation": false},
		revision,
	)


func _test_world_graph_semantic_subschemas() -> void:
	var world := _world("world/test/a", 3)
	world["spatial_domain"]["physical_backend_endpoint"] = "10.0.0.2:7777"
	_assert_error(
		WorldDescriptorScript.validate(world),
		"UNEXPECTED_SEMANTIC_FIELD",
		"WorldDescriptor accepted physical_backend_endpoint alias",
	)

	world = _world("world/test/a", 3)
	world["projection_policy"]["nested"] = {"upstream_endpoint": "server-b.internal:7777"}
	_assert_error(
		WorldDescriptorScript.validate(world),
		"UNEXPECTED_SEMANTIC_FIELD",
		"WorldDescriptor accepted arbitrary nested projection-policy extension",
	)

	var relation := _relation(7)
	relation["reference_frame_relation"]["physical_route"] = "route-b"
	_assert_error(
		WorldRelationScript.validate(relation),
		"UNEXPECTED_SEMANTIC_FIELD",
		"WorldRelation accepted physical routing alias",
	)

	var plan := InterestPlanScript.create(
		"interest-plan/test/b",
		"world/test/b",
		"PROJECTION",
		"fine",
		["gateway-session/test/a"],
		1,
		{"bytes_per_second": 1000, "backend_endpoint": "10.0.0.2:7777"},
		9,
		6,
		true,
	)
	_assert_error(
		InterestPlanScript.validate(plan),
		"UNEXPECTED_SEMANTIC_FIELD",
		"AggregatedInterestPlan accepted backend_endpoint alias",
	)

	_assert_ok(WorldDescriptorScript.validate(_world("world/test/a", 3)), "Registered WorldDescriptor semantic fields rejected")
	_assert_ok(WorldRelationScript.validate(_relation(7)), "Registered WorldRelation semantic fields rejected")


func _test_absence_reintroduction_provenance() -> void:
	var world_a := _world("world/test/a", 3, 1000)
	var world_b := _world("world/test/b", 4, 1001)
	var relation := _relation(7)
	var s1 := WorldGraphScript.reconstruct_from_directory(
		"world-graph/test/partition",
		11,
		9,
		[world_a, world_b],
		[relation],
	)
	_assert_ok(WorldGraphScript.validate(s1), "S1 invalid")

	var legacy_current := s1.duplicate(true)
	legacy_current.erase("absent_world_provenance")
	legacy_current.erase("absent_relation_provenance")
	var legacy_candidate := legacy_current.duplicate(true)
	legacy_candidate["directory_revision"] = 12
	legacy_candidate["graph_revision"] = 10
	_assert_ok(
		WorldGraphScript.validate_newer(legacy_candidate, legacy_current),
		"Legacy snapshot without optional provenance fields cannot participate in R7 validation",
	)

	var s2 := WorldGraphScript.reconstruct_from_directory(
		"world-graph/test/partition",
		12,
		10,
		[world_b],
		[],
		s1,
	)
	_assert_ok(WorldGraphScript.validate_newer(s2, s1), "Legitimate temporary world/relation absence rejected")
	_assert(Dictionary(s2["absent_world_provenance"]).has("world/test/a"), "Removed world did not leave provenance tombstone")
	_assert(Dictionary(s2["absent_relation_provenance"]).has("world-relation/test/a-b"), "Removed relation did not leave provenance tombstone")

	var dropped_tombstone := s2.duplicate(true)
	dropped_tombstone["graph_revision"] = 11
	dropped_tombstone["directory_revision"] = 13
	dropped_tombstone["absent_world_provenance"].erase("world/test/a")
	_assert_error(
		WorldGraphScript.validate_newer(dropped_tombstone, s2),
		"WORLD_ABSENCE_PROVENANCE_REWRITTEN",
		"Absent-world provenance was allowed to disappear",
	)

	var stale_a := _world("world/test/a", 2, 1000)
	var s3_stale := WorldGraphScript.reconstruct_from_directory(
		"world-graph/test/partition",
		13,
		11,
		[stale_a, world_b],
		[],
		s2,
	)
	_assert_error(
		WorldGraphScript.validate_newer(s3_stale, s2),
		"STALE_REINTRODUCED_WORLD_REVISION",
		"A@3 -> absent -> A@2 rollback was accepted",
	)

	var changed_same_revision := _world("world/test/a", 3, 1999)
	var s3_changed := WorldGraphScript.reconstruct_from_directory(
		"world-graph/test/partition",
		13,
		11,
		[changed_same_revision, world_b],
		[],
		s2,
	)
	_assert_error(
		WorldGraphScript.validate_newer(s3_changed, s2),
		"WORLD_REVISION_REINTRODUCED_WITH_DIFFERENT_CONTENT",
		"A@3 -> absent -> changed A@3 was accepted",
	)

	var fresh_a := _world("world/test/a", 4, 1200)
	var s3_good := WorldGraphScript.reconstruct_from_directory(
		"world-graph/test/partition",
		13,
		11,
		[fresh_a, world_b],
		[],
		s2,
	)
	_assert_ok(WorldGraphScript.validate_newer(s3_good, s2), "Valid higher-revision world reintroduction rejected")

	var r2 := WorldGraphScript.reconstruct_from_directory(
		"world-graph/test/relation-partition",
		12,
		10,
		[world_a, world_b],
		[],
		WorldGraphScript.reconstruct_from_directory(
			"world-graph/test/relation-partition",
			11,
			9,
			[world_a, world_b],
			[relation],
		),
	)
	var stale_relation := _relation(6)
	var r3 := WorldGraphScript.reconstruct_from_directory(
		"world-graph/test/relation-partition",
		13,
		11,
		[world_a, world_b],
		[stale_relation],
		r2,
	)
	_assert_error(
		WorldGraphScript.validate_newer(r3, r2),
		"STALE_REINTRODUCED_RELATION_REVISION",
		"Relation@7 -> absent -> Relation@6 rollback was accepted",
	)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code,
		"%s: %s" % [message, result],
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("EG0 R7 review repairs: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("EG0 R7 review repairs: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
