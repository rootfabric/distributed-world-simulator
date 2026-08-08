extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureGraph = preload("res://scripts/simulation/procedural/features/feature_graph.gd")
const RiverFeature = preload("res://scripts/simulation/procedural/features/river_feature.gd")
const FluidRegionId = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")
const FluidSurfaceDescriptor = preload("res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd")
const RiverSpline = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfile = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")
const WaterSurfaceQuery = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const WaterSurfaceSample = preload("res://scripts/simulation/procedural/contracts/water_surface_sample.gd")
const FeatureBounds = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_hydrology_fixture_factory.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_fluid_region_identity_and_generic_descriptor()
	_test_river_spline_and_channel_contracts()
	_test_provider_determinism_and_feature_graph()
	_test_water_surface_queries()
	_test_invalid_paths()
	_test_source_boundaries()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g6-hydrology-fluid-surface.v1.json"
	_check(FileAccess.file_exists(path), "G6 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G6 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g6-hydrology-fluid-surface-v0", "G6 checkpoint")
		_check(String(parsed.get("base_branch", "")) == "feature/g5-world-feature-graph", "G6 stacked on G5")
		_check(not bool(parsed.get("cell_owns_river_identity", true)), "cell cannot own river identity")
		_check(not bool(parsed.get("renderer_owns_fluid_truth", true)), "renderer cannot own fluid truth")
		_check(not bool(parsed.get("full_cfd", true)), "G6 is not CFD")


func _test_fluid_region_identity_and_generic_descriptor() -> void:
	var water_a := FluidRegionId.derive(Fixture.BODY_ID, "fluid/water", Fixture.SEED, Fixture.GENERATOR_VERSION, Fixture.FLUID_STABLE_KEY)
	var water_b := FluidRegionId.derive(Fixture.BODY_ID, "fluid/water", Fixture.SEED, Fixture.GENERATOR_VERSION, Fixture.FLUID_STABLE_KEY)
	_ok(water_a, "water region id A")
	_ok(water_b, "water region id B")
	if _success(water_a) and _success(water_b):
		_check(String(water_a["details"]["fluid_region_id"]) == String(water_b["details"]["fluid_region_id"]), "fluid region id deterministic")
		_ok(FluidRegionId.validate(water_a["details"]["fluid_region_id"]), "fluid region id validates")
	var methane := FluidRegionId.derive(Fixture.BODY_ID, "fluid/methane", Fixture.SEED, Fixture.GENERATOR_VERSION, "fluid-region-key/g6-methane-test")
	_ok(methane, "generic methane region id")
	if _success(water_a) and _success(methane):
		_check(String(water_a["details"]["fluid_region_id"]) != String(methane["details"]["fluid_region_id"]), "fluid type participates in identity")

	var generic_bounds := FeatureBounds.sphere(Fixture.FRAME_ID, [Fixture.RADIUS_M, 0.0, 0.0], 1000.0)
	var descriptor := FluidSurfaceDescriptor.create(
		Fixture.BODY_ID, Fixture.FRAME_ID, "fluid/methane", Fixture.SEED + 1, "1.0.0",
		"fluid-region-key/g6-methane-sea", generic_bounds, FluidSurfaceDescriptor.CONSTANT_LEVEL,
		{"level_m": 42.0}, {"example": "non-water-fluid"}
	)
	_ok(FluidSurfaceDescriptor.validate(descriptor), "generic non-water fluid descriptor")
	_check(String(descriptor["fluid_type_id"]) == "fluid/methane", "descriptor keeps generic fluid type")


func _test_river_spline_and_channel_contracts() -> void:
	var spline := Fixture.river_spline()
	var profile := Fixture.channel_profile()
	_ok(RiverSpline.validate(spline), "river spline contract")
	_ok(RiverChannelProfile.validate(profile), "river channel profile contract")
	var length_result := RiverSpline.total_length_m(spline)
	_ok(length_result, "river spline length")
	if _success(length_result):
		_check(float(length_result["details"]["length_m"]) > 1000000.0, "mega river is globally sized")
	var source := RiverSpline.sample(spline, 0.0)
	var middle := RiverSpline.sample(spline, 0.5)
	var mouth := RiverSpline.sample(spline, 1.0)
	_ok(source, "source sample")
	_ok(middle, "middle sample")
	_ok(mouth, "mouth sample")
	if _success(source) and _success(mouth):
		_check(_vector3(source["details"]["position_m"]).length() > _vector3(mouth["details"]["position_m"]).length(), "canonical water course descends source to mouth")
	var source_profile := RiverChannelProfile.sample(profile, 0.0)
	var mouth_profile := RiverChannelProfile.sample(profile, 1.0)
	_ok(source_profile, "source profile")
	_ok(mouth_profile, "mouth profile")
	if _success(source_profile) and _success(mouth_profile):
		_check(float(source_profile["details"]["width_m"]) < float(mouth_profile["details"]["width_m"]), "river widens downstream")
		_check(float(source_profile["details"]["depth_m"]) < float(mouth_profile["details"]["depth_m"]), "river deepens downstream")


func _test_provider_determinism_and_feature_graph() -> void:
	var provider_a = Fixture.provider()
	var provider_b = Fixture.provider()
	_check(provider_a != null and provider_b != null, "providers configure")
	if provider_a == null or provider_b == null:
		return
	var feature_a: Dictionary = provider_a.river_feature()
	var feature_b: Dictionary = provider_b.river_feature()
	_ok(RiverFeature.validate(feature_a), "river feature validates")
	_check(String(feature_a["feature_id"]) == String(feature_b["feature_id"]), "river feature identity deterministic")
	_check(String(feature_a["checksum"]) == String(feature_b["checksum"]), "river feature payload deterministic")
	_check(provider_a.manifest_hash() == provider_b.manifest_hash(), "provider manifest deterministic")
	var descriptor_a: Dictionary = provider_a.fluid_surface_descriptor()
	var descriptor_b: Dictionary = provider_b.fluid_surface_descriptor()
	_check(String(descriptor_a["fluid_region_id"]) == String(descriptor_b["fluid_region_id"]), "fluid region identity deterministic")

	var graph = FeatureGraph.new()
	_ok(graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID), "G5 graph configure for G6")
	_ok(provider_a.install_into_graph(graph), "river feature installs into G5 graph")
	_ok(graph.seal(), "G5 graph seals with river feature")
	_check(graph.feature_ids() == [String(feature_a["feature_id"])], "G5 graph owns one canonical river feature")


func _test_water_surface_queries() -> void:
	var provider = Fixture.provider()
	if provider == null:
		_check(false, "provider required for query tests")
		return
	var spline := Fixture.river_spline()
	var early := RiverSpline.sample(spline, 0.2)
	var late := RiverSpline.sample(spline, 0.8)
	_ok(early, "early canonical spline sample")
	_ok(late, "late canonical spline sample")
	if not _success(early) or not _success(late):
		return
	var early_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, early["details"]["position_m"], 10.0)
	var late_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, late["details"]["position_m"], 10.0)
	_ok(WaterSurfaceQuery.validate(early_query), "water query contract")
	var early_result: Dictionary = provider.query_surface(early_query)
	var late_result: Dictionary = provider.query_surface(late_query)
	_ok(early_result, "early water query")
	_ok(late_result, "late water query")
	if _success(early_result) and bool(early_result["details"].get("matched", false)):
		var sample: Dictionary = early_result["details"]["sample"]
		_ok(WaterSurfaceSample.validate(sample), "early sample contract")
		_check(bool(sample["inside_channel"]), "centerline query is inside channel")
		_check(_vector3(sample["flow_vector_mps"]).length() > 1.0, "query exposes canonical flow vector")
	if _success(early_result) and _success(late_result) and bool(early_result["details"].get("matched", false)) and bool(late_result["details"].get("matched", false)):
		var early_sample: Dictionary = early_result["details"]["sample"]
		var late_sample: Dictionary = late_result["details"]["sample"]
		_check(float(early_sample["channel_width_m"]) < float(late_sample["channel_width_m"]), "query follows downstream channel profile")
		_check(float(early_sample["normalized_distance"]) < float(late_sample["normalized_distance"]), "query preserves source-to-mouth ordering")

	var middle := RiverSpline.sample(spline, 0.5)
	if _success(middle):
		var center := _vector3(middle["details"]["position_m"])
		var far_position := center + center.normalized() * 5000.0
		var far_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, _array3(far_position), 100.0)
		var far_result: Dictionary = provider.query_surface(far_query)
		_ok(far_result, "far query is valid")
		if _success(far_result):
			_check(not bool(far_result["details"].get("matched", true)), "query outside search distance does not match")
		var tangent := _vector3(middle["details"]["tangent"])
		var normal := center.normalized()
		var lateral := normal.cross((tangent - normal * tangent.dot(normal)).normalized()).normalized()
		var outside_channel_position := center + lateral * 500.0
		var bank_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, _array3(outside_channel_position), 1000.0)
		var bank_result: Dictionary = provider.query_surface(bank_query)
		_ok(bank_result, "nearby off-channel query")
		if _success(bank_result) and bool(bank_result["details"].get("matched", false)):
			_check(not bool(bank_result["details"]["sample"]["inside_channel"]), "query can distinguish bank from water channel")

	var other_region := FluidRegionId.derive(Fixture.BODY_ID, "fluid/water", Fixture.SEED + 99, "1.0.0", "fluid-region-key/other-water")
	if _success(other_region):
		var filtered_query := WaterSurfaceQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, early["details"]["position_m"], 10.0, String(other_region["details"]["fluid_region_id"]))
		var filtered_result: Dictionary = provider.query_surface(filtered_query)
		_ok(filtered_result, "valid other-region filter")
		if _success(filtered_result):
			_check(not bool(filtered_result["details"].get("matched", true)), "fluid-region filter isolates canonical region")


func _test_invalid_paths() -> void:
	var spline := Fixture.river_spline()
	var tampered := spline.duplicate(true)
	tampered["points"][0]["position_m"][0] = float(tampered["points"][0]["position_m"][0]) + 1.0
	_check(not _success(RiverSpline.validate(tampered)), "river spline checksum catches tamper")
	var invalid_profile := Fixture.channel_profile()
	invalid_profile["width_source_m"] = 0.0
	invalid_profile["checksum"] = GeoUtils.compute_checksum(invalid_profile)
	_check(not _success(RiverChannelProfile.validate(invalid_profile)), "zero-width channel rejected")
	var provider = Fixture.provider()
	if provider != null:
		var wrong_body_query := WaterSurfaceQuery.create("body/other", Fixture.FRAME_ID, Fixture.river_spline()["points"][0]["position_m"], 10.0)
		var result: Dictionary = provider.query_surface(wrong_body_query)
		_check(not _success(result), "wrong-body query rejected")
		_check(String(result.get("error_code", "")) == "CASUAL_RIVER_QUERY_BODY_MISMATCH", "wrong-body rejection precise")


func _test_source_boundaries() -> void:
	var paths := [
		"res://scripts/simulation/procedural/contracts/fluid_region_id.gd",
		"res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd",
		"res://scripts/simulation/procedural/contracts/river_spline.gd",
		"res://scripts/simulation/procedural/contracts/river_channel_profile.gd",
		"res://scripts/simulation/procedural/contracts/water_surface_query.gd",
		"res://scripts/simulation/procedural/contracts/water_surface_sample.gd",
		"res://scripts/simulation/procedural/features/river_feature.gd",
		"res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd",
	]
	var forbidden := ["SurfaceCellKey", "SurfaceLodSelector", "MeshInstance3D", "ImmediateMesh", "Camera3D", "RenderingServer", "RandomNumberGenerator", "randf(", "randi(", "OCEAN_PLANET", "EARTH", "MOON"]
	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		_check(not source.is_empty(), "source readable: %s" % path)
		for token in forbidden:
			_check(source.find(token) < 0, "canonical hydrology source excludes %s" % token)


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s %s" % [label, String(result.get("error_code", "")), result.get("details", {})])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _finish() -> void:
	if failures.is_empty():
		print("G6 hydrology/fluid surface: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G6 hydrology/fluid surface: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
