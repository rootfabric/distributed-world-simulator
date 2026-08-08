extends SceneTree

const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const GeodeticPosition = preload("res://scripts/simulation/procedural/contracts/geodetic_position.gd")
const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const SurfaceLodPolicy = preload("res://scripts/simulation/procedural/contracts/surface_lod_policy.gd")
const SphereBodyShapeProvider = preload("res://scripts/simulation/procedural/geodesy/sphere_body_shape_provider.gd")
const GeodesyService = preload("res://scripts/simulation/procedural/geodesy/geodesy_service.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const SurfaceLodSelector = preload("res://scripts/simulation/procedural/surface/surface_lod_selector.gd")
const SurfaceCellLifecycle = preload("res://scripts/simulation/procedural/surface/surface_cell_lifecycle.gd")

const BODY_ID := "body/procedural-g2"
const RECIPE_ID := "planet-recipe/g2-flat"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_run_fly_in_out()
	_finish()


func _run_fly_in_out() -> void:
	var definition := PlanetDefinition.create(BODY_ID, 2026080803, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)
	var geodesy = GeodesyService.new()
	_ok(geodesy.configure(definition, SphereBodyShapeProvider.new()), "geodesy configure")
	var policy := SurfaceLodPolicy.create(0, 8, 0.45, 0.3, 10.0, 1536)
	var selector = SurfaceLodSelector.new()
	_ok(selector.configure(definition, policy), "selector configure")
	var lifecycle = SurfaceCellLifecycle.new()

	var altitudes: Array[float] = [50000000.0, 10000000.0, 2000000.0, 500000.0, 100000.0, 50000.0, 10000.0, 2000.0, 500.0, 100.0, 10.0, 0.0]
	var previous_leaves: Array = []
	var previous_max_lod: int = -1
	var near_max_lod: int = 0
	for altitude_m in altitudes:
		var geo := GeodeticPosition.create(BODY_ID, 23.5, 41.25, altitude_m)
		var body_result: Dictionary = geodesy.geodetic_to_body(geo)
		_ok(body_result, "fly-in body")
		if not _success(body_result):
			continue
		var body: Dictionary = body_result["details"]["body_fixed_position"]
		var selected: Dictionary = selector.select_cells(body, previous_leaves)
		_ok(selected, "fly-in selection")
		if not _success(selected):
			continue
		var leaves: Array = selected["details"]["leaves"]
		var max_lod: int = int(selected["details"]["max_selected_lod"])
		_check(leaves.size() <= int(policy["max_leaf_cells"]), "fly-in budget bounded")
		_check(_is_leaf_cover_valid(leaves), "fly-in leaves contain no ancestor overlap")
		if previous_max_lod >= 0:
			_check(max_lod >= previous_max_lod - 1, "fly-in does not catastrophically coarsen")
		previous_max_lod = max_lod
		near_max_lod = maxi(near_max_lod, max_lod)
		var reconcile: Dictionary = lifecycle.reconcile(leaves)
		_ok(reconcile, "fly-in lifecycle reconcile")
		_check(lifecycle.size() <= int(policy["max_leaf_cells"]) * 2, "lifecycle bounded during handoff")
		_complete_lifecycle_handoff(lifecycle)
		previous_leaves = leaves
	_check(near_max_lod >= 4, "fly-in reaches meaningful refinement")

	var fly_out_altitudes: Array[float] = [1000.0, 10000.0, 100000.0, 500000.0, 2000000.0, 10000000.0, 50000000.0]
	var last_leaf_count: int = previous_leaves.size()
	for altitude_m in fly_out_altitudes:
		var geo := GeodeticPosition.create(BODY_ID, 23.5, 41.25, altitude_m)
		var body_result: Dictionary = geodesy.geodetic_to_body(geo)
		_ok(body_result, "fly-out body")
		if not _success(body_result):
			continue
		var selected: Dictionary = selector.select_cells(body_result["details"]["body_fixed_position"], previous_leaves)
		_ok(selected, "fly-out selection")
		if not _success(selected):
			continue
		var leaves: Array = selected["details"]["leaves"]
		_check(leaves.size() <= int(policy["max_leaf_cells"]), "fly-out budget bounded")
		if altitude_m >= 100000.0:
			_check(leaves.size() <= maxi(last_leaf_count + 64, last_leaf_count * 2), "fly-out no explosive leaf growth")
		last_leaf_count = leaves.size()
		_ok(lifecycle.reconcile(leaves), "fly-out lifecycle reconcile")
		_complete_lifecycle_handoff(lifecycle)
		previous_leaves = leaves
	_check(lifecycle.size() <= int(policy["max_leaf_cells"]), "retired cells are reclaimed")


func _complete_lifecycle_handoff(lifecycle) -> void:
	# Build the incoming cover first. Old ACTIVE cells stay in RETIRING until all
	# newly requested cells are ACTIVE, so a renderer can keep seamless coverage.
	var snapshot: Array = lifecycle.snapshot()
	for record in snapshot:
		var cell: Dictionary = record["cell"]
		if String(record["state"]) == SurfaceCellLifecycle.STATE_REQUESTED:
			_ok(lifecycle.begin_build(cell), "handoff requested->building")
			_ok(lifecycle.activate(cell), "handoff building->active")
	var after_build: Array = lifecycle.snapshot()
	for record in after_build:
		var cell: Dictionary = record["cell"]
		if String(record["state"]) == SurfaceCellLifecycle.STATE_RETIRING:
			_ok(lifecycle.complete_retire(cell), "handoff retiring->removed")


func _is_leaf_cover_valid(leaves: Array) -> bool:
	var tokens: Dictionary = {}
	for cell in leaves:
		tokens[SurfaceCellKey.token(cell)] = true
	for cell in leaves:
		var lod: int = int(cell["lod"])
		var x: int = int(cell["x"])
		var y: int = int(cell["y"])
		for ancestor_lod in range(lod - 1, -1, -1):
			var shift: int = lod - ancestor_lod
			var ancestor := SurfaceCellKey.create(
				String(cell["body_id"]), String(cell["face"]), ancestor_lod, x >> shift, y >> shift
			)
			if tokens.has(SurfaceCellKey.token(ancestor)):
				return false
	return true


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
		print("G2 fly-in/out LOD continuity: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G2 fly-in/out LOD continuity: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
