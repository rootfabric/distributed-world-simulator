extends SceneTree

const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const RiverSpline = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const WaterSurfaceQuery = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_hydrology_fixture_factory.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var provider = Fixture.provider()
	_check(provider != null, "provider configures")
	if provider == null:
		_finish()
		return
	var feature: Dictionary = provider.river_feature()
	var canonical_feature_id := String(feature["feature_id"])
	var canonical_region_id := String(provider.fluid_surface_descriptor()["fluid_region_id"])
	var canonical_manifest: String = String(provider.manifest_hash())
	var addressing = CubeSphereAddressing.new()
	var spline := Fixture.river_spline()
	var all_lod_cell_sets: Dictionary = {}

	for lod in [2, 4, 8, 12]:
		var cell_tokens: Dictionary = {}
		var faces: Dictionary = {}
		for point_value in spline["points"]:
			var position: Array = point_value["position_m"]
			var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, position, lod)
			_ok(addressed, "river point addressed at LOD %d" % lod)
			if not _success(addressed):
				continue
			var cell: Dictionary = addressed["details"]["cell"]
			cell_tokens[SurfaceCellKey.identity_token(cell)] = true
			faces[String(cell["face"])] = true
		_check(cell_tokens.size() >= 2, "river spans multiple representation cells at LOD %d" % lod)
		_check(faces.has("PX") and faces.has("PZ"), "river crosses PX/PZ seam at LOD %d" % lod)
		all_lod_cell_sets[lod] = cell_tokens.keys()

		# Canonical query never receives the representation cell or LOD.
		var canonical_position := RiverSpline.sample(spline, 0.55)
		_ok(canonical_position, "canonical river sample at LOD %d" % lod)
		if _success(canonical_position):
			var query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, canonical_position["details"]["position_m"], 10.0, canonical_region_id)
			var water: Dictionary = provider.query_surface(query)
			_ok(water, "water query at LOD %d" % lod)
			if _success(water):
				_check(bool(water["details"].get("matched", false)), "same canonical water exists at LOD %d" % lod)
				if bool(water["details"].get("matched", false)):
					_check(String(water["details"]["sample"]["feature_id"]) == canonical_feature_id, "river feature id independent of LOD")
					_check(String(water["details"]["sample"]["fluid_region_id"]) == canonical_region_id, "fluid region id independent of LOD")
		_check(provider.manifest_hash() == canonical_manifest, "cell addressing cannot mutate hydrology manifest")

	_check(all_lod_cell_sets[2] != all_lod_cell_sets[12], "representation cell set changes with LOD")
	_check(String(Fixture.provider().river_feature()["feature_id"]) == canonical_feature_id, "regeneration keeps river identity")
	_check(String(Fixture.provider().fluid_surface_descriptor()["fluid_region_id"]) == canonical_region_id, "regeneration keeps fluid identity")
	_finish()


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s %s" % [label, String(result.get("error_code", "")), result.get("details", {})])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G6 river/cell LOD identity: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G6 river/cell LOD identity: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
