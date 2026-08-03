extends SceneTree

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")
const MaterialCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Generator = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const GeneratorProfile = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const BrickSnapshot = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const Materializer = preload("res://scripts/simulation/matter/storage/matter_brick_materializer.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")
const SummaryBuilder = preload("res://scripts/simulation/representation/matter/matter_summary_builder.gd")
const Field = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_field.gd")
const MeshData = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_mesh_data.gd")
const FieldBuilder = preload("res://scripts/simulation/representation/matter/meshing/matter_multiresolution_field_builder.gd")
const Mesher = preload("res://scripts/simulation/representation/matter/meshing/matter_multiresolution_mesher.gd")
const ResourceFactory = preload("res://scripts/world/matter/representation/matter_representation_mesh_resource_factory.gd")

var failures: Array[String] = []
var assertions: int = 0
var material_catalog: Dictionary = {}
var generator_profile: Dictionary = {}
var feature_catalog: Dictionary = {}
var body: Dictionary = {}
var grid_profile: Dictionary = {}


func _init() -> void:
	_build_fixture()
	_test_real_surface_lod0_and_lod1()
	_finish()


func _build_fixture() -> void:
	material_catalog = MaterialCatalog.default_catalog()
	generator_profile = Generator.default_profile()
	feature_catalog = Generator.default_feature_catalog(generator_profile)
	body = Generator.default_body_definition(generator_profile, material_catalog, feature_catalog)
	grid_profile = GridProfile.create({
		"body_id": body.get("body_id", ""),
		"body_frame_id": body.get("body_frame_id", ""),
		"root_half_extent_m": GeneratorProfile.root_bounds_radius_m(generator_profile),
	})
	_assert(not material_catalog.is_empty(), "RL2 real material catalog is empty")
	_assert(not generator_profile.is_empty(), "RL2 real generator profile is empty")
	_assert(not feature_catalog.is_empty(), "RL2 real feature catalog is empty")
	_assert(not body.is_empty(), "RL2 real body definition is empty")
	_assert_ok(GridProfile.validate(grid_profile), "RL2 real grid profile rejected")


func _test_real_surface_lod0_and_lod1() -> void:
	var direction := Vector3(0.91, 0.31, -0.27).normalized()
	var surface_radius_m: float = Generator.surface_radius_validated(generator_profile, feature_catalog, direction)
	_assert(surface_radius_m > 0.0, "RL2 real surface radius is invalid")
	var max_level: int = int(grid_profile["max_level"])
	var fine_address: Dictionary = CellGrid.address_for_position(
		grid_profile, direction * surface_radius_m, max_level
	)
	var coarse_address: Dictionary = CellAddress.parent(fine_address)
	_assert_ok(CellGrid.validate_address(grid_profile, fine_address), "RL2 real fine address rejected")
	_assert_ok(CellGrid.validate_address(grid_profile, coarse_address), "RL2 real coarse address rejected")
	var fine_snapshots: Array = _materialize_descendants(fine_address, 17)
	var coarse_snapshots: Array = _materialize_descendants(coarse_address, 17)
	_assert(fine_snapshots.size() == 1, "RL2 real LOD0 snapshot count changed")
	_assert(coarse_snapshots.size() == 8, "RL2 real LOD1 snapshot count changed")
	for snapshot_value in coarse_snapshots:
		_assert_ok(BrickSnapshot.validate(snapshot_value), "RL2 real source snapshot rejected")
	var fine_summary: Dictionary = _summary_for(fine_address, fine_snapshots, 6, 17)
	var coarse_summary: Dictionary = _summary_for(coarse_address, coarse_snapshots, 6, 17)
	_assert_ok(SummaryNode.validate(fine_summary), "RL2 real LOD0 summary rejected")
	_assert_ok(SummaryNode.validate(coarse_summary), "RL2 real LOD1 summary rejected")
	var fine_field: Dictionary = FieldBuilder.build(fine_summary, fine_snapshots, grid_profile)
	var coarse_field: Dictionary = FieldBuilder.build(coarse_summary, coarse_snapshots, grid_profile)
	_assert_ok(Field.validate(fine_field, grid_profile), "RL2 real LOD0 field rejected")
	_assert_ok(Field.validate(coarse_field, grid_profile), "RL2 real LOD1 field rejected")
	_assert(float(coarse_field["sample_spacing_m"]) == float(fine_field["sample_spacing_m"]) * 2.0, "RL2 real LOD1 spacing changed")
	var fine_mesh: Dictionary = Mesher.build(fine_field, grid_profile)
	var coarse_mesh: Dictionary = Mesher.build(coarse_field, grid_profile)
	_assert_ok(MeshData.validate(fine_mesh), "RL2 real LOD0 mesh rejected")
	_assert_ok(MeshData.validate(coarse_mesh), "RL2 real LOD1 mesh rejected")
	_assert(String(fine_mesh["status"]) == MeshData.STATUS_READY, "RL2 real LOD0 surface mesh is empty")
	_assert(String(coarse_mesh["status"]) == MeshData.STATUS_READY, "RL2 real LOD1 surface mesh is empty")
	_assert(int(fine_mesh["triangle_count"]) > 0, "RL2 real LOD0 mesh has no triangles")
	_assert(int(coarse_mesh["triangle_count"]) > 0, "RL2 real LOD1 mesh has no triangles")
	_assert(float(coarse_mesh["geometric_error_m"]) == float(fine_mesh["geometric_error_m"]) * 2.0, "RL2 real LOD1 error changed")
	_assert(String(fine_mesh["source_snapshot_set_hash"]) != String(coarse_mesh["source_snapshot_set_hash"]), "RL2 real LOD source sets collapsed")
	var shuffled: Array = coarse_snapshots.duplicate()
	shuffled.reverse()
	var replay_field: Dictionary = FieldBuilder.build(coarse_summary, shuffled, grid_profile)
	var replay_mesh: Dictionary = Mesher.build(replay_field, grid_profile)
	_assert_ok(MeshData.validate(replay_mesh), "RL2 real reordered replay rejected")
	_assert(String(replay_mesh["content_hash"]) == String(coarse_mesh["content_hash"]), "RL2 real mesh depends on source arrival order")
	_assert(replay_mesh["vertices"] == coarse_mesh["vertices"], "RL2 real replay vertices changed")
	_assert(replay_mesh["indices"] == coarse_mesh["indices"], "RL2 real replay indices changed")
	var detail_manifest: Dictionary = MeshData.to_artifact_manifest(fine_mesh, true, true, 3)
	var coarse_manifest: Dictionary = MeshData.to_artifact_manifest(coarse_mesh, false, true, 3)
	_assert_ok(ArtifactManifest.validate(detail_manifest), "RL2 real detail manifest rejected")
	_assert_ok(ArtifactManifest.validate(coarse_manifest), "RL2 real simplified manifest rejected")
	_assert(bool(detail_manifest["collision_capable"]), "RL2 real detail collision capability changed")
	_assert(not bool(coarse_manifest["collision_capable"]), "RL2 real simplified mesh became collision-capable")
	_assert(String(detail_manifest["artifact_hash"]) == String(fine_mesh["content_hash"]), "RL2 real detail artifact is not content-addressed")
	var presenter: Node3D = ResourceFactory.create_presenter(fine_mesh, [], null, null, true)
	_assert(presenter != null, "RL2 real presenter was not created")
	if presenter != null:
		_assert(presenter.get_node_or_null("Surface") is MeshInstance3D, "RL2 real presenter surface is missing")
		_assert(presenter.get_node_or_null("Collision/Shape") is CollisionShape3D, "RL2 real presenter collision is missing")
		presenter.free()
	_assert(RepresentationUtils.is_lower_hex_64(String(coarse_mesh["content_hash"])), "RL2 real content hash is invalid")


func _materialize_descendants(target_address: Dictionary, state_revision: int) -> Array:
	var addresses: Array = _descendants_at_level(target_address, int(grid_profile["max_level"]))
	var snapshots: Array = []
	for address_value in addresses:
		var snapshot: Dictionary = Materializer.materialize(
			body,
			material_catalog,
			generator_profile,
			feature_catalog,
			grid_profile,
			address_value,
			state_revision
		)
		if snapshot.is_empty():
			return []
		snapshots.append(snapshot)
	return snapshots


func _summary_for(
	target_address: Dictionary,
	snapshots: Array,
	authority_epoch: int,
	summary_revision: int
) -> Dictionary:
	var summaries: Dictionary = {}
	var current_level: int = int(grid_profile["max_level"])
	for snapshot_value in snapshots:
		var summary: Dictionary = SummaryBuilder.from_brick_snapshot(
			snapshot_value, grid_profile, authority_epoch, summary_revision, 1
		)
		if summary.is_empty():
			return {}
		summaries[String(summary["cell_address"]["cell_id"])] = summary
	while current_level > int(target_address["level"]):
		var grouped: Dictionary = {}
		for summary_value in summaries.values():
			var child_summary: Dictionary = summary_value
			var parent_address: Dictionary = CellAddress.parent(child_summary["cell_address"])
			var parent_id: String = String(parent_address["cell_id"])
			if not grouped.has(parent_id):
				grouped[parent_id] = {"address": parent_address, "children": []}
			grouped[parent_id]["children"].append(child_summary)
		var next: Dictionary = {}
		var parent_ids: Array = grouped.keys()
		parent_ids.sort()
		for parent_id in parent_ids:
			var group: Dictionary = grouped[parent_id]
			var parent_summary: Dictionary = SummaryBuilder.from_children(
				String(body["body_id"]),
				group["address"],
				grid_profile,
				group["children"],
				authority_epoch,
				summary_revision,
				1
			)
			if parent_summary.is_empty():
				return {}
			next[parent_id] = parent_summary
		summaries = next
		current_level -= 1
	return summaries.get(String(target_address["cell_id"]), {})


func _descendants_at_level(address: Dictionary, target_level: int) -> Array:
	if int(address.get("level", -1)) > target_level:
		return []
	var frontier: Array = [address]
	while not frontier.is_empty() and int(frontier[0]["level"]) < target_level:
		var next: Array = []
		for current_value in frontier:
			for child_index in range(8):
				next.append(CellAddress.child(current_value, child_index))
		frontier = next
	frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_id"]) < String(b["cell_id"])
	)
	return frontier


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("RL2 real asteroid multiresolution: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("RL2 real asteroid multiresolution: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
