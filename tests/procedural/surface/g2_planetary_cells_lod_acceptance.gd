extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const PlanetEnvironment = preload("res://scripts/simulation/procedural/contracts/planet_environment.gd")
const PlanetRecipe = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")
const Context = preload("res://scripts/simulation/procedural/contracts/geo_generation_context.gd")
const SurfaceQuery = preload("res://scripts/simulation/procedural/contracts/geo_surface_query.gd")
const GeoSample = preload("res://scripts/simulation/procedural/contracts/geo_sample.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const SurfaceLodPolicy = preload("res://scripts/simulation/procedural/contracts/surface_lod_policy.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const SurfaceLodSelector = preload("res://scripts/simulation/procedural/surface/surface_lod_selector.gd")
const SurfaceCellLifecycle = preload("res://scripts/simulation/procedural/surface/surface_cell_lifecycle.gd")
const GeoKernel = preload("res://scripts/simulation/procedural/geo_kernel.gd")
const FlatProvider = preload("res://scripts/simulation/procedural/providers/flat_surface_provider.gd")

const BODY_ID := "body/procedural-g2"
const RECIPE_ID := "planet-recipe/g2-flat"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const HEIGHT_FIELD := "geo/surface-height-m"
const VECTOR_TOLERANCE := 0.000000001

var assertions: int = 0
var failures: Array[String] = []
var addressing = CubeSphereAddressing.new()


func _init() -> void:
	_test_manifest()
	_test_cell_key_contract()
	_test_face_centers_and_direction_addressing()
	_test_quadtree_parent_children()
	_test_same_level_neighbors_and_boundaries()
	_test_lod_policy_and_hysteresis()
	_test_lod_selection_determinism_and_budget()
	_test_lifecycle()
	_test_geo_semantics_independent_from_lod()
	_test_source_boundaries()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g2-planetary-cells-lod.v1.json"
	_check(FileAccess.file_exists(path), "G2 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G2 manifest JSON object")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g2-planetary-cells-lod-v0", "G2 manifest checkpoint")
		_check(String(parsed.get("implementation_branch", "")) == "feature/g2-planetary-cells-lod", "G2 manifest branch")
		_check(String(parsed.get("base_commit", "")) == "b30b1cad64a7176f2e3155fbe5cea2ec811c2e7a", "G2 manifest base")
		_check(not bool(parsed.get("runtime_worlds_changed", true)), "G2 runtime worlds unchanged")
		_check(not bool(parsed.get("production_terrain_changed", true)), "G2 production terrain unchanged")
		_check(not bool(parsed.get("canonical_world_semantics_changed_by_lod", true)), "LOD does not change world semantics")
	_check(FileAccess.file_exists("res://scenes/labs/procedural/g2_planetary_cells_lab.tscn"), "G2 debug lab scene exists")


func _test_cell_key_contract() -> void:
	var root := SurfaceCellKey.create(BODY_ID, "px", 0, 0, 0)
	_ok(SurfaceCellKey.validate(root), "root key")
	_check(String(root["face"]) == "PX", "face canonicalized")
	_check(not SurfaceCellKey.token(root).is_empty(), "cell token")
	_check(SurfaceCellKey.normalize(root) == root, "cell normalization")

	var bad_face := SurfaceCellKey.create(BODY_ID, "QQ", 0, 0, 0)
	_error(SurfaceCellKey.validate(bad_face), "INVALID_SURFACE_CELL_FACE", "bad face")
	var bad_lod := SurfaceCellKey.create(BODY_ID, "PX", SurfaceCellKey.MAX_LOD + 1, 0, 0)
	_error(SurfaceCellKey.validate(bad_lod), "SURFACE_CELL_LOD_OUT_OF_RANGE", "bad lod")
	var bad_xy := SurfaceCellKey.create(BODY_ID, "PX", 2, 4, 0)
	_error(SurfaceCellKey.validate(bad_xy), "SURFACE_CELL_COORDINATE_OUT_OF_RANGE", "bad coordinate")

	var roots_result: Dictionary = addressing.root_cells(BODY_ID)
	_ok(roots_result, "root cells")
	if _success(roots_result):
		var roots: Array = roots_result["details"]["cells"]
		_check(roots.size() == 6, "six cube roots")
		var faces: Array[String] = []
		for cell in roots:
			faces.append(String(cell["face"]))
		_check(faces == SurfaceCellKey.FACES, "root face order canonical")


func _test_face_centers_and_direction_addressing() -> void:
	var expected := {
		"PX": [1.0, 0.0, 0.0],
		"NX": [-1.0, 0.0, 0.0],
		"PY": [0.0, 1.0, 0.0],
		"NY": [0.0, -1.0, 0.0],
		"PZ": [0.0, 0.0, 1.0],
		"NZ": [0.0, 0.0, -1.0],
	}
	for face in SurfaceCellKey.FACES:
		var root := SurfaceCellKey.create(BODY_ID, face, 0, 0, 0)
		var center: Dictionary = addressing.cell_center_direction(root)
		_ok(center, "center %s" % face)
		if _success(center):
			_check(_vector_distance(Array(center["details"]["direction"]), expected[face]) <= VECTOR_TOLERANCE, "face center %s" % face)

	for direction in [
		[1.0, 0.1, 0.2],
		[-1.0, -0.2, 0.3],
		[0.2, 1.0, -0.4],
		[-0.3, -1.0, -0.5],
		[-0.4, 0.2, 1.0],
		[0.3, -0.4, -1.0],
	]:
		var face_uv: Dictionary = addressing.direction_to_face_uv(direction)
		_ok(face_uv, "direction to face")
		if not _success(face_uv):
			continue
		var rebuilt: Dictionary = addressing.face_uv_to_direction(
			String(face_uv["details"]["face"]),
			float(face_uv["details"]["u"]),
			float(face_uv["details"]["v"])
		)
		_ok(rebuilt, "face to direction")
		if _success(rebuilt):
			_check(_vector(Array(rebuilt["details"]["direction"])).dot(_vector(direction).normalized()) >= 1.0 - VECTOR_TOLERANCE, "direction roundtrip")

	var body := BodyFixedPosition.create(BODY_ID, [RADIUS_M, 123.0, 456.0])
	var cell_result: Dictionary = addressing.body_position_to_cell(body, 8)
	_ok(cell_result, "body to cell")
	if _success(cell_result):
		_check(int(cell_result["details"]["cell"]["lod"]) == 8, "body cell lod")
		_check(String(cell_result["details"]["cell"]["face"]) == "PX", "body cell face")

	_error(addressing.direction_to_face_uv([0.0, 0.0, 0.0]), "ZERO_CUBE_SPHERE_DIRECTION", "zero direction")
	_error(addressing.direction_to_face_uv([NAN, 0.0, 1.0]), "INVALID_CUBE_SPHERE_DIRECTION", "NaN direction")


func _test_quadtree_parent_children() -> void:
	var root := SurfaceCellKey.create(BODY_ID, "PX", 0, 0, 0)
	_error(addressing.parent(root), "SURFACE_CELL_ROOT_HAS_NO_PARENT", "root parent")
	var children_result: Dictionary = addressing.children(root)
	_ok(children_result, "root children")
	if not _success(children_result):
		return
	var children: Array = children_result["details"]["cells"]
	_check(children.size() == 4, "four children")
	var tokens: Dictionary = {}
	for child in children:
		_ok(SurfaceCellKey.validate(child), "child valid")
		_check(int(child["lod"]) == 1, "child lod")
		tokens[SurfaceCellKey.token(child)] = true
		var parent_result: Dictionary = addressing.parent(child)
		_ok(parent_result, "child parent")
		if _success(parent_result):
			_check(parent_result["details"]["cell"] == root, "parent roundtrip")
	_check(tokens.size() == 4, "children unique")

	var deep := SurfaceCellKey.create(BODY_ID, "NZ", 9, 341, 177)
	var cursor := deep
	for expected_lod in range(8, -1, -1):
		var parent_result: Dictionary = addressing.parent(cursor)
		_ok(parent_result, "deep parent")
		if not _success(parent_result):
			break
		cursor = parent_result["details"]["cell"]
		_check(int(cursor["lod"]) == expected_lod, "deep parent lod")
	_check(int(cursor["lod"]) == 0, "deep reaches root")


func _test_same_level_neighbors_and_boundaries() -> void:
	# Exhaust every cell through LOD3, then probe all six face boundaries at
	# higher LODs. This keeps the focused runner fast while still covering every
	# face transform and both edge orientations.
	for lod in range(0, 4):
		var side: int = 1 << lod
		for face in SurfaceCellKey.FACES:
			for y in range(side):
				for x in range(side):
					_assert_all_neighbors(SurfaceCellKey.create(BODY_ID, face, lod, x, y))
	for lod in [4, 8, 12]:
		var side: int = 1 << lod
		var samples: Array[int] = [0, side / 4, side / 2, side - 1]
		for face in SurfaceCellKey.FACES:
			for sample in samples:
				_assert_all_neighbors(SurfaceCellKey.create(BODY_ID, face, lod, 0, sample))
				_assert_all_neighbors(SurfaceCellKey.create(BODY_ID, face, lod, side - 1, sample))
				_assert_all_neighbors(SurfaceCellKey.create(BODY_ID, face, lod, sample, 0))
				_assert_all_neighbors(SurfaceCellKey.create(BODY_ID, face, lod, sample, side - 1))


func _assert_all_neighbors(cell: Dictionary) -> void:
	var lod: int = int(cell["lod"])
	for direction in CubeSphereAddressing.NEIGHBOR_DIRECTIONS:
		var neighbor_result: Dictionary = addressing.neighbor(cell, direction)
		_ok(neighbor_result, "neighbor %s L%d" % [direction, lod])
		if not _success(neighbor_result):
			continue
		var neighbor: Dictionary = neighbor_result["details"]["cell"]
		_check(int(neighbor["lod"]) == lod, "neighbor same lod")
		_check(SurfaceCellKey.token(neighbor) != SurfaceCellKey.token(cell), "neighbor distinct")
		_check(_neighbor_set_contains(neighbor, cell), "neighbor relationship reciprocal by some edge")
		_check(_shared_corner_count(cell, neighbor) >= 2, "neighbor shares edge corners")


func _test_lod_policy_and_hysteresis() -> void:
	var policy := SurfaceLodPolicy.create(0, 6, 0.5, 0.3, 1.0, 4096)
	_ok(SurfaceLodPolicy.validate(policy), "lod policy")
	var bad_hysteresis := SurfaceLodPolicy.create(0, 6, 0.3, 0.3, 1.0, 4096)
	_error(SurfaceLodPolicy.validate(bad_hysteresis), "INVALID_SURFACE_LOD_HYSTERESIS", "lod hysteresis")
	var impossible_min_budget := SurfaceLodPolicy.create(3, 6, 0.5, 0.3, 1.0, 100)
	_error(SurfaceLodPolicy.validate(impossible_min_budget), "SURFACE_LOD_LEAF_BUDGET_BELOW_MIN_LOD", "min lod budget")

	var selector = SurfaceLodSelector.new()
	_ok(selector.configure(_definition(), policy), "lod selector configure")
	var root := SurfaceCellKey.create(BODY_ID, "PX", 0, 0, 0)
	var edge_m: float = RADIUS_M * PI * 0.5
	var middle_ratio: float = 0.4
	var distance_m: float = edge_m / middle_ratio
	var observer := BodyFixedPosition.create(BODY_ID, [RADIUS_M + distance_m, 0.0, 0.0])
	var fresh: Dictionary = selector.evaluate_cell(root, observer, false)
	var split: Dictionary = selector.evaluate_cell(root, observer, true)
	_ok(fresh, "fresh lod evaluation")
	_ok(split, "split lod evaluation")
	if _success(fresh) and _success(split):
		_check(not bool(fresh["details"]["should_refine"]), "fresh cell waits above refine threshold")
		_check(bool(split["details"]["should_refine"]), "previous split retained inside hysteresis band")
		_check(_approx(float(fresh["details"]["ratio"]), middle_ratio, 0.000000001), "hysteresis ratio")


func _test_lod_selection_determinism_and_budget() -> void:
	var policy := SurfaceLodPolicy.create(0, 7, 0.45, 0.3, 10.0, 1024)
	var selector = SurfaceLodSelector.new()
	_ok(selector.configure(_definition(), policy), "selector configure")
	var near_observer := BodyFixedPosition.create(BODY_ID, [RADIUS_M + 50000.0, 0.0, 0.0])
	var first: Dictionary = selector.select_cells(near_observer)
	_ok(first, "near selection")
	if not _success(first):
		return
	var leaves: Array = first["details"]["leaves"]
	_check(leaves.size() >= 6, "selection covers roots")
	_check(leaves.size() <= int(policy["max_leaf_cells"]), "selection honors budget")
	_check(int(first["details"]["max_selected_lod"]) > 0, "near selection refines")
	_check(not String(first["details"]["selection_hash"]).is_empty(), "selection hash")

	var second: Dictionary = selector.select_cells(near_observer)
	_ok(second, "repeat selection")
	if _success(second):
		_check(first["details"]["selection_hash"] == second["details"]["selection_hash"], "same input same selection")
		_check(first["details"]["leaves"] == second["details"]["leaves"], "same leaves deterministic")

	var reversed_previous := leaves.duplicate(true)
	reversed_previous.reverse()
	var with_previous_a: Dictionary = selector.select_cells(near_observer, leaves)
	var with_previous_b: Dictionary = selector.select_cells(near_observer, reversed_previous)
	_ok(with_previous_a, "previous selection A")
	_ok(with_previous_b, "previous selection B")
	if _success(with_previous_a) and _success(with_previous_b):
		_check(with_previous_a["details"]["selection_hash"] == with_previous_b["details"]["selection_hash"], "previous order independent")

	var far_observer := BodyFixedPosition.create(BODY_ID, [RADIUS_M + 50000000.0, 0.0, 0.0])
	var far: Dictionary = selector.select_cells(far_observer, leaves)
	_ok(far, "far selection")
	if _success(far):
		_check(int(far["details"]["leaf_count"]) <= int(first["details"]["leaf_count"]), "fly out does not increase leaves")
		_check(int(far["details"]["max_selected_lod"]) <= int(first["details"]["max_selected_lod"]), "fly out does not refine")

	var wrong_body := BodyFixedPosition.create("body/other", [RADIUS_M, 0.0, 0.0])
	_error(selector.select_cells(wrong_body), "SURFACE_LOD_BODY_MISMATCH", "selector body mismatch")


func _test_lifecycle() -> void:
	var lifecycle = SurfaceCellLifecycle.new()
	var a := SurfaceCellKey.create(BODY_ID, "PX", 2, 1, 1)
	var b := SurfaceCellKey.create(BODY_ID, "PX", 2, 2, 1)
	var first: Dictionary = lifecycle.reconcile([b, a])
	_ok(first, "lifecycle initial reconcile")
	_check(lifecycle.size() == 2, "lifecycle creates two")
	_check(lifecycle.get_state(a) == SurfaceCellLifecycle.STATE_REQUESTED, "A requested")
	_check(lifecycle.get_state(b) == SurfaceCellLifecycle.STATE_REQUESTED, "B requested")
	_ok(lifecycle.begin_build(a), "A building")
	_check(lifecycle.get_state(a) == SurfaceCellLifecycle.STATE_BUILDING, "A building state")
	_ok(lifecycle.activate(a), "A active")
	_check(lifecycle.get_state(a) == SurfaceCellLifecycle.STATE_ACTIVE, "A active state")

	var retire: Dictionary = lifecycle.reconcile([])
	_ok(retire, "retire all")
	_check(lifecycle.get_state(a) == SurfaceCellLifecycle.STATE_RETIRING, "A retiring")
	_check(lifecycle.get_state(b) == SurfaceCellLifecycle.STATE_RETIRING, "B retiring")

	var revive: Dictionary = lifecycle.reconcile([a, b])
	_ok(revive, "revive")
	_check(lifecycle.get_state(a) == SurfaceCellLifecycle.STATE_ACTIVE, "active artifact revives active")
	_check(lifecycle.get_state(b) == SurfaceCellLifecycle.STATE_REQUESTED, "unbuilt artifact revives requested")

	_error(lifecycle.activate(b), "INVALID_SURFACE_CELL_LIFECYCLE_TRANSITION", "cannot activate before building")
	_ok(lifecycle.begin_build(b), "B building")
	_ok(lifecycle.activate(b), "B active")
	_ok(lifecycle.begin_retire(a), "A explicit retire")
	_ok(lifecycle.complete_retire(a), "A complete retire")
	_check(lifecycle.get_state(a).is_empty(), "A removed")
	_check(lifecycle.size() == 1, "one lifecycle record remains")
	var snapshot: Array = lifecycle.snapshot()
	_check(snapshot.size() == 1 and String(snapshot[0]["state"]) == SurfaceCellLifecycle.STATE_ACTIVE, "snapshot stable")


func _test_geo_semantics_independent_from_lod() -> void:
	var provider = FlatProvider.new(12.5)
	var environment := PlanetEnvironment.create(
		"planet-environment/g2-neutral",
		"gravity-model/unspecified",
		"atmosphere-model/unspecified",
		"temperature-model/unspecified",
		"fluid-catalog/none",
		"weathering-model/none",
		"material-catalog/unspecified",
		{}
	)
	var recipe := PlanetRecipe.create(RECIPE_ID, "1.0.0", environment, [provider.get_descriptor()])
	var kernel = GeoKernel.new()
	_ok(kernel.configure(_definition(), recipe, [provider]), "G0 kernel under G2")
	var context := Context.create(BODY_ID, "geo-scope/g2", 1000.0, 100.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
	var position := [RADIUS_M + 100.0, 1234.5, -777.25]
	var query := SurfaceQuery.create(BODY_ID, position, [HEIGHT_FIELD])
	var before: Dictionary = kernel.sample_surface(context, query)
	_ok(before, "geo sample before lod")

	var body := BodyFixedPosition.create(BODY_ID, position)
	for lod in [0, 2, 5, 9, 14]:
		var cell_result: Dictionary = addressing.body_position_to_cell(body, lod)
		_ok(cell_result, "address same point at LOD %d" % lod)

	var after: Dictionary = kernel.sample_surface(context, query)
	_ok(after, "geo sample after lod")
	if _success(before) and _success(after):
		_check(before["details"]["sample"] == after["details"]["sample"], "GeoSample independent from LOD addressing")
		_check(_approx(float(GeoSample.field_value(after["details"]["sample"], HEIGHT_FIELD, NAN)), 12.5, 0.0), "flat semantic value unchanged")


func _test_source_boundaries() -> void:
	var paths: Array[String] = [
		"res://scripts/simulation/procedural/contracts/surface_cell_key.gd",
		"res://scripts/simulation/procedural/contracts/surface_lod_policy.gd",
		"res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd",
		"res://scripts/simulation/procedural/surface/surface_lod_selector.gd",
		"res://scripts/simulation/procedural/surface/surface_cell_lifecycle.gd",
	]
	var forbidden := [
		"extends Node", "extends SceneTree", "MeshInstance3D", "ArrayMesh", "RenderingServer",
		"Terrain3D", "VoxelLodTerrain", "Camera3D", "MultiplayerPeer", "RandomNumberGenerator",
		"randf(", "randi(", "GeoKernel.new()",
	]
	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		_check(not source.is_empty(), "source exists: %s" % path)
		for marker in forbidden:
			_check(not source.contains(marker), "no %s in %s" % [marker, path])


func _definition() -> Dictionary:
	return PlanetDefinition.create(BODY_ID, 2026080803, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)


func _neighbor_set_contains(from_cell: Dictionary, target: Dictionary) -> bool:
	var target_token: String = SurfaceCellKey.token(target)
	for direction in CubeSphereAddressing.NEIGHBOR_DIRECTIONS:
		var result: Dictionary = addressing.neighbor(from_cell, direction)
		if _success(result) and SurfaceCellKey.token(result["details"]["cell"]) == target_token:
			return true
	return false


func _shared_corner_count(a: Dictionary, b: Dictionary) -> int:
	var a_result: Dictionary = addressing.cell_corner_directions(a)
	var b_result: Dictionary = addressing.cell_corner_directions(b)
	if not _success(a_result) or not _success(b_result):
		return 0
	var matches: int = 0
	for a_corner in a_result["details"]["corners"]:
		for b_corner in b_result["details"]["corners"]:
			if _vector_distance(Array(a_corner), Array(b_corner)) <= 0.00000001:
				matches += 1
				break
	return matches


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _vector_distance(a: Array, b: Array) -> float:
	return _vector(a).distance_to(_vector(b))


func _approx(a: float, b: float, tolerance: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= tolerance


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s" % [label, String(result.get("error_code", ""))])


func _error(result: Dictionary, code: String, label: String) -> void:
	_check(not _success(result), "%s unexpectedly succeeded" % label)
	if not _success(result):
		_check(String(result.get("error_code", "")) == code, "%s expected %s got %s" % [label, code, String(result.get("error_code", ""))])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G2 planetary cells + LOD: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G2 planetary cells + LOD: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
