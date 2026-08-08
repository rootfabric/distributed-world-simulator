extends SceneTree

const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const PlanetEnvironment = preload("res://scripts/simulation/procedural/contracts/planet_environment.gd")
const PlanetRecipe = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")
const Context = preload("res://scripts/simulation/procedural/contracts/geo_generation_context.gd")
const SurfaceQuery = preload("res://scripts/simulation/procedural/contracts/geo_surface_query.gd")
const GeoSample = preload("res://scripts/simulation/procedural/contracts/geo_sample.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const GeoKernel = preload("res://scripts/simulation/procedural/geo_kernel.gd")
const MacroProvider = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")

const BODY_ID := "body/procedural-g3"
const RECIPE_ID := "planet-recipe/g3-casual"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const HEIGHT_FIELD := "geo/surface-height-m"
const SEED := 2026080801
const AMPLITUDE_M := 900.0
const WAVELENGTH_M := 600000.0
const HEIGHT_EPSILON := 0.00000001

var assertions: int = 0
var failures: Array[String] = []
var addressing = CubeSphereAddressing.new()
var provider = MacroProvider.new(SEED, RADIUS_M, AMPLITUDE_M, WAVELENGTH_M, 4, 0.5, 0.0)


func _init() -> void:
	_test_manifest_and_descriptor()
	_test_determinism_seed_and_radial_invariance()
	_test_height_bounds_and_macro_variation()
	_test_local_continuity()
	_test_cube_face_seam_continuity()
	_test_coarse_fine_shared_vertices()
	_test_geo_kernel_and_lod_invariance()
	_test_provider_source_boundary()
	_finish()


func _test_manifest_and_descriptor() -> void:
	var path := "res://config/procedural/g3-casual-macro-surface.v1.json"
	_check(FileAccess.file_exists(path), "G3 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G3 manifest JSON object")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g3-casual-macro-surface-v0", "G3 checkpoint")
		_check(String(parsed.get("implementation_branch", "")) == "feature/g3-casual-macro-surface", "G3 branch")
		_check(String(parsed.get("base_commit", "")) == "6319e1e312c7c663d5d05c0806f5a42cf68ad441", "G3 base")
		_check(not bool(parsed.get("runtime_worlds_changed", true)), "production runtime unchanged")
		_check(not bool(parsed.get("production_terrain_changed", true)), "production terrain unchanged")
		_check(not bool(parsed.get("canonical_world_semantics_depend_on_lod", true)), "macro truth independent from LOD")

	var descriptor: Dictionary = provider.get_descriptor()
	_check(String(descriptor.get("provider_id", "")) == MacroProvider.PROVIDER_ID, "provider id")
	_check(String(descriptor.get("contract_version", "")) == "1.0.0", "contract version")
	_check(String(descriptor.get("generator_version", "")) == "1.0.0", "generator version")
	_check(Array(descriptor.get("requires", [])).is_empty(), "macro v1 has no semantic dependencies")
	_check(Array(descriptor.get("provides", [])) == [HEIGHT_FIELD], "macro provides height")
	_check(bool(descriptor.get("deterministic", false)), "macro deterministic descriptor")
	var params: Dictionary = descriptor.get("parameters", {})
	_check(int(params.get("seed", -1)) == SEED, "seed in provenance")
	_check(_approx(float(params.get("amplitude_m", -1.0)), AMPLITUDE_M, 0.0), "amplitude in provenance")
	_check(_approx(float(params.get("base_wavelength_m", -1.0)), WAVELENGTH_M, 0.0), "wavelength in provenance")
	_check(String(params.get("domain", "")) == "body-fixed-unit-direction-v1", "global direction domain")

	var changed_seed = MacroProvider.new(SEED + 1, RADIUS_M, AMPLITUDE_M, WAVELENGTH_M, 4, 0.5, 0.0)
	_check(provider.get_descriptor()["checksum"] != changed_seed.get_descriptor()["checksum"], "seed changes descriptor provenance")
	var changed_shape = MacroProvider.new(SEED, RADIUS_M, AMPLITUDE_M * 2.0, WAVELENGTH_M, 4, 0.5, 0.0)
	_check(provider.get_descriptor()["checksum"] != changed_shape.get_descriptor()["checksum"], "amplitude changes descriptor provenance")


func _test_determinism_seed_and_radial_invariance() -> void:
	var second = MacroProvider.new(SEED, RADIUS_M, AMPLITUDE_M, WAVELENGTH_M, 4, 0.5, 0.0)
	var different = MacroProvider.new(SEED + 77, RADIUS_M, AMPLITUDE_M, WAVELENGTH_M, 4, 0.5, 0.0)
	var changed_points: int = 0
	for latitude_deg in [-80.0, -55.0, -25.0, 0.0, 17.0, 43.0, 75.0]:
		for longitude_deg in [-170.0, -120.0, -65.0, -10.0, 35.0, 95.0, 155.0]:
			var direction := _direction_from_lat_lon(latitude_deg, longitude_deg)
			var h1 := _height(provider, direction * RADIUS_M)
			var h2 := _height(second, direction * RADIUS_M)
			var hd := _height(different, direction * RADIUS_M)
			_check(_approx(h1, h2, 0.0), "same seed exact deterministic")
			if absf(h1 - hd) > 0.001:
				changed_points += 1
			for radius in [RADIUS_M - 1000.0, RADIUS_M, RADIUS_M + 100.0, RADIUS_M + 50000.0, RADIUS_M + 1000000.0]:
				var hr := _height(provider, direction * radius)
				_check(_approx(h1, hr, HEIGHT_EPSILON), "height independent from query radius")
	_check(changed_points >= 40, "different seed changes global macro form")


func _test_height_bounds_and_macro_variation() -> void:
	var minimum: float = INF
	var maximum: float = -INF
	var sum: float = 0.0
	var count: int = 0
	for lat_i in range(-8, 9):
		var lat: float = float(lat_i) * 10.0
		for lon_i in range(36):
			var lon: float = -180.0 + float(lon_i) * 10.0
			var h := _height(provider, _direction_from_lat_lon(lat, lon) * RADIUS_M)
			_check(is_finite(h), "height finite")
			_check(h >= -AMPLITUDE_M - HEIGHT_EPSILON and h <= AMPLITUDE_M + HEIGHT_EPSILON, "height bounded by configured amplitude")
			minimum = minf(minimum, h)
			maximum = maxf(maximum, h)
			sum += h
			count += 1
	_check(count > 500, "global sample density")
	_check(maximum - minimum > 400.0, "macro surface has visible relief span")
	_check(absf(sum / float(count)) < AMPLITUDE_M * 0.5, "macro field not collapsed to one sign")


func _test_local_continuity() -> void:
	# Probe multiple places with arc-scale offsets. G3 does not promise slope or
	# erosion semantics yet, only that its kilometer-scale macro field is smooth.
	for latitude_deg in [-60.0, -25.0, 0.0, 30.0, 65.0]:
		for longitude_deg in [-145.0, -70.0, 0.0, 77.0, 149.0]:
			var base := _direction_from_lat_lon(latitude_deg, longitude_deg)
			var h0 := _height(provider, base * RADIUS_M)
			for arc_m in [1.0, 10.0, 100.0, 1000.0]:
				var delta_deg: float = rad_to_deg(arc_m / RADIUS_M)
				var shifted := _direction_from_lat_lon(latitude_deg, longitude_deg + delta_deg)
				var h1 := _height(provider, shifted * RADIUS_M)
				var max_delta: float = 1.0 + arc_m * 0.05
				_check(absf(h1 - h0) <= max_delta, "macro continuity at %.1f m arc" % arc_m)


func _test_cube_face_seam_continuity() -> void:
	# Every same-level seam through LOD3 must agree at the two shared geometric
	# edge corners. The provider never sees cell identity, only the shared 3D point.
	for lod in range(0, 4):
		var side: int = 1 << lod
		for face in SurfaceCellKey.FACES:
			for y in range(side):
				for x in range(side):
					var cell := SurfaceCellKey.create(BODY_ID, face, lod, x, y)
					for edge in CubeSphereAddressing.NEIGHBOR_DIRECTIONS:
						var nr: Dictionary = addressing.neighbor(cell, edge)
						_ok(nr, "seam neighbor")
						if not _success(nr):
							continue
						_assert_shared_edge_heights(cell, nr["details"]["cell"])


func _assert_shared_edge_heights(a: Dictionary, b: Dictionary) -> void:
	var ar: Dictionary = addressing.cell_corner_directions(a)
	var br: Dictionary = addressing.cell_corner_directions(b)
	_ok(ar, "A corners")
	_ok(br, "B corners")
	if not _success(ar) or not _success(br):
		return
	var shared: int = 0
	for ac in ar["details"]["corners"]:
		for bc in br["details"]["corners"]:
			if _vector(Array(ac)).distance_to(_vector(Array(bc))) <= 0.00000001:
				shared += 1
				var ha := _height(provider, _vector(Array(ac)) * RADIUS_M)
				var hb := _height(provider, _vector(Array(bc)) * RADIUS_M)
				_check(_approx(ha, hb, 0.000001), "shared seam point has same macro height")
				break
	_check(shared >= 2, "neighbor has shared geometric edge")


func _test_coarse_fine_shared_vertices() -> void:
	for face in SurfaceCellKey.FACES:
		for lod in [0, 2, 5, 8]:
			var side: int = 1 << lod
			var x: int = min(side - 1, side / 3)
			var y: int = min(side - 1, side / 2)
			var parent := SurfaceCellKey.create(BODY_ID, face, lod, x, y)
			var children_result: Dictionary = addressing.children(parent)
			_ok(children_result, "children for shared macro vertices")
			if not _success(children_result):
				continue
			var parent_corners: Dictionary = addressing.cell_corner_directions(parent)
			_ok(parent_corners, "parent corners")
			if not _success(parent_corners):
				continue
			var child_corners: Array = []
			for child in children_result["details"]["cells"]:
				var cr: Dictionary = addressing.cell_corner_directions(child)
				_ok(cr, "child corners")
				if _success(cr):
					child_corners.append_array(cr["details"]["corners"])
			for pc in parent_corners["details"]["corners"]:
				var matched: bool = false
				for cc in child_corners:
					if _vector(Array(pc)).distance_to(_vector(Array(cc))) <= 0.00000001:
						matched = true
						_check(_approx(
							_height(provider, _vector(Array(pc)) * RADIUS_M),
							_height(provider, _vector(Array(cc)) * RADIUS_M),
							0.000001
						), "coarse/fine shared vertex height stable")
						break
				_check(matched, "parent corner survives refinement")


func _test_geo_kernel_and_lod_invariance() -> void:
	var environment := PlanetEnvironment.create(
		"planet-environment/g3-neutral",
		"gravity-model/unspecified",
		"atmosphere-model/unspecified",
		"temperature-model/unspecified",
		"fluid-catalog/none",
		"weathering-model/none",
		"material-catalog/unspecified",
		{}
	)
	var recipe := PlanetRecipe.create(RECIPE_ID, "1.0.0", environment, [provider.get_descriptor()])
	var definition := PlanetDefinition.create(BODY_ID, SEED, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)
	var kernel = GeoKernel.new()
	_ok(kernel.configure(definition, recipe, [provider]), "GeoKernel with casual macro provider")

	var direction := _direction_from_lat_lon(37.25, -122.5)
	var position := direction * RADIUS_M
	var query := SurfaceQuery.create(BODY_ID, [position.x, position.y, position.z], [HEIGHT_FIELD])
	var reference_height: float = NAN
	var reference_manifest: String = ""
	for resolution_m in [100000.0, 10000.0, 1000.0, 100.0, 10.0, 1.0]:
		var context := Context.create(BODY_ID, "geo-scope/g3", resolution_m, resolution_m * 0.25, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
		var result: Dictionary = kernel.sample_surface(context, query)
		_ok(result, "kernel sample at %.1f m resolution" % resolution_m)
		if not _success(result):
			continue
		var sample: Dictionary = result["details"]["sample"]
		var height: float = float(GeoSample.field_value(sample, HEIGHT_FIELD, NAN))
		_check(is_finite(height), "kernel height finite")
		if is_nan(reference_height):
			reference_height = height
			reference_manifest = String(sample["provider_manifest_hash"])
		else:
			_check(_approx(height, reference_height, 0.0), "resolution does not change canonical macro height")
			_check(String(sample["provider_manifest_hash"]) == reference_manifest, "resolution does not change provider provenance")

	var body := BodyFixedPosition.create(BODY_ID, [position.x, position.y, position.z])
	var cell_tokens: Dictionary = {}
	for lod in [0, 2, 5, 9, 14]:
		var cell_result: Dictionary = addressing.body_position_to_cell(body, lod)
		_ok(cell_result, "same macro point address at LOD %d" % lod)
		if _success(cell_result):
			cell_tokens[SurfaceCellKey.token(cell_result["details"]["cell"])] = true
		var context := Context.create(BODY_ID, "geo-scope/g3-lod", maxf(1.0, 100000.0 / pow(2.0, lod)), 10.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
		var result: Dictionary = kernel.sample_surface(context, query)
		_ok(result, "sample after LOD address %d" % lod)
		if _success(result):
			_check(_approx(float(GeoSample.field_value(result["details"]["sample"], HEIGHT_FIELD, NAN)), reference_height, 0.0), "LOD does not change macro world truth")
	_check(cell_tokens.size() == 5, "point obtains distinct representation scopes across LOD")


func _test_provider_source_boundary() -> void:
	var path := "res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd"
	var source := FileAccess.get_file_as_string(path)
	_check(not source.is_empty(), "macro provider source exists")
	for forbidden in [
		"extends Node", "extends SceneTree", "MeshInstance3D", "ArrayMesh", "ImmediateMesh",
		"RenderingServer", "Terrain3D", "VoxelLodTerrain", "Camera3D", "SurfaceCellKey",
		"CubeSphereAddressing", "face_uv", "cell_uv", "RandomNumberGenerator", "randf(", "randi(",
	]:
		_check(not source.contains(forbidden), "provider has no forbidden coupling: %s" % forbidden)
	_check(source.contains("body-fixed-unit-direction-v1"), "provider declares global body-fixed domain")


func _height(target_provider, position: Vector3) -> float:
	var query := SurfaceQuery.create(BODY_ID, [position.x, position.y, position.z], [HEIGHT_FIELD])
	var result: Dictionary = target_provider.sample_surface({}, query, {})
	if not _success(result):
		failures.append("direct macro sample failed: %s" % String(result.get("error_code", "")))
		return NAN
	return float(result["details"]["values"][HEIGHT_FIELD])


func _direction_from_lat_lon(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat: float = deg_to_rad(latitude_deg)
	var lon: float = deg_to_rad(longitude_deg)
	var cos_lat: float = cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _approx(a: float, b: float, tolerance: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= tolerance


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s" % [label, String(result.get("error_code", ""))])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G3 casual macro surface: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G3 casual macro surface: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
