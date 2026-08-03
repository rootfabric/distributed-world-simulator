extends SceneTree

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const ProfileScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const MaterializerScript = preload("res://scripts/simulation/matter/storage/matter_brick_materializer.gd")
const MeshDataScript = preload("res://scripts/world/matter/meshing/matter_brick_mesh_data.gd")
const MesherScript = preload("res://scripts/world/matter/meshing/matter_tetrahedral_mesher.gd")
const ResourceFactoryScript = preload("res://scripts/world/matter/meshing/matter_mesh_resource_factory.gd")
const SeamValidatorScript = preload("res://scripts/world/matter/meshing/matter_mesh_seam_validator.gd")
const StreamerScript = preload("res://scripts/world/matter/lab/matter_local_mesh_streamer.gd")

var failures: Array[String] = []
var assertions: int = 0
var manifest: Dictionary = {}
var material_catalog: Dictionary = {}
var profile: Dictionary = {}
var feature_catalog: Dictionary = {}
var body: Dictionary = {}
var grid_profile: Dictionary = {}
var basalt_composition: Dictionary = {}


func _init() -> void:
	_load_fixture()
	_test_manifest()
	_test_synthetic_plane_seam()
	_test_real_asteroid_surface_mesh()
	_test_real_asteroid_sibling_seam()
	_test_empty_bricks()
	_test_resource_factory()
	_test_local_streamer()
	_test_negative_cases()
	_finish()


func _load_fixture() -> void:
	material_catalog = MaterialCatalogScript.default_catalog()
	profile = GeneratorScript.default_profile()
	feature_catalog = GeneratorScript.default_feature_catalog(profile)
	body = GeneratorScript.default_body_definition(profile, material_catalog, feature_catalog)
	grid_profile = GridProfileScript.create({
		"body_id": body.get("body_id", ""),
		"body_frame_id": body.get("body_frame_id", ""),
		"root_half_extent_m": ProfileScript.root_bounds_radius_m(profile),
	})
	basalt_composition = CompositionScript.from_weights({"matter/basalt": 1.0})
	var path: String = "res://config/matter/mw3-local-meshing.v1.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed


func _test_manifest() -> void:
	_assert(not manifest.is_empty(), "MW3 manifest is missing or invalid")
	if manifest.is_empty():
		return
	_assert(
		String(manifest.get("schema", "")) \
			== "planet_simulator.mw3_local_meshing_manifest.v1",
		"MW3 manifest schema changed"
	)
	_assert(String(manifest.get("checkpoint", "")) == "v17.3.0-simulation-mw3-local-meshing", "MW3 checkpoint changed")
	_assert(String(manifest.get("base_checkpoint", "")) == "v17.2.0-simulation-mw2-sparse-bricks", "MW3 base changed")
	_assert(String(manifest.get("base_delivery", "")) == "fix1", "MW3 base delivery changed")
	_assert(String(manifest.get("recommended_branch", "")) == "feature/mw3-local-meshing", "MW3 branch changed")
	_assert(not bool(manifest.get("runtime_worlds_changed", true)), "MW3 unexpectedly changes runtime worlds")
	_assert(not bool(manifest.get("moon_runtime_changed", true)), "MW3 unexpectedly changes Moon runtime")
	_assert(not bool(manifest.get("world_catalog_changed", true)), "MW3 unexpectedly changes world catalog")
	_assert(bool(manifest.get("local_mesh_added", false)), "MW3 local mesh flag missing")
	_assert(bool(manifest.get("local_collision_added", false)), "MW3 collision flag missing")
	_assert(not bool(manifest.get("canonical_matter_changed", true)), "MW3 changes canonical matter")
	_assert(
		String(manifest.get("mesher", {}).get("algorithm", "")) \
			== "FREUDENTHAL_MARCHING_TETRAHEDRA",
		"MW3 mesher algorithm changed"
	)
	_assert(int(manifest.get("mesher", {}).get("tetrahedra_per_cell", 0)) == 6, "MW3 tetrahedron count changed")
	_assert(
		String(manifest.get("mesher", {}).get("triangle_winding", "")) \
			== "GODOT_CLOCKWISE_ALIGNED_TO_OUTWARD_GRADIENT",
		"MW3 triangle winding contract changed"
	)
	_assert(
		bool(manifest.get("collision", {}).get("backface_collision", false)),
		"MW3 two-sided collision contract changed"
	)
	_assert(
		String(manifest.get("lab_scene", "")) \
			== "res://scenes/labs/matter_asteroid_meshing_lab.tscn",
		"MW3 lab scene changed"
	)


func _test_synthetic_plane_seam() -> void:
	var left_cell: Dictionary = _cell_from_path([0])
	var right_cell: Dictionary = _cell_from_path([1])
	var plane_y_m: float = -680.0
	var left_snapshot: Dictionary = _plane_snapshot(left_cell, plane_y_m, "left")
	var right_snapshot: Dictionary = _plane_snapshot(right_cell, plane_y_m, "right")
	_assert_ok(SnapshotScript.validate(left_snapshot), "Synthetic left snapshot rejected")
	_assert_ok(SnapshotScript.validate(right_snapshot), "Synthetic right snapshot rejected")
	var left_mesh: Dictionary = MesherScript.build_mesh_data(left_snapshot, grid_profile)
	var right_mesh: Dictionary = MesherScript.build_mesh_data(right_snapshot, grid_profile)
	_assert_ok(MeshDataScript.validate(left_mesh), "Synthetic left mesh rejected")
	_assert_ok(MeshDataScript.validate(right_mesh), "Synthetic right mesh rejected")
	_assert(String(left_mesh["status"]) == MeshDataScript.STATUS_READY, "Synthetic left mesh is empty")
	_assert(String(right_mesh["status"]) == MeshDataScript.STATUS_READY, "Synthetic right mesh is empty")
	_assert(int(left_mesh["triangle_count"]) > 0, "Synthetic left mesh has no triangles")
	_assert(int(right_mesh["triangle_count"]) > 0, "Synthetic right mesh has no triangles")
	var seam: Dictionary = SeamValidatorScript.compare_shared_plane(
		left_mesh, right_mesh, 0, 0.0
	)
	_assert_ok(seam, "Synthetic sibling mesh seam mismatch")
	var seam_details: Dictionary = seam.get("details", {})
	_assert(int(seam_details.get("boundary_vertex_count", 0)) > 0, "Synthetic seam has no boundary vertices")
	_assert(int(seam_details.get("boundary_normal_count", 0)) > 0, "Synthetic seam has no boundary normals")
	_assert(int(seam_details.get("boundary_segment_count", 0)) > 0, "Synthetic seam has no boundary segments")
	var replay: Dictionary = MesherScript.build_mesh_data(left_snapshot, grid_profile)
	_assert_ok(MeshDataScript.validate(replay), "Synthetic replay mesh rejected")
	_assert(
		String(replay["content_hash"]) == String(left_mesh["content_hash"]),
		"Synthetic mesh hash is non-deterministic"
	)
	_assert(replay["vertices"] == left_mesh["vertices"], "Synthetic mesh vertices are non-deterministic")
	_assert(replay["normals"] == left_mesh["normals"], "Synthetic mesh normals are non-deterministic")
	_assert(replay["indices"] == left_mesh["indices"], "Synthetic mesh indices are non-deterministic")
	_validate_mesh_geometry(left_mesh, "synthetic left")
	_validate_mesh_geometry(right_mesh, "synthetic right")


func _test_real_asteroid_surface_mesh() -> void:
	var surface_radius_m: float = GeneratorScript.surface_radius_validated(
		profile, feature_catalog, Vector3.RIGHT
	)
	_assert(surface_radius_m > 800.0 and surface_radius_m < 1400.0, "MW1 +X surface radius is outside root")
	var surface_cell: Dictionary = CellGridScript.address_for_position(
		grid_profile, Vector3(surface_radius_m, 0.0, 0.0), 5
	)
	_assert_ok(CellGridScript.validate_address(grid_profile, surface_cell), "Real surface cell rejected")
	var snapshot: Dictionary = MaterializerScript.materialize(
		body, material_catalog, profile, feature_catalog, grid_profile, surface_cell, 0
	)
	_assert_ok(SnapshotScript.validate(snapshot), "Real asteroid surface snapshot rejected")
	var mesh_data: Dictionary = MesherScript.build_mesh_data(snapshot, grid_profile)
	_assert_ok(MeshDataScript.validate(mesh_data), "Real asteroid mesh rejected")
	_assert(String(mesh_data["status"]) == MeshDataScript.STATUS_READY, "Real asteroid surface mesh is empty")
	_assert(int(mesh_data["triangle_count"]) > 8, "Real asteroid surface mesh has too few triangles")
	_assert(int(mesh_data["triangle_count"]) <= 6144, "Real asteroid surface mesh exceeds tetrahedral maximum")
	var real_vertices: PackedVector3Array = mesh_data["vertices"]
	_assert(real_vertices.size() <= int(mesh_data["triangle_count"]) * 3, "Real mesh has invalid vertex count")
	_assert(MatterUtilsScript.is_lower_hex_64(mesh_data["content_hash"]), "Real mesh content hash is invalid")
	_validate_mesh_geometry(mesh_data, "real asteroid")
	var replay: Dictionary = MesherScript.build_mesh_data(snapshot, grid_profile)
	_assert(
		String(replay.get("content_hash", "")) == String(mesh_data["content_hash"]),
		"Real asteroid mesh is non-deterministic"
	)


func _test_real_asteroid_sibling_seam() -> void:
	var surface_radius_m: float = GeneratorScript.surface_radius_validated(
		profile, feature_catalog, Vector3.RIGHT
	)
	var positive_cell: Dictionary = CellGridScript.address_for_position(
		grid_profile, Vector3(surface_radius_m, 1.0, 1.0), 5
	)
	var negative_cell: Dictionary = CellGridScript.address_for_position(
		grid_profile, Vector3(surface_radius_m, -1.0, 1.0), 5
	)
	_assert_ok(
		CellGridScript.validate_address(grid_profile, positive_cell),
		"Real positive-Y seam cell rejected"
	)
	_assert_ok(
		CellGridScript.validate_address(grid_profile, negative_cell),
		"Real negative-Y seam cell rejected"
	)
	var positive_snapshot: Dictionary = MaterializerScript.materialize(
		body, material_catalog, profile, feature_catalog, grid_profile, positive_cell, 0
	)
	var negative_snapshot: Dictionary = MaterializerScript.materialize(
		body, material_catalog, profile, feature_catalog, grid_profile, negative_cell, 0
	)
	_assert_ok(SnapshotScript.validate(positive_snapshot), "Real positive-Y snapshot rejected")
	_assert_ok(SnapshotScript.validate(negative_snapshot), "Real negative-Y snapshot rejected")
	var positive_mesh: Dictionary = MesherScript.build_mesh_data(positive_snapshot, grid_profile)
	var negative_mesh: Dictionary = MesherScript.build_mesh_data(negative_snapshot, grid_profile)
	_assert_ok(MeshDataScript.validate(positive_mesh), "Real positive-Y mesh rejected")
	_assert_ok(MeshDataScript.validate(negative_mesh), "Real negative-Y mesh rejected")
	_assert(
		String(positive_mesh["status"]) == MeshDataScript.STATUS_READY,
		"Real positive-Y seam mesh is empty"
	)
	_assert(
		String(negative_mesh["status"]) == MeshDataScript.STATUS_READY,
		"Real negative-Y seam mesh is empty"
	)
	var seam: Dictionary = SeamValidatorScript.compare_shared_plane(
		negative_mesh, positive_mesh, 1, 0.0
	)
	_assert_ok(seam, "Real MW1 sibling seam mismatch")
	var seam_details: Dictionary = seam.get("details", {})
	_assert(int(seam_details.get("boundary_vertex_count", 0)) > 0, "Real seam has no vertices")
	_assert(int(seam_details.get("boundary_normal_count", 0)) > 0, "Real seam has no normals")
	_assert(int(seam_details.get("boundary_segment_count", 0)) > 0, "Real seam has no segments")


func _test_empty_bricks() -> void:
	var fixtures: Array = [
		Vector3.ZERO,
		Vector3(1400.0, 1400.0, 1400.0),
	]
	for point in fixtures:
		var cell: Dictionary = CellGridScript.address_for_position(grid_profile, point, 5)
		_assert_ok(CellGridScript.validate_address(grid_profile, cell), "Empty-brick fixture cell rejected")
		var snapshot: Dictionary = MaterializerScript.materialize(
			body, material_catalog, profile, feature_catalog, grid_profile, cell, 0
		)
		_assert_ok(SnapshotScript.validate(snapshot), "Empty-brick fixture snapshot rejected")
		var mesh_data: Dictionary = MesherScript.build_mesh_data(snapshot, grid_profile)
		_assert_ok(MeshDataScript.validate(mesh_data), "Empty-brick mesh rejected")
		_assert(String(mesh_data["status"]) == MeshDataScript.STATUS_EMPTY, "Uniform brick generated triangles")
		_assert(int(mesh_data["triangle_count"]) == 0, "Uniform brick triangle count is not zero")
		var empty_vertices: PackedVector3Array = mesh_data["vertices"]
		_assert(empty_vertices.is_empty(), "Uniform brick contains vertices")
		_assert(ResourceFactoryScript.create_array_mesh(mesh_data) == null, "Empty mesh created ArrayMesh")
		_assert(ResourceFactoryScript.create_concave_shape(mesh_data) == null, "Empty mesh created collision shape")


func _test_resource_factory() -> void:
	var left_snapshot: Dictionary = _plane_snapshot(_cell_from_path([0]), -680.0, "resource")
	var mesh_data: Dictionary = MesherScript.build_mesh_data(left_snapshot, grid_profile)
	var array_mesh: ArrayMesh = ResourceFactoryScript.create_array_mesh(mesh_data)
	_assert(array_mesh != null, "MW3 resource factory returned null ArrayMesh")
	if array_mesh != null:
		_assert(array_mesh.get_surface_count() == 1, "MW3 ArrayMesh surface count changed")
		var arrays: Array = array_mesh.surface_get_arrays(0)
		var source_vertices: PackedVector3Array = mesh_data["vertices"]
		var source_indices: PackedInt32Array = mesh_data["indices"]
		var mesh_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var mesh_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_assert(mesh_vertices.size() == source_vertices.size(), "ArrayMesh vertex count mismatch")
		_assert(mesh_indices.size() == source_indices.size(), "ArrayMesh index count mismatch")
	var shape: ConcavePolygonShape3D = ResourceFactoryScript.create_concave_shape(mesh_data)
	_assert(shape != null, "MW3 collision factory returned null shape")
	if shape != null:
		var collision_indices: PackedInt32Array = mesh_data["indices"]
		_assert(shape.get_faces().size() == collision_indices.size(), "Collision face count mismatch")
		_assert(shape.backface_collision, "MW3 collision must remain two-sided")
	var presenter: Node3D = ResourceFactoryScript.create_presenter(mesh_data, null, true)
	_assert(presenter != null, "MW3 presenter factory returned null")
	if presenter != null:
		var expected_origin: Vector3 = mesh_data["origin_body_local_m"]
		_assert(presenter.position == expected_origin, "MW3 presenter origin mismatch")
		_assert(presenter.get_node_or_null("Surface") is MeshInstance3D, "MW3 presenter surface missing")
		_assert(presenter.get_node_or_null("Collision") is StaticBody3D, "MW3 presenter collision missing")
		var collision_shape = presenter.get_node_or_null("Collision/Shape")
		_assert(collision_shape is CollisionShape3D, "MW3 presenter collision shape missing")
		presenter.free()


func _test_local_streamer() -> void:
	var observer := Node3D.new()
	observer.name = "MW3TestObserver"
	observer.position = Vector3(1140.0, 0.0, 0.0)
	root.add_child(observer)
	var streamer = StreamerScript.new()
	streamer.name = "MW3TestStreamer"
	streamer.cell_level = 5
	streamer.load_radius_cells = 1
	streamer.max_builds_per_frame = 1
	streamer.build_collision = false
	root.add_child(streamer)
	_assert_ok(streamer.configure(
		body, material_catalog, profile, feature_catalog, grid_profile, observer
	), "MW3 local streamer configuration failed")
	var initial_stats: Dictionary = streamer.stats()
	_assert(bool(initial_stats.get("configured", false)), "MW3 streamer did not enter configured state")
	_assert(int(initial_stats.get("desired_count", 0)) == 27, "MW3 streamer desired neighborhood changed")
	_assert(int(initial_stats.get("pending_count", 0)) == 27, "MW3 streamer pending neighborhood changed")
	_assert(int(initial_stats.get("failed_brick_count", -1)) == 0, "MW3 streamer starts with failures")
	var initial_ids: Array = streamer.desired_address_ids()
	var sorted_ids: Array = initial_ids.duplicate()
	sorted_ids.sort()
	_assert(initial_ids == sorted_ids, "MW3 streamer address IDs are not sorted")
	_assert(streamer.build_next_pending(), "MW3 streamer did not resolve first pending cell")
	var after_build: Dictionary = streamer.stats()
	_assert(int(after_build.get("pending_count", -1)) == 26, "MW3 streamer did not consume one pending cell")
	_assert(
		int(after_build.get("surface_brick_count", 0))
		+ int(after_build.get("empty_brick_count", 0))
		+ int(after_build.get("failed_brick_count", 0)) == 1,
		"MW3 streamer did not classify first resolved cell"
	)
	_assert(int(after_build.get("failed_brick_count", 0)) == 0, "MW3 streamer failed a valid brick")
	var first_generation: int = int(after_build.get("request_generation", 0))
	observer.position += Vector3(100.0, 0.0, 0.0)
	_assert_ok(streamer.refresh_now(), "MW3 streamer refresh after observer move failed")
	var moved_stats: Dictionary = streamer.stats()
	_assert(
		int(moved_stats.get("request_generation", 0)) == first_generation + 1,
		"MW3 streamer request generation did not advance"
	)
	_assert(streamer.desired_address_ids() != initial_ids, "MW3 streamer neighborhood did not move with observer")
	streamer.free()
	observer.free()
	var outside_observer := Node3D.new()
	outside_observer.position = Vector3(4000.0, 0.0, 0.0)
	root.add_child(outside_observer)
	var outside_streamer = StreamerScript.new()
	outside_streamer.cell_level = 5
	root.add_child(outside_streamer)
	_assert_fail(outside_streamer.configure(
		body, material_catalog, profile, feature_catalog, grid_profile, outside_observer
	), "MW3 streamer accepted observer outside root bounds")
	_assert(
		not bool(outside_streamer.stats().get("configured", true)),
		"MW3 streamer remained configured after failed initial refresh"
	)
	outside_streamer.free()
	outside_observer.free()


func _test_negative_cases() -> void:
	var snapshot: Dictionary = _plane_snapshot(_cell_from_path([0]), -680.0, "negative")
	var mesh_data: Dictionary = MesherScript.build_mesh_data(snapshot, grid_profile)
	var corrupted_snapshot: Dictionary = snapshot.duplicate(true)
	corrupted_snapshot["checksum"] = "0".repeat(64)
	_assert(
		MesherScript.build_mesh_data(corrupted_snapshot, grid_profile).is_empty(),
		"Mesher accepted corrupted snapshot"
	)
	var wrong_grid: Dictionary = GridProfileScript.create({
		"body_id": body["body_id"],
		"body_frame_id": body["body_frame_id"],
		"root_half_extent_m": 1450.0,
		"grid_id": "matter-grid-foreign",
	})
	_assert(MesherScript.build_mesh_data(snapshot, wrong_grid).is_empty(), "Mesher accepted foreign grid")
	_assert(MesherScript.build_mesh_data(snapshot, grid_profile, INF).is_empty(), "Mesher accepted infinite iso level")
	var mismatched_attributes: Dictionary = MeshDataScript.create(
		String(mesh_data["source_snapshot_checksum"]),
		int(mesh_data["source_state_revision"]),
		mesh_data["address"],
		mesh_data["origin_body_local_m"],
		float(mesh_data["iso_level_m"]),
		mesh_data["vertices"],
		PackedVector3Array(),
		mesh_data["colors"],
		mesh_data["indices"]
	)
	_assert_fail(
		MeshDataScript.validate(mismatched_attributes),
		"Mesh data accepted mismatched attribute arrays"
	)
	var bad_hash: Dictionary = mesh_data.duplicate(true)
	bad_hash["content_hash"] = "0".repeat(64)
	_assert_fail(MeshDataScript.validate(bad_hash), "Mesh data accepted corrupted content hash")
	var bad_normal: Dictionary = mesh_data.duplicate(true)
	var normals: PackedVector3Array = PackedVector3Array(bad_normal["normals"]).duplicate()
	normals[0] = Vector3.ZERO
	bad_normal["normals"] = normals
	bad_normal["content_hash"] = "0".repeat(64)
	_assert_fail(MeshDataScript.validate(bad_normal), "Mesh data accepted zero normal")
	var bad_color: Dictionary = mesh_data.duplicate(true)
	var colors: PackedColorArray = PackedColorArray(bad_color["colors"]).duplicate()
	colors[0] = Color(2.0, 0.0, 0.0, 1.0)
	bad_color["colors"] = colors
	bad_color["content_hash"] = "0".repeat(64)
	_assert_fail(MeshDataScript.validate(bad_color), "Mesh data accepted out-of-range color")
	var bad_bounds: Dictionary = mesh_data.duplicate(true)
	bad_bounds["surface_bounds_max_m"] = Vector3(999.0, 999.0, 999.0)
	bad_bounds["content_hash"] = "0".repeat(64)
	_assert_fail(MeshDataScript.validate(bad_bounds), "Mesh data accepted incorrect bounds")
	var mismatched_normals: PackedVector3Array = PackedVector3Array(
		mesh_data["normals"]
	).duplicate()
	var mesh_vertices: PackedVector3Array = mesh_data["vertices"]
	var mesh_origin: Vector3 = mesh_data["origin_body_local_m"]
	for vertex_index in range(mesh_vertices.size()):
		if absf((mesh_origin + mesh_vertices[vertex_index]).x) <= 0.000001:
			mismatched_normals[vertex_index] = Vector3.RIGHT
			break
	var normal_mismatch_mesh: Dictionary = MeshDataScript.create(
		String(mesh_data["source_snapshot_checksum"]),
		int(mesh_data["source_state_revision"]),
		mesh_data["address"],
		mesh_data["origin_body_local_m"],
		float(mesh_data["iso_level_m"]),
		mesh_data["vertices"],
		mismatched_normals,
		mesh_data["colors"],
		mesh_data["indices"]
	)
	_assert_fail(
		SeamValidatorScript.compare_shared_plane(mesh_data, normal_mismatch_mesh, 0, 0.0),
		"Seam validator accepted mismatched boundary normals"
	)
	_assert_fail(
		SeamValidatorScript.compare_shared_plane(mesh_data, mesh_data, 0, 100.0),
		"Seam validator accepted two empty plane intersections"
	)
	_assert_fail(
		SeamValidatorScript.compare_shared_plane(mesh_data, {}, 0, 0.0),
		"Seam validator accepted missing right mesh"
	)
	_assert_fail(
		SeamValidatorScript.compare_shared_plane(mesh_data, mesh_data, 3, 0.0),
		"Seam validator accepted invalid axis"
	)
	_assert(ResourceFactoryScript.create_presenter({}, null, true) == null, "Presenter accepted invalid mesh data")


func _plane_snapshot(cell_address: Dictionary, plane_y_m: float, suffix: String) -> Dictionary:
	var samples: Array = []
	var axis_count: int = BrickLayoutScript.sample_axis_count(grid_profile)
	for z in range(axis_count):
		for y in range(axis_count):
			for x in range(axis_count):
				var point: Vector3 = BrickLayoutScript.sample_position_m(
					grid_profile, cell_address, x, y, z
				)
				var distance_m: float = point.y - plane_y_m
				if distance_m <= 0.0:
					samples.append(SampleScript.create(
						distance_m,
						1.0,
						2900.0,
						basalt_composition,
						0.95,
						180.0,
						0.05,
						["matter-state/bonded"]
					))
				else:
					samples.append(SampleScript.vacuum(distance_m, 3.0))
	return SnapshotScript.create(
		"matter-snapshot/mw3-plane-%s" % suffix,
		BrickLayoutScript.brick_address(grid_profile, cell_address),
		String(body["checksum"]),
		String(profile["generator_version"]),
		int(profile["generator_seed"]),
		0,
		samples
	)


func _validate_mesh_geometry(mesh_data: Dictionary, label: String) -> void:
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var normals: PackedVector3Array = mesh_data["normals"]
	var colors: PackedColorArray = mesh_data["colors"]
	var indices: PackedInt32Array = mesh_data["indices"]
	for index in range(vertices.size()):
		var vertex: Vector3 = vertices[index]
		var normal: Vector3 = normals[index]
		var color: Color = colors[index]
		_assert(is_finite(vertex.x) and is_finite(vertex.y) and is_finite(vertex.z), "%s has non-finite vertex" % label)
		_assert(absf(normal.length() - 1.0) < 0.00001, "%s has non-unit normal" % label)
		_assert(color.r >= 0.0 and color.r <= 1.0, "%s has invalid red channel" % label)
		_assert(color.g >= 0.0 and color.g <= 1.0, "%s has invalid green channel" % label)
		_assert(color.b >= 0.0 and color.b <= 1.0, "%s has invalid blue channel" % label)
	for triangle_offset in range(0, indices.size(), 3):
		var a: int = indices[triangle_offset]
		var b: int = indices[triangle_offset + 1]
		var c: int = indices[triangle_offset + 2]
		var face_normal: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		_assert(face_normal.length_squared() > 0.000000000001, "%s contains degenerate triangle" % label)
		var expected_normal: Vector3 = (normals[a] + normals[b] + normals[c]).normalized()
		_assert(face_normal.dot(expected_normal) < 0.0, "%s triangle winding is not Godot-clockwise" % label)


func _cell_from_path(path: Array) -> Dictionary:
	var address: Dictionary = CellGridScript.root_address(grid_profile)
	for child_index in path:
		address = CellGridScript.child(address, int(child_index), grid_profile)
		if address.is_empty():
			return {}
	return address


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, String(result.get("error_code", ""))])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("MW3 local meshing: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MW3 local meshing: FAIL (%d failures / %d assertions)" % [failures.size(), assertions])
	quit(1)
