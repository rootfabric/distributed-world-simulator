extends SceneTree

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayout = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const BrickSnapshot = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterSample = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")
const SummaryBuilder = preload("res://scripts/simulation/representation/matter/matter_summary_builder.gd")
const RebuildTask = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_rebuild_task.gd")
const RebuildQueue = preload("res://scripts/simulation/representation/matter/matter_summary_rebuild_queue.gd")
const DirtyPropagator = preload("res://scripts/simulation/representation/matter/matter_summary_dirty_propagator.gd")
const PersistenceManifest = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_persistence_manifest.gd")
const SummaryPyramid = preload("res://scripts/simulation/representation/matter/matter_summary_pyramid.gd")

var failures: Array[String] = []
var assertions: int = 0
var grid_profile: Dictionary = {}
var root_address: Dictionary = {}
var parent_0: Dictionary = {}
var leaf_a_address: Dictionary = {}
var leaf_b_address: Dictionary = {}
var outside_leaf_address: Dictionary = {}
var leaf_a_snapshot: Dictionary = {}
var leaf_b_snapshot: Dictionary = {}
var leaf_a: Dictionary = {}
var leaf_b: Dictionary = {}
var parent_summary: Dictionary = {}
var root_summary: Dictionary = {}


func _init() -> void:
	_build_fixture()
	_test_config()
	_test_leaf_summary()
	_test_parent_summary()
	_test_summary_contract_fences()
	_test_dirty_propagator()
	_test_rebuild_queue()
	_test_pyramid_registration()
	_test_mutation_dirty_propagation()
	_test_repeated_invalidation_coalescing()
	_test_persistence_manifest()
	_test_handoff_invalidation()
	_test_atomic_capacity_fences()
	_test_runtime_object_rejection()
	_finish()


func _build_fixture() -> void:
	grid_profile = GridProfile.create({
		"body_id": "body/asteroid-rl1",
		"body_frame_id": "frame/asteroid-rl1",
		"root_center_m": [0.0, 0.0, 0.0],
		"root_half_extent_m": 16.0,
		"max_level": 3,
		"brick_interior_resolution": 2,
		"ghost_border_samples": 1,
	})
	root_address = CellGrid.root_address(grid_profile)
	parent_0 = CellGrid.child(root_address, 0, grid_profile)
	leaf_a_address = CellGrid.child(parent_0, 0, grid_profile)
	leaf_b_address = CellGrid.child(parent_0, 1, grid_profile)
	var parent_1: Dictionary = CellGrid.child(root_address, 1, grid_profile)
	outside_leaf_address = CellGrid.child(parent_1, 0, grid_profile)
	leaf_a_snapshot = _snapshot(leaf_a_address, "leaf-a", 5, "A")
	leaf_b_snapshot = _snapshot(leaf_b_address, "leaf-b", 7, "B")
	leaf_a = SummaryBuilder.from_brick_snapshot(leaf_a_snapshot, grid_profile, 4, 7, 1)
	leaf_b = SummaryBuilder.from_brick_snapshot(leaf_b_snapshot, grid_profile, 4, 7, 1)
	parent_summary = SummaryBuilder.from_children(
		"body/asteroid-rl1", parent_0, grid_profile, [leaf_b, leaf_a], 4, 7, 1
	)
	root_summary = SummaryBuilder.from_children(
		"body/asteroid-rl1", root_address, grid_profile, [parent_summary], 4, 7, 1
	)


func _test_config() -> void:
	var path := "res://config/representation/matter-summary-pyramid.v1.json"
	_assert(FileAccess.file_exists(path), "RL1 config missing")
	var file := FileAccess.open(path, FileAccess.READ)
	_assert(file != null, "RL1 config unreadable")
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	_assert(typeof(parsed) == TYPE_DICTIONARY, "RL1 config is not an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var config: Dictionary = parsed
	_assert(String(config.get("checkpoint", "")) == "v17.10.0-simulation-rl1-matter-summary-pyramid", "RL1 checkpoint changed")
	_assert(String(config.get("accepted_base", "")) == "v17.9.0-simulation-rl0-representation-contracts-fix1", "RL1 base changed")
	_assert(String(config.get("recommended_branch", "")) == "feature/rl1-matter-summary-pyramid", "RL1 branch changed")
	_assert(bool(config.get("summary", {}).get("regional_authority_scoped", false)), "RL1 is not region scoped")
	_assert(int(config.get("summary", {}).get("parent_child_branching", 0)) == 8, "RL1 octree branching changed")
	_assert(bool(config.get("dirty_propagation", {}).get("queue_updates_are_atomic", false)), "RL1 queue atomicity disabled")
	_assert(not bool(config.get("boundaries", {}).get("mesh_or_collision_generated", true)), "RL1 generates presentation artifacts")
	_assert(not bool(config.get("boundaries", {}).get("production_worlds_changed", true)), "RL1 changes production worlds")


func _test_leaf_summary() -> void:
	_assert_ok(GridProfile.validate(grid_profile), "Grid profile rejected")
	_assert_ok(BrickSnapshot.validate(leaf_a_snapshot), "Leaf A snapshot rejected")
	_assert_ok(SummaryNode.validate(leaf_a), "Leaf A summary rejected")
	_assert(String(leaf_a["summary_id"]) == SummaryNode.summary_id_for("body/asteroid-rl1", leaf_a_address), "Leaf summary ID changed")
	_assert(String(leaf_a["scope_id"]) == SummaryNode.scope_id_for("body/asteroid-rl1", leaf_a_address), "Leaf scope ID changed")
	_assert(int(leaf_a["child_count"]) == 0, "Leaf has children")
	_assert(int(leaf_a["leaf_count"]) == 1, "Leaf count changed")
	_assert(int(leaf_a["sample_count"]) == 125, "Leaf sample count changed")
	_assert(int(leaf_a["occupied_sample_count"]) == 60, "Leaf occupied count changed")
	_assert(int(leaf_a["surface_sample_count"]) == 20, "Leaf surface count changed")
	_assert(absf(float(leaf_a["minimum_signed_distance_m"]) + 2.0) < 0.000000001, "Leaf minimum SDF changed")
	_assert(absf(float(leaf_a["maximum_signed_distance_m"]) - 2.0) < 0.000000001, "Leaf maximum SDF changed")
	_assert(float(leaf_a["minimum_occupancy_ratio"]) == 0.0, "Leaf minimum occupancy changed")
	_assert(float(leaf_a["maximum_occupancy_ratio"]) == 1.0, "Leaf maximum occupancy changed")
	_assert(bool(leaf_a["contains_matter"]), "Leaf matter presence missing")
	_assert(bool(leaf_a["contains_vacuum"]), "Leaf vacuum presence missing")
	_assert(bool(leaf_a["contains_surface"]), "Leaf surface presence missing")
	_assert(absf(float(leaf_a["total_occupancy_weight"]) - 50.0) < 0.000000001, "Leaf material total changed")
	var materials: Array = leaf_a["material_occupancy_weights"]
	_assert(materials.size() == 2, "Leaf material count changed")
	_assert(String(materials[0]["material_id"]) == "material/basalt", "Leaf materials not sorted")
	_assert(absf(float(materials[0]["occupancy_weight"]) - 47.5) < 0.000000001, "Basalt weight changed")
	_assert(String(materials[1]["material_id"]) == "material/ice", "Ice material missing")
	_assert(absf(float(materials[1]["occupancy_weight"]) - 2.5) < 0.000000001, "Ice weight changed")
	_assert(int(leaf_a["minimum_descendant_revision"]) == 5, "Leaf minimum descendant revision changed")
	_assert(int(leaf_a["maximum_descendant_revision"]) == 5, "Leaf maximum descendant revision changed")
	_assert(RepresentationUtils.is_lower_hex_64(leaf_a["dependency_hash"]), "Leaf dependency hash invalid")
	_assert(RepresentationUtils.is_lower_hex_64(leaf_a["descendant_revision_hash"]), "Leaf descendant hash invalid")
	var source: Dictionary = SummaryNode.to_source_revision(leaf_a)
	_assert_ok(SourceRevision.validate(source), "Leaf source projection rejected")
	_assert(int(source["source_revision"]) == 7, "Leaf source revision changed")
	_assert(String(source["source_hash"]) == String(leaf_a["checksum"]), "Leaf source hash changed")


func _test_parent_summary() -> void:
	_assert_ok(SummaryNode.validate(parent_summary), "Parent summary rejected")
	var reordered: Dictionary = SummaryBuilder.from_children(
		"body/asteroid-rl1", parent_0, grid_profile, [leaf_a, leaf_b], 4, 7, 1
	)
	_assert(parent_summary == reordered, "Parent summary depends on child arrival order")
	_assert(int(parent_summary["child_count"]) == 2, "Parent child count changed")
	_assert(int(parent_summary["leaf_count"]) == 2, "Parent leaf count changed")
	_assert(int(parent_summary["sample_count"]) == 250, "Parent sample count changed")
	_assert(int(parent_summary["occupied_sample_count"]) == 160, "Parent occupied count changed")
	_assert(int(parent_summary["surface_sample_count"]) == 20, "Parent surface count changed")
	_assert(absf(float(parent_summary["total_occupancy_weight"]) - 150.0) < 0.000000001, "Parent material total changed")
	_assert(int(parent_summary["minimum_descendant_revision"]) == 5, "Parent minimum revision changed")
	_assert(int(parent_summary["maximum_descendant_revision"]) == 7, "Parent maximum revision changed")
	_assert(bool(parent_summary["contains_surface"]), "Parent surface presence missing")
	_assert_ok(SummaryNode.validate(root_summary), "Root summary rejected")
	_assert(int(root_summary["child_count"]) == 1, "Sparse root child count changed")
	_assert(int(root_summary["leaf_count"]) == 2, "Root leaf count changed")
	var wrong_parent: Dictionary = SummaryBuilder.from_children(
		"body/asteroid-rl1", root_address, grid_profile, [leaf_a], 4, 7, 1
	)
	_assert(wrong_parent.is_empty(), "Non-direct child accepted by parent builder")
	var mixed_epoch: Dictionary = SummaryBuilder.from_brick_snapshot(leaf_b_snapshot, grid_profile, 5, 7, 1)
	_assert(not mixed_epoch.is_empty(), "Mixed-epoch fixture failed")
	_assert(SummaryBuilder.from_children("body/asteroid-rl1", parent_0, grid_profile, [leaf_a, mixed_epoch], 4, 7, 1).is_empty(), "Mixed authority epochs accepted")
	_assert(SummaryBuilder.from_children("body/asteroid-rl1", parent_0, grid_profile, [leaf_a, leaf_b], 4, 6, 1).is_empty(), "Parent revision behind descendant accepted")
	var changed_snapshot := _snapshot(leaf_a_address, "leaf-a", 8, "C")
	var changed_leaf := SummaryBuilder.from_brick_snapshot(changed_snapshot, grid_profile, 4, 8, 2)
	var changed_parent := SummaryBuilder.from_children("body/asteroid-rl1", parent_0, grid_profile, [changed_leaf, leaf_b], 4, 8, 2)
	_assert(String(changed_leaf["descendant_revision_hash"]) != String(leaf_a["descendant_revision_hash"]), "Leaf descendant hash ignored source change")
	_assert(String(changed_parent["descendant_revision_hash"]) != String(parent_summary["descendant_revision_hash"]), "Parent descendant hash ignored child change")
	_assert(String(changed_parent["dependency_hash"]) != String(parent_summary["dependency_hash"]), "Parent dependency hash ignored child change")


func _test_summary_contract_fences() -> void:
	var extra := leaf_a.duplicate(true)
	extra["mesh"] = "forbidden"
	_assert_fail(SummaryNode.validate(extra), "Summary accepted presentation field")
	var stale_checksum := leaf_a.duplicate(true)
	stale_checksum["summary_revision"] = 8
	_assert_fail(SummaryNode.validate(stale_checksum), "Summary accepted stale checksum")
	var reversed_sdf := leaf_a.duplicate(true)
	reversed_sdf["minimum_signed_distance_m"] = 3.0
	reversed_sdf["checksum"] = RepresentationUtils.compute_checksum(reversed_sdf)
	_assert_fail(SummaryNode.validate(reversed_sdf), "Summary accepted reversed SDF range")
	var bad_flag := leaf_a.duplicate(true)
	bad_flag["contains_surface"] = false
	bad_flag["checksum"] = RepresentationUtils.compute_checksum(bad_flag)
	_assert_fail(SummaryNode.validate(bad_flag), "Summary accepted inconsistent surface flag")
	var unsorted := leaf_a.duplicate(true)
	unsorted["material_occupancy_weights"].reverse()
	unsorted["checksum"] = RepresentationUtils.compute_checksum(unsorted)
	_assert_fail(SummaryNode.validate(unsorted), "Summary accepted unsorted materials")
	var wrong_total := leaf_a.duplicate(true)
	wrong_total["total_occupancy_weight"] = 51.0
	wrong_total["checksum"] = RepresentationUtils.compute_checksum(wrong_total)
	_assert_fail(SummaryNode.validate(wrong_total), "Summary accepted material total mismatch")
	var wrong_scope := leaf_a.duplicate(true)
	wrong_scope["scope_id"] = "representation-scope/matter-summary/wrong"
	wrong_scope["checksum"] = RepresentationUtils.compute_checksum(wrong_scope)
	_assert_fail(SummaryNode.validate(wrong_scope), "Summary accepted wrong scope")


func _test_dirty_propagator() -> void:
	var chain: Array = DirtyPropagator.mutation_chain(leaf_a_address, root_address)
	_assert(chain.size() == 3, "Mutation dirty chain size changed")
	_assert(chain[0] == leaf_a_address, "Mutation chain does not start at leaf")
	_assert(chain[1] == parent_0, "Mutation chain parent changed")
	_assert(chain[2] == root_address, "Mutation chain does not stop at region root")
	_assert(DirtyPropagator.mutation_chain(outside_leaf_address, parent_0).is_empty(), "Out-of-region mutation produced dirty chain")
	var scopes: Array = DirtyPropagator.sorted_scope_ids("body/asteroid-rl1", chain)
	_assert(scopes.size() == 3, "Dirty scope count changed")
	var sorted_scopes: Array = scopes.duplicate()
	sorted_scopes.sort()
	_assert(scopes == sorted_scopes, "Dirty scopes are not canonical")
	var handoff_cells: Array = DirtyPropagator.handoff_cells(root_address, [leaf_b, root_summary, leaf_a, parent_summary])
	_assert(handoff_cells.size() == 4, "Handoff cell set changed")
	_assert(int(handoff_cells[0]["level"]) == 2, "Handoff ordering is not fine-to-coarse")
	_assert(int(handoff_cells[3]["level"]) == 0, "Handoff root_address ordering changed")
	var sparse_handoff_cells: Array = DirtyPropagator.handoff_cells(root_address, [leaf_a])
	_assert(sparse_handoff_cells.size() == 3, "Handoff omitted unloaded intermediate ancestor")
	_assert(sparse_handoff_cells[1] == parent_0, "Handoff reconstructed wrong intermediate ancestor")


func _test_rebuild_queue() -> void:
	var queue := RebuildQueue.new()
	_assert_ok(queue.setup(2), "Queue setup failed")
	var leaf_task := _task(leaf_a_address, 4, 8, "MUTATION", [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0], 1)
	var parent_task := _task(parent_0, 4, 8, "MUTATION", [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0], 1)
	var root_task := _task(root_address, 4, 8, "MUTATION", [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0], 1)
	_assert_ok(RebuildTask.validate(leaf_task), "Leaf rebuild task rejected")
	_assert_ok(queue.enqueue_many([parent_task, leaf_task]), "Queue batch enqueue failed")
	_assert(queue.size() == 2, "Queue size changed")
	_assert(String(queue.peek()["cell_address"]["cell_id"]) == String(leaf_a_address["cell_id"]), "Queue is not fine-to-coarse")
	_assert_fail(queue.enqueue(root_task), "Queue accepted task above capacity")
	_assert(queue.size() == 2, "Capacity failure mutated queue")
	var advanced := _task(leaf_a_address, 4, 9, "MUTATION", [-2.0, -2.0, -2.0, 2.0, 2.0, 2.0], 2)
	_assert_ok(queue.enqueue(advanced), "Queue failed to coalesce advanced task")
	_assert(queue.size() == 2, "Queue coalescing added duplicate")
	var merged: Dictionary = queue.get_task(String(leaf_a_address["cell_id"]))
	_assert(int(merged["target_source_revision"]) == 9, "Queue did not advance source frontier")
	_assert(Array(merged["dirty_bounds_m"]) == [-2.0, -2.0, -2.0, 2.0, 2.0, 2.0], "Queue did not union dirty bounds")
	_assert(int(merged["enqueue_revision"]) == 1, "Queue coalescing lost fairness")
	_assert_fail(queue.enqueue(leaf_task), "Queue accepted rebuild frontier rollback")
	_assert(int(queue.pop()["priority_level"]) == 2, "Queue pop order changed")
	_assert(int(queue.pop()["priority_level"]) == 1, "Queue parent order changed")
	_assert(queue.is_empty(), "Queue not empty after pops")


func _test_pyramid_registration() -> void:
	var pyramid := _pyramid(8)
	_assert_ok(pyramid.register_summary(leaf_a), "Leaf A registration failed")
	_assert_ok(pyramid.register_summary(leaf_b), "Leaf B registration failed")
	_assert_ok(pyramid.register_summary(parent_summary), "Parent registration failed")
	_assert_ok(pyramid.register_summary(root_summary), "Root registration failed")
	_assert(pyramid.summary_count() == 4, "Pyramid summary count changed")
	_assert(int(pyramid.source_revision()["source_revision"]) == 7, "Initial pyramid source revision changed")
	var ahead_leaf := SummaryBuilder.from_brick_snapshot(leaf_a_snapshot, grid_profile, 4, 8, 2)
	_assert_fail(pyramid.register_summary(ahead_leaf), "Summary ahead of pyramid source frontier accepted")
	_assert_ok(pyramid.register_summary(leaf_a), "Exact summary replay rejected")
	var replay: Dictionary = pyramid.register_summary(leaf_a)
	_assert(bool(replay.get("details", {}).get("replay", false)), "Exact replay not marked")
	var same_revision_changed_snapshot := _snapshot(leaf_a_address, "leaf-a", 5, "C")
	var same_revision_changed := SummaryBuilder.from_brick_snapshot(same_revision_changed_snapshot, grid_profile, 4, 7, 2)
	_assert_fail(pyramid.register_summary(same_revision_changed), "Same-revision summary mutation accepted")
	var old_summary := SummaryBuilder.from_brick_snapshot(leaf_a_snapshot, grid_profile, 4, 6, 1)
	_assert(not old_summary.is_empty(), "Old summary fixture failed")
	_assert_fail(pyramid.register_summary(old_summary), "Summary revision rollback accepted")
	var foreign := leaf_a.duplicate(true)
	foreign["body_id"] = "body/other"
	foreign["summary_id"] = SummaryNode.summary_id_for("body/other", foreign["cell_address"])
	foreign["scope_id"] = SummaryNode.scope_id_for("body/other", foreign["cell_address"])
	foreign["checksum"] = RepresentationUtils.compute_checksum(foreign)
	_assert_ok(SummaryNode.validate(foreign), "Foreign summary fixture invalid")
	_assert_fail(pyramid.register_summary(foreign), "Foreign body summary accepted")
	var regional := SummaryPyramid.new()
	_assert_ok(regional.setup(grid_profile, parent_0, _source(4, 7, "source-7"), 4), "Regional pyramid setup failed")
	var outside_snapshot := _snapshot(outside_leaf_address, "outside", 7, "B")
	var outside_summary := SummaryBuilder.from_brick_snapshot(outside_snapshot, grid_profile, 4, 7, 1)
	_assert_fail(regional.register_summary(outside_summary), "Out-of-region summary accepted")
	_assert(not pyramid.get_ready_summary(String(root_address["cell_id"])).is_empty(), "Clean root not ready")


func _test_mutation_dirty_propagation() -> void:
	var pyramid := _loaded_pyramid(8)
	var previous := _source(4, 7, "source-7")
	var current := _source(4, 8, "source-8")
	var result: Dictionary = pyramid.invalidate_mutation(
		"representation-invalidation/rl1/mutation-8",
		previous,
		current,
		leaf_a_address,
		[-8.0, -8.0, -8.0, 0.0, 0.0, 0.0],
		800
	)
	_assert_ok(result, "Mutation invalidation failed")
	_assert(int(pyramid.source_revision()["source_revision"]) == 8, "Mutation did not advance pyramid source revision")
	var invalidation: Dictionary = result.get("details", {}).get("invalidation", {})
	_assert_ok(Invalidation.validate(invalidation), "RL0 invalidation projection rejected")
	_assert(String(invalidation["reason"]) == "MUTATION", "Mutation reason changed")
	_assert(Array(invalidation["affected_scope_ids"]).size() == 3, "Mutation affected scope count changed")
	_assert(pyramid.dirty_count() == 3, "Mutation dirty count changed")
	_assert(pyramid.queue_size() == 3, "Mutation queue count changed")
	_assert(pyramid.is_dirty(String(leaf_a_address["cell_id"])), "Changed leaf not dirty")
	_assert(pyramid.is_dirty(String(parent_0["cell_id"])), "Parent not dirty")
	_assert(pyramid.is_dirty(String(root_address["cell_id"])), "Root not dirty")
	_assert(not pyramid.is_dirty(String(leaf_b_address["cell_id"])), "Unchanged sibling became dirty")
	_assert(pyramid.get_ready_summary(String(leaf_a_address["cell_id"])).is_empty(), "Dirty leaf remained ready")
	_assert(not pyramid.get_summary(String(leaf_a_address["cell_id"])).is_empty(), "Stale leaf was discarded")
	_assert_fail(pyramid.register_summary(leaf_a), "Old dirty summary replay accepted")
	_assert(pyramid.dirty_count() == 3 and pyramid.queue_size() == 3, "Rejected stale replay changed rebuild state")
	var tasks: Array = pyramid.queued_tasks()
	_assert(int(tasks[0]["priority_level"]) == 2, "Mutation queue does not start with leaf")
	_assert(int(tasks[1]["priority_level"]) == 1, "Mutation queue parent order changed")
	_assert(int(tasks[2]["priority_level"]) == 0, "Mutation queue root order changed")
	_assert(pyramid.export_persistence_manifest("matter-summary-manifest/dirty", 1).is_empty(), "Dirty root persisted as ready manifest")
	var new_snapshot := _snapshot(leaf_a_address, "leaf-a", 8, "C")
	var new_leaf := SummaryBuilder.from_brick_snapshot(new_snapshot, grid_profile, 4, 8, 2)
	_assert_ok(pyramid.register_summary(new_leaf), "Rebuilt leaf registration failed")
	_assert(pyramid.dirty_count() == 2 and pyramid.queue_size() == 2, "Leaf rebuild did not clear one dirty task")
	var new_parent := SummaryBuilder.from_children("body/asteroid-rl1", parent_0, grid_profile, [new_leaf, leaf_b], 4, 8, 2)
	_assert_ok(pyramid.register_summary(new_parent), "Rebuilt parent registration failed")
	var new_root := SummaryBuilder.from_children("body/asteroid-rl1", root_address, grid_profile, [new_parent], 4, 8, 2)
	_assert_ok(pyramid.register_summary(new_root), "Rebuilt root registration failed")
	_assert(pyramid.dirty_count() == 0 and pyramid.queue_size() == 0, "Rebuild chain did not converge")
	_assert(not pyramid.get_ready_summary(String(root_address["cell_id"])).is_empty(), "Rebuilt root not ready")
	var rebuilt_manifest: Dictionary = pyramid.export_persistence_manifest("matter-summary-manifest/revision-8", 2)
	_assert_ok(PersistenceManifest.validate(rebuilt_manifest), "Rebuilt mixed-revision manifest rejected")
	_assert(int(rebuilt_manifest["source_revision"]["source_revision"]) == 8, "Rebuilt manifest lost source frontier")
	var found_unchanged_revision: bool = false
	for entry in rebuilt_manifest["entries"]:
		if String(entry["cell_id"]) == String(leaf_b_address["cell_id"]):
			found_unchanged_revision = int(entry["summary_revision"]) == 7
	_assert(found_unchanged_revision, "Manifest did not preserve unchanged child summary revision")
	var duplicate_transition: Dictionary = pyramid.invalidate_mutation(
		"representation-invalidation/rl1/reused-frontier",
		previous, current, leaf_a_address, [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0], 801
	)
	_assert_fail(duplicate_transition, "Already-consumed source frontier accepted again")
	_assert(pyramid.dirty_count() == 0 and pyramid.queue_size() == 0, "Rejected reused frontier changed rebuild state")


func _test_repeated_invalidation_coalescing() -> void:
	var pyramid := _loaded_pyramid(8)
	var first: Dictionary = pyramid.invalidate_mutation(
		"representation-invalidation/rl1/coalesce-8",
		_source(4, 7, "source-7"),
		_source(4, 8, "source-8"),
		leaf_a_address,
		[-8.0, -8.0, -8.0, 0.0, 0.0, 0.0],
		810
	)
	_assert_ok(first, "First coalesced invalidation failed")
	var stale_frontier: Dictionary = pyramid.invalidate_mutation(
		"representation-invalidation/rl1/coalesce-stale",
		_source(4, 7, "source-7"),
		_source(4, 9, "source-9"),
		leaf_a_address,
		[0.0, 0.0, 0.0, 8.0, 8.0, 8.0],
		811
	)
	_assert_fail(stale_frontier, "Stale previous source frontier accepted during coalescing")
	_assert(int(pyramid.source_revision()["source_revision"]) == 8 and pyramid.queue_size() == 3, "Rejected stale frontier changed pyramid state")
	var wrong_hash_frontier: Dictionary = pyramid.invalidate_mutation(
		"representation-invalidation/rl1/coalesce-wrong-hash",
		_source(4, 8, "different-source-8"),
		_source(4, 9, "source-9"),
		leaf_a_address,
		[0.0, 0.0, 0.0, 8.0, 8.0, 8.0],
		811
	)
	_assert_fail(wrong_hash_frontier, "Same numeric frontier with foreign source hash accepted")
	_assert(int(pyramid.source_revision()["source_revision"]) == 8 and pyramid.queue_size() == 3, "Rejected foreign source hash changed pyramid state")
	var second: Dictionary = pyramid.invalidate_mutation(
		"representation-invalidation/rl1/coalesce-9",
		_source(4, 8, "source-8"),
		_source(4, 9, "source-9"),
		leaf_a_address,
		[0.0, 0.0, 0.0, 8.0, 8.0, 8.0],
		812
	)
	_assert_ok(second, "Second coalesced invalidation failed")
	_assert(int(pyramid.source_revision()["source_revision"]) == 9, "Coalesced invalidation did not advance source frontier")
	_assert(pyramid.dirty_count() == 3 and pyramid.queue_size() == 3, "Coalescing duplicated dirty ancestors")
	var leaf_task: Dictionary = {}
	for task in pyramid.queued_tasks():
		if String(task["cell_address"]["cell_id"]) == String(leaf_a_address["cell_id"]):
			leaf_task = task
	_assert(not leaf_task.is_empty(), "Coalesced leaf task missing")
	_assert(int(leaf_task["target_source_revision"]) == 9, "Coalesced task retained old target revision")
	_assert(int(leaf_task["enqueue_revision"]) == 1, "Coalesced task lost original fairness")
	_assert(Array(leaf_task["dirty_bounds_m"]) == [-8.0, -8.0, -8.0, 8.0, 8.0, 8.0], "Coalesced task did not union dirty bounds")
	var dirty: Dictionary = pyramid.dirty_record(String(leaf_a_address["cell_id"]))
	_assert(int(dirty["target_source_revision"]) == 9, "Dirty record retained old target revision")
	_assert(Array(dirty["dirty_bounds_m"]) == Array(leaf_task["dirty_bounds_m"]), "Dirty record diverged from queue bounds")


func _test_persistence_manifest() -> void:
	var pyramid := _loaded_pyramid(8)
	var manifest: Dictionary = pyramid.export_persistence_manifest("matter-summary-manifest/region-root/1", 1)
	_assert_ok(PersistenceManifest.validate(manifest), "Persistence manifest rejected")
	_assert(int(manifest["entry_count"]) == 4, "Persistence manifest entry count changed")
	_assert(int(manifest["source_revision"]["source_revision"]) == 7, "Persistence manifest source frontier changed")
	_assert(String(manifest["entries"][0]["cell_id"]) < String(manifest["entries"][1]["cell_id"]), "Manifest entries not sorted")
	for entry in manifest["entries"]:
		_assert(String(entry["storage_key"]) == "summary/%s" % String(entry["summary_hash"]), "Manifest storage key changed")
	var reversed: Array = pyramid.all_summaries()
	reversed.reverse()
	var deterministic := PersistenceManifest.create(
		"matter-summary-manifest/region-root/1",
		"body/asteroid-rl1",
		root_address,
		GridProfile.content_hash(grid_profile),
		_source(4, 7, "source-7"),
		1,
		reversed
	)
	_assert(manifest == deterministic, "Persistence manifest depends on summary arrival order")
	_assert(String(manifest["manifest_hash"]) == RepresentationUtils.payload_hash(manifest["entries"]), "Manifest content hash changed")
	var bad_storage: Dictionary = manifest.duplicate(true)
	bad_storage["entries"][0]["storage_key"] = "summary/wrong"
	bad_storage["manifest_hash"] = RepresentationUtils.payload_hash(bad_storage["entries"])
	bad_storage["checksum"] = RepresentationUtils.compute_checksum(bad_storage)
	_assert_fail(PersistenceManifest.validate(bad_storage), "Manifest accepted wrong content key")
	var outside_entry: Dictionary = manifest.duplicate(true)
	outside_entry["entries"][0]["cell_address"] = outside_leaf_address.duplicate(true)
	outside_entry["entries"][0]["cell_id"] = String(outside_leaf_address["cell_id"])
	outside_entry["entries"][0]["level"] = int(outside_leaf_address["level"])
	outside_entry["entries"][0]["summary_id"] = SummaryNode.summary_id_for("body/asteroid-rl1", outside_leaf_address)
	outside_entry["entries"][0]["scope_id"] = SummaryNode.scope_id_for("body/asteroid-rl1", outside_leaf_address)
	outside_entry["entries"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_id"]) < String(b["cell_id"])
	)
	outside_entry["manifest_hash"] = RepresentationUtils.payload_hash(outside_entry["entries"])
	outside_entry["checksum"] = RepresentationUtils.compute_checksum(outside_entry)
	_assert_fail(PersistenceManifest.validate(outside_entry), "Manifest accepted summary outside authority region")
	var missing_root := PersistenceManifest.create(
		"matter-summary-manifest/no-root",
		"body/asteroid-rl1",
		root_address,
		GridProfile.content_hash(grid_profile),
		_source(4, 7, "source-7"),
		1,
		[leaf_a, leaf_b, parent_summary]
	)
	_assert(missing_root.is_empty(), "Manifest without region root accepted")


func _test_handoff_invalidation() -> void:
	var pyramid := _loaded_pyramid(8)
	var previous := _source(4, 7, "source-7")
	var target := _source(5, 7, "source-7")
	var result: Dictionary = pyramid.invalidate_handoff(
		"representation-invalidation/rl1/handoff-5",
		previous,
		target,
		[-16.0, -16.0, -16.0, 16.0, 16.0, 16.0],
		900
	)
	_assert_ok(result, "Handoff invalidation failed")
	var invalidation: Dictionary = result.get("details", {}).get("invalidation", {})
	_assert_ok(Invalidation.validate(invalidation), "Handoff RL0 invalidation rejected")
	_assert(String(invalidation["reason"]) == "HANDOFF", "Handoff reason changed")
	_assert(pyramid.authority_epoch() == 5, "Pyramid authority epoch did not advance")
	_assert(int(pyramid.source_revision()["source_revision"]) == 7, "Handoff changed stable source revision")
	_assert(pyramid.dirty_count() == 4, "Handoff did not dirty loaded subtree")
	_assert(pyramid.queue_size() == 4, "Handoff rebuild queue count changed")
	for task in pyramid.queued_tasks():
		_assert(int(task["target_authority_epoch"]) == 5, "Handoff task retained old epoch")
		_assert(int(task["target_source_revision"]) == 7, "Handoff task changed source revision")
	_assert_fail(pyramid.register_summary(leaf_a), "Old-epoch summary accepted after handoff")
	var leaf_a_epoch5 := SummaryBuilder.from_brick_snapshot(leaf_a_snapshot, grid_profile, 5, 7, 2)
	var leaf_b_epoch5 := SummaryBuilder.from_brick_snapshot(leaf_b_snapshot, grid_profile, 5, 7, 2)
	var parent_epoch5 := SummaryBuilder.from_children("body/asteroid-rl1", parent_0, grid_profile, [leaf_a_epoch5, leaf_b_epoch5], 5, 7, 2)
	var root_epoch5 := SummaryBuilder.from_children("body/asteroid-rl1", root_address, grid_profile, [parent_epoch5], 5, 7, 2)
	_assert_ok(pyramid.register_summary(leaf_a_epoch5), "Target leaf A rebuild failed")
	_assert_ok(pyramid.register_summary(leaf_b_epoch5), "Target leaf B rebuild failed")
	_assert_ok(pyramid.register_summary(parent_epoch5), "Target parent rebuild failed")
	_assert_ok(pyramid.register_summary(root_epoch5), "Target root rebuild failed")
	_assert(pyramid.dirty_count() == 0 and pyramid.queue_size() == 0, "Handoff rebuild did not converge")
	var manifest: Dictionary = pyramid.export_persistence_manifest("matter-summary-manifest/epoch-5", 2)
	_assert_ok(PersistenceManifest.validate(manifest), "Epoch-5 manifest rejected")
	_assert(int(manifest["authority_epoch"]) == 5, "Manifest retained old authority epoch")
	_assert(int(manifest["source_revision"]["source_revision"]) == 7, "Handoff manifest source revision changed")
	var rollback := _source(4, 8, "source-8")
	_assert_fail(pyramid.invalidate_handoff("representation-invalidation/rl1/rollback", target, rollback, [-16.0, -16.0, -16.0, 16.0, 16.0, 16.0], 901), "Authority rollback handoff accepted")


func _test_atomic_capacity_fences() -> void:
	var mutation_limited := _loaded_pyramid(2)
	var mutation: Dictionary = mutation_limited.invalidate_mutation(
		"representation-invalidation/rl1/capacity-mutation",
		_source(4, 7, "source-7"),
		_source(4, 8, "source-8"),
		leaf_a_address,
		[-1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
		1000
	)
	_assert_fail(mutation, "Mutation above queue capacity accepted")
	_assert(mutation_limited.dirty_count() == 0, "Failed mutation changed dirty state")
	_assert(mutation_limited.queue_size() == 0, "Failed mutation changed queue")
	_assert(mutation_limited.authority_epoch() == 4, "Failed mutation changed authority")
	_assert(int(mutation_limited.source_revision()["source_revision"]) == 7, "Failed mutation changed source revision")
	var handoff_limited := _loaded_pyramid(3)
	var handoff: Dictionary = handoff_limited.invalidate_handoff(
		"representation-invalidation/rl1/capacity-handoff",
		_source(4, 7, "source-7"),
		_source(5, 7, "source-7"),
		[-16.0, -16.0, -16.0, 16.0, 16.0, 16.0],
		1001
	)
	_assert_fail(handoff, "Handoff above queue capacity accepted")
	_assert(handoff_limited.dirty_count() == 0, "Failed handoff changed dirty state")
	_assert(handoff_limited.queue_size() == 0, "Failed handoff changed queue")
	_assert(handoff_limited.authority_epoch() == 4, "Failed handoff advanced authority")
	_assert(int(handoff_limited.source_revision()["source_revision"]) == 7, "Failed handoff changed source revision")


func _test_runtime_object_rejection() -> void:
	var runtime_node := Node3D.new()
	_assert(RepresentationUtils.canonical_json({"summary": leaf_a, "runtime": runtime_node}).is_empty(), "Runtime Node3D entered summary payload")
	runtime_node.free()
	var encoded: String = RepresentationUtils.canonical_json({"summary": leaf_a, "manifest": _loaded_pyramid(8).export_persistence_manifest("matter-summary-manifest/json", 1)})
	_assert(not encoded.is_empty(), "RL1 contracts are not JSON-safe")
	_assert(JSON.parse_string(encoded) != null, "RL1 canonical JSON cannot be decoded")


func _pyramid(capacity: int) -> RefCounted:
	var pyramid := SummaryPyramid.new()
	_assert_ok(pyramid.setup(grid_profile, root_address, _source(4, 7, "source-7"), capacity), "Pyramid setup failed")
	return pyramid


func _loaded_pyramid(capacity: int) -> RefCounted:
	var pyramid = _pyramid(capacity)
	_assert_ok(pyramid.register_summary(leaf_a), "Fixture leaf A registration failed")
	_assert_ok(pyramid.register_summary(leaf_b), "Fixture leaf B registration failed")
	_assert_ok(pyramid.register_summary(parent_summary), "Fixture parent registration failed")
	_assert_ok(pyramid.register_summary(root_summary), "Fixture root registration failed")
	return pyramid


func _snapshot(address: Dictionary, name: String, revision: int, pattern: String) -> Dictionary:
	var samples: Array = []
	var basalt := Composition.create([{"material_id": "material/basalt", "mass_fraction": 1.0}])
	var ice := Composition.create([{"material_id": "material/ice", "mass_fraction": 1.0}])
	var mixed := Composition.create([
		{"material_id": "material/basalt", "mass_fraction": 0.75},
		{"material_id": "material/ice", "mass_fraction": 0.25},
	])
	for index in range(GridProfile.sample_count(grid_profile)):
		if pattern == "A":
			if index < 40:
				samples.append(MatterSample.create(-2.0, 1.0, 2800.0, basalt, 1.0, 210.0, 0.05, []))
			elif index < 60:
				samples.append(MatterSample.create(0.0, 0.5, 2200.0, mixed, 0.8, 180.0, 0.2, []))
			else:
				samples.append(MatterSample.vacuum(2.0, 3.0))
		elif pattern == "B":
			if index < 100:
				samples.append(MatterSample.create(-1.0, 1.0, 920.0, ice, 0.9, 150.0, 0.1, []))
			else:
				samples.append(MatterSample.vacuum(1.0, 3.0))
		else:
			if index < 20:
				samples.append(MatterSample.create(-3.0, 1.0, 2800.0, basalt, 1.0, 210.0, 0.05, []))
			elif index < 80:
				samples.append(MatterSample.create(0.0, 0.25, 2200.0, mixed, 0.7, 170.0, 0.25, []))
			else:
				samples.append(MatterSample.vacuum(3.0, 3.0))
	return BrickSnapshot.create(
		"matter-brick-snapshot/%s/revision/%d" % [name, revision],
		BrickLayout.brick_address(grid_profile, address),
		_hash("body-definition"),
		"1.0.0",
		2026073101,
		revision,
		samples
	)


func _source(epoch: int, revision: int, seed: String) -> Dictionary:
	return SourceRevision.create(
		"MATTER",
		"body/asteroid-rl1",
		epoch,
		revision,
		_hash(seed),
		_hash("dependencies-%s" % seed)
	)


func _task(
	address: Dictionary,
	epoch: int,
	revision: int,
	reason: String,
	bounds: Array,
	enqueue_revision: int
) -> Dictionary:
	var id_hash: String = RepresentationUtils.payload_hash({
		"cell_id": address["cell_id"],
		"epoch": epoch,
		"revision": revision,
		"enqueue_revision": enqueue_revision,
	})
	return RebuildTask.create(
		"matter-summary-rebuild/%s" % id_hash,
		"body/asteroid-rl1",
		address,
		epoch,
		revision,
		reason,
		bounds,
		enqueue_revision
	)


func _hash(text: String) -> String:
	return text.sha256_text()


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result.get("error_code", "")])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("RL1 matter summary pyramid: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("RL1 matter summary pyramid: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
