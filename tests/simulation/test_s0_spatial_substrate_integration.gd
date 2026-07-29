extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const CellDescriptorScript = preload("res://scripts/simulation/spatial/spatial_cell_descriptor.gd")
const AuthorityAddressScript = preload("res://scripts/simulation/spatial/aggregate_authority_address.gd")
const ShardDescriptorScript = preload("res://scripts/simulation/spatial/aggregate_shard_descriptor.gd")
const NeighbourDescriptorScript = preload("res://scripts/simulation/spatial/cell_neighbour_descriptor.gd")
const BoundarySummaryScript = preload("res://scripts/simulation/spatial/boundary_summary.gd")
const SpatialIndexScript = preload("res://scripts/simulation/spatial/spatial_aggregate_index.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_registration_and_indexing()
	_test_fail_closed_boundaries()
	_finish()


func _test_registration_and_indexing() -> void:
	var index = SpatialIndexScript.new()
	_assert_ok(index.setup(), "Spatial index setup failed")
	_assert_ok(index.setup(), "Spatial index setup replay failed")
	var root: Dictionary = _root_cell()
	var cell_a: Dictionary = _child_cell(0, [-100, -100, -10], [0, 0, 10])
	var cell_b: Dictionary = _child_cell(1, [0, -100, -10], [100, 0, 10])
	var cell_c: Dictionary = _child_cell(2, [-100, 0, -10], [0, 100, 10])
	_assert_ok(index.register_cell(root), "Root cell registration failed")
	_assert_ok(index.register_cell(cell_a), "Cell A registration failed")
	_assert_ok(index.register_cell(cell_b), "Cell B registration failed")
	_assert_ok(index.register_cell(cell_c), "Cell C registration failed")
	var root_replay: Dictionary = index.register_cell(root)
	_assert_ok(root_replay, "Root cell replay failed")
	_assert(bool(root_replay.get("details", {}).get("replay", false)), "Root cell replay was not marked")

	var parent_link: Dictionary = NeighbourDescriptorScript.create(
		"cell-neighbour/root-a",
		_cell_id(root),
		_cell_id(cell_a),
		NeighbourDescriptorScript.RELATION_PARENT_CHILD,
		"boundary/child-0",
		"boundary/parent",
		true
	)
	var face_ab: Dictionary = NeighbourDescriptorScript.create(
		"cell-neighbour/a-b",
		_cell_id(cell_a),
		_cell_id(cell_b),
		NeighbourDescriptorScript.RELATION_FACE,
		"boundary/east",
		"boundary/west",
		true
	)
	var face_ac: Dictionary = NeighbourDescriptorScript.create(
		"cell-neighbour/a-c",
		_cell_id(cell_a),
		_cell_id(cell_c),
		NeighbourDescriptorScript.RELATION_FACE,
		"boundary/north",
		"boundary/south",
		true
	)
	_assert_ok(index.register_neighbour(parent_link), "Parent-child link registration failed")
	_assert_ok(index.register_neighbour(face_ab), "A-B neighbour registration failed")
	_assert_ok(index.register_neighbour(face_ac), "A-C neighbour registration failed")
	_assert(index.get_neighbour_cell_ids(_cell_id(cell_a)) == [_cell_id(root), _cell_id(cell_b), _cell_id(cell_c)], "Cell A neighbour query is wrong")
	_assert(index.get_neighbour_cell_ids(_cell_id(cell_b)) == [_cell_id(cell_a)], "Bidirectional neighbour query is wrong")

	var authority_a: Dictionary = AuthorityAddressScript.create("region-authority/a", 3, "authority-route/a")
	var authority_b: Dictionary = AuthorityAddressScript.create("region-authority/b", 8, "authority-route/b")
	var environment: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/environment/a",
		"environment-field/earth/main",
		"ENVIRONMENT_CELL",
		"planet_simulator.environment_cell.v1",
		1,
		[_cell_id(cell_a)],
		authority_a
	)
	var population_a: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/meadow/a",
		"population-field/meadow/main",
		"POPULATION_FIELD",
		"planet_simulator.population_field.v1",
		1,
		[_cell_id(cell_a), _cell_id(cell_b)],
		authority_b
	)
	var population_b: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/meadow/b",
		"population-field/meadow/main",
		"POPULATION_FIELD",
		"planet_simulator.population_field.v1",
		1,
		[_cell_id(cell_c)],
		authority_a,
		["aggregate-shard/meadow/a"]
	)
	_assert_ok(index.bind_shard(environment), "Environment shard binding failed")
	_assert_ok(index.bind_shard(population_a), "Population shard A binding failed")
	_assert_ok(index.bind_shard(population_b), "Population shard B binding failed")
	var population_a_v2: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/meadow/a",
		"population-field/meadow/main",
		"POPULATION_FIELD",
		"planet_simulator.population_field.v1",
		2,
		[_cell_id(cell_a), _cell_id(cell_b)],
		authority_b,
		["aggregate-shard/meadow/b"]
	)
	_assert_ok(index.bind_shard(population_a_v2), "Population shard A neighbour update failed")

	_assert(index.get_shard_ids_for_cell(_cell_id(cell_a)) == ["aggregate-shard/environment/a", "aggregate-shard/meadow/a"], "Multiple aggregate kinds were not indexed in one cell")
	_assert(index.get_cell_ids_for_shard("aggregate-shard/meadow/a") == [_cell_id(cell_a), _cell_id(cell_b)], "One shard did not cover multiple cells")
	_assert(index.get_shard_ids_for_logical_aggregate("population-field/meadow/main") == ["aggregate-shard/meadow/a", "aggregate-shard/meadow/b"], "Logical aggregate shards are not indexed")
	var authorities: Dictionary = index.get_authority_addresses_for_cell(_cell_id(cell_a))
	_assert(authorities.size() == 2, "Cell did not preserve independent shard authorities")
	_assert(String(authorities["aggregate-shard/environment/a"]["authority_owner_id"]) == "region-authority/a", "Environment authority is wrong")
	_assert(String(authorities["aggregate-shard/meadow/a"]["authority_owner_id"]) == "region-authority/b", "Population authority was inferred from cell")

	var summary1: Dictionary = BoundarySummaryScript.create(
		"boundary-summary/meadow/a-b/1",
		"aggregate-shard/meadow/a",
		"aggregate-shard/meadow/b",
		"boundary/meadow/a-b",
		"planet_simulator.vegetation_boundary.v1",
		10,
		100,
		200,
		{"seed_pressure": 0.25, "water_flow": 1.5}
	)
	_assert_ok(index.publish_boundary_summary(summary1), "Boundary summary publication failed")
	var summary_replay: Dictionary = index.publish_boundary_summary(summary1)
	_assert_ok(summary_replay, "Boundary summary replay failed")
	_assert(bool(summary_replay.get("details", {}).get("replay", false)), "Boundary summary replay was not marked")
	var summary2: Dictionary = BoundarySummaryScript.create(
		"boundary-summary/meadow/a-b/2",
		"aggregate-shard/meadow/a",
		"aggregate-shard/meadow/b",
		"boundary/meadow/a-b",
		"planet_simulator.vegetation_boundary.v1",
		11,
		200,
		300,
		{"seed_pressure": 0.5, "water_flow": 1.2}
	)
	_assert_ok(index.publish_boundary_summary(summary2), "New boundary summary publication failed")
	var latest: Dictionary = index.get_latest_boundary_summary(
		"aggregate-shard/meadow/a",
		"aggregate-shard/meadow/b",
		"boundary/meadow/a-b",
		"planet_simulator.vegetation_boundary.v1"
	)
	_assert(String(latest.get("summary_id", "")) == "boundary-summary/meadow/a-b/2", "Latest boundary summary is wrong")
	latest["values_by_key"]["water_flow"] = 999.0
	var latest_again: Dictionary = index.get_latest_boundary_summary(
		"aggregate-shard/meadow/a",
		"aggregate-shard/meadow/b",
		"boundary/meadow/a-b",
		"planet_simulator.vegetation_boundary.v1"
	)
	_assert(float(latest_again["values_by_key"]["water_flow"]) == 1.2, "Boundary summary leaked a mutable alias")
	var counts: Dictionary = index.get_counts()
	_assert(counts == {"cells": 4, "shards": 3, "neighbours": 3, "boundary_summaries": 2}, "Spatial index counts are wrong")


func _test_fail_closed_boundaries() -> void:
	var unconfigured = SpatialIndexScript.new()
	_assert_fail(unconfigured.register_cell(_root_cell()), "Unconfigured spatial index accepted a cell")
	var index = SpatialIndexScript.new()
	_assert_ok(index.setup(), "Fail-closed index setup failed")
	var child_before_parent: Dictionary = _child_cell(0, [-100, -100, -10], [0, 0, 10])
	_assert_fail(index.register_cell(child_before_parent), "Child cell registered before parent")
	var root: Dictionary = _root_cell()
	_assert_ok(index.register_cell(root), "Fail-closed root registration failed")
	var outside_child: Dictionary = _child_cell(0, [-200, -100, -10], [0, 0, 10])
	_assert_fail(index.register_cell(outside_child), "Child bounds outside parent accepted")
	var capacity_child_address: Dictionary = CellAddressScript.child(root["address"], 7)
	var capacity_child: Dictionary = CellDescriptorScript.create(capacity_child_address, "body/earth/fixed", [0, 0, 0], [1, 1, 1], 4)
	_assert_fail(index.register_cell(capacity_child), "Child index beyond parent capacity accepted")
	var cell_a: Dictionary = _child_cell(0, [-100, -100, -10], [0, 0, 10])
	var cell_b: Dictionary = _child_cell(1, [0, -100, -10], [100, 0, 10])
	_assert_ok(index.register_cell(cell_a), "Fail-closed cell A registration failed")
	_assert_ok(index.register_cell(cell_b), "Fail-closed cell B registration failed")
	var wrong_parent_link: Dictionary = NeighbourDescriptorScript.create(
		"cell-neighbour/wrong-parent",
		_cell_id(cell_a),
		_cell_id(cell_b),
		NeighbourDescriptorScript.RELATION_PARENT_CHILD,
		"boundary/child",
		"boundary/parent",
		true
	)
	_assert_fail(index.register_neighbour(wrong_parent_link), "Invalid parent-child relation accepted")
	var face_link: Dictionary = NeighbourDescriptorScript.create(
		"cell-neighbour/a-b",
		_cell_id(cell_a),
		_cell_id(cell_b),
		NeighbourDescriptorScript.RELATION_FACE,
		"boundary/east",
		"boundary/west",
		true
	)
	_assert_ok(index.register_neighbour(face_link), "Fail-closed face link failed")
	var reverse_duplicate: Dictionary = NeighbourDescriptorScript.create(
		"cell-neighbour/b-a-duplicate",
		_cell_id(cell_b),
		_cell_id(cell_a),
		NeighbourDescriptorScript.RELATION_FACE,
		"boundary/west",
		"boundary/east",
		true
	)
	_assert_fail(index.register_neighbour(reverse_duplicate), "Reverse duplicate bidirectional link accepted")
	var authority: Dictionary = AuthorityAddressScript.create("region-authority/a", 2, "authority-route/a")
	var unknown_cell_shard: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/unknown/a",
		"logical/unknown",
		"PROCESS",
		"planet_simulator.process.v1",
		1,
		["universe/main/instance/earth-01/space/surface/grid/quad-tree/revision/1/root/face-0/level/1/path/9"],
		authority
	)
	_assert_fail(index.bind_shard(unknown_cell_shard), "Shard with unknown cell accepted")
	var shard_a: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/test/a",
		"logical/test",
		"PROCESS",
		"planet_simulator.process.v1",
		1,
		[_cell_id(cell_a)],
		authority
	)
	_assert_ok(index.bind_shard(shard_a), "Fail-closed shard A binding failed")
	var stale_update: Dictionary = shard_a.duplicate(true)
	stale_update["cell_ids"] = [_cell_id(cell_b)]
	_assert_fail(index.bind_shard(stale_update), "Same-revision shard mutation accepted")
	_assert(index.get_cell_ids_for_shard("aggregate-shard/test/a") == [_cell_id(cell_a)], "Failed shard update changed live mappings")
	var unknown_neighbour: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/test/b",
		"logical/test",
		"PROCESS",
		"planet_simulator.process.v1",
		1,
		[_cell_id(cell_b)],
		authority,
		["aggregate-shard/missing"]
	)
	_assert_fail(index.bind_shard(unknown_neighbour), "Unknown neighbour shard accepted")
	var owner_without_epoch: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/test/a",
		"logical/test",
		"PROCESS",
		"planet_simulator.process.v1",
		2,
		[_cell_id(cell_a)],
		AuthorityAddressScript.create("region-authority/b", 2, "authority-route/b")
	)
	_assert_fail(index.bind_shard(owner_without_epoch), "Owner change without higher epoch accepted")
	var valid_owner_transfer: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/test/a",
		"logical/test",
		"PROCESS",
		"planet_simulator.process.v1",
		2,
		[_cell_id(cell_a)],
		AuthorityAddressScript.create("region-authority/b", 3, "authority-route/b")
	)
	_assert_ok(index.bind_shard(valid_owner_transfer), "Owner transfer with higher epoch failed")
	_assert(String(index.get_authority_address_for_shard("aggregate-shard/test/a")["authority_owner_id"]) == "region-authority/b", "Valid authority transfer was not stored")
	var authority_rollback: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/test/a",
		"logical/test",
		"PROCESS",
		"planet_simulator.process.v1",
		3,
		[_cell_id(cell_a)],
		AuthorityAddressScript.create("region-authority/a", 2, "authority-route/a")
	)
	_assert_fail(index.bind_shard(authority_rollback), "Authority epoch rollback accepted")
	_assert(String(index.get_authority_address_for_shard("aggregate-shard/test/a")["authority_owner_id"]) == "region-authority/b", "Rejected authority rollback changed live state")
	var unconnected_b: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/unconnected/b",
		"logical/unconnected",
		"PROCESS",
		"planet_simulator.process.v1",
		1,
		[_cell_id(root)],
		authority
	)
	_assert_ok(index.bind_shard(unconnected_b), "Unconnected shard binding failed")
	var invalid_summary: Dictionary = BoundarySummaryScript.create(
		"boundary-summary/unconnected/1",
		"aggregate-shard/test/a",
		"aggregate-shard/unconnected/b",
		"boundary/unconnected",
		"planet_simulator.test_boundary.v1",
		1,
		0,
		1,
		{"value": 1}
	)
	_assert_fail(index.publish_boundary_summary(invalid_summary), "Boundary summary between non-neighbour shards accepted")

	var connected_b: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/test/b",
		"logical/test",
		"PROCESS",
		"planet_simulator.process.v1",
		1,
		[_cell_id(cell_b)],
		authority,
		["aggregate-shard/test/a"]
	)
	_assert_ok(index.bind_shard(connected_b), "Connected shard B binding failed")
	var first_summary: Dictionary = BoundarySummaryScript.create(
		"boundary-summary/test/a-b/1",
		"aggregate-shard/test/a",
		"aggregate-shard/test/b",
		"boundary/test/a-b",
		"planet_simulator.test_boundary.v1",
		5, 10, 20, {"value": 1}
	)
	_assert_ok(index.publish_boundary_summary(first_summary), "First monotonic boundary summary failed")
	var revision_rollback: Dictionary = BoundarySummaryScript.create(
		"boundary-summary/test/a-b/2",
		"aggregate-shard/test/a",
		"aggregate-shard/test/b",
		"boundary/test/a-b",
		"planet_simulator.test_boundary.v1",
		4, 20, 30, {"value": 2}
	)
	_assert_fail(index.publish_boundary_summary(revision_rollback), "Boundary source revision rollback accepted")
	var overlapping_window: Dictionary = BoundarySummaryScript.create(
		"boundary-summary/test/a-b/3",
		"aggregate-shard/test/a",
		"aggregate-shard/test/b",
		"boundary/test/a-b",
		"planet_simulator.test_boundary.v1",
		6, 19, 30, {"value": 3}
	)
	_assert_fail(index.publish_boundary_summary(overlapping_window), "Overlapping boundary summary window accepted")


func _root_cell() -> Dictionary:
	var address: Dictionary = CellAddressScript.create("main", "earth-01", "surface", "quad-tree", 1, "face-0", [])
	return CellDescriptorScript.create(address, "body/earth/fixed", [-100, -100, -10], [100, 100, 10], 4)


func _child_cell(child_index: int, minimum_m: Array, maximum_m: Array) -> Dictionary:
	var address: Dictionary = CellAddressScript.child(_root_cell()["address"], child_index)
	return CellDescriptorScript.create(address, "body/earth/fixed", minimum_m, maximum_m, 4)


func _cell_id(descriptor: Dictionary) -> String:
	return String(descriptor["address"]["cell_id"])


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("S0 spatial substrate integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("S0 spatial substrate integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
