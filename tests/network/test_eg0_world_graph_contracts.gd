extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const WorldDescriptorScript = preload("res://scripts/network/gateway/world_descriptor.gd")
const WorldRelationScript = preload("res://scripts/network/gateway/world_relation.gd")
const WorldGraphScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")
const ClientWorldViewScript = preload("res://scripts/network/gateway/client_world_view.gd")
const InterestPlanScript = preload("res://scripts/network/gateway/aggregated_interest_plan.gd")

const FIXTURE_PATH := "res://tests/network/fixtures/edge_gateway/eg0_world_graph_fixtures.v1.json"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	var fixture: Dictionary = _load_fixture()
	if fixture.is_empty():
		_finish()
		return
	_test_golden_contracts(fixture)
	_test_stale_revisions(fixture)
	_test_projection_policy_cannot_grant_mutation(fixture)
	_test_view_has_no_simulation_endpoint(fixture)
	_test_interest_aggregation(fixture)
	_test_large_world_graph_without_connections()
	_finish()


func _load_fixture() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(FIXTURE_PATH)
	_assert(not text.is_empty(), "World graph fixture file missing")
	var parsed = JSON.parse_string(text)
	_assert(parsed is Dictionary, "World graph fixture root must be Dictionary")
	return Dictionary(parsed) if parsed is Dictionary else {}


func _test_golden_contracts(fixture: Dictionary) -> void:
	var validators: Array = [
		["world_descriptor_a", WorldDescriptorScript],
		["world_descriptor_b", WorldDescriptorScript],
		["world_relation", WorldRelationScript],
		["world_graph_snapshot", WorldGraphScript],
		["client_world_view", ClientWorldViewScript],
		["aggregated_interest_plan", InterestPlanScript],
	]
	for entry in validators:
		var key: String = String(entry[0])
		var value: Dictionary = Dictionary(fixture.get(key, {}))
		var check: Dictionary = entry[1].validate(value)
		_assert(bool(check.get("success", false)), "%s rejected: %s" % [key, check])
		var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
		_assert(bool(round_trip.get("success", false)), "%s is not JSON-safe" % key)


func _test_stale_revisions(fixture: Dictionary) -> void:
	var relation: Dictionary = Dictionary(fixture["world_relation"])
	var stale_relation: Dictionary = relation.duplicate(true)
	_assert_error(
		WorldRelationScript.validate_newer(stale_relation, relation),
		"STALE_RELATION_REVISION",
		"Same relation revision accepted as newer",
	)
	var graph: Dictionary = Dictionary(fixture["world_graph_snapshot"])
	var stale_graph: Dictionary = graph.duplicate(true)
	stale_graph["graph_revision"] = int(graph["graph_revision"]) - 1
	_assert_error(
		WorldGraphScript.validate_newer(stale_graph, graph),
		"STALE_GRAPH_REVISION",
		"Older graph revision accepted",
	)
	var view: Dictionary = Dictionary(fixture["client_world_view"])
	var stale_view: Dictionary = view.duplicate(true)
	stale_view["view_revision"] = int(view["view_revision"]) - 1
	_assert_error(
		ClientWorldViewScript.validate_newer(stale_view, view),
		"STALE_VIEW_REVISION",
		"Older view revision accepted",
	)


func _test_projection_policy_cannot_grant_mutation(fixture: Dictionary) -> void:
	var world: Dictionary = Dictionary(fixture["world_descriptor_a"]).duplicate(true)
	world["projection_policy"]["allows_mutation"] = true
	_assert_error(
		WorldDescriptorScript.validate(world),
		"PROJECTION_MUTATION_AUTHORITY_FORBIDDEN",
		"World projection policy granted mutation authority",
	)
	var relation: Dictionary = Dictionary(fixture["world_relation"]).duplicate(true)
	relation["projection_policy"]["allows_mutation"] = true
	_assert_error(
		WorldRelationScript.validate(relation),
		"PROJECTION_MUTATION_AUTHORITY_FORBIDDEN",
		"Relation projection policy granted mutation authority",
	)


func _test_view_has_no_simulation_endpoint(fixture: Dictionary) -> void:
	var view: Dictionary = Dictionary(fixture["client_world_view"]).duplicate(true)
	view["projection_streams"][0]["simulation_server_endpoint"] = "198.51.100.10:7777"
	_assert_error(
		ClientWorldViewScript.validate(view),
		"UNEXPECTED_FIELD",
		"ClientWorldView leaked simulation-server endpoint",
	)


func _test_interest_aggregation(fixture: Dictionary) -> void:
	var plan: Dictionary = Dictionary(fixture["aggregated_interest_plan"])
	_assert(Array(plan["subscriber_sessions"]).size() == 2, "Golden interest plan does not aggregate two sessions")
	var duplicate: Dictionary = plan.duplicate(true)
	duplicate["subscriber_sessions"].append("gateway-session/test/a")
	_assert_error(
		InterestPlanScript.validate(duplicate),
		"DUPLICATE_SUBSCRIBER_SESSION",
		"Duplicate subscriber session accepted",
	)
	var writable: Dictionary = plan.duplicate(true)
	writable["read_only"] = false
	_assert_error(
		InterestPlanScript.validate(writable),
		"INTEREST_PLAN_NOT_READ_ONLY",
		"Writable interest plan accepted",
	)


func _test_large_world_graph_without_connections() -> void:
	var worlds: Array = []
	var relations: Array = []
	for index in range(1000):
		worlds.append(WorldDescriptorScript.create(
			"world/test/large-%d" % index,
			"planet_surface",
			"reference-frame/test/sol",
			{"kind": "partition", "index": index},
			{"kind": "sphere", "radius": 1000 + index},
			"authority-subject/test/large-%d" % index,
			["coarse"],
			{"read_only": true, "allows_mutation": false},
			["coarse"],
			{"neighbor_depth": 1},
			{"max_projection_neighbors": 4},
			1,
		))
	var graph: Dictionary = WorldGraphScript.create(
		"world-graph/test/large-partition",
		100,
		100,
		worlds,
		relations,
		true,
		true,
	)
	_assert_ok(WorldGraphScript.validate(graph), "1000-world read-only graph rejected")
	_assert(Array(graph["worlds"]).size() == 1000, "1000-world graph truncated")
	_assert(not graph.has("upstream_connections"), "Graph contract unexpectedly requires upstream connections")
	var forged: Dictionary = graph.duplicate(true)
	forged["upstream_connections"] = ["world/test/large-0"]
	_assert_error(
		WorldGraphScript.validate(forged),
		"UNEXPECTED_FIELD",
		"World graph accepted physical upstream connection state",
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
		print("EG0 World Graph/View/Interest contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("EG0 World Graph/View/Interest contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
