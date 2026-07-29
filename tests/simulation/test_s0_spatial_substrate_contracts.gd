extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const CellDescriptorScript = preload("res://scripts/simulation/spatial/spatial_cell_descriptor.gd")
const AuthorityAddressScript = preload("res://scripts/simulation/spatial/aggregate_authority_address.gd")
const ShardDescriptorScript = preload("res://scripts/simulation/spatial/aggregate_shard_descriptor.gd")
const NeighbourDescriptorScript = preload("res://scripts/simulation/spatial/cell_neighbour_descriptor.gd")
const BoundarySummaryScript = preload("res://scripts/simulation/spatial/boundary_summary.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_cell_address()
	_test_cell_descriptor()
	_test_authority_and_shard_descriptor()
	_test_neighbour_descriptor()
	_test_boundary_summary()
	_test_runner_contracts()
	_finish()


func _test_cell_address() -> void:
	var root: Dictionary = _root_address()
	_assert_ok(CellAddressScript.validate(root), "Valid root cell address rejected")
	_assert(int(root["level"]) == 0 and root["path"].is_empty(), "Root address hierarchy is wrong")
	_assert(String(root["cell_id"]).contains("/level/0/path/root"), "Root cell ID is not canonical")
	var child: Dictionary = CellAddressScript.child(root, 3)
	_assert_ok(CellAddressScript.validate(child), "Valid child cell address rejected")
	_assert(int(child["level"]) == 1 and child["path"] == [3], "Child path is wrong")
	_assert(CellAddressScript.parent(child) == root, "Child parent roundtrip failed")
	var grandchild: Dictionary = CellAddressScript.child(child, 2)
	_assert(CellAddressScript.is_ancestor(root, grandchild), "Root not recognized as ancestor")
	_assert(CellAddressScript.is_ancestor(child, grandchild), "Parent not recognized as ancestor")
	_assert(not CellAddressScript.is_ancestor(child, child), "Cell recognized as its own ancestor")
	_assert(CellAddressScript.child(root, -1).is_empty(), "Negative child index accepted")
	var wrong_id: Dictionary = child.duplicate(true)
	wrong_id["cell_id"] += "/changed"
	_assert_fail(CellAddressScript.validate(wrong_id), "Mismatched cell ID accepted")
	var wrong_level: Dictionary = child.duplicate(true)
	wrong_level["level"] = 2
	_assert_fail(CellAddressScript.validate(wrong_level), "Path/level mismatch accepted")
	var unsafe_path: Dictionary = child.duplicate(true)
	unsafe_path["path"] = [9007199254740992.0]
	unsafe_path["cell_id"] = CellAddressScript.compute_cell_id(unsafe_path)
	_assert_fail(CellAddressScript.validate(unsafe_path), "Unsafe JSON child index accepted")
	var uppercase: Dictionary = child.duplicate(true)
	uppercase["space_id"] = "Surface"
	uppercase["cell_id"] = CellAddressScript.compute_cell_id(uppercase)
	_assert_fail(CellAddressScript.validate(uppercase), "Uppercase cell namespace accepted")
	var runtime_value: Dictionary = child.duplicate(true)
	runtime_value["path"] = [RefCounted.new()]
	_assert_fail(CellAddressScript.validate(runtime_value), "Runtime value accepted in cell path")
	var same_after_origin_shift: Dictionary = CellAddressScript.create("main", "earth-01", "surface", "quad-tree", 1, "face-0", [3, 2])
	var render_origin_a: Vector3 = Vector3(0.0, 0.0, 0.0)
	var render_origin_b: Vector3 = Vector3(1000000.0, -2000000.0, 3000000.0)
	_assert(render_origin_a != render_origin_b and same_after_origin_shift["cell_id"] == grandchild["cell_id"], "Cell identity depends on render origin")


func _test_cell_descriptor() -> void:
	var root: Dictionary = _root_address()
	var descriptor: Dictionary = CellDescriptorScript.create(root, "body/earth/fixed", [-100.0, -100.0, -10.0], [100.0, 100.0, 10.0], 4)
	_assert_ok(CellDescriptorScript.validate(descriptor), "Valid root cell descriptor rejected")
	_assert(String(descriptor["parent_cell_id"]).is_empty(), "Root descriptor has a parent")
	_assert(not descriptor.has("authority_owner_id") and not descriptor.has("authority_epoch"), "Cell descriptor embeds authority")
	var child_address: Dictionary = CellAddressScript.child(root, 1)
	var child: Dictionary = CellDescriptorScript.create(child_address, "body/earth/fixed", [0.0, -100.0, -10.0], [100.0, 0.0, 10.0], 4)
	_assert_ok(CellDescriptorScript.validate(child), "Valid child descriptor rejected")
	_assert(String(child["parent_cell_id"]) == String(root["cell_id"]), "Child descriptor parent ID is wrong")
	var wrong_parent: Dictionary = child.duplicate(true)
	wrong_parent["parent_cell_id"] = "cell/wrong"
	_assert_fail(CellDescriptorScript.validate(wrong_parent), "Wrong parent cell ID accepted")
	var no_extent: Dictionary = descriptor.duplicate(true)
	no_extent["bounds_m"] = {"minimum_m": [0, 0, 0], "maximum_m": [0, 0, 0]}
	_assert_fail(CellDescriptorScript.validate(no_extent), "Zero-extent cell bounds accepted")
	var inverted: Dictionary = descriptor.duplicate(true)
	inverted["bounds_m"]["minimum_m"][0] = 101.0
	_assert_fail(CellDescriptorScript.validate(inverted), "Inverted cell bounds accepted")
	var authority_field: Dictionary = descriptor.duplicate(true)
	authority_field["authority_owner_id"] = "authority/main"
	_assert_fail(CellDescriptorScript.validate(authority_field), "Authority field accepted in spatial descriptor")
	var runtime_bounds: Dictionary = descriptor.duplicate(true)
	runtime_bounds["bounds_m"]["minimum_m"][0] = RefCounted.new()
	_assert_fail(CellDescriptorScript.validate(runtime_bounds), "Runtime object accepted in cell bounds")


func _test_authority_and_shard_descriptor() -> void:
	var authority: Dictionary = AuthorityAddressScript.create("region-authority/a", 4, "authority-route/a")
	_assert_ok(AuthorityAddressScript.validate(authority), "Valid aggregate authority address rejected")
	var bad_epoch: Dictionary = authority.duplicate(true)
	bad_epoch["authority_epoch"] = 0
	_assert_fail(AuthorityAddressScript.validate(bad_epoch), "Zero authority epoch accepted")
	var cells: Array = [_child_id(1), _child_id(0), _child_id(1)]
	var shard: Dictionary = ShardDescriptorScript.create(
		"aggregate-shard/environment/a",
		"environment-field/earth/main",
		"ENVIRONMENT_CELL",
		"planet_simulator.environment_cell.v1",
		1,
		cells,
		authority,
		[]
	)
	_assert_ok(ShardDescriptorScript.validate(shard), "Valid aggregate shard rejected")
	_assert(shard["cell_ids"] == [_child_id(0), _child_id(1)], "Shard cell IDs are not canonical sorted unique")
	_assert(String(shard["authority_address"]["authority_owner_id"]) == "region-authority/a", "Shard authority address changed")
	var unsorted: Dictionary = shard.duplicate(true)
	unsorted["cell_ids"] = [_child_id(1), _child_id(0)]
	_assert_fail(ShardDescriptorScript.validate(unsorted), "Unsorted shard cell IDs accepted")
	var self_neighbour: Dictionary = shard.duplicate(true)
	self_neighbour["neighbour_shard_ids"] = [String(shard["shard_id"])]
	_assert_fail(ShardDescriptorScript.validate(self_neighbour), "Shard accepted itself as neighbour")
	var bad_kind: Dictionary = shard.duplicate(true)
	bad_kind["aggregate_kind"] = "environment-cell"
	_assert_fail(ShardDescriptorScript.validate(bad_kind), "Noncanonical aggregate kind accepted")
	var authority_from_cell: Dictionary = shard.duplicate(true)
	authority_from_cell.erase("authority_address")
	authority_from_cell["authority_cell_id"] = _child_id(0)
	_assert_fail(ShardDescriptorScript.validate(authority_from_cell), "Cell-derived authority representation accepted")


func _test_neighbour_descriptor() -> void:
	var link: Dictionary = NeighbourDescriptorScript.create(
		"cell-neighbour/face-0/0-1",
		_child_id(0),
		_child_id(1),
		NeighbourDescriptorScript.RELATION_FACE,
		"boundary/east",
		"boundary/west",
		true,
		1
	)
	_assert_ok(NeighbourDescriptorScript.validate(link), "Valid neighbour descriptor rejected")
	var self_link: Dictionary = link.duplicate(true)
	self_link["target_cell_id"] = self_link["source_cell_id"]
	_assert_fail(NeighbourDescriptorScript.validate(self_link), "Cell self-neighbour accepted")
	var bad_relation: Dictionary = link.duplicate(true)
	bad_relation["relation_kind"] = "NEAR"
	_assert_fail(NeighbourDescriptorScript.validate(bad_relation), "Unknown neighbour relation accepted")
	var missing_direction: Dictionary = link.duplicate(true)
	missing_direction["bidirectional"] = 1
	_assert_fail(NeighbourDescriptorScript.validate(missing_direction), "Non-boolean bidirectional flag accepted")


func _test_boundary_summary() -> void:
	var summary: Dictionary = BoundarySummaryScript.create(
		"boundary-summary/meadow/a-b/1",
		"aggregate-shard/meadow/a",
		"aggregate-shard/meadow/b",
		"boundary/meadow/a-b",
		"planet_simulator.vegetation_boundary.v1",
		12,
		100,
		200,
		{"seed_pressure": 0.4, "water_flow": 2.5}
	)
	_assert_ok(BoundarySummaryScript.validate(summary), "Valid boundary summary rejected")
	var modified: Dictionary = summary.duplicate(true)
	modified["values_by_key"]["water_flow"] = 9.0
	_assert_fail(BoundarySummaryScript.validate(modified), "Modified boundary summary checksum accepted")
	var bad_ticks: Dictionary = summary.duplicate(true)
	bad_ticks["from_tick"] = 300
	bad_ticks["checksum"] = BoundarySummaryScript.compute_checksum(bad_ticks)
	_assert_fail(BoundarySummaryScript.validate(bad_ticks), "Reversed boundary tick range accepted")
	var runtime_value: Dictionary = summary.duplicate(true)
	runtime_value["values_by_key"]["node"] = RefCounted.new()
	runtime_value["checksum"] = BoundarySummaryScript.compute_checksum(runtime_value)
	_assert_fail(BoundarySummaryScript.validate(runtime_value), "Runtime boundary value accepted")
	var bad_key: Dictionary = summary.duplicate(true)
	bad_key["values_by_key"] = {"Seed Pressure": 1.0}
	bad_key["checksum"] = BoundarySummaryScript.compute_checksum(bad_key)
	_assert_fail(BoundarySummaryScript.validate(bad_key), "Noncanonical boundary value key accepted")


func _test_runner_contracts() -> void:
	var s0_runner: String = FileAccess.get_file_as_string("res://RUN_S0_SPATIAL_SUBSTRATE_TESTS.ps1")
	var network_runner: String = FileAccess.get_file_as_string("res://RUN_NETWORK_CONTRACT_TESTS.ps1")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	_assert(not s0_runner.is_empty(), "S0 PowerShell runner is missing")
	_assert(s0_runner.contains("function Write-JsonFileAtomically"), "S0 runner lacks atomic summary writer")
	_assert(s0_runner.contains("$Stream.Flush($true)"), "S0 runner does not force summary flush")
	_assert(s0_runner.contains("PSNativeCommandUseErrorActionPreference"), "S0 runner is not stderr-safe")
	_assert(s0_runner.contains("test_s0_spatial_substrate_contracts.gd") and s0_runner.contains("test_s0_spatial_substrate_integration.gd"), "S0 runner omits S0 tests")
	_assert(network_runner.contains("test_s0_spatial_substrate_contracts.gd") and network_runner.contains("test_s0_spatial_substrate_integration.gd"), "Network runner omits S0 tests")
	_assert(world_runner.contains("test_s0_spatial_substrate_contracts.gd") and world_runner.contains("test_s0_spatial_substrate_integration.gd"), "World runner omits S0 tests")


func _root_address() -> Dictionary:
	return CellAddressScript.create("main", "earth-01", "surface", "quad-tree", 1, "face-0", [])


func _child_id(index: int) -> String:
	return String(CellAddressScript.child(_root_address(), index)["cell_id"])


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
		print("S0 spatial substrate contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("S0 spatial substrate contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
