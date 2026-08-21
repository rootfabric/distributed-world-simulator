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
	_test_client_domain_error_taxonomy()
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


func _client_frame(
		frame_id: String,
		direction: String,
		channel: String,
		sequence: int,
		payload_schema: String,
		payload: Dictionary,
) -> Dictionary:
	return FrameScript.create(
		frame_id,
		"gateway-session/test/a",
		direction,
		channel,
		sequence,
		payload_schema,
		payload,
	)


# EG0-R7-V-001 regression coverage: domain error taxonomy must stay distinct
# from fail-closed exact schema admission for every registered client payload
# schema. Missing/invalid required semantic fields keep their domain-specific
# codes; only fully valid payloads with unregistered extra fields are rejected
# as CLIENT_PAYLOAD_SCHEMA_VIOLATION.
func _test_client_domain_error_taxonomy() -> void:
	var operation := _client_frame(
		"frame/test/r7-operation",
		"CLIENT_TO_WORLD",
		"WORLD_OPERATION",
		7,
		"planet_simulator.test_world_operation.v1",
		{"operation_id": "operation/test/pickup-1", "command": "pickup", "target_id": "entity/test/item-1"},
	)
	_assert_ok(FrameScript.validate(operation), "Valid registered WORLD_OPERATION frame rejected")

	var missing_operation := operation.duplicate(true)
	missing_operation["payload"].erase("operation_id")
	_assert_error(
		FrameScript.validate(missing_operation),
		"INVALID_OPERATION_ID",
		"WORLD_OPERATION missing operation_id lost its domain error",
	)

	var invalid_operation := operation.duplicate(true)
	invalid_operation["payload"]["operation_id"] = "entity/not-an-operation"
	_assert_error(
		FrameScript.validate(invalid_operation),
		"INVALID_OPERATION_ID",
		"WORLD_OPERATION invalid operation_id lost its domain error",
	)

	var operation_extra := operation.duplicate(true)
	operation_extra["payload"]["delivery_target"] = "10.0.0.2:7777"
	_assert_error(
		FrameScript.validate(operation_extra),
		"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
		"Valid WORLD_OPERATION accepted delivery_target alias",
	)

	var input := _client_frame(
		"frame/test/r7-input",
		"CLIENT_TO_WORLD",
		"INPUT_MOVEMENT",
		8,
		"planet_simulator.test_input.v1",
		{"input_seq": 42, "axis_x": 1},
	)
	_assert_ok(FrameScript.validate(input), "Valid registered INPUT_MOVEMENT frame rejected")

	var missing_input := input.duplicate(true)
	missing_input["payload"].erase("input_seq")
	_assert_error(
		FrameScript.validate(missing_input),
		"INVALID_INPUT_SEQUENCE",
		"INPUT_MOVEMENT missing input_seq lost its domain error",
	)

	var input_extra := input.duplicate(true)
	input_extra["payload"]["backend_endpoint"] = "10.0.0.2:7777"
	_assert_error(
		FrameScript.validate(input_extra),
		"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
		"Valid INPUT_MOVEMENT accepted backend_endpoint alias",
	)

	var projection := _client_frame(
		"frame/test/r7-projection",
		"WORLD_TO_CLIENT",
		"WORLD_PROJECTION",
		9,
		"planet_simulator.test_world_projection.v1",
		{"read_only": true, "source_revision": 4, "entities": ["entity/test/tree-1"]},
	)
	_assert_ok(FrameScript.validate(projection), "Valid registered WORLD_PROJECTION frame rejected")

	var writable_projection := projection.duplicate(true)
	writable_projection["payload"]["read_only"] = false
	_assert_error(
		FrameScript.validate(writable_projection),
		"PROJECTION_NOT_READ_ONLY",
		"WORLD_PROJECTION read_only=false lost its domain error",
	)

	var projection_extra := projection.duplicate(true)
	projection_extra["payload"]["physical_route"] = "route-b"
	_assert_error(
		FrameScript.validate(projection_extra),
		"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
		"Valid WORLD_PROJECTION accepted physical_route alias",
	)

	var snapshot := _client_frame(
		"frame/test/r7-snapshot-domain",
		"WORLD_TO_CLIENT",
		"AUTHORITATIVE_SNAPSHOT",
		10,
		"planet_simulator.test_snapshot.v1",
		{"revision": 2},
	)
	_assert_ok(FrameScript.validate(snapshot), "Valid registered AUTHORITATIVE_SNAPSHOT frame rejected")

	var invalid_snapshot_revision := snapshot.duplicate(true)
	invalid_snapshot_revision["payload"]["revision"] = 0
	_assert_error(
		FrameScript.validate(invalid_snapshot_revision),
		"INVALID_CLIENT_PAYLOAD",
		"AUTHORITATIVE_SNAPSHOT revision=0 lost its domain error",
	)

	var missing_snapshot_revision := snapshot.duplicate(true)
	missing_snapshot_revision["payload"].erase("revision")
	_assert_error(
		FrameScript.validate(missing_snapshot_revision),
		"INVALID_CLIENT_PAYLOAD",
		"AUTHORITATIVE_SNAPSHOT missing revision lost its domain error",
	)

	var snapshot_extra := snapshot.duplicate(true)
	snapshot_extra["payload"]["future_unknown_field"] = {"nested": true}
	_assert_error(
		FrameScript.validate(snapshot_extra),
		"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
		"Valid AUTHORITATIVE_SNAPSHOT accepted future_unknown_field",
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
