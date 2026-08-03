extends SceneTree

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BrickSnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const ProfileScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")
const FeatureCatalogScript = preload("res://scripts/simulation/matter/generation/asteroid_feature_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const MaterializerScript = preload("res://scripts/simulation/matter/storage/matter_brick_materializer.gd")
const SparseStoreScript = preload("res://scripts/simulation/matter/storage/matter_sparse_brick_store.gd")
const QueryResultScript = preload("res://scripts/simulation/matter/query/matter_query_result.gd")
const QueryServiceScript = preload("res://scripts/simulation/matter/query/matter_query_service.gd")

var failures: Array[String] = []
var assertions: int = 0
var manifest: Dictionary = {}
var profile: Dictionary = {}
var material_catalog: Dictionary = {}
var feature_catalog: Dictionary = {}
var body: Dictionary = {}
var grid_profile: Dictionary = {}


func _init() -> void:
	_load_fixture()
	_test_manifest()
	_test_root_bounds_contract()
	_test_grid_profile_contract()
	_test_hierarchical_cells()
	_test_nested_sibling_lattice_seams()
	_test_brick_lattice()
	_test_materialization_and_ghost_seams()
	_test_sparse_store()
	_test_query_service()
	_test_negative_cases()
	_finish()


func _load_fixture() -> void:
	profile = ProfileScript.default_profile()
	material_catalog = MaterialCatalogScript.default_catalog()
	feature_catalog = FeatureCatalogScript.create(profile)
	body = GeneratorScript.default_body_definition(profile, material_catalog, feature_catalog)
	grid_profile = GridProfileScript.create({
		"body_id": body.get("body_id", ""),
		"body_frame_id": body.get("body_frame_id", ""),
		"root_half_extent_m": ProfileScript.root_bounds_radius_m(profile),
	})
	var path: String = "res://config/matter/mw2-sparse-bricks-and-query.v1.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed


func _test_manifest() -> void:
	_assert(not manifest.is_empty(), "MW2 manifest is missing or invalid")
	if manifest.is_empty():
		return
	_assert(String(manifest.get("schema", "")) == "planet_simulator.mw2_sparse_bricks_manifest.v1", "MW2 manifest schema changed")
	_assert(String(manifest.get("checkpoint", "")) == "v17.2.0-simulation-mw2-sparse-bricks", "MW2 checkpoint changed")
	_assert(String(manifest.get("base_checkpoint", "")) == "v17.1.0-simulation-mw1-fixed-seed-asteroid", "MW2 base changed")
	_assert(String(manifest.get("recommended_branch", "")) == "feature/mw2-sparse-bricks", "MW2 branch changed")
	_assert(not bool(manifest.get("runtime_worlds_changed", true)), "MW2 unexpectedly changes runtime worlds")
	_assert(not bool(manifest.get("moon_runtime_changed", true)), "MW2 unexpectedly changes Moon runtime")
	_assert(not bool(manifest.get("mesh_or_collision_added", true)), "MW2 unexpectedly adds mesh or collision")
	var layout = manifest.get("brick_layout")
	_assert(typeof(layout) == TYPE_DICTIONARY, "MW2 brick layout is missing")
	if typeof(layout) == TYPE_DICTIONARY:
		_assert(int(layout.get("interior_resolution", 0)) == 8, "MW2 interior resolution changed")
		_assert(int(layout.get("ghost_border_samples", 0)) == 1, "MW2 ghost border changed")
		_assert(int(layout.get("sample_axis_count", 0)) == 11, "MW2 sample axis count changed")
		_assert(int(layout.get("sample_count", 0)) == 1331, "MW2 sample count changed")


func _test_root_bounds_contract() -> void:
	_assert_ok(ProfileScript.validate(profile), "Default MW1 profile rejected after MW2 bounds hardening")
	var declared_radius_m: float = ProfileScript.root_bounds_radius_m(profile)
	var profile_required_m: float = ProfileScript.required_root_bounds_radius_m(profile)
	var full_required_m: float = GeneratorScript.required_root_bounds_radius_m(profile, feature_catalog)
	_assert(absf(declared_radius_m - 1450.0) < 0.000000001, "Declared root radius changed")
	_assert(profile_required_m > 1200.0 and profile_required_m < declared_radius_m, "Profile root requirement is invalid")
	_assert(full_required_m >= profile_required_m and full_required_m < declared_radius_m, "Feature-aware root requirement is invalid")
	var undersized_profile: Dictionary = ProfileScript.create({"root_bounds_radius_ratio": 1.1})
	_assert_fail(ProfileScript.validate(undersized_profile), "Profile with undersized root bounds accepted")
	var escaped_features: Dictionary = feature_catalog.duplicate(true)
	for feature in escaped_features["features"]:
		if String(feature["feature_kind"]) == "ADD_LOBE":
			feature["center_m"] = [1800.0, 0.0, 0.0]
			break
	escaped_features["catalog_hash"] = MatterUtilsScript.payload_hash(escaped_features["features"])
	escaped_features["checksum"] = MatterUtilsScript.compute_checksum(escaped_features)
	_assert_ok(FeatureCatalogScript.validate(escaped_features), "Mutated feature fixture is structurally invalid")
	var escaped_body: Dictionary = GeneratorScript.default_body_definition(profile, material_catalog, escaped_features)
	_assert(not escaped_body.is_empty(), "Body definition could not bind escaped feature catalog")
	_assert_fail(
		GeneratorScript.validate_configuration(escaped_body, material_catalog, profile, escaped_features),
		"Feature escaping root bounds accepted"
	)


func _test_grid_profile_contract() -> void:
	_assert_ok(GridProfileScript.validate(grid_profile), "Default MW2 grid profile rejected")
	_assert(GridProfileScript.normalize(grid_profile) == grid_profile, "MW2 grid normalization changed canonical value")
	_assert(GridProfileScript.sample_axis_count(grid_profile) == 11, "MW2 sample axis count is not 11")
	_assert(GridProfileScript.sample_count(grid_profile) == 1331, "MW2 sample count is not 1331")
	_assert(MatterUtilsScript.is_lower_hex_64(GridProfileScript.content_hash(grid_profile)), "MW2 grid hash is invalid")
	var replay: Dictionary = GridProfileScript.create({
		"body_id": body["body_id"],
		"body_frame_id": body["body_frame_id"],
		"root_half_extent_m": 1450.0,
	})
	_assert(replay == grid_profile, "MW2 grid profile is non-deterministic")
	var bad_resolution: Dictionary = grid_profile.duplicate(true)
	bad_resolution["brick_interior_resolution"] = 1
	bad_resolution["checksum"] = MatterUtilsScript.compute_checksum(bad_resolution)
	_assert_fail(GridProfileScript.validate(bad_resolution), "Invalid brick resolution accepted")
	var no_ghost: Dictionary = grid_profile.duplicate(true)
	no_ghost["ghost_border_samples"] = 0
	no_ghost["checksum"] = MatterUtilsScript.compute_checksum(no_ghost)
	_assert_fail(GridProfileScript.validate(no_ghost), "Zero ghost border accepted")


func _test_hierarchical_cells() -> void:
	var root: Dictionary = CellGridScript.root_address(grid_profile)
	_assert_ok(CellGridScript.validate_address(grid_profile, root), "MW2 root cell rejected")
	_assert(int(root["level"]) == 0, "MW2 root level changed")
	var root_bounds: Dictionary = CellGridScript.bounds(grid_profile, root)
	_assert_ok(CellGridScript.validate_bounds(root_bounds), "MW2 root bounds rejected")
	_assert(absf(float(root_bounds["edge_length_m"]) - 2900.0) < 0.000000001, "MW2 root edge changed")
	for child_index in range(8):
		var child: Dictionary = CellGridScript.child(root, child_index, grid_profile)
		_assert_ok(CellGridScript.validate_address(grid_profile, child), "Child %d rejected" % child_index)
		_assert(int(child["level"]) == 1, "Child %d has wrong level" % child_index)
		_assert(CellGridScript.parent(child, grid_profile) == root, "Child %d parent mismatch" % child_index)
		var child_bounds: Dictionary = CellGridScript.bounds(grid_profile, child)
		_assert_ok(CellGridScript.validate_bounds(child_bounds), "Child %d bounds rejected" % child_index)
		_assert(absf(float(child_bounds["edge_length_m"]) - 1450.0) < 0.000000001, "Child %d edge mismatch" % child_index)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17202026
	for level in range(int(grid_profile["max_level"]) + 1):
		for iteration in range(64):
			var point: Vector3 = Vector3(
				rng.randf_range(-1449.999, 1449.999),
				rng.randf_range(-1449.999, 1449.999),
				rng.randf_range(-1449.999, 1449.999)
			)
			var address: Dictionary = CellGridScript.address_for_position(grid_profile, point, level)
			_assert_ok(CellGridScript.validate_address(grid_profile, address), "Random cell address rejected")
			_assert(int(address["level"]) == level, "Random cell level mismatch")
			_assert(CellGridScript.contains_position(grid_profile, address, point), "Mapped cell does not contain source point")
	var boundary_address: Dictionary = CellGridScript.address_for_position(grid_profile, Vector3.ZERO, 3)
	_assert(Array(boundary_address["path"]) == [7, 0, 0], "Center tie-break is not positive-first")
	_assert(CellGridScript.address_for_position(grid_profile, Vector3(1450.1, 0.0, 0.0), 1).is_empty(), "Out-of-root position received a cell")


func _test_nested_sibling_lattice_seams() -> void:
	var path_pairs: Array = [
		[[0], [1]],
		[[7, 0], [7, 1]],
		[[2, 5, 2], [2, 5, 3]],
		[[6, 1, 4, 6], [6, 1, 4, 7]],
		[[3, 7, 2, 5, 0], [3, 7, 2, 5, 1]],
	]
	var interior_min: int = BrickLayoutScript.interior_min_index(grid_profile)
	var interior_max: int = BrickLayoutScript.interior_max_index(grid_profile)
	var axis_count: int = BrickLayoutScript.sample_axis_count(grid_profile)
	for pair in path_pairs:
		var left: Dictionary = _cell_from_path(Array(pair[0]))
		var right: Dictionary = _cell_from_path(Array(pair[1]))
		_assert_ok(CellGridScript.validate_address(grid_profile, left), "Nested left sibling rejected")
		_assert_ok(CellGridScript.validate_address(grid_profile, right), "Nested right sibling rejected")
		for z in range(axis_count):
			for y in range(axis_count):
				_assert(
					BrickLayoutScript.sample_position_m(grid_profile, left, interior_max, y, z) 						== BrickLayoutScript.sample_position_m(grid_profile, right, interior_min, y, z),
					"Nested shared-face coordinate mismatch"
				)
				_assert(
					BrickLayoutScript.sample_position_m(grid_profile, left, interior_max + 1, y, z) 						== BrickLayoutScript.sample_position_m(grid_profile, right, interior_min + 1, y, z),
					"Nested positive ghost coordinate mismatch"
				)
				_assert(
					BrickLayoutScript.sample_position_m(grid_profile, left, interior_max - 1, y, z) 						== BrickLayoutScript.sample_position_m(grid_profile, right, interior_min - 1, y, z),
					"Nested negative ghost coordinate mismatch"
				)


func _test_brick_lattice() -> void:
	var cell: Dictionary = CellGridScript.address_for_position(grid_profile, Vector3(300.0, -250.0, 100.0), 3)
	var axis_count: int = BrickLayoutScript.sample_axis_count(grid_profile)
	var count: int = BrickLayoutScript.sample_count(grid_profile)
	_assert(axis_count == 11, "Unexpected lattice axis count")
	_assert(count == 1331, "Unexpected lattice sample count")
	var seen: Dictionary = {}
	for index in range(count):
		var coordinates: Array = BrickLayoutScript.coordinates_from_flat_index(grid_profile, index)
		_assert(coordinates.size() == 3, "Flat index did not decode")
		var replay_index: int = BrickLayoutScript.flat_index(
			grid_profile, int(coordinates[0]), int(coordinates[1]), int(coordinates[2])
		)
		_assert(replay_index == index, "Flat lattice round-trip mismatch at %d" % index)
		seen[replay_index] = true
	_assert(seen.size() == count, "Lattice flat indices are not unique")
	var minimum_index: int = BrickLayoutScript.interior_min_index(grid_profile)
	var maximum_index: int = BrickLayoutScript.interior_max_index(grid_profile)
	var cell_bounds: Dictionary = CellGridScript.bounds(grid_profile, cell)
	var minimum_position: Vector3 = BrickLayoutScript.sample_position_m(
		grid_profile, cell, minimum_index, minimum_index, minimum_index
	)
	var maximum_position: Vector3 = BrickLayoutScript.sample_position_m(
		grid_profile, cell, maximum_index, maximum_index, maximum_index
	)
	_assert(_vector_equal(minimum_position, _vector3(cell_bounds["minimum_m"])), "Interior minimum sample is not cell minimum")
	_assert(_vector_equal(maximum_position, _vector3(cell_bounds["maximum_m"])), "Interior maximum sample is not cell maximum")
	for z in range(axis_count):
		for y in range(axis_count):
			for x in range(axis_count):
				var position: Vector3 = BrickLayoutScript.sample_position_validated(
					grid_profile, cell_bounds, x, y, z
				)
				var coordinates: Array = BrickLayoutScript.lattice_coordinates_for_position_validated(
					grid_profile, cell_bounds, position
				)
				_assert(coordinates == [x, y, z], "Lattice position round-trip mismatch")


func _test_materialization_and_ghost_seams() -> void:
	var root: Dictionary = CellGridScript.root_address(grid_profile)
	var left: Dictionary = CellGridScript.child(root, 0, grid_profile)
	var right: Dictionary = CellGridScript.child(root, 1, grid_profile)
	var left_snapshot: Dictionary = MaterializerScript.materialize(
		body, material_catalog, profile, feature_catalog, grid_profile, left, 0
	)
	var right_snapshot: Dictionary = MaterializerScript.materialize(
		body, material_catalog, profile, feature_catalog, grid_profile, right, 0
	)
	_assert_ok(BrickSnapshotScript.validate(left_snapshot), "Left MW2 brick rejected")
	_assert_ok(BrickSnapshotScript.validate(right_snapshot), "Right MW2 brick rejected")
	_assert(int(left_snapshot["sample_count"]) == 1331, "Left MW2 brick sample count changed")
	_assert(int(right_snapshot["sample_count"]) == 1331, "Right MW2 brick sample count changed")
	var replay_left: Dictionary = MaterializerScript.materialize(
		body, material_catalog, profile, feature_catalog, grid_profile, left, 0
	)
	_assert(replay_left == left_snapshot, "MW2 brick materialization is non-deterministic")
	var interior_min: int = BrickLayoutScript.interior_min_index(grid_profile)
	var interior_max: int = BrickLayoutScript.interior_max_index(grid_profile)
	var axis_count: int = BrickLayoutScript.sample_axis_count(grid_profile)
	for z in range(axis_count):
		for y in range(axis_count):
			_assert(
				_snapshot_signature(left_snapshot, interior_max, y, z) \
					== _snapshot_signature(right_snapshot, interior_min, y, z),
				"Shared interior face mismatch at y=%d z=%d" % [y, z]
			)
			_assert(
				_snapshot_signature(left_snapshot, interior_max + 1, y, z) \
					== _snapshot_signature(right_snapshot, interior_min + 1, y, z),
				"Positive ghost overlap mismatch at y=%d z=%d" % [y, z]
			)
			_assert(
				_snapshot_signature(left_snapshot, interior_max - 1, y, z) \
					== _snapshot_signature(right_snapshot, interior_min - 1, y, z),
				"Negative ghost overlap mismatch at y=%d z=%d" % [y, z]
			)
	var face_position_left: Vector3 = BrickLayoutScript.sample_position_m(
		grid_profile, left, interior_max, interior_min + 3, interior_min + 5
	)
	var face_position_right: Vector3 = BrickLayoutScript.sample_position_m(
		grid_profile, right, interior_min, interior_min + 3, interior_min + 5
	)
	_assert(face_position_left == face_position_right, "Shared face positions are not bit-identical")


func _test_sparse_store() -> void:
	var store = SparseStoreScript.new()
	_assert_ok(store.configure(body, grid_profile), "Sparse store configuration failed")
	_assert(store.size() == 0, "Sparse store is not empty after configuration")
	var cell: Dictionary = CellGridScript.address_for_position(grid_profile, Vector3(450.0, 120.0, -80.0), 2)
	var snapshot0: Dictionary = MaterializerScript.materialize(
		body, material_catalog, profile, feature_catalog, grid_profile, cell, 0
	)
	var snapshot1: Dictionary = MaterializerScript.materialize(
		body, material_catalog, profile, feature_catalog, grid_profile, cell, 1
	)
	var undersized_snapshot: Dictionary = BrickSnapshotScript.create(
		"matter-snapshot/undersized/revision/0",
		snapshot0["address"],
		String(body["checksum"]),
		String(profile["generator_version"]),
		int(profile["generator_seed"]),
		0,
		[BrickSnapshotScript.sample_at(snapshot0, 0)]
	)
	_assert_ok(BrickSnapshotScript.validate(undersized_snapshot), "Undersized snapshot fixture rejected")
	_assert_fail(store.put(undersized_snapshot), "Sparse store accepted wrong lattice sample count")
	_assert_ok(store.put(snapshot0), "Sparse store rejected revision 0")
	_assert(store.size() == 1, "Sparse store size did not become one")
	var hash0: String = store.content_hash()
	_assert(MatterUtilsScript.is_lower_hex_64(hash0), "Sparse store hash is invalid")
	_assert_ok(store.put(snapshot0), "Sparse store rejected idempotent replay")
	_assert(store.content_hash() == hash0, "Idempotent replay changed sparse store hash")
	var typed_variant_conflict: Dictionary = snapshot0.duplicate(true)
	typed_variant_conflict["geometry_channel"]["occupancy_ratio"][0] = int(
		typed_variant_conflict["geometry_channel"]["occupancy_ratio"][0]
	)
	_assert_ok(BrickSnapshotScript.validate(typed_variant_conflict), "Typed-variant conflict fixture rejected")
	_assert(
		String(typed_variant_conflict["checksum"]) == String(snapshot0["checksum"]),
		"Typed-variant fixture unexpectedly changed canonical checksum"
	)
	_assert(typed_variant_conflict != snapshot0, "Typed-variant fixture did not change strict DTO")
	_assert_fail(store.put(typed_variant_conflict), "Sparse store accepted same-checksum typed mutation")
	var same_revision_conflict: Dictionary = snapshot0.duplicate(true)
	same_revision_conflict["snapshot_id"] = "matter-snapshot/conflict/revision/0"
	same_revision_conflict["checksum"] = MatterUtilsScript.compute_checksum(same_revision_conflict)
	_assert_ok(BrickSnapshotScript.validate(same_revision_conflict), "Same-revision conflict fixture rejected")
	_assert_fail(store.put(same_revision_conflict), "Sparse store accepted same-revision conflicting snapshot")
	var wrong_generator: Dictionary = snapshot0.duplicate(true)
	wrong_generator["generator_version"] = "1.0.1"
	wrong_generator["checksum"] = MatterUtilsScript.compute_checksum(wrong_generator)
	_assert_ok(BrickSnapshotScript.validate(wrong_generator), "Wrong-generator fixture rejected")
	_assert_fail(store.put(wrong_generator), "Sparse store accepted foreign generator version")
	_assert_ok(store.put(snapshot1), "Sparse store rejected revision 1")
	_assert(store.content_hash() != hash0, "Higher revision did not change sparse store hash")
	_assert_fail(store.put(snapshot0), "Sparse store accepted stale revision")
	var fetched: Dictionary = store.get_snapshot(snapshot1["address"])
	_assert(fetched == snapshot1, "Sparse store returned wrong snapshot")
	fetched["state_revision"] = 99
	_assert(int(store.get_snapshot(snapshot1["address"])["state_revision"]) == 1, "Sparse store leaked mutable snapshot reference")
	_assert_ok(store.erase(snapshot1["address"], 1), "Sparse store erase failed")
	_assert(store.size() == 0, "Sparse store did not erase snapshot")


func _test_query_service() -> void:
	var service = QueryServiceScript.new()
	_assert_ok(service.configure(body, material_catalog, profile, feature_catalog, grid_profile), "MW2 query service configuration failed")
	_assert(service.materialized_count() == 0, "Query service starts with materialized bricks")
	var cell: Dictionary = CellGridScript.address_for_position(grid_profile, Vector3(250.0, -100.0, 75.0), 3)
	var x: int = BrickLayoutScript.interior_min_index(grid_profile) + 3
	var y: int = BrickLayoutScript.interior_min_index(grid_profile) + 4
	var z: int = BrickLayoutScript.interior_min_index(grid_profile) + 2
	var lattice_position: Vector3 = BrickLayoutScript.sample_position_m(grid_profile, cell, x, y, z)
	var before: Dictionary = service.query_cell_lattice(cell, x, y, z)
	_assert_ok(QueryResultScript.validate(before), "Procedural lattice query rejected")
	_assert(String(before["source"]) == "PROCEDURAL_BASE", "Unmaterialized query did not use procedural base")
	var snapshot: Dictionary = service.materialize_cell(cell, 4)
	_assert_ok(BrickSnapshotScript.validate(snapshot), "Query service failed to materialize cell")
	_assert(service.materialized_count() == 1, "Query service materialized count is wrong")
	var after: Dictionary = service.query_cell_lattice(cell, x, y, z)
	_assert_ok(QueryResultScript.validate(after), "Materialized lattice query rejected")
	_assert(String(after["source"]) == "MATERIALIZED_BRICK", "Materialized query did not use brick")
	_assert(int(after["state_revision"]) == 4, "Materialized query revision changed")
	_assert(after["sample_lattice_index"] == [x, y, z], "Materialized query lattice index changed")
	_assert(after["sample"] == BrickSnapshotScript.sample_at(
		snapshot, BrickLayoutScript.flat_index(grid_profile, x, y, z)
	), "Materialized query sample mismatch")
	var owning_query: Dictionary = service.query(lattice_position, 3)
	_assert_ok(QueryResultScript.validate(owning_query), "Owning-cell query rejected")
	_assert(String(owning_query["source"]) == "MATERIALIZED_BRICK", "Exact owning-cell lattice query missed sparse brick")
	var off_lattice: Vector3 = lattice_position + Vector3(0.123, 0.057, -0.091)
	var off_result: Dictionary = service.query(off_lattice, 3)
	_assert_ok(QueryResultScript.validate(off_result), "Off-lattice procedural query rejected")
	_assert(String(off_result["source"]) == "PROCEDURAL_BASE", "Off-lattice query incorrectly snapped to brick")
	_assert(MatterUtilsScript.is_lower_hex_64(service.sparse_content_hash()), "Query service sparse hash is invalid")
	_assert(service.query(Vector3(2000.0, 0.0, 0.0), 3).is_empty(), "Out-of-root query returned a result")


func _test_negative_cases() -> void:
	var malformed_body: Dictionary = body.duplicate(true)
	malformed_body["checksum"] = "0".repeat(64)
	var direct_store = SparseStoreScript.new()
	_assert_fail(
		direct_store.configure(malformed_body, grid_profile),
		"Sparse store accepted invalid body definition"
	)
	var too_small_grid: Dictionary = GridProfileScript.create({
		"body_id": body["body_id"],
		"body_frame_id": body["body_frame_id"],
		"root_half_extent_m": 1200.0,
	})
	_assert_ok(GridProfileScript.validate(too_small_grid), "Small grid should be structurally valid")
	var service = QueryServiceScript.new()
	_assert_fail(
		service.configure(body, material_catalog, profile, feature_catalog, too_small_grid),
		"Query service accepted grid that does not contain the asteroid"
	)
	var shifted_grid: Dictionary = GridProfileScript.create({
		"body_id": body["body_id"],
		"body_frame_id": body["body_frame_id"],
		"root_center_m": [500.0, 0.0, 0.0],
		"root_half_extent_m": 1450.0,
	})
	_assert_ok(GridProfileScript.validate(shifted_grid), "Shifted grid fixture rejected")
	var shifted_service = QueryServiceScript.new()
	_assert_fail(
		shifted_service.configure(body, material_catalog, profile, feature_catalog, shifted_grid),
		"Query service accepted shifted grid that clips the asteroid"
	)
	var foreign_grid: Dictionary = GridProfileScript.create({
		"body_id": "body/foreign",
		"body_frame_id": "body/foreign/fixed",
		"root_half_extent_m": 1450.0,
	})
	_assert_ok(GridProfileScript.validate(foreign_grid), "Foreign grid fixture rejected")
	var foreign_service = QueryServiceScript.new()
	_assert_fail(
		foreign_service.configure(body, material_catalog, profile, feature_catalog, foreign_grid),
		"Query service accepted foreign body grid"
	)
	var root: Dictionary = CellGridScript.root_address(grid_profile)
	var invalid_child: Dictionary = CellGridScript.child(root, 8, grid_profile)
	_assert(invalid_child.is_empty(), "Octree child index 8 accepted")
	_assert(BrickLayoutScript.flat_index(grid_profile, -1, 0, 0) == -1, "Negative lattice index accepted")
	_assert(BrickLayoutScript.coordinates_from_flat_index(grid_profile, 1331).is_empty(), "Out-of-range flat index decoded")


func _cell_from_path(path: Array) -> Dictionary:
	var address: Dictionary = CellGridScript.root_address(grid_profile)
	for child_index in path:
		address = CellGridScript.child(address, int(child_index), grid_profile)
		if address.is_empty():
			return {}
	return address


func _snapshot_signature(snapshot: Dictionary, x: int, y: int, z: int) -> Dictionary:
	var index: int = BrickLayoutScript.flat_index(grid_profile, x, y, z)
	var geometry: Dictionary = snapshot["geometry_channel"]
	var composition_channel: Dictionary = snapshot["composition_channel"]
	var properties: Dictionary = snapshot["property_channel"]
	var palette_index: int = int(composition_channel["palette_indices"][index])
	return {
		"signed_distance_m": float(geometry["signed_distance_m"][index]),
		"occupancy_ratio": float(geometry["occupancy_ratio"][index]),
		"composition_checksum": String(composition_channel["palette"][palette_index]["checksum"]),
		"density_kg_m3": float(properties["density_kg_m3"][index]),
		"integrity_ratio": float(properties["integrity_ratio"][index]),
		"temperature_k": float(properties["temperature_k"][index]),
		"porosity_ratio": float(properties["porosity_ratio"][index]),
		"flags": Array(properties["flags"][index]).duplicate(),
	}


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _vector_equal(a: Vector3, b: Vector3, tolerance: float = 0.000000001) -> bool:
	return a.distance_to(b) <= tolerance


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
		print("MW2 sparse bricks and query: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MW2 sparse bricks and query: FAIL (%d failures / %d assertions)" % [failures.size(), assertions])
	quit(1)
