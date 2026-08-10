extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const Query = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const Provenance = preload("res://scripts/simulation/procedural/contracts/semantic_field_provenance.gd")
const Sample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Bundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const Valley = preload("res://scripts/simulation/procedural/geomorphology/valley_incision_baseline_v1.gd")

const BODY_ID := "body/g8-valley-fixture"
const FRAME_ID := "body/g8-valley-fixture/fixed"
const POSITION := [6000000.0, 100.0, -200.0]
const SOURCE_HEIGHT_M := 100.0

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_formula_and_bounds()
	_test_determinism_and_binding()
	_test_rejections()
	_test_ownership_boundary()
	_finish()


func _test_manifest() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/procedural/g8-1-valley-incision-baseline.v1.json"))
	_check(parsed is Dictionary, "G8.1 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g8.1-valley-incision-baseline", "G8.1 checkpoint")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G8.1 candidate status")
		_check(String(parsed.get("generator_id", "")) == Valley.GENERATOR_ID, "manifest generator id")
		_check(Array(parsed.get("inputs", [])) == [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE], "manifest inputs")
		_check(not bool(parsed.get("ownership", {}).get("matter_mutation", true)), "manifest excludes Matter mutation")
		_check(not bool(parsed.get("ownership", {}).get("lod_dependency", true)), "manifest excludes LOD dependency")


func _test_formula_and_bounds() -> void:
	var profile := Profile.create("geomorphology-profile/g8-valley-default")
	_ok(Profile.validate(profile), "default profile validates")

	var zero := Valley.apply(_bundle(0.0, SOURCE_HEIGHT_M), profile)
	_ok(zero, "zero influence applies")
	if _success(zero):
		var deformation: Dictionary = zero["details"]["deformation"]
		_ok(Deformation.validate_against_profile(deformation, profile), "zero deformation validates")
		_check(_near(float(deformation["component_deltas_m"][Deformation.COMPONENT_VALLEY]), 0.0), "zero influence gives zero valley delta")
		_check(_near(float(deformation["resolved_surface_height_m"]), SOURCE_HEIGHT_M), "zero influence preserves height")

	var quarter := Valley.apply(_bundle(0.25, SOURCE_HEIGHT_M), profile)
	_ok(quarter, "quarter influence applies")
	if _success(quarter):
		var q: Dictionary = quarter["details"]["deformation"]
		_check(_near(float(q["component_deltas_m"][Deformation.COMPONENT_VALLEY]), -22.5), "quarter influence follows exponent")
		_check(_near(float(q["resolved_surface_height_m"]), 77.5), "quarter resolved height")
		_check(_only_valley_nonzero(q), "quarter changes valley component only")

	var half := Valley.apply(_bundle(0.5, SOURCE_HEIGHT_M), profile)
	_ok(half, "half influence applies")
	if _success(half) and _success(quarter):
		var half_delta := float(half["details"]["deformation"]["component_deltas_m"][Deformation.COMPONENT_VALLEY])
		var quarter_delta := float(quarter["details"]["deformation"]["component_deltas_m"][Deformation.COMPONENT_VALLEY])
		_check(half_delta < quarter_delta, "incision deepens monotonically")

	var full := Valley.apply(_bundle(1.0, SOURCE_HEIGHT_M), profile)
	_ok(full, "unit influence applies")
	if _success(full):
		var f: Dictionary = full["details"]["deformation"]
		_check(_near(float(f["component_deltas_m"][Deformation.COMPONENT_VALLEY]), -180.0), "unit influence reaches max valley depth")
		_check(_near(float(f["resolved_surface_height_m"]), -80.0), "unit influence resolved height")
		_check(absf(float(f["component_deltas_m"][Deformation.COMPONENT_VALLEY])) <= float(profile["valley_max_depth_m"]), "valley delta bounded by profile")

	var linear_profile := Profile.create("geomorphology-profile/g8-valley-linear", "1.0.0", 40.0, 35.0, 8.0, 12.0, 6.0, 1.0, 0.35)
	var linear := Valley.apply(_bundle(0.5, SOURCE_HEIGHT_M), linear_profile)
	_ok(linear, "custom linear profile applies")
	if _success(linear):
		_check(_near(float(linear["details"]["deformation"]["component_deltas_m"][Deformation.COMPONENT_VALLEY]), -20.0), "custom profile controls depth/exponent")


func _test_determinism_and_binding() -> void:
	var profile := Profile.create("geomorphology-profile/g8-valley-determinism")
	var source := _bundle(0.6, 250.0)
	var first := Valley.apply(source, profile)
	var second := Valley.apply(source, profile)
	_ok(first, "first deterministic sample")
	_ok(second, "second deterministic sample")
	if _success(first) and _success(second):
		var a: Dictionary = first["details"]["deformation"]
		var b: Dictionary = second["details"]["deformation"]
		_check(String(a["checksum"]) == String(b["checksum"]), "same inputs produce same deformation checksum")
		_check(String(a["source_semantic_bundle_checksum"]) == String(source["checksum"]), "output binds source semantic bundle checksum")
		_check(String(a["profile_checksum"]) == String(profile["checksum"]), "output binds profile checksum")
		_check(a["body_fixed_position_m"] == POSITION, "output preserves body-fixed position")

	var changed_source := _bundle(0.7, 250.0)
	var changed := Valley.apply(changed_source, profile)
	_ok(changed, "changed semantic source applies")
	if _success(first) and _success(changed):
		_check(String(first["details"]["deformation"]["checksum"]) != String(changed["details"]["deformation"]["checksum"]), "semantic input change changes deformation checksum")


func _test_rejections() -> void:
	var profile := Profile.create("geomorphology-profile/g8-valley-rejections")
	var out_of_range := Valley.apply(_bundle(1.1, SOURCE_HEIGHT_M), profile)
	_check(not _success(out_of_range), "out-of-range influence rejected")
	_check(String(out_of_range.get("error_code", "")) == "G8_1_VALLEY_INFLUENCE_OUT_OF_RANGE", "out-of-range error code")

	var missing_query := Query.create(BODY_ID, FRAME_ID, POSITION, [Registry.SURFACE_HEIGHT_M])
	var provenance := _provenance()
	var surface := Sample.create(Registry.SURFACE_HEIGHT_M, BODY_ID, FRAME_ID, POSITION, SOURCE_HEIGHT_M, provenance)
	var missing_bundle := Bundle.create(missing_query, {Registry.SURFACE_HEIGHT_M: surface})
	_ok(Bundle.validate(missing_bundle), "missing-valley source bundle itself validates")
	var missing := Valley.apply(missing_bundle, profile)
	_check(not _success(missing), "missing valley semantic rejected")
	_check(String(missing.get("error_code", "")) == "G8_1_REQUIRED_SEMANTIC_FIELD_MISSING", "missing valley error code")

	var bad_profile := profile.duplicate(true)
	bad_profile["valley_max_depth_m"] = -1.0
	bad_profile["checksum"] = GeoUtils.compute_checksum(bad_profile)
	var invalid_profile_result := Valley.apply(_bundle(0.5, SOURCE_HEIGHT_M), bad_profile)
	_check(not _success(invalid_profile_result), "invalid profile rejected")


func _test_ownership_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/geomorphology/valley_incision_baseline_v1.gd")
	for forbidden in [
		"SurfaceCellKey",
		"surface_cell_key",
		"AuthorityRegion",
		"InterestRegion",
		"MaterialDefinitionId",
		"material_definition_id",
		"MatterRevision",
		"ENetMultiplayerPeer",
		"Camera3D",
	]:
		_check(source.find(forbidden) < 0, "G8.1 source excludes %s" % forbidden)
	_check(source.find("lod") < 0 and source.find("LOD") < 0, "G8.1 source excludes LOD")


func _bundle(valley_influence: float, surface_height_m: float) -> Dictionary:
	var query := Query.create(BODY_ID, FRAME_ID, POSITION, [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE])
	var provenance := _provenance()
	var surface := Sample.create(Registry.SURFACE_HEIGHT_M, BODY_ID, FRAME_ID, POSITION, surface_height_m, provenance)
	var valley := Sample.create(Registry.VALLEY_INFLUENCE, BODY_ID, FRAME_ID, POSITION, valley_influence, provenance)
	return Bundle.create(query, {
		Registry.SURFACE_HEIGHT_M: surface,
		Registry.VALLEY_INFLUENCE: valley,
	})


func _provenance() -> Dictionary:
	return Provenance.create(
		"semantic-field-producer/g8-valley-fixture",
		"1.0.0",
		[],
		[],
		GeoUtils.payload_hash({"fixture": "g8.1"})
	)


func _only_valley_nonzero(deformation: Dictionary) -> bool:
	var components: Dictionary = deformation["component_deltas_m"]
	return (
		float(components[Deformation.COMPONENT_VALLEY]) < 0.0
		and _near(float(components[Deformation.COMPONENT_RIVER_CHANNEL]), 0.0)
		and _near(float(components[Deformation.COMPONENT_BANK]), 0.0)
		and _near(float(components[Deformation.COMPONENT_FLOODPLAIN]), 0.0)
		and _near(float(components[Deformation.COMPONENT_EROSION_DEPOSITION]), 0.0)
	)


func _near(a: float, b: float) -> bool:
	return GeoUtils.approximately_equal(a, b, 0.0000001)


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s (%s)" % [label, String(result.get("error_code", ""))])


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("G8.1 Valley Incision Baseline: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("G8.1 FAIL: %s" % failure)
	print("G8.1 Valley Incision Baseline: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
