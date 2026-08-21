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
	_test_projection_policy_and_grant_cannot_authorize_mutation(fixture)
	_test_view_has_no_simulation_endpoint(fixture)
	_test_interest_aggregation(fixture)
	_test_world_graph_cache_semantics(fixture)
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
		["client_world_view_b", ClientWorldViewScript],
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
	var world: Dictionary = Dictionary(fixture["world_descriptor_a"])
	var stale_world: Dictionary = world.duplicate(true)
	stale_world["world_revision"] = int(world["world_revision"]) - 1
	_assert_error(
		WorldDescriptorScript.validate_newer(stale_world, world),
		"STALE_WORLD_REVISION",
		"Older world revision accepted",
	)

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


func _test_projection_policy_and_grant_cannot_authorize_mutation(fixture: Dictionary) -> void:
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

	var authority_grant: Dictionary = Dictionary(fixture["client_world_view"]).duplicate(true)
	authority_grant["projection_streams"][0]["projection_grant"] = "authority/test/a"
	_assert_error(
		ClientWorldViewScript.validate(authority_grant),
		"INVALID_ID",
		"Authority identity accepted in projection_grant namespace",
	)

	var grant_with_mutation_flag: Dictionary = Dictionary(fixture["client_world_view"]).duplicate(true)
	grant_with_mutation_flag["projection_streams"][0]["allows_mutation"] = true
	_assert_error(
		ClientWorldViewScript.validate(grant_with_mutation_flag),
		"UNEXPECTED_FIELD",
		"Projection grant/view entry accepted mutation-authority field",
	)


func _test_view_has_no_simulation_endpoint(fixture: Dictionary) -> void:
	var nested_endpoint: Dictionary = Dictionary(fixture["client_world_view"]).duplicate(true)
	nested_endpoint["projection_streams"][0]["simulation_server_endpoint"] = "198.51.100.10:7777"
	_assert_error(
		ClientWorldViewScript.validate(nested_endpoint),
		"UNEXPECTED_FIELD",
		"ClientWorldView leaked simulation-server endpoint",
	)

	var top_level_endpoint: Dictionary = Dictionary(fixture["client_world_view"]).duplicate(true)
	top_level_endpoint["simulation_server_endpoint"] = "server-europe-3.internal:3322"
	_assert_error(
		ClientWorldViewScript.validate(top_level_endpoint),
		"UNEXPECTED_FIELD",
		"ClientWorldView accepted top-level simulation-server endpoint",
	)

	var peer_id: Dictionary = Dictionary(fixture["client_world_view"]).duplicate(true)
	peer_id["peer_id"] = 42
	_assert_error(
		ClientWorldViewScript.validate(peer_id),
		"UNEXPECTED_FIELD",
		"ClientWorldView accepted transport peer_id",
	)


func _test_interest_aggregation(fixture: Dictionary) -> void:
	var view_a: Dictionary = Dictionary(fixture["client_world_view"])
	var view_b: Dictionary = Dictionary(fixture["client_world_view_b"])
	var plan: Dictionary = Dictionary(fixture["aggregated_interest_plan"])
	var stream_a: Dictionary = Dictionary(Array(view_a["projection_streams"])[0])
	var stream_b: Dictionary = Dictionary(Array(view_b["projection_streams"])[0])
	var subscribers: Array = Array(plan["subscriber_sessions"])

	_assert(String(stream_a["source_world_id"]) == String(plan["source_world_id"]), "Alice source does not match aggregate source")
	_assert(String(stream_b["source_world_id"]) == String(plan["source_world_id"]), "Bob source does not match aggregate source")
	_assert(String(stream_a["lod_class"]) == String(plan["representation_or_lod"]), "Alice LOD is not aggregation-compatible")
	_assert(String(stream_b["lod_class"]) == String(plan["representation_or_lod"]), "Bob LOD is not aggregation-compatible")
	_assert(subscribers.has(String(view_a["gateway_session_id"])), "Aggregate plan omitted Alice")
	_assert(subscribers.has(String(view_b["gateway_session_id"])), "Aggregate plan omitted Bob")
	_assert(subscribers.size() == 2, "Golden interest plan does not aggregate exactly two sessions")

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

	var physical_link_state: Dictionary = plan.duplicate(true)
	physical_link_state["backend_link_id"] = "backend-link/test/forbidden"
	_assert_error(
		InterestPlanScript.validate(physical_link_state),
		"UNEXPECTED_FIELD",
		"AggregatedInterestPlan accepted physical backend-link state",
	)


func _test_world_graph_cache_semantics(fixture: Dictionary) -> void:
	var graph: Dictionary = Dictionary(fixture["world_graph_snapshot"])
	_assert(String(graph["source_owner"]) == "WORLD_DIRECTORY", "WorldGraph cache source owner is not WORLD_DIRECTORY")
	_assert(bool(graph["read_only"]), "WorldGraph cache is not read-only")
	_assert(bool(graph["reconstructible"]), "WorldGraph cache is not reconstructible")
	_assert(not bool(graph["canonical"]), "WorldGraph cache incorrectly claims canonical truth")

	var reconstructed: Dictionary = WorldGraphScript.reconstruct_from_directory(
		String(graph["graph_snapshot_id"]),
		int(graph["directory_revision"]),
		int(graph["graph_revision"]),
		Array(graph["worlds"]),
		Array(graph["relations"]),
	)
	_assert_ok(WorldGraphScript.validate(reconstructed), "Directory reconstruction produced invalid WorldGraph cache")
	_assert(
		NetworkUtilsScript.canonical_json(reconstructed["worlds"]) == NetworkUtilsScript.canonical_json(graph["worlds"]),
		"Directory reconstruction changed world descriptors",
	)
	_assert(
		NetworkUtilsScript.canonical_json(reconstructed["relations"]) == NetworkUtilsScript.canonical_json(graph["relations"]),
		"Directory reconstruction changed world relations",
	)

	var wrong_owner: Dictionary = graph.duplicate(true)
	wrong_owner["source_owner"] = "GATEWAY"
	_assert_error(
		WorldGraphScript.validate(wrong_owner),
		"WORLD_GRAPH_SOURCE_OWNER_INVALID",
		"Gateway accepted itself as WorldGraph topology truth owner",
	)

	var canonical: Dictionary = graph.duplicate(true)
	canonical["canonical"] = true
	_assert_error(
		WorldGraphScript.validate(canonical),
		"WORLD_GRAPH_CANONICAL_FORBIDDEN",
		"Gateway WorldGraph cache accepted canonical=true",
	)

	var mutable: Dictionary = graph.duplicate(true)
	mutable["read_only"] = false
	_assert_error(
		WorldGraphScript.validate(mutable),
		"WORLD_GRAPH_NOT_READ_ONLY",
		"Mutable Gateway WorldGraph cache accepted",
	)

	var non_reconstructible: Dictionary = graph.duplicate(true)
	non_reconstructible["reconstructible"] = false
	_assert_error(
		WorldGraphScript.validate(non_reconstructible),
		"WORLD_GRAPH_NOT_RECONSTRUCTIBLE",
		"Non-reconstructible Gateway WorldGraph cache accepted",
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
	var graph: Dictionary = WorldGraphScript.reconstruct_from_directory(
		"world-graph/test/large-partition",
		100,
		100,
		worlds,
		relations,
	)
	_assert_ok(WorldGraphScript.validate(graph), "1000-world read-only graph rejected")
	_assert(Array(graph["worlds"]).size() == 1000, "1000-world graph truncated")
	_assert(not graph.has("upstream_connections"), "Graph contract unexpectedly requires upstream connections")
	_assert(not graph.has("backend_links"), "Graph contract unexpectedly carries backend-link state")
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
