extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const WorldFeature = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const FluidType = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")
const FluidRegionId = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")
const FluidSurfaceDescriptor = preload("res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd")
const RiverSpline = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfile = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")
const G5Fixture = preload("res://tests/procedural/fixtures/g5_feature_fixture_factory.gd")
const CasualRiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_compile_from_g5_semantics()
	_test_determinism_and_order_independence()
	_test_geometry_can_change_without_identity_reroll()
	_test_fluid_type_is_explicit_provider_input()
	_test_invalid_sources()
	_test_source_boundaries()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g6-1-casual-river-provider.v1.json"
	_check(FileAccess.file_exists(path), "G6.1 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G6.1 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g6.1-casual-river-provider-v1", "G6.1 checkpoint")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G6.1 candidate status")
		_check(String(parsed.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-08-R1", "G6.1 P0 revision")
		var rules: Dictionary = parsed.get("identity_rules", {})
		_check(bool(rules.get("g5_feature_id_remains_semantic_owner", false)), "G5 feature remains semantic owner")
		_check(not bool(rules.get("surface_cell_is_identity_input", true)), "surface cell excluded from identity")
		_check(not bool(rules.get("lod_is_identity_input", true)), "LOD excluded from identity")
		_check(not bool(rules.get("camera_is_identity_input", true)), "camera excluded from identity")
		_check(not bool(rules.get("renderer_is_identity_input", true)), "renderer excluded from identity")
		var boundaries: Dictionary = parsed.get("architecture_boundaries", {})
		_check(not bool(boundaries.get("writes_canonical_world_state", true)), "provider is read/compile only")
		_check(not bool(boundaries.get("owns_authority", true)), "provider does not own authority")
		_check(not bool(boundaries.get("owns_persistence", true)), "provider does not own persistence")


func _test_compile_from_g5_semantics() -> void:
	var valley := G5Fixture.valley()
	var river := G5Fixture.river(String(valley["feature_id"]))
	_ok(WorldFeature.validate(river), "G5 river feature validates")
	var compiled: Dictionary = CasualRiverProvider.compile(river, valley)
	_ok(compiled, "G6.1 compiles G5 river + valley")
	if not _success(compiled):
		return
	var details: Dictionary = compiled["details"]
	_check(String(details["provider_id"]) == CasualRiverProvider.PROVIDER_ID, "provider id pinned")
	_check(String(details["provider_version"]) == CasualRiverProvider.PROVIDER_VERSION, "provider version pinned")
	_check(String(details["source_feature_id"]) == String(river["feature_id"]), "G5 river FeatureId remains semantic source")
	_check(String(details["valley_feature_id"]) == String(valley["feature_id"]), "linked valley semantics retained")
	_ok(FluidRegionId.validate(details["fluid_region_id"]), "derived fluid region validates")
	_ok(RiverSpline.validate(details["river_spline"]), "derived spline validates")
	_ok(RiverChannelProfile.validate(details["channel_profile"]), "derived channel profile validates")
	_ok(FluidSurfaceDescriptor.validate(details["fluid_surface_descriptor"]), "derived fluid surface validates")
	_check(String(details["fluid_surface_descriptor"]["source_feature_id"]) == String(river["feature_id"]), "surface descriptor links canonical G5 river")
	_check(String(details["fluid_surface_descriptor"]["fluid_type_id"]) == FluidType.WATER, "provider uses canonical G6 water type")
	_check(details["river_spline"]["points_m"].size() == CasualRiverProvider.CONTROL_POINT_COUNT, "casual spline control-point count pinned")
	_check(String(details["river_spline"]["fluid_region_id"]) == String(details["fluid_region_id"]), "spline and region identity compose")
	_check(String(details["channel_profile"]["fluid_region_id"]) == String(details["fluid_region_id"]), "profile and region identity compose")


func _test_determinism_and_order_independence() -> void:
	var valley := G5Fixture.valley()
	var river := G5Fixture.river(String(valley["feature_id"]))
	var first: Dictionary = CasualRiverProvider.compile(river, valley)
	# Exercise unrelated feature construction between identical provider calls. Canonical result must not depend on call/query order.
	G5Fixture.seam_fault()
	G5Fixture.cave_system()
	var second: Dictionary = CasualRiverProvider.compile(river, valley)
	_ok(first, "first deterministic compile")
	_ok(second, "second deterministic compile")
	if _success(first) and _success(second):
		var a: Dictionary = first["details"]
		var b: Dictionary = second["details"]
		_check(String(a["fluid_region_id"]) == String(b["fluid_region_id"]), "fluid identity deterministic")
		_check(String(a["river_spline"]["spline_id"]) == String(b["river_spline"]["spline_id"]), "spline identity deterministic")
		_check(String(a["river_spline"]["checksum"]) == String(b["river_spline"]["checksum"]), "spline geometry deterministic")
		_check(String(a["channel_profile"]["checksum"]) == String(b["channel_profile"]["checksum"]), "channel profile deterministic")
		_check(String(a["fluid_surface_descriptor"]["checksum"]) == String(b["fluid_surface_descriptor"]["checksum"]), "surface descriptor deterministic")
		_check(String(a["manifest_hash"]) == String(b["manifest_hash"]), "provider manifest deterministic")


func _test_geometry_can_change_without_identity_reroll() -> void:
	var valley := G5Fixture.valley()
	var river := G5Fixture.river(String(valley["feature_id"]))
	var baseline: Dictionary = CasualRiverProvider.compile(river, valley)
	var reshaped := river.duplicate(true)
	for index in range(reshaped["anchors"].size()):
		var anchor: Dictionary = reshaped["anchors"][index]
		if String(anchor.get("role", "")) == "feature-anchor-role/source":
			anchor["position_m"][0] = float(anchor["position_m"][0]) + 1250.0
			anchor["checksum"] = GeoUtils.compute_checksum(anchor)
			reshaped["anchors"][index] = anchor
	reshaped["checksum"] = GeoUtils.compute_checksum(reshaped)
	_ok(WorldFeature.validate(reshaped), "reshaped source feature remains valid")
	_check(String(reshaped["feature_id"]) == String(river["feature_id"]), "reshaping does not reroll G5 FeatureId")
	var changed: Dictionary = CasualRiverProvider.compile(reshaped, valley)
	_ok(baseline, "baseline geometry compile")
	_ok(changed, "reshaped geometry compile")
	if _success(baseline) and _success(changed):
		var a: Dictionary = baseline["details"]
		var b: Dictionary = changed["details"]
		_check(String(a["fluid_region_id"]) == String(b["fluid_region_id"]), "geometry change keeps FluidRegionId")
		_check(String(a["river_spline"]["spline_id"]) == String(b["river_spline"]["spline_id"]), "geometry change keeps spline identity")
		_check(String(a["channel_profile"]["profile_id"]) == String(b["channel_profile"]["profile_id"]), "geometry change keeps profile identity")
		_check(String(a["river_spline"]["checksum"]) != String(b["river_spline"]["checksum"]), "geometry change updates spline checksum")
		_check(String(a["manifest_hash"]) != String(b["manifest_hash"]), "geometry change updates provider manifest")

	var reshaped_valley := valley.duplicate(true)
	reshaped_valley["attributes"]["g6_1_shape_revision"] = 2
	reshaped_valley["checksum"] = GeoUtils.compute_checksum(reshaped_valley)
	_ok(WorldFeature.validate(reshaped_valley), "reshaped valley remains valid")
	var valley_changed: Dictionary = CasualRiverProvider.compile(river, reshaped_valley)
	_ok(valley_changed, "valley geometry/semantic revision compiles")
	if _success(baseline) and _success(valley_changed):
		var a2: Dictionary = baseline["details"]
		var b2: Dictionary = valley_changed["details"]
		_check(String(a2["fluid_region_id"]) == String(b2["fluid_region_id"]), "valley revision cannot reroll fluid identity")
		_check(String(a2["river_spline"]["spline_id"]) == String(b2["river_spline"]["spline_id"]), "valley revision cannot reroll spline identity")
		_check(String(a2["river_spline"]["checksum"]) != String(b2["river_spline"]["checksum"]), "valley revision may reshape derived spline")


func _test_fluid_type_is_explicit_provider_input() -> void:
	var valley := G5Fixture.valley()
	var river := G5Fixture.river(String(valley["feature_id"]))
	var water: Dictionary = CasualRiverProvider.compile(river, valley, FluidType.WATER)
	var methane: Dictionary = CasualRiverProvider.compile(river, valley, FluidType.METHANE)
	_ok(water, "water river compile")
	_ok(methane, "methane river compile")
	if _success(water) and _success(methane):
		_check(String(water["details"]["source_feature_id"]) == String(methane["details"]["source_feature_id"]), "fluid projection does not change G5 feature identity")
		_check(String(water["details"]["fluid_region_id"]) != String(methane["details"]["fluid_region_id"]), "fluid type participates in fluid region identity")
		_check(String(methane["details"]["fluid_surface_descriptor"]["fluid_type_id"]) == FluidType.METHANE, "provider supports non-water fluid projection without world-type switch")


func _test_invalid_sources() -> void:
	var valley := G5Fixture.valley()
	var river := G5Fixture.river(String(valley["feature_id"]))
	var not_river: Dictionary = G5Fixture.seam_fault()
	var not_river_result: Dictionary = CasualRiverProvider.compile(not_river)
	_check(not _success(not_river_result), "non-river source rejected")
	_check(String(not_river_result.get("error_code", "")) == "G6_1_SOURCE_FEATURE_NOT_RIVER", "non-river rejection precise")

	var missing_mouth := river.duplicate(true)
	var remaining: Array = []
	for anchor in missing_mouth["anchors"]:
		if String(anchor.get("role", "")) != "feature-anchor-role/mouth":
			remaining.append(anchor)
	missing_mouth["anchors"] = remaining
	missing_mouth["checksum"] = GeoUtils.compute_checksum(missing_mouth)
	_ok(WorldFeature.validate(missing_mouth), "river without mouth is still generic G5-valid")
	var missing_result: Dictionary = CasualRiverProvider.compile(missing_mouth, valley)
	_check(String(missing_result.get("error_code", "")) == "G6_1_RIVER_MOUTH_ANCHOR_REQUIRED", "G6.1 requires semantic mouth")

	var wrong_valley: Dictionary = G5Fixture.seam_fault()
	var wrong_support: Dictionary = CasualRiverProvider.compile(river, wrong_valley)
	_check(String(wrong_support.get("error_code", "")) == "G6_1_SUPPORT_FEATURE_NOT_VALLEY", "support feature must be valley")
	var invalid_type: Dictionary = CasualRiverProvider.compile(river, valley, "fluid/water")
	_check(String(invalid_type.get("error_code", "")) == "INVALID_G6_1_FLUID_TYPE", "legacy/foreign fluid namespace rejected")


func _test_source_boundaries() -> void:
	var path := "res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd"
	var source := FileAccess.get_file_as_string(path)
	_check(not source.is_empty(), "G6.1 provider source readable")
	for token in [
		"SurfaceCellKey",
		"SurfaceLodSelector",
		"CubeSphereAddressing",
		"MeshInstance3D",
		"ImmediateMesh",
		"Camera3D",
		"RenderingServer",
		"RandomNumberGenerator",
		"randf(",
		"randi(",
		"rpc(",
		"multiplayer",
	]:
		_check(source.find(token) < 0, "G6.1 canonical provider excludes %s" % token)


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
		print("G6.1 CasualRiverProviderV1: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G6.1 CasualRiverProviderV1: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
