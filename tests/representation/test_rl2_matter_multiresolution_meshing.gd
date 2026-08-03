extends SceneTree

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const BrickLayout = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const BrickSnapshot = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterSample = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")
const SummaryBuilder = preload("res://scripts/simulation/representation/matter/matter_summary_builder.gd")
const SourceSet = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_meshing_source_set.gd")
const Field = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_field.gd")
const MeshData = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_mesh_data.gd")
const Transition = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_cross_level_transition.gd")
const FieldBuilder = preload("res://scripts/simulation/representation/matter/meshing/matter_multiresolution_field_builder.gd")
const Mesher = preload("res://scripts/simulation/representation/matter/meshing/matter_multiresolution_mesher.gd")
const Boundary = preload("res://scripts/simulation/representation/matter/meshing/matter_mesh_boundary.gd")
const TransitionBuilder = preload("res://scripts/simulation/representation/matter/meshing/matter_cross_level_transition_builder.gd")
const TransitionValidator = preload("res://scripts/simulation/representation/matter/meshing/matter_cross_level_transition_validator.gd")
const LodBalancer = preload("res://scripts/simulation/representation/matter/meshing/matter_lod_neighborhood_balancer.gd")
const InvalidationResolver = preload("res://scripts/simulation/representation/matter/meshing/matter_meshing_invalidation_resolver.gd")
const ResourceFactory = preload("res://scripts/world/matter/representation/matter_representation_mesh_resource_factory.gd")

var failures: Array[String] = []
var assertions: int = 0
var grid_profile: Dictionary = {}
var basalt: Dictionary = {}
var vacuum_composition: Dictionary = {}
var fine_address: Dictionary = {}
var coarse_address: Dictionary = {}
var macro_address: Dictionary = {}
var fine_snapshots: Array = []
var coarse_snapshots: Array = []
var macro_snapshots: Array = []
var fine_summary: Dictionary = {}
var coarse_summary: Dictionary = {}
var macro_summary: Dictionary = {}
var fine_field: Dictionary = {}
var coarse_field: Dictionary = {}
var macro_field: Dictionary = {}
var fine_mesh: Dictionary = {}
var coarse_mesh: Dictionary = {}
var macro_mesh: Dictionary = {}


func _init() -> void:
	_build_fixture()
	_test_config()
	_test_source_sets()
	_test_fields()
	_test_meshes()
	_test_same_level_seam()
	_test_cross_level_transition()
	_test_resource_factory()
	_test_lod_balancing()
	_test_invalidation_projection()
	_test_contract_fences()
	_finish()


func _build_fixture() -> void:
	grid_profile = GridProfile.create({
		"universe_id": "planet-simulator",
		"instance_id": "rl2-tests",
		"space_id": "asteroid-rl2",
		"grid_id": "matter-grid-rl2",
		"grid_revision": 1,
		"root_id": "asteroid-rl2-root",
		"body_id": "body/asteroid-rl2",
		"body_frame_id": "frame/asteroid-rl2",
		"root_center_m": [0.0, 0.0, 0.0],
		"root_half_extent_m": 64.0,
		"max_level": 3,
		"brick_interior_resolution": 4,
		"ghost_border_samples": 1,
	})
	_assert_ok(GridProfile.validate(grid_profile), "RL2 grid profile rejected")
	basalt = Composition.create([{"material_id": "material/basalt", "mass_fraction": 1.0}])
	vacuum_composition = Composition.empty()
	_assert_ok(Composition.validate(basalt), "RL2 basalt composition rejected")
	fine_address = CellGrid.address_for_position(grid_profile, Vector3(-1.0, -1.0, -1.0), 3)
	coarse_address = CellGrid.address_for_position(grid_profile, Vector3(1.0, -1.0, -1.0), 2)
	macro_address = CellGrid.address_for_position(grid_profile, Vector3(-1.0, 1.0, 1.0), 1)
	_assert_ok(CellGrid.validate_address(grid_profile, fine_address), "Fine address rejected")
	_assert_ok(CellGrid.validate_address(grid_profile, coarse_address), "Coarse address rejected")
	_assert_ok(CellGrid.validate_address(grid_profile, macro_address), "Macro address rejected")
	fine_snapshots = _snapshots_for(fine_address, 7)
	coarse_snapshots = _snapshots_for(coarse_address, 7)
	macro_snapshots = _snapshots_for(macro_address, 7)
	_assert(fine_snapshots.size() == 1, "LOD0 snapshot count changed")
	_assert(coarse_snapshots.size() == 8, "LOD1 snapshot count changed")
	_assert(macro_snapshots.size() == 64, "LOD2 snapshot count changed")
	fine_summary = _summary_for(fine_address, fine_snapshots, 4, 7)
	coarse_summary = _summary_for(coarse_address, coarse_snapshots, 4, 7)
	macro_summary = _summary_for(macro_address, macro_snapshots, 4, 7)
	_assert_ok(SummaryNode.validate(fine_summary), "Fine summary rejected")
	_assert_ok(SummaryNode.validate(coarse_summary), "Coarse summary rejected")
	_assert_ok(SummaryNode.validate(macro_summary), "Macro summary rejected")
	fine_field = FieldBuilder.build(fine_summary, fine_snapshots, grid_profile)
	coarse_field = FieldBuilder.build(coarse_summary, coarse_snapshots, grid_profile)
	macro_field = FieldBuilder.build(macro_summary, macro_snapshots, grid_profile)
	fine_mesh = Mesher.build(fine_field, grid_profile)
	coarse_mesh = Mesher.build(coarse_field, grid_profile)
	macro_mesh = Mesher.build(macro_field, grid_profile)


func _test_config() -> void:
	var path := "res://config/representation/matter-multiresolution-meshing.v1.json"
	_assert(FileAccess.file_exists(path), "RL2 config is missing")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_assert(typeof(parsed) == TYPE_DICTIONARY, "RL2 config is invalid JSON")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var config: Dictionary = parsed
	_assert(String(config.get("checkpoint", "")) == "v17.13.0-simulation-rl2-matter-multiresolution-meshing", "RL2 checkpoint changed")
	_assert(String(config.get("build_id", "")) == "rl2-matter-multiresolution-meshing-transitions", "RL2 build id changed")
	_assert(int(config.get("maximum_lod_level", -1)) == 2, "RL2 maximum LOD changed")
	_assert(String(config.get("transition_strategy", "")) == "FINE_BOUNDARY_SKIRT_V1", "RL2 transition strategy changed")
	_assert(int(config.get("maximum_neighbor_lod_delta", 0)) == 1, "RL2 neighbor delta changed")
	_assert(not bool(config.get("canonical_matter_changed", true)), "RL2 changes canonical Matter")
	_assert(not bool(config.get("network_streaming_added", true)), "RL2 unexpectedly adds network streaming")
	_assert(not bool(config.get("background_scheduler_added", true)), "RL2 unexpectedly adds scheduler")


func _test_source_sets() -> void:
	var fine_set: Dictionary = SourceSet.create(fine_summary, fine_snapshots, grid_profile)
	var coarse_set: Dictionary = SourceSet.create(coarse_summary, coarse_snapshots, grid_profile)
	var macro_set: Dictionary = SourceSet.create(macro_summary, macro_snapshots, grid_profile)
	_assert_ok(SourceSet.validate(fine_set, grid_profile), "LOD0 source set rejected")
	_assert_ok(SourceSet.validate(coarse_set, grid_profile), "LOD1 source set rejected")
	_assert_ok(SourceSet.validate(macro_set, grid_profile), "LOD2 source set rejected")
	_assert(int(fine_set["lod_level"]) == 0 and int(fine_set["expected_snapshot_count"]) == 1, "LOD0 source topology changed")
	_assert(int(coarse_set["lod_level"]) == 1 and int(coarse_set["expected_snapshot_count"]) == 8, "LOD1 source topology changed")
	_assert(int(macro_set["lod_level"]) == 2 and int(macro_set["expected_snapshot_count"]) == 64, "LOD2 source topology changed")
	_assert(String(fine_set["source_summary_checksum"]) == String(fine_summary["checksum"]), "LOD0 summary binding changed")
	_assert(String(coarse_set["source_summary_checksum"]) == String(coarse_summary["checksum"]), "LOD1 summary binding changed")
	_assert(String(macro_set["source_summary_checksum"]) == String(macro_summary["checksum"]), "LOD2 summary binding changed")
	var shuffled: Array = coarse_snapshots.duplicate()
	shuffled.reverse()
	var shuffled_set: Dictionary = SourceSet.create(coarse_summary, shuffled, grid_profile)
	_assert_ok(SourceSet.validate(shuffled_set, grid_profile), "Shuffled LOD1 source set rejected")
	_assert(String(shuffled_set["snapshot_set_hash"]) == String(coarse_set["snapshot_set_hash"]), "Source set depends on arrival order")
	_assert(shuffled_set["snapshots"] == coarse_set["snapshots"], "Source descriptors are not canonical")
	var incomplete: Array = coarse_snapshots.slice(0, 7)
	_assert(SourceSet.create(coarse_summary, incomplete, grid_profile).is_empty(), "Incomplete source coverage accepted")
	var duplicate: Array = coarse_snapshots.duplicate()
	duplicate[7] = duplicate[0]
	_assert(SourceSet.create(coarse_summary, duplicate, grid_profile).is_empty(), "Duplicate source cell accepted")
	var tampered: Dictionary = coarse_set.duplicate(true)
	tampered["snapshot_set_hash"] = _hash("wrong-set")
	tampered["checksum"] = RepresentationUtils.compute_checksum(tampered)
	_assert_fail(SourceSet.validate(tampered, grid_profile), "Tampered source set hash accepted")


func _test_fields() -> void:
	_assert_ok(Field.validate(fine_field, grid_profile), "LOD0 field rejected")
	_assert_ok(Field.validate(coarse_field, grid_profile), "LOD1 field rejected")
	_assert_ok(Field.validate(macro_field, grid_profile), "LOD2 field rejected")
	_assert(int(fine_field["lod_level"]) == 0, "Fine field LOD changed")
	_assert(int(coarse_field["lod_level"]) == 1, "Coarse field LOD changed")
	_assert(int(macro_field["lod_level"]) == 2, "Macro field LOD changed")
	_assert(float(coarse_field["sample_spacing_m"]) == float(fine_field["sample_spacing_m"]) * 2.0, "LOD1 spacing is not doubled")
	_assert(float(macro_field["sample_spacing_m"]) == float(fine_field["sample_spacing_m"]) * 4.0, "LOD2 spacing is not quadrupled")
	_assert(String(fine_field["representation_key"]["artifact_kind"]) == "DETAIL", "LOD0 artifact kind changed")
	_assert(String(coarse_field["representation_key"]["artifact_kind"]) == "SIMPLIFIED_MESH", "LOD1 artifact kind changed")
	_assert(String(macro_field["representation_key"]["artifact_kind"]) == "MACRO_PROXY", "LOD2 artifact kind changed")
	_assert(int(fine_field["signed_distance_m"].size()) == 125, "Field lattice size changed")
	_assert(float(fine_field["minimum_signed_distance_m"]) < 0.0, "Fine field lost matter")
	_assert(float(fine_field["maximum_signed_distance_m"]) > 0.0, "Fine field lost vacuum")
	var shuffled: Array = coarse_snapshots.duplicate()
	shuffled.shuffle()
	var replay: Dictionary = FieldBuilder.build(coarse_summary, shuffled, grid_profile)
	_assert_ok(Field.validate(replay, grid_profile), "Shuffled field replay rejected")
	_assert(String(replay["field_hash"]) == String(coarse_field["field_hash"]), "Field hash depends on input order")
	_assert(replay["signed_distance_m"] == coarse_field["signed_distance_m"], "Field samples depend on input order")
	var unknown_composition: Dictionary = Composition.create([{
		"material_id": "material/rl2-unknown-mineral",
		"mass_fraction": 1.0,
	}])
	var unknown_snapshot: Dictionary = _snapshot(fine_address, 7, 0.0, unknown_composition)
	var unknown_summary: Dictionary = _summary_for(fine_address, [unknown_snapshot], 4, 7)
	var unknown_field_a: Dictionary = FieldBuilder.build(unknown_summary, [unknown_snapshot], grid_profile)
	var unknown_field_b: Dictionary = FieldBuilder.build(unknown_summary, [unknown_snapshot], grid_profile)
	_assert_ok(Field.validate(unknown_field_a, grid_profile), "Unknown-material field rejected")
	_assert(unknown_field_a["colors_rgba"] == unknown_field_b["colors_rgba"], "Unknown-material color is non-deterministic")
	var unknown_colors: Array = unknown_field_a["colors_rgba"]
	var colors_normalized: bool = true
	for color_value in unknown_colors:
		var color: Array = color_value
		if color.size() != 4 or float(color[0]) < 0.0 or float(color[0]) > 1.0 \
			or float(color[1]) < 0.0 or float(color[1]) > 1.0 \
			or float(color[2]) < 0.0 or float(color[2]) > 1.0 \
			or float(color[3]) < 0.0 or float(color[3]) > 1.0:
			colors_normalized = false
			break
	_assert(colors_normalized, "Unknown-material color left normalized range")
	_assert(unknown_colors != fine_field["colors_rgba"], "Unknown material reused basalt presentation color")
	var inconsistent: Array = coarse_snapshots.duplicate(true)
	inconsistent[0] = _snapshot(inconsistent[0]["address"]["cell_address"], 7, 0.25)
	var inconsistent_summary: Dictionary = _summary_for(coarse_address, inconsistent, 4, 7)
	_assert_ok(SummaryNode.validate(inconsistent_summary), "Inconsistent fixture summary rejected")
	_assert(FieldBuilder.build(inconsistent_summary, inconsistent, grid_profile).is_empty(), "Inconsistent shared SDF sample accepted")
	var tampered: Dictionary = fine_field.duplicate(true)
	tampered["signed_distance_m"][0] = float(tampered["signed_distance_m"][0]) + 1.0
	tampered["checksum"] = RepresentationUtils.compute_checksum(tampered)
	_assert_fail(Field.validate(tampered, grid_profile), "Field payload changed without field hash")
	_assert(not RepresentationUtils.canonical_json(fine_field).is_empty(), "Field is not JSON-safe")
	var runtime_node := Node3D.new()
	_assert(RepresentationUtils.canonical_json({"field": fine_field, "runtime": runtime_node}).is_empty(), "Runtime Node3D entered field contract")
	runtime_node.free()


func _test_meshes() -> void:
	_assert_ok(MeshData.validate(fine_mesh), "LOD0 mesh rejected")
	_assert_ok(MeshData.validate(coarse_mesh), "LOD1 mesh rejected")
	_assert_ok(MeshData.validate(macro_mesh), "LOD2 mesh rejected")
	_assert(String(fine_mesh["status"]) == MeshData.STATUS_READY, "LOD0 mesh is empty")
	_assert(String(coarse_mesh["status"]) == MeshData.STATUS_READY, "LOD1 mesh is empty")
	_assert(String(macro_mesh["status"]) == MeshData.STATUS_READY, "LOD2 mesh is empty")
	_assert(int(fine_mesh["triangle_count"]) > 0, "LOD0 mesh has no triangles")
	_assert(int(coarse_mesh["triangle_count"]) > 0, "LOD1 mesh has no triangles")
	_assert(int(macro_mesh["triangle_count"]) > 0, "LOD2 mesh has no triangles")
	_assert(float(coarse_mesh["geometric_error_m"]) == float(fine_mesh["geometric_error_m"]) * 2.0, "LOD1 error is not doubled")
	_assert(float(macro_mesh["geometric_error_m"]) == float(fine_mesh["geometric_error_m"]) * 4.0, "LOD2 error is not quadrupled")
	var fine_replay: Dictionary = Mesher.build(fine_field, grid_profile)
	_assert_ok(MeshData.validate(fine_replay), "LOD0 replay rejected")
	_assert(String(fine_replay["content_hash"]) == String(fine_mesh["content_hash"]), "LOD0 mesh is non-deterministic")
	_assert(fine_replay["vertices"] == fine_mesh["vertices"], "LOD0 vertices are non-deterministic")
	_assert(fine_replay["indices"] == fine_mesh["indices"], "LOD0 indices are non-deterministic")
	var detail_manifest: Dictionary = MeshData.to_artifact_manifest(fine_mesh, true, true, 1)
	var simplified_manifest: Dictionary = MeshData.to_artifact_manifest(coarse_mesh, false, true, 1)
	var macro_manifest: Dictionary = MeshData.to_artifact_manifest(macro_mesh, false, false, 1)
	_assert_ok(ArtifactManifest.validate(detail_manifest), "Detail artifact manifest rejected")
	_assert_ok(ArtifactManifest.validate(simplified_manifest), "Simplified artifact manifest rejected")
	_assert_ok(ArtifactManifest.validate(macro_manifest), "Macro artifact manifest rejected")
	_assert(bool(detail_manifest["collision_capable"]), "Detail collision capability changed")
	_assert(not bool(simplified_manifest["collision_capable"]), "Simplified mesh unexpectedly collision-capable")
	_assert(not bool(macro_manifest["interior_capable"]), "Macro proxy unexpectedly claims interiors")
	_assert(MeshData.to_artifact_manifest(coarse_mesh, true, true, 1).is_empty(), "LOD1 artifact accepted collision capability")
	_assert(MeshData.to_artifact_manifest(macro_mesh, false, true, 1).is_empty(), "Macro artifact accepted interior capability")
	_assert(MeshData.to_artifact_manifest(macro_mesh, true, false, 1).is_empty(), "Macro artifact accepted collision capability")
	_assert(String(detail_manifest["artifact_hash"]) == String(fine_mesh["content_hash"]), "Artifact hash is not content-addressed")
	var tampered: Dictionary = fine_mesh.duplicate(true)
	tampered["vertices"][0] += Vector3(0.1, 0.0, 0.0)
	_assert_fail(MeshData.validate(tampered), "Tampered mesh content accepted")
	var empty_address: Dictionary = CellGrid.address_for_position(grid_profile, Vector3(-48.0, -48.0, 48.0), 3)
	var empty_snapshot: Dictionary = _vacuum_snapshot(empty_address, 7)
	var empty_summary: Dictionary = _summary_for(empty_address, [empty_snapshot], 4, 7)
	var empty_field: Dictionary = FieldBuilder.build(empty_summary, [empty_snapshot], grid_profile)
	var empty_mesh: Dictionary = Mesher.build(empty_field, grid_profile)
	_assert_ok(MeshData.validate(empty_mesh), "Empty mesh rejected")
	_assert(String(empty_mesh["status"]) == MeshData.STATUS_EMPTY, "Vacuum field generated geometry")
	_assert(int(empty_mesh["triangle_count"]) == 0, "Vacuum triangle count changed")


func _test_same_level_seam() -> void:
	var left_address: Dictionary = CellGrid.address_for_position(grid_profile, Vector3(-17.0, -1.0, -1.0), 3)
	var right_address: Dictionary = CellGrid.address_for_position(grid_profile, Vector3(-15.0, -1.0, -1.0), 3)
	var left_snapshot: Dictionary = _snapshot(left_address, 7, 0.0)
	var right_snapshot: Dictionary = _snapshot(right_address, 7, 0.0)
	var left_summary: Dictionary = _summary_for(left_address, [left_snapshot], 4, 7)
	var right_summary: Dictionary = _summary_for(right_address, [right_snapshot], 4, 7)
	var left_mesh: Dictionary = Mesher.build(FieldBuilder.build(left_summary, [left_snapshot], grid_profile), grid_profile)
	var right_mesh: Dictionary = Mesher.build(FieldBuilder.build(right_summary, [right_snapshot], grid_profile), grid_profile)
	_assert_ok(MeshData.validate(left_mesh), "Same-level left mesh rejected")
	_assert_ok(MeshData.validate(right_mesh), "Same-level right mesh rejected")
	var face: Dictionary = Boundary.shared_face(left_mesh, right_mesh)
	_assert(not face.is_empty(), "Same-level shared face not found")
	if face.is_empty():
		return
	var left_segments: Array = Boundary.segments(left_mesh, int(face["axis"]), float(face["plane_coordinate_m"]))
	var right_segments: Array = Boundary.segments(right_mesh, int(face["axis"]), float(face["plane_coordinate_m"]))
	_assert(left_segments.size() > 0, "Same-level seam has no segments")
	_assert(left_segments.size() == right_segments.size(), "Same-level seam segment count differs")
	_assert(Boundary.segment_hash(left_segments) == Boundary.segment_hash(right_segments), "Same-level seam hash differs")


func _test_cross_level_transition() -> void:
	var transition: Dictionary = TransitionBuilder.build(fine_mesh, coarse_mesh)
	_assert_ok(Transition.validate(transition), "Cross-level transition rejected")
	_assert(String(transition["status"]) == Transition.STATUS_READY, "Cross-level transition is empty")
	_assert(int(transition["boundary_segment_count"]) > 0, "Transition has no boundary segments")
	_assert(int(transition["triangle_count"]) == int(transition["boundary_segment_count"]) * 4, "Transition triangle topology changed")
	_assert(float(transition["skirt_depth_m"]) >= float(coarse_mesh["geometric_error_m"]), "Transition depth is below coarse error")
	_assert_ok(TransitionValidator.validate_coverage(fine_mesh, coarse_mesh, transition), "Transition does not cover fine boundary")
	var replay: Dictionary = TransitionBuilder.build(fine_mesh, coarse_mesh)
	_assert_ok(Transition.validate(replay), "Transition replay rejected")
	_assert(String(replay["content_hash"]) == String(transition["content_hash"]), "Transition is non-deterministic")
	_assert(replay["vertices"] == transition["vertices"], "Transition vertices are non-deterministic")
	var manifest: Dictionary = Transition.to_artifact_manifest(transition, 1)
	_assert_ok(ArtifactManifest.validate(manifest), "Transition artifact manifest rejected")
	_assert(String(manifest["media_type"]) == Transition.MEDIA_TYPE, "Transition media type changed")
	_assert(not bool(manifest["collision_capable"]), "Transition unexpectedly collision-capable")
	_assert(not bool(manifest["interior_capable"]), "Transition unexpectedly interior-capable")
	var shallow: Dictionary = transition.duplicate(true)
	shallow["skirt_depth_m"] = float(shallow["geometric_error_m"]) * 0.5
	_assert_fail(Transition.validate(shallow), "Transition below geometric error accepted")
	var excessive: Dictionary = TransitionBuilder.build(fine_mesh, coarse_mesh)
	excessive["skirt_depth_m"] = float(excessive["skirt_depth_m"]) * 2.0
	excessive["content_hash"] = _hash("excessive-depth")
	_assert_fail(TransitionValidator.validate_coverage(fine_mesh, coarse_mesh, excessive), "Non-canonical transition depth accepted")
	var shifted: Dictionary = TransitionBuilder.build(fine_mesh, coarse_mesh)
	shifted["vertices"][0] += Vector3(0.0, 0.25, 0.0)
	shifted["content_hash"] = _hash("shifted-transition")
	_assert_fail(TransitionValidator.validate_coverage(fine_mesh, coarse_mesh, shifted), "Altered transition geometry accepted")
	_assert(TransitionBuilder.build(fine_mesh, macro_mesh).is_empty(), "LOD0-to-LOD2 transition accepted without balancing")
	var non_adjacent_field: Dictionary = FieldBuilder.build(macro_summary, macro_snapshots, grid_profile)
	var non_adjacent_mesh: Dictionary = Mesher.build(non_adjacent_field, grid_profile)
	_assert(TransitionBuilder.build(fine_mesh, non_adjacent_mesh).is_empty(), "Non-adjacent transition accepted")


func _test_resource_factory() -> void:
	var transition: Dictionary = TransitionBuilder.build(fine_mesh, coarse_mesh)
	var array_mesh: ArrayMesh = ResourceFactory.create_array_mesh(fine_mesh)
	_assert(array_mesh != null, "RL2 ArrayMesh was not created")
	if array_mesh != null:
		_assert(array_mesh.get_surface_count() == 1, "RL2 ArrayMesh surface count changed")
		_assert(array_mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, "RL2 ArrayMesh primitive changed")
		var arrays: Array = array_mesh.surface_get_arrays(0)
		_assert(PackedVector3Array(arrays[Mesh.ARRAY_VERTEX]).size() == fine_mesh["vertices"].size(), "RL2 ArrayMesh lost vertices")
		_assert(PackedInt32Array(arrays[Mesh.ARRAY_INDEX]).size() == fine_mesh["indices"].size(), "RL2 ArrayMesh lost indices")
	var transition_mesh: ArrayMesh = ResourceFactory.create_array_mesh(transition)
	_assert(transition_mesh != null, "RL2 transition ArrayMesh was not created")
	var shape: ConcavePolygonShape3D = ResourceFactory.create_concave_shape(fine_mesh)
	_assert(shape != null, "RL2 collision shape was not created")
	if shape != null:
		_assert(shape.get_faces().size() == fine_mesh["indices"].size(), "RL2 collision faces changed")
	var presenter: Node3D = ResourceFactory.create_presenter(fine_mesh, [transition], null, null, true)
	_assert(presenter != null, "RL2 presenter was not created")
	if presenter != null:
		_assert(presenter.get_node_or_null("Surface") is MeshInstance3D, "RL2 presenter surface is missing")
		_assert(presenter.get_node_or_null("Collision/Shape") is CollisionShape3D, "RL2 presenter collision is missing")
		_assert(presenter.get_node_or_null("Transition_00") is MeshInstance3D, "RL2 presenter transition is missing")
		var transition_node: MeshInstance3D = presenter.get_node("Transition_00")
		_assert(transition_node.position.is_equal_approx(transition["origin_body_local_m"] - fine_mesh["origin_body_local_m"]), "RL2 transition origin projection changed")
		presenter.free()
	_assert(ResourceFactory.create_array_mesh({}) == null, "Invalid RL2 artifact created an ArrayMesh")
	_assert(ResourceFactory.create_concave_shape(coarse_mesh) == null, "Coarse representation created close collision")
	_assert(ResourceFactory.create_presenter(coarse_mesh, [transition], null, null, false) == null, "Foreign fine transition attached to coarse presenter")


func _test_lod_balancing() -> void:
	var neighbor: Dictionary = CellGrid.address_for_position(grid_profile, Vector3(1.0, -1.0, -1.0), 3)
	var far_neighbor: Dictionary = CellGrid.address_for_position(grid_profile, Vector3(17.0, -1.0, -1.0), 3)
	var entries: Array = [
		{"cell_address": far_neighbor, "lod_level": 2},
		{"cell_address": fine_address, "lod_level": 0},
		{"cell_address": neighbor, "lod_level": 2},
	]
	var plan: Dictionary = LodBalancer.balance(entries, grid_profile)
	_assert_ok(LodBalancer.validate(plan, grid_profile), "Balanced LOD plan rejected")
	_assert(int(plan["adjustment_count"]) >= 1, "LOD balancer made no adjustment")
	var by_id: Dictionary = {}
	for entry in plan["entries"]:
		by_id[String(entry["cell_address"]["cell_id"])] = int(entry["lod_level"])
	_assert(int(by_id[String(fine_address["cell_id"])]) == 0, "Balancer coarsened fine request")
	_assert(int(by_id[String(neighbor["cell_id"])]) == 1, "Balancer did not refine adjacent LOD2")
	var reversed: Array = entries.duplicate(true)
	reversed.reverse()
	var replay: Dictionary = LodBalancer.balance(reversed, grid_profile)
	_assert_ok(LodBalancer.validate(replay, grid_profile), "Reordered LOD plan rejected")
	_assert(String(replay["checksum"]) == String(plan["checksum"]), "LOD balancing depends on arrival order")
	var invalid_plan: Dictionary = plan.duplicate(true)
	for entry in invalid_plan["entries"]:
		if String(entry["cell_address"]["cell_id"]) == String(neighbor["cell_id"]):
			entry["lod_level"] = 2
	invalid_plan["checksum"] = RepresentationUtils.compute_checksum(invalid_plan)
	_assert_fail(LodBalancer.validate(invalid_plan, grid_profile), "Unbalanced neighbor delta accepted")


func _test_invalidation_projection() -> void:
	var previous: Dictionary = SourceRevision.create("MATTER", "body/asteroid-rl2", 4, 7, _hash("source-7"), _hash("deps-7"))
	var current: Dictionary = SourceRevision.create("MATTER", "body/asteroid-rl2", 4, 8, _hash("source-8"), _hash("deps-8"))
	var scopes: Array = [String(coarse_summary["scope_id"]), String(fine_summary["scope_id"])]
	scopes.sort()
	var invalidation: Dictionary = Invalidation.create(
		"representation-invalidation/rl2/mutation-8",
		previous,
		current,
		[-16.0, -16.0, -16.0, 32.0, 0.0, 0.0],
		"MUTATION",
		scopes,
		1200
	)
	_assert_ok(Invalidation.validate(invalidation), "RL2 invalidation fixture rejected")
	var result: Dictionary = InvalidationResolver.stale_keys(invalidation, [macro_mesh["representation_key"], coarse_mesh["representation_key"], fine_mesh["representation_key"], fine_mesh["representation_key"]])
	_assert_ok(result, "Meshing invalidation projection failed")
	var stale: Array = result.get("details", {}).get("stale_keys", [])
	_assert(stale.size() == 2, "Meshing invalidation did not select exact affected keys")
	_assert(String(stale[0]["scope_id"]) < String(stale[1]["scope_id"]), "Stale keys are not canonical")
	_assert(RepresentationUtils.is_lower_hex_64(result.get("details", {}).get("stale_key_hash")), "Stale key hash is invalid")
	var invalid_key: Dictionary = fine_mesh["representation_key"].duplicate(true)
	invalid_key["lod_level"] = 33
	_assert_fail(InvalidationResolver.stale_keys(invalidation, [invalid_key]), "Invalid representation key entered invalidation projection")


func _test_contract_fences() -> void:
	var bad_source: Dictionary = SourceSet.create(fine_summary, fine_snapshots, grid_profile)
	bad_source["source_revision"]["authority_epoch"] = 3
	bad_source["source_revision"]["checksum"] = RepresentationUtils.compute_checksum(bad_source["source_revision"])
	bad_source["checksum"] = RepresentationUtils.compute_checksum(bad_source)
	_assert_fail(SourceSet.validate(bad_source, grid_profile), "Source set accepted summary hash under altered epoch")
	var bad_kind_field: Dictionary = fine_field.duplicate(true)
	bad_kind_field["representation_key"]["artifact_kind"] = "SIMPLIFIED_MESH"
	bad_kind_field["representation_key"]["checksum"] = RepresentationUtils.compute_checksum(bad_kind_field["representation_key"])
	bad_kind_field["checksum"] = RepresentationUtils.compute_checksum(bad_kind_field)
	_assert_fail(Field.validate(bad_kind_field, grid_profile), "LOD0 field accepted simplified artifact kind")
	var bad_field: Dictionary = fine_field.duplicate(true)
	bad_field["representation_key"]["scope_id"] = String(coarse_summary["scope_id"])
	bad_field["representation_key"]["checksum"] = RepresentationUtils.compute_checksum(bad_field["representation_key"])
	bad_field["checksum"] = RepresentationUtils.compute_checksum(bad_field)
	_assert_fail(Field.validate(bad_field, grid_profile), "Field accepted foreign representation scope")
	var bad_mesh: Dictionary = fine_mesh.duplicate(true)
	bad_mesh["triangle_count"] = int(bad_mesh["triangle_count"]) + 1
	_assert_fail(MeshData.validate(bad_mesh), "Mesh accepted incorrect triangle count")
	var bad_kind_mesh: Dictionary = fine_mesh.duplicate(true)
	bad_kind_mesh["representation_key"]["artifact_kind"] = "MACRO_PROXY"
	bad_kind_mesh["representation_key"]["checksum"] = RepresentationUtils.compute_checksum(bad_kind_mesh["representation_key"])
	bad_kind_mesh["content_hash"] = _hash("bad-kind-mesh")
	_assert_fail(MeshData.validate(bad_kind_mesh), "LOD0 mesh accepted macro artifact kind")
	var transition: Dictionary = TransitionBuilder.build(fine_mesh, coarse_mesh)
	var bad_transition: Dictionary = transition.duplicate(true)
	bad_transition["coarse_representation_key"] = fine_mesh["representation_key"].duplicate(true)
	_assert_fail(Transition.validate(bad_transition), "Transition accepted equal LOD keys")
	var bad_projection: Dictionary = transition.duplicate(true)
	bad_projection["representation_key"] = coarse_mesh["representation_key"].duplicate(true)
	bad_projection["content_hash"] = _hash("bad-transition-projection")
	_assert_fail(Transition.validate(bad_projection), "Transition accepted representation key not bound to fine side")
	var bad_color: Dictionary = transition.duplicate(true)
	bad_color["colors"][0] = Color(2.0, 0.0, 0.0, 1.0)
	bad_color["content_hash"] = _hash("bad-transition-color")
	_assert_fail(Transition.validate(bad_color), "Transition accepted out-of-range vertex color")
	var bad_artifact_binding: Dictionary = transition.duplicate(true)
	bad_artifact_binding["fine_artifact_hash"] = _hash("foreign-fine-artifact")
	bad_artifact_binding["content_hash"] = _hash("bad-transition-artifact-binding")
	_assert_fail(Transition.validate(bad_artifact_binding), "Transition accepted foreign fine artifact hash")


func _snapshots_for(target_address: Dictionary, revision: int) -> Array:
	var addresses: Array = _descendants_at_level(target_address, int(grid_profile["max_level"]))
	var result: Array = []
	for address in addresses:
		result.append(_snapshot(address, revision, 0.0))
	return result


func _summary_for(
	target_address: Dictionary,
	snapshots: Array,
	authority_epoch: int,
	summary_revision: int
) -> Dictionary:
	var summaries: Dictionary = {}
	var current_level: int = int(grid_profile["max_level"])
	for snapshot_value in snapshots:
		var snapshot: Dictionary = snapshot_value
		var summary: Dictionary = SummaryBuilder.from_brick_snapshot(
			snapshot, grid_profile, authority_epoch, summary_revision, 1
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
				"body/asteroid-rl2",
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


func _snapshot(
	address: Dictionary,
	revision: int,
	distance_offset: float,
	material_composition: Dictionary = {}
) -> Dictionary:
	var samples: Array = []
	var selected_composition: Dictionary = basalt if material_composition.is_empty() else material_composition
	var axis_count: int = GridProfile.sample_axis_count(grid_profile)
	for z in range(axis_count):
		for y in range(axis_count):
			for x in range(axis_count):
				var position: Vector3 = BrickLayout.sample_position_m(grid_profile, address, x, y, z)
				var distance_m: float = _sdf(position) + distance_offset
				if distance_m <= 0.0:
					samples.append(MatterSample.create(distance_m, 1.0, 2800.0, selected_composition, 1.0, 210.0, 0.05, []))
				else:
					samples.append(MatterSample.vacuum(distance_m, 3.0))
	var id_hash: String = String(address["cell_id"]).sha256_text().substr(0, 20)
	return BrickSnapshot.create(
		"matter-brick-snapshot/rl2/%s/revision/%d" % [id_hash, revision],
		BrickLayout.brick_address(grid_profile, address),
		_hash("body-definition-rl2"),
		"1.0.0",
		2026073101,
		revision,
		samples
	)


func _vacuum_snapshot(address: Dictionary, revision: int) -> Dictionary:
	var samples: Array = []
	for _index in range(GridProfile.sample_count(grid_profile)):
		samples.append(MatterSample.vacuum(10.0, 3.0))
	var id_hash: String = String(address["cell_id"]).sha256_text().substr(0, 20)
	return BrickSnapshot.create(
		"matter-brick-snapshot/rl2-vacuum/%s/revision/%d" % [id_hash, revision],
		BrickLayout.brick_address(grid_profile, address),
		_hash("body-definition-rl2"),
		"1.0.0",
		2026073101,
		revision,
		samples
	)


func _sdf(position: Vector3) -> float:
	return position.y - 0.12 * position.z - 0.004 * position.z * position.z + 0.03 * position.x + 2.0


func _descendants_at_level(root: Dictionary, target_level: int) -> Array:
	var frontier: Array = [root.duplicate(true)]
	while int(frontier[0]["level"]) < target_level:
		var next: Array = []
		for address_value in frontier:
			for child_index in range(8):
				next.append(CellAddress.child(address_value, child_index))
		frontier = next
	frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_id"]) < String(b["cell_id"])
	)
	return frontier


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
		print("RL2 Matter multiresolution meshing: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("RL2 Matter multiresolution meshing: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
