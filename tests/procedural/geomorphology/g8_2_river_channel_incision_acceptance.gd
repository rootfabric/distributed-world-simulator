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
const River = preload("res://scripts/simulation/procedural/geomorphology/river_channel_incision_v1.gd")

const BODY_ID := "body/g8-river-fixture"
const FRAME_ID := "body/g8-river-fixture/fixed"
const POSITION := [6000000.0, 100.0, -200.0]
const SOURCE_HEIGHT_M := 100.0
const VALLEY_INFLUENCE := 0.25
const RIVER_WIDTH_M := 100.0

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest_and_parents()
	_test_center_core_edge_profile()
	_test_valley_composition()
	_test_determinism_and_profile_control()
	_test_rejections()
	_test_ownership_boundary()
	_finish()


func _test_manifest_and_parents() -> void:
	var g81 = JSON.parse_string(FileAccess.get_file_as_string("res://validation/g8-1-valley-incision-baseline-validation.json"))
	_check(g81 is Dictionary, "G8.1 validation parses")
	if g81 is Dictionary:
		_check(String(g81.get("decision", "")) == "ACCEPTED", "G8.1 parent accepted")
		_check(String(g81.get("automated_evidence", {}).get("tested_head", "")) == "42940c0b7f16b2ccf3704d7e603691415b1360cf", "G8.1 accepted tested head")

	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/procedural/g8-2-river-channel-incision.v1.json"))
	_check(parsed is Dictionary, "G8.2 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g8.2-river-channel-incision", "G8.2 checkpoint")
		_check(String(parsed.get("status", "")) == "ACCEPTED", "G8.2 accepted status")
		_check(String(parsed.get("acceptance", {}).get("tested_head", "")) == "491fe10877c70c362c14ab595a8a0204165a880a", "G8.2 accepted tested head")
		_check(String(parsed.get("generator_id", "")) == River.GENERATOR_ID, "manifest generator id")
		_check(Array(parsed.get("inputs", [])) == [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M], "manifest inputs")
		_check(not bool(parsed.get("ownership", {}).get("matter_mutation", true)), "manifest excludes Matter mutation")
		_check(not bool(parsed.get("ownership", {}).get("lod_dependency", true)), "manifest excludes LOD dependency")


func _test_center_core_edge_profile() -> void:
	var profile := Profile.create("geomorphology-profile/g8-river-default")
	_ok(Profile.validate(profile), "default profile validates")

	var center := River.apply(_bundle(0.0, RIVER_WIDTH_M), profile)
	_ok(center, "centerline applies")
	if _success(center):
		var d: Dictionary = center["details"]["deformation"]
		_check(_near(float(center["details"]["channel_weight"]), 1.0), "centerline weight is one")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_RIVER_CHANNEL]), -35.0), "centerline reaches max river depth")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_VALLEY]), -22.5), "centerline preserves valley incision")
		_check(_near(float(d["resolved_surface_height_m"]), 42.5), "centerline resolved height composes valley plus river")
		_check(_only_valley_and_river_nonzero(d), "centerline only valley and river are nonzero")

	var core_boundary := River.apply(_bundle(32.5, RIVER_WIDTH_M), profile)
	_ok(core_boundary, "core boundary applies")
	if _success(core_boundary):
		_check(_near(float(core_boundary["details"]["normalized_distance"]), 0.65), "default core boundary normalized distance")
		_check(_near(float(core_boundary["details"]["channel_weight"]), 1.0), "core boundary remains full depth")

	var transition := River.apply(_bundle(41.25, RIVER_WIDTH_M), profile)
	_ok(transition, "softness midpoint applies")
	if _success(transition):
		var d: Dictionary = transition["details"]["deformation"]
		_check(_near(float(transition["details"]["normalized_distance"]), 0.825), "transition normalized distance")
		_check(_near(float(transition["details"]["channel_weight"]), 0.5), "softness midpoint cubic weight")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_RIVER_CHANNEL]), -17.5), "softness midpoint half river depth")

	var edge := River.apply(_bundle(50.0, RIVER_WIDTH_M), profile)
	_ok(edge, "half-width edge applies")
	if _success(edge):
		var d: Dictionary = edge["details"]["deformation"]
		_check(_near(float(edge["details"]["channel_weight"]), 0.0), "half-width edge weight zero")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_RIVER_CHANNEL]), 0.0), "half-width edge river incision zero")

	var outside := River.apply(_bundle(75.0, RIVER_WIDTH_M), profile)
	_ok(outside, "outside channel applies")
	if _success(outside):
		_check(_near(float(outside["details"]["channel_weight"]), 0.0), "outside channel weight zero")


func _test_valley_composition() -> void:
	var profile := Profile.create("geomorphology-profile/g8-river-compose")
	var source := _bundle(10.0, RIVER_WIDTH_M)
	var valley := Valley.apply(source, profile)
	var river := River.apply(source, profile)
	_ok(valley, "valley parent applies on river bundle")
	_ok(river, "river composition applies")
	if _success(valley) and _success(river):
		var vd: Dictionary = valley["details"]["deformation"]
		var rd: Dictionary = river["details"]["deformation"]
		_check(String(river["details"]["valley_deformation_checksum"]) == String(vd["checksum"]), "river reports exact parent valley checksum")
		_check(_near(float(rd["component_deltas_m"][Deformation.COMPONENT_VALLEY]), float(vd["component_deltas_m"][Deformation.COMPONENT_VALLEY])), "river preserves exact valley delta")
		_check(String(rd["source_semantic_bundle_checksum"]) == String(source["checksum"]), "river binds same semantic bundle checksum")
		_check(String(vd["source_semantic_bundle_checksum"]) == String(source["checksum"]), "valley parent binds same semantic bundle checksum")
		_check(String(rd["profile_checksum"]) == String(profile["checksum"]), "river binds profile checksum")
		_ok(Deformation.validate_against_profile(rd, profile), "composed deformation validates against profile")


func _test_determinism_and_profile_control() -> void:
	var profile := Profile.create("geomorphology-profile/g8-river-determinism")
	var source := _bundle(41.25, RIVER_WIDTH_M)
	var first := River.apply(source, profile)
	var second := River.apply(source, profile)
	_ok(first, "first deterministic river sample")
	_ok(second, "second deterministic river sample")
	if _success(first) and _success(second):
		_check(String(first["details"]["deformation"]["checksum"]) == String(second["details"]["deformation"]["checksum"]), "same river inputs produce same deformation checksum")

	var hard_profile := Profile.create("geomorphology-profile/g8-river-hard", "1.0.0", 180.0, 20.0, 8.0, 12.0, 6.0, 1.5, 0.0)
	var hard_inside := River.apply(_bundle(49.0, RIVER_WIDTH_M), hard_profile)
	var hard_edge := River.apply(_bundle(50.0, RIVER_WIDTH_M), hard_profile)
	_ok(hard_inside, "hard-edge inside applies")
	_ok(hard_edge, "hard-edge boundary applies")
	if _success(hard_inside):
		_check(_near(float(hard_inside["details"]["deformation"]["component_deltas_m"][Deformation.COMPONENT_RIVER_CHANNEL]), -20.0), "zero softness keeps full depth inside")
	if _success(hard_edge):
		_check(_near(float(hard_edge["details"]["deformation"]["component_deltas_m"][Deformation.COMPONENT_RIVER_CHANNEL]), 0.0), "zero softness ends at half width")

	var wider := River.apply(_bundle(41.25, 200.0), profile)
	_ok(wider, "wider river applies")
	if _success(first) and _success(wider):
		_check(float(wider["details"]["channel_weight"]) > float(first["details"]["channel_weight"]), "larger width increases incision weight at same physical distance")


func _test_rejections() -> void:
	var profile := Profile.create("geomorphology-profile/g8-river-rejections")
	var missing_query := Query.create(BODY_ID, FRAME_ID, POSITION, [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M])
	var provenance := _provenance()
	var missing_bundle := Bundle.create(missing_query, {
		Registry.SURFACE_HEIGHT_M: Sample.create(Registry.SURFACE_HEIGHT_M, BODY_ID, FRAME_ID, POSITION, SOURCE_HEIGHT_M, provenance),
		Registry.VALLEY_INFLUENCE: Sample.create(Registry.VALLEY_INFLUENCE, BODY_ID, FRAME_ID, POSITION, VALLEY_INFLUENCE, provenance),
		Registry.RIVER_DISTANCE_M: Sample.create(Registry.RIVER_DISTANCE_M, BODY_ID, FRAME_ID, POSITION, 0.0, provenance),
	})
	_ok(Bundle.validate(missing_bundle), "missing-width source bundle itself validates")
	var missing := River.apply(missing_bundle, profile)
	_check(not _success(missing), "missing river width rejected")
	_check(String(missing.get("error_code", "")) == "G8_2_REQUIRED_SEMANTIC_FIELD_MISSING", "missing width error code")

	var zero_width := River.apply(_bundle(0.0, 0.0), profile)
	_check(not _success(zero_width), "zero river width rejected")

	var negative_distance := River.apply(_bundle(-1.0, RIVER_WIDTH_M), profile)
	_check(not _success(negative_distance), "negative river distance rejected")


func _test_ownership_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/geomorphology/river_channel_incision_v1.gd")
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
		"FileAccess.open(",
	]:
		_check(source.find(forbidden) < 0, "G8.2 source excludes %s" % forbidden)
	_check(source.find("lod") < 0 and source.find("LOD") < 0, "G8.2 source excludes LOD")


func _bundle(river_distance_m: float, river_width_m: float) -> Dictionary:
	var fields := [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M]
	var query := Query.create(BODY_ID, FRAME_ID, POSITION, fields)
	var provenance := _provenance()
	return Bundle.create(query, {
		Registry.SURFACE_HEIGHT_M: Sample.create(Registry.SURFACE_HEIGHT_M, BODY_ID, FRAME_ID, POSITION, SOURCE_HEIGHT_M, provenance),
		Registry.VALLEY_INFLUENCE: Sample.create(Registry.VALLEY_INFLUENCE, BODY_ID, FRAME_ID, POSITION, VALLEY_INFLUENCE, provenance),
		Registry.RIVER_DISTANCE_M: Sample.create(Registry.RIVER_DISTANCE_M, BODY_ID, FRAME_ID, POSITION, river_distance_m, provenance),
		Registry.RIVER_WIDTH_M: Sample.create(Registry.RIVER_WIDTH_M, BODY_ID, FRAME_ID, POSITION, river_width_m, provenance),
	})


func _provenance() -> Dictionary:
	return Provenance.create(
		"semantic-field-producer/g8-river-fixture",
		"1.0.0",
		[],
		[],
		GeoUtils.payload_hash({"fixture": "g8.2"})
	)


func _only_valley_and_river_nonzero(deformation: Dictionary) -> bool:
	var components: Dictionary = deformation["component_deltas_m"]
	return (
		float(components[Deformation.COMPONENT_VALLEY]) < 0.0
		and float(components[Deformation.COMPONENT_RIVER_CHANNEL]) < 0.0
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
		print("G8.2 River Channel Incision: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("G8.2 FAIL: %s" % failure)
	print("G8.2 River Channel Incision: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
