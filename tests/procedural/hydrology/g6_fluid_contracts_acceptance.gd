extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureBounds = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FluidType = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")
const FluidRegionId = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")
const FluidSurfaceDescriptor = preload("res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd")
const RiverSpline = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfile = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")
const WaterSurfaceQuery = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const G5Fixture = preload("res://tests/procedural/fixtures/g5_feature_fixture_factory.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_fluid_type_and_region_identity()
	_test_surface_descriptor()
	_test_river_spline()
	_test_channel_profile()
	_test_water_surface_query()
	_test_source_boundaries()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g6-fluid-contracts.v1.json"
	_check(FileAccess.file_exists(path), "G6.0 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G6.0 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g6.0-fluid-contracts", "G6.0 checkpoint")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G6.0 status")
		_check(String(parsed.get("base_branch", "")) == "feature/g5-world-feature-graph", "G6.0 stacked on accepted G5")
		_check(String(parsed.get("base_commit", "")) == "e7b10c09a6be879b25cd5c7ec8407832fd758ac2", "G6.0 exact G5 branch head")
		_check(String(parsed.get("g5_accepted_candidate", "")) == "34be9d35e7f0a0e6c7a7c7c8bdd58b70c95413b4", "G5 accepted candidate pinned")
		var schemas: Dictionary = parsed.get("schemas", {})
		_check(String(schemas.get("fluid_surface_descriptor", "")) == FluidSurfaceDescriptor.SCHEMA, "surface descriptor schema declared")
		_check(String(schemas.get("river_spline", "")) == RiverSpline.SCHEMA, "river spline schema declared")
		_check(String(schemas.get("river_channel_profile", "")) == RiverChannelProfile.SCHEMA, "river channel schema declared")
		_check(String(schemas.get("water_surface_query", "")) == WaterSurfaceQuery.SCHEMA, "water query schema declared")
		var invariants: Dictionary = parsed.get("invariants", {})
		_check(bool(invariants.get("fluid_region_is_canonical", false)), "fluid region canonical")
		_check(not bool(invariants.get("surface_cell_owns_fluid_identity", true)), "cell does not own fluid identity")
		_check(not bool(invariants.get("lod_changes_fluid_identity", true)), "quality level does not change fluid identity")
		_check(not bool(invariants.get("camera_changes_fluid_identity", true)), "camera does not change fluid identity")
		_check(not bool(invariants.get("renderer_changes_fluid_identity", true)), "renderer does not change fluid identity")
		_check(not bool(invariants.get("renderer_dependency_allowed", true)), "renderer dependency forbidden")
		_check(not bool(invariants.get("network_transport_dependency_allowed", true)), "transport dependency forbidden")
		var deferred: Dictionary = parsed.get("deferred", {})
		_check(String(deferred.get("casual_river_provider", "")) == "G6.1", "provider deferred to G6.1")
		_check(String(deferred.get("cross_cell_cross_lod_continuity", "")) == "G6.2", "continuity deferred to G6.2")
		_check(String(deferred.get("runtime_water_surface_query", "")) == "G6.3", "runtime query deferred to G6.3")
		_check(String(deferred.get("casual_visual_river_lab", "")) == "G6.4", "visual river deferred to G6.4")


func _test_fluid_type_and_region_identity() -> void:
	for fluid_type_id in [FluidType.WATER, FluidType.LAVA, FluidType.METHANE, FluidType.AMMONIA]:
		_ok(FluidType.validate(fluid_type_id), "fluid type %s" % fluid_type_id)
	_check(not _success(FluidType.validate("water")), "unqualified fluid type rejected")
	_check(not _success(FluidType.validate("feature-type/water")), "foreign namespace rejected")

	var id_a: Dictionary = FluidRegionId.derive(G5Fixture.BODY_ID, FluidType.WATER, G5Fixture.SEED, "1.0.0", "fluid-key/river-001")
	var id_b: Dictionary = FluidRegionId.derive(G5Fixture.BODY_ID, FluidType.WATER, G5Fixture.SEED, "1.0.0", "fluid-key/river-001")
	_ok(id_a, "fluid region A")
	_ok(id_b, "fluid region B")
	if _success(id_a) and _success(id_b):
		var region_a: String = String(id_a["details"]["fluid_region_id"])
		var region_b: String = String(id_b["details"]["fluid_region_id"])
		_check(region_a == region_b, "same canonical fluid inputs reproduce identity")
		_ok(FluidRegionId.validate(region_a), "derived region id validates")
	var changed_key := FluidRegionId.derive(G5Fixture.BODY_ID, FluidType.WATER, G5Fixture.SEED, "1.0.0", "fluid-key/river-002")
	var changed_type := FluidRegionId.derive(G5Fixture.BODY_ID, FluidType.LAVA, G5Fixture.SEED, "1.0.0", "fluid-key/river-001")
	var changed_version := FluidRegionId.derive(G5Fixture.BODY_ID, FluidType.WATER, G5Fixture.SEED, "2.0.0", "fluid-key/river-001")
	if _success(id_a) and _success(changed_key) and _success(changed_type) and _success(changed_version):
		var original := String(id_a["details"]["fluid_region_id"])
		_check(original != String(changed_key["details"]["fluid_region_id"]), "stable key changes fluid identity")
		_check(original != String(changed_type["details"]["fluid_region_id"]), "fluid type changes fluid identity")
		_check(original != String(changed_version["details"]["fluid_region_id"]), "generator version changes fluid identity")
	_check(not _success(FluidRegionId.derive(G5Fixture.BODY_ID, FluidType.WATER, G5Fixture.SEED, "1.0.0", "feature-key/wrong")), "foreign stable-key namespace rejected")


func _test_surface_descriptor() -> void:
	var region_id := _water_region_id()
	var valley := G5Fixture.valley()
	var river := G5Fixture.river(String(valley["feature_id"]))
	var bounds := FeatureBounds.sphere(G5Fixture.FRAME_ID, river["bounds"]["center_m"], 700000.0)
	var descriptor := FluidSurfaceDescriptor.create(
		region_id,
		G5Fixture.BODY_ID,
		FluidType.WATER,
		G5Fixture.FRAME_ID,
		String(river["feature_id"]),
		bounds,
		FluidSurfaceDescriptor.PROFILED,
		G5Fixture.RADIUS_M + 5.0,
		{"semantic": "river-water"}
	)
	_ok(FluidSurfaceDescriptor.validate(descriptor), "fluid surface descriptor")
	_check(String(descriptor["source_feature_id"]) == String(river["feature_id"]), "descriptor links G5 feature")
	_check(String(descriptor["fluid_region_id"]) == region_id, "descriptor preserves canonical region")

	var repeated := FluidSurfaceDescriptor.create(
		region_id, G5Fixture.BODY_ID, FluidType.WATER, G5Fixture.FRAME_ID,
		String(river["feature_id"]), bounds, FluidSurfaceDescriptor.PROFILED,
		G5Fixture.RADIUS_M + 5.0, {"semantic": "river-water"}
	)
	_check(String(descriptor["checksum"]) == String(repeated["checksum"]), "surface descriptor deterministic")

	var tampered := descriptor.duplicate(true)
	tampered["reference_level_m"] = float(tampered["reference_level_m"]) + 1.0
	_check(not _success(FluidSurfaceDescriptor.validate(tampered)), "surface checksum catches tamper")
	var bad_feature := descriptor.duplicate(true)
	bad_feature["source_feature_id"] = "world-feature/river/not-a-hash"
	bad_feature["checksum"] = GeoUtils.compute_checksum(bad_feature)
	_check(not _success(FluidSurfaceDescriptor.validate(bad_feature)), "invalid source feature rejected")
	var bad_frame := descriptor.duplicate(true)
	bad_frame["bounds"] = FeatureBounds.sphere("body/other/fixed", [0.0, 0.0, 0.0], 10.0)
	bad_frame["checksum"] = GeoUtils.compute_checksum(bad_frame)
	_check(String(FluidSurfaceDescriptor.validate(bad_frame).get("error_code", "")) == "FLUID_SURFACE_BOUNDS_FRAME_MISMATCH", "surface bounds frame mismatch precise")


func _test_river_spline() -> void:
	var region_id := _water_region_id()
	var points := [
		[G5Fixture.RADIUS_M, 0.0, 0.0],
		[G5Fixture.RADIUS_M, 1000.0, 2000.0],
		[G5Fixture.RADIUS_M, 2500.0, 5000.0],
	]
	var spline := RiverSpline.create(region_id, "river-spline-key/main", G5Fixture.FRAME_ID, points)
	_ok(RiverSpline.validate(spline), "river spline")
	_check(spline["points_m"].size() == 3, "river spline point count")
	var spline_id := String(spline["spline_id"])
	var checksum := String(spline["checksum"])

	var reshaped_points := points.duplicate(true)
	reshaped_points[1] = [G5Fixture.RADIUS_M + 50.0, 1500.0, 2100.0]
	var reshaped := RiverSpline.create(region_id, "river-spline-key/main", G5Fixture.FRAME_ID, reshaped_points)
	_ok(RiverSpline.validate(reshaped), "reshaped river spline")
	_check(String(reshaped["spline_id"]) == spline_id, "spline identity survives canonical geometry change")
	_check(String(reshaped["checksum"]) != checksum, "spline checksum records geometry change")
	var branch := RiverSpline.create(region_id, "river-spline-key/tributary-a", G5Fixture.FRAME_ID, points)
	_check(String(branch["spline_id"]) != spline_id, "spline stable key separates branches")

	var too_short := RiverSpline.create(region_id, "river-spline-key/short", G5Fixture.FRAME_ID, [[0.0, 0.0, 0.0]])
	_check(not _success(RiverSpline.validate(too_short)), "single-point spline rejected")
	var degenerate := RiverSpline.create(region_id, "river-spline-key/degenerate", G5Fixture.FRAME_ID, [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]])
	_check(String(RiverSpline.validate(degenerate).get("error_code", "")) == "DEGENERATE_RIVER_SPLINE_SEGMENT", "degenerate segment rejected precisely")
	var identity_tamper := spline.duplicate(true)
	identity_tamper["stable_key"] = "river-spline-key/other"
	identity_tamper["checksum"] = GeoUtils.compute_checksum(identity_tamper)
	_check(String(RiverSpline.validate(identity_tamper).get("error_code", "")) == "RIVER_SPLINE_IDENTITY_MISMATCH", "spline identity tamper rejected")


func _test_channel_profile() -> void:
	var region_id := _water_region_id()
	var samples := [
		RiverChannelProfile.sample(1.0, 18.0, 3.0, 6.0),
		RiverChannelProfile.sample(0.0, 8.0, 1.5, 3.0),
		RiverChannelProfile.sample(0.5, 12.0, 2.0, 4.0),
	]
	var profile := RiverChannelProfile.create(region_id, samples, {"profile": "casual-v0"})
	_ok(RiverChannelProfile.validate(profile), "river channel profile")
	_check(float(profile["samples"][0]["t"]) == 0.0, "profile canonical start")
	_check(float(profile["samples"][1]["t"]) == 0.5, "profile canonical middle")
	_check(float(profile["samples"][2]["t"]) == 1.0, "profile canonical end")
	var profile_id := String(profile["profile_id"])
	var checksum := String(profile["checksum"])

	var widened := RiverChannelProfile.create(region_id, [
		RiverChannelProfile.sample(0.0, 10.0, 1.5, 3.0),
		RiverChannelProfile.sample(1.0, 20.0, 3.0, 6.0),
	])
	_ok(RiverChannelProfile.validate(widened), "widened profile")
	_check(String(widened["profile_id"]) == profile_id, "channel identity survives profile geometry change")
	_check(String(widened["checksum"]) != checksum, "channel checksum records profile change")

	var duplicate_t := RiverChannelProfile.create(region_id, [
		RiverChannelProfile.sample(0.0, 8.0, 1.0, 2.0),
		RiverChannelProfile.sample(0.0, 9.0, 1.0, 2.0),
		RiverChannelProfile.sample(1.0, 10.0, 1.0, 2.0),
	])
	_check(String(RiverChannelProfile.validate(duplicate_t).get("error_code", "")) == "RIVER_CHANNEL_SAMPLES_NOT_SORTED_UNIQUE", "duplicate profile sample rejected")
	var negative_width := RiverChannelProfile.create(region_id, [
		RiverChannelProfile.sample(0.0, -1.0, 1.0, 2.0),
		RiverChannelProfile.sample(1.0, 10.0, 1.0, 2.0),
	])
	_check(String(RiverChannelProfile.validate(negative_width).get("error_code", "")) == "INVALID_RIVER_CHANNEL_WIDTH", "negative width rejected")
	var missing_end := RiverChannelProfile.create(region_id, [
		RiverChannelProfile.sample(0.0, 8.0, 1.0, 2.0),
		RiverChannelProfile.sample(0.8, 10.0, 1.0, 2.0),
	])
	_check(String(RiverChannelProfile.validate(missing_end).get("error_code", "")) == "RIVER_CHANNEL_PROFILE_MISSING_END_SAMPLE", "profile end sample required")


func _test_water_surface_query() -> void:
	var query := WaterSurfaceQuery.create(G5Fixture.BODY_ID, G5Fixture.FRAME_ID, [G5Fixture.RADIUS_M, 0.0, 0.0], 50.0)
	_ok(WaterSurfaceQuery.validate(query), "default water surface query")
	_check(query["fluid_type_ids"] == [FluidType.WATER], "water query defaults to water")

	var mixed := WaterSurfaceQuery.create(
		G5Fixture.BODY_ID,
		G5Fixture.FRAME_ID,
		[G5Fixture.RADIUS_M, 0.0, 0.0],
		100.0,
		[FluidType.METHANE, FluidType.WATER, FluidType.LAVA, FluidType.WATER]
	)
	_ok(WaterSurfaceQuery.validate(mixed), "multi-fluid surface query")
	_check(mixed["fluid_type_ids"] == [FluidType.LAVA, FluidType.METHANE, FluidType.WATER], "query fluid types canonicalized")
	var repeated := WaterSurfaceQuery.create(
		G5Fixture.BODY_ID, G5Fixture.FRAME_ID, [G5Fixture.RADIUS_M, 0.0, 0.0], 100.0,
		[FluidType.WATER, FluidType.LAVA, FluidType.METHANE]
	)
	_check(String(mixed["checksum"]) == String(repeated["checksum"]), "query order does not change canonical request")

	var tampered := query.duplicate(true)
	tampered["position_m"] = [0.0, 0.0, 0.0]
	_check(not _success(WaterSurfaceQuery.validate(tampered)), "query checksum catches position tamper")
	var invalid_type := query.duplicate(true)
	invalid_type["fluid_type_ids"] = ["fluid/water"]
	invalid_type["checksum"] = GeoUtils.compute_checksum(invalid_type)
	_check(String(WaterSurfaceQuery.validate(invalid_type).get("error_code", "")) == "INVALID_WATER_SURFACE_QUERY_FLUID_TYPE", "query rejects foreign fluid namespace")


func _test_source_boundaries() -> void:
	var paths := [
		"res://scripts/simulation/procedural/contracts/fluid_type.gd",
		"res://scripts/simulation/procedural/contracts/fluid_region_id.gd",
		"res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd",
		"res://scripts/simulation/procedural/contracts/river_spline.gd",
		"res://scripts/simulation/procedural/contracts/river_channel_profile.gd",
		"res://scripts/simulation/procedural/contracts/water_surface_query.gd",
	]
	var forbidden := [
		"extends Node", "extends SceneTree", "MeshInstance3D", "ArrayMesh", "ImmediateMesh", "RenderingServer",
		"SurfaceCellKey", "surface_cell_key", "SurfaceLodSelector", "Camera3D", "MultiplayerPeer",
		"RandomNumberGenerator", "randf(", "randi(", "GeoKernel.new()",
	]
	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		_check(not source.is_empty(), "G6.0 core source readable %s" % path)
		for token in forbidden:
			_check(source.find(token) < 0, "fluid core excludes %s in %s" % [token, path])


func _water_region_id() -> String:
	var result: Dictionary = FluidRegionId.derive(G5Fixture.BODY_ID, FluidType.WATER, G5Fixture.SEED + 10, "1.0.0", "fluid-key/river-001")
	_ok(result, "water region fixture id")
	if not _success(result):
		return ""
	return String(result["details"]["fluid_region_id"])


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
		print("G6.0 fluid contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G6.0 fluid contracts: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
