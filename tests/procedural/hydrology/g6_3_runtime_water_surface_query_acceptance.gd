extends SceneTree

const WaterSurfaceQuery = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const WaterSurfaceSample = preload("res://scripts/simulation/procedural/contracts/water_surface_sample.gd")
const FluidType = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")
const CasualRiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")
const WaterSurfaceResolver = preload("res://scripts/simulation/procedural/hydrology/water_surface_resolver_v1.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_exact_surface_query()
	_test_search_distance_and_no_match()
	_test_fluid_type_filter()
	_test_body_frame_filter()
	_test_deterministic_multi_region_winner()
	_test_invalid_inputs()
	_test_source_boundaries()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g6-3-runtime-water-surface-query.v1.json"
	_check(FileAccess.file_exists(path), "G6.3 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G6.3 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g6.3-runtime-water-surface-query-resolver", "G6.3 checkpoint pinned")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G6.3 candidate status")
		_check(String(parsed.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-08-R1", "G6.3 P0 revision")
		var service: Dictionary = parsed.get("runtime_service", {})
		_check(String(service.get("id", "")) == WaterSurfaceResolver.RESOLVER_ID, "G6.3 resolver id pinned")
		_check(int(service.get("curve_subdivisions_per_segment", -1)) == WaterSurfaceResolver.CURVE_SUBDIVISIONS_PER_SEGMENT, "G6.3 curve resolution pinned")
		var boundaries: Dictionary = parsed.get("architecture_boundaries", {})
		_check(not bool(boundaries.get("surface_cell_is_query_input", true)), "surface cell excluded from query")
		_check(not bool(boundaries.get("lod_is_query_input", true)), "LOD excluded from query")
		_check(not bool(boundaries.get("resolver_owns_authority", true)), "resolver does not own authority")
		_check(not bool(boundaries.get("resolver_mutates_world_state", true)), "resolver does not mutate world")


func _test_exact_surface_query() -> void:
	var river: Dictionary = Fixture.river()
	var compiled: Dictionary = CasualRiverProvider.compile(river)
	_ok(compiled, "G6.3 provider compiles seam river")
	if not _success(compiled):
		return
	var details: Dictionary = compiled["details"]
	var query_position: Array = details["river_spline"]["points_m"][3]
	var query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, query_position, 0.01, [FluidType.WATER])
	_ok(WaterSurfaceQuery.validate(query), "G6.3 exact query validates")
	var resolved: Dictionary = WaterSurfaceResolver.resolve(query, [compiled])
	_ok(resolved, "G6.3 exact query resolves")
	if not _success(resolved):
		return
	_check(bool(resolved["details"].get("matched", false)), "G6.3 exact river point matched")
	if not bool(resolved["details"].get("matched", false)):
		return
	var sample: Dictionary = resolved["details"]["sample"]
	_ok(WaterSurfaceSample.validate(sample), "G6.3 sample validates")
	_check(String(sample["source_feature_id"]) == String(river["feature_id"]), "G6.3 sample keeps G5 FeatureId")
	_check(String(sample["fluid_region_id"]) == String(details["fluid_region_id"]), "G6.3 sample keeps FluidRegionId")
	_check(String(sample["fluid_type_id"]) == FluidType.WATER, "G6.3 water type returned")
	_check(float(sample["distance_to_surface_m"]) <= 0.01, "G6.3 exact query is on water surface")
	_check(float(sample["channel_width_m"]) > 0.0, "G6.3 channel width available")
	_check(float(sample["channel_depth_m"]) >= 0.0, "G6.3 channel depth available")
	_check(float(sample["downstream_t"]) > 0.0 and float(sample["downstream_t"]) < 1.0, "G6.3 downstream t available")
	_check(_unit_length(sample["surface_normal"]), "G6.3 surface normal normalized")
	_check(_unit_length(sample["flow_direction"]), "G6.3 flow direction normalized")


func _test_search_distance_and_no_match() -> void:
	var compiled: Dictionary = CasualRiverProvider.compile(Fixture.river())
	_ok(compiled, "G6.3 distance fixture compiles")
	if not _success(compiled):
		return
	var point := _vector3(compiled["details"]["river_spline"]["points_m"][2])
	var near_position := point.normalized() * (point.length() + 2.0)
	var near_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, _array3(near_position), 5.0, [FluidType.WATER])
	var near_result: Dictionary = WaterSurfaceResolver.resolve(near_query, [compiled])
	_ok(near_result, "G6.3 near-surface query resolves")
	if _success(near_result):
		_check(bool(near_result["details"].get("matched", false)), "G6.3 max distance finds nearby surface")
		if bool(near_result["details"].get("matched", false)):
			_check(float(near_result["details"]["sample"]["distance_to_surface_m"]) <= 5.0, "G6.3 nearby distance bounded")

	var far_position := point.normalized() * (point.length() + 100.0)
	var far_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, _array3(far_position), 5.0, [FluidType.WATER])
	var far_result: Dictionary = WaterSurfaceResolver.resolve(far_query, [compiled])
	_ok(far_result, "G6.3 far query resolves to no-match")
	if _success(far_result):
		_check(not bool(far_result["details"].get("matched", true)), "G6.3 far query does not match")
		_check(String(far_result["details"].get("reason", "")) == "NO_FLUID_SURFACE_WITHIN_DISTANCE", "G6.3 no-match reason pinned")


func _test_fluid_type_filter() -> void:
	var compiled_water: Dictionary = CasualRiverProvider.compile(Fixture.river(), {}, FluidType.WATER)
	_ok(compiled_water, "G6.3 water candidate compiles")
	if not _success(compiled_water):
		return
	var point: Array = compiled_water["details"]["river_spline"]["points_m"][1]
	var methane_only := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, 1.0, [FluidType.METHANE])
	var filtered: Dictionary = WaterSurfaceResolver.resolve(methane_only, [compiled_water])
	_ok(filtered, "G6.3 methane filter resolves")
	if _success(filtered):
		_check(not bool(filtered["details"].get("matched", true)), "G6.3 water excluded by methane filter")
		_check(int(filtered["details"].get("eligible_candidates", -1)) == 0, "G6.3 filtered candidate not evaluated")


func _test_body_frame_filter() -> void:
	var compiled: Dictionary = CasualRiverProvider.compile(Fixture.river())
	_ok(compiled, "G6.3 body/frame fixture compiles")
	if not _success(compiled):
		return
	var point: Array = compiled["details"]["river_spline"]["points_m"][0]
	var other_body := WaterSurfaceQuery.create("body/g6-other", Fixture.FRAME_ID, point, 1.0, [FluidType.WATER])
	var body_result: Dictionary = WaterSurfaceResolver.resolve(other_body, [compiled])
	_ok(body_result, "G6.3 other body query resolves")
	if _success(body_result):
		_check(not bool(body_result["details"].get("matched", true)), "G6.3 other body cannot match river")
	var other_frame := WaterSurfaceQuery.create(Fixture.BODY_ID, "body/g6-other/fixed", point, 1.0, [FluidType.WATER])
	var frame_result: Dictionary = WaterSurfaceResolver.resolve(other_frame, [compiled])
	_ok(frame_result, "G6.3 other frame query resolves")
	if _success(frame_result):
		_check(not bool(frame_result["details"].get("matched", true)), "G6.3 other frame cannot match river")


func _test_deterministic_multi_region_winner() -> void:
	var river := Fixture.river()
	var water: Dictionary = CasualRiverProvider.compile(river, {}, FluidType.WATER)
	var methane: Dictionary = CasualRiverProvider.compile(river, {}, FluidType.METHANE)
	_ok(water, "G6.3 deterministic water candidate")
	_ok(methane, "G6.3 deterministic methane candidate")
	if not _success(water) or not _success(methane):
		return
	var point: Array = water["details"]["river_spline"]["points_m"][0]
	var query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, 0.01, [FluidType.WATER, FluidType.METHANE])
	var forward: Dictionary = WaterSurfaceResolver.resolve(query, [water, methane])
	var reverse: Dictionary = WaterSurfaceResolver.resolve(query, [methane, water])
	_ok(forward, "G6.3 forward candidate order resolves")
	_ok(reverse, "G6.3 reverse candidate order resolves")
	if _success(forward) and _success(reverse):
		_check(bool(forward["details"].get("matched", false)), "G6.3 multi-region forward matched")
		_check(bool(reverse["details"].get("matched", false)), "G6.3 multi-region reverse matched")
		if bool(forward["details"].get("matched", false)) and bool(reverse["details"].get("matched", false)):
			var forward_id := String(forward["details"]["sample"]["fluid_region_id"])
			var reverse_id := String(reverse["details"]["sample"]["fluid_region_id"])
			_check(forward_id == reverse_id, "G6.3 winner independent of registration order")
			_check(String(forward["details"]["sample"]["checksum"]) == String(reverse["details"]["sample"]["checksum"]), "G6.3 deterministic winner sample checksum")
			var water_id := String(water["details"]["fluid_region_id"])
			var methane_id := String(methane["details"]["fluid_region_id"])
			var expected_id := water_id if water_id < methane_id else methane_id
			_check(forward_id == expected_id, "G6.3 tie break uses lexical FluidRegionId")


func _test_invalid_inputs() -> void:
	var compiled: Dictionary = CasualRiverProvider.compile(Fixture.river())
	_ok(compiled, "G6.3 invalid-input fixture compiles")
	if not _success(compiled):
		return
	var point: Array = compiled["details"]["river_spline"]["points_m"][0]
	var invalid_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, -1.0, [FluidType.WATER])
	var invalid_query_result: Dictionary = WaterSurfaceResolver.resolve(invalid_query, [compiled])
	_check(not _success(invalid_query_result), "G6.3 invalid query rejected")
	_check(String(invalid_query_result.get("error_code", "")) == "INVALID_G6_3_WATER_SURFACE_QUERY", "G6.3 invalid query error pinned")

	var broken: Dictionary = compiled.duplicate(true)
	broken["details"]["fluid_region_id"] = "fluid-region/broken"
	var valid_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, 1.0, [FluidType.WATER])
	var broken_result: Dictionary = WaterSurfaceResolver.resolve(valid_query, [broken])
	_check(not _success(broken_result), "G6.3 broken composition rejected")
	_check(String(broken_result.get("error_code", "")) == "INVALID_G6_3_COMPILED_GEOGRAPHY", "G6.3 broken composition error pinned")


func _test_source_boundaries() -> void:
	var resolver_source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/hydrology/water_surface_resolver_v1.gd")
	var sample_source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/contracts/water_surface_sample.gd")
	for forbidden in [
		"SurfaceCellKey",
		"CubeSphereAddressing",
		"Camera3D",
		"MeshInstance3D",
		"ArrayMesh",
		"RenderingServer",
		"MultiplayerPeer",
		"AuthorityRegion",
		"InterestRegion",
		"RandomNumberGenerator",
		"randf(",
		"randi(",
	]:
		_check(resolver_source.find(forbidden) == -1, "G6.3 resolver excludes %s" % forbidden)
		_check(sample_source.find(forbidden) == -1, "G6.3 sample excludes %s" % forbidden)


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s %s" % [label, String(result.get("error_code", "")), result.get("details", {})])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _unit_length(value: Array) -> bool:
	var vector := _vector3(value)
	return absf(vector.length_squared() - 1.0) <= 0.00001


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _finish() -> void:
	if failures.is_empty():
		print("G6.3 runtime WaterSurfaceQuery: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G6.3 runtime WaterSurfaceQuery: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
