extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const Query = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const Provenance = preload("res://scripts/simulation/procedural/contracts/semantic_field_provenance.gd")
const Sample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Bundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const River = preload("res://scripts/simulation/procedural/geomorphology/river_channel_incision_v1.gd")
const BanksFloodplain = preload("res://scripts/simulation/procedural/geomorphology/banks_floodplain_shaping_v1.gd")

const BODY_ID := "body/g8-banks-floodplain-fixture"
const FRAME_ID := "body/g8-banks-floodplain-fixture/fixed"
const POSITION := [6000000.0, 100.0, -200.0]
const SOURCE_HEIGHT_M := 100.0
const VALLEY_INFLUENCE := 0.25
const RIVER_WIDTH_M := 100.0

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest_and_parent()
	_test_channel_bank_floodplain_zones()
	_test_parent_composition()
	_test_determinism_and_profile_control()
	_test_rejections()
	_test_ownership_boundary()
	_finish()


func _test_manifest_and_parent() -> void:
	var g82 = JSON.parse_string(FileAccess.get_file_as_string("res://validation/g8-2-river-channel-incision-validation.json"))
	_check(g82 is Dictionary, "G8.2 validation parses")
	if g82 is Dictionary:
		_check(String(g82.get("decision", "")) == "ACCEPTED", "G8.2 parent accepted")
		_check(String(g82.get("automated_evidence", {}).get("tested_head", "")) == "491fe10877c70c362c14ab595a8a0204165a880a", "G8.2 accepted tested head")

	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/procedural/g8-3-banks-floodplain-shaping.v1.json"))
	_check(parsed is Dictionary, "G8.3 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g8.3-banks-and-floodplain-shaping", "G8.3 checkpoint")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G8.3 candidate status")
		_check(String(parsed.get("generator_id", "")) == BanksFloodplain.GENERATOR_ID, "manifest generator id")
		_check(Array(parsed.get("inputs", [])) == [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M], "manifest inputs")
		_check(not bool(parsed.get("ownership", {}).get("matter_mutation", true)), "manifest excludes Matter mutation")
		_check(not bool(parsed.get("ownership", {}).get("fluid_surface_distance_used", true)), "manifest does not fake fluid surface elevation")


func _test_channel_bank_floodplain_zones() -> void:
	var profile := Profile.create("geomorphology-profile/g8-banks-floodplain-default")
	_ok(Profile.validate(profile), "default profile validates")

	var center := BanksFloodplain.apply(_bundle(0.0, RIVER_WIDTH_M), profile)
	_ok(center, "channel center applies")
	if _success(center):
		var d: Dictionary = center["details"]["deformation"]
		_check(_near(float(center["details"]["bank_weight"]), 0.0), "channel center bank weight zero")
		_check(_near(float(center["details"]["floodplain_weight"]), 0.0), "channel center floodplain weight zero")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_BANK]), 0.0), "channel center bank delta zero")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_FLOODPLAIN]), 0.0), "channel center floodplain delta zero")

	var channel_edge := BanksFloodplain.apply(_bundle(50.0, RIVER_WIDTH_M), profile)
	_ok(channel_edge, "channel edge applies")
	if _success(channel_edge):
		_check(_near(float(channel_edge["details"]["normalized_distance"]), 1.0), "channel edge normalized distance one")
		_check(_near(float(channel_edge["details"]["bank_weight"]), 0.0), "bank starts continuously from zero at channel edge")

	var bank_peak := BanksFloodplain.apply(_bundle(75.0, RIVER_WIDTH_M), profile)
	_ok(bank_peak, "bank peak applies")
	if _success(bank_peak):
		var d: Dictionary = bank_peak["details"]["deformation"]
		_check(_near(float(bank_peak["details"]["normalized_distance"]), 1.5), "bank peak normalized distance")
		_check(_near(float(bank_peak["details"]["bank_weight"]), 1.0), "bank peak weight one")
		_check(_near(float(bank_peak["details"]["floodplain_weight"]), 0.0), "bank peak does not yet shape floodplain")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_BANK]), 2.0), "bank peak uses profile max scaled by valley influence")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_FLOODPLAIN]), 0.0), "bank peak floodplain delta zero")

	var bank_outer := BanksFloodplain.apply(_bundle(100.0, RIVER_WIDTH_M), profile)
	_ok(bank_outer, "bank outer edge applies")
	if _success(bank_outer):
		_check(_near(float(bank_outer["details"]["normalized_distance"]), 2.0), "bank outer normalized distance")
		_check(_near(float(bank_outer["details"]["bank_weight"]), 0.0), "bank ends continuously at outer edge")
		_check(_near(float(bank_outer["details"]["floodplain_weight"]), 0.0), "floodplain begins continuously from zero")

	var flood_transition := BanksFloodplain.apply(_bundle(112.5, RIVER_WIDTH_M), profile)
	_ok(flood_transition, "floodplain transition applies")
	if _success(flood_transition):
		var d: Dictionary = flood_transition["details"]["deformation"]
		_check(_near(float(flood_transition["details"]["normalized_distance"]), 2.25), "floodplain transition normalized distance")
		_check(_near(float(flood_transition["details"]["floodplain_weight"]), 0.5), "floodplain transition cubic midpoint")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_FLOODPLAIN]), -1.5), "floodplain transition half weighted depth")

	var flood_core := BanksFloodplain.apply(_bundle(125.0, RIVER_WIDTH_M), profile)
	_ok(flood_core, "floodplain core applies")
	if _success(flood_core):
		var d: Dictionary = flood_core["details"]["deformation"]
		_check(_near(float(flood_core["details"]["normalized_distance"]), 2.5), "floodplain core normalized distance")
		_check(_near(float(flood_core["details"]["floodplain_weight"]), 1.0), "floodplain core weight one")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_FLOODPLAIN]), -3.0), "floodplain core uses profile max scaled by valley influence")

	var flood_fade := BanksFloodplain.apply(_bundle(262.5, RIVER_WIDTH_M), profile)
	_ok(flood_fade, "floodplain outer fade applies")
	if _success(flood_fade):
		var d: Dictionary = flood_fade["details"]["deformation"]
		_check(_near(float(flood_fade["details"]["normalized_distance"]), 5.25), "floodplain fade normalized distance")
		_check(_near(float(flood_fade["details"]["floodplain_weight"]), 0.5), "floodplain outer fade cubic midpoint")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_FLOODPLAIN]), -1.5), "floodplain outer fade half depth")

	var outside := BanksFloodplain.apply(_bundle(300.0, RIVER_WIDTH_M), profile)
	_ok(outside, "outside floodplain applies")
	if _success(outside):
		var d: Dictionary = outside["details"]["deformation"]
		_check(_near(float(outside["details"]["bank_weight"]), 0.0), "outside bank weight zero")
		_check(_near(float(outside["details"]["floodplain_weight"]), 0.0), "outside floodplain weight zero")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_BANK]), 0.0), "outside bank delta zero")
		_check(_near(float(d["component_deltas_m"][Deformation.COMPONENT_FLOODPLAIN]), 0.0), "outside floodplain delta zero")


func _test_parent_composition() -> void:
	var profile := Profile.create("geomorphology-profile/g8-banks-floodplain-compose")
	for distance_m in [25.0, 75.0, 125.0, 300.0]:
		var source := _bundle(distance_m, RIVER_WIDTH_M)
		var parent := River.apply(source, profile)
		var shaped := BanksFloodplain.apply(source, profile)
		_ok(parent, "river parent applies at distance %.1f" % distance_m)
		_ok(shaped, "G8.3 applies at distance %.1f" % distance_m)
		if _success(parent) and _success(shaped):
			var pd: Dictionary = parent["details"]["deformation"]
			var sd: Dictionary = shaped["details"]["deformation"]
			_check(String(shaped["details"]["river_deformation_checksum"]) == String(pd["checksum"]), "G8.3 reports exact G8.2 checksum at %.1f" % distance_m)
			_check(_near(float(sd["component_deltas_m"][Deformation.COMPONENT_VALLEY]), float(pd["component_deltas_m"][Deformation.COMPONENT_VALLEY])), "G8.3 preserves valley component at %.1f" % distance_m)
			_check(_near(float(sd["component_deltas_m"][Deformation.COMPONENT_RIVER_CHANNEL]), float(pd["component_deltas_m"][Deformation.COMPONENT_RIVER_CHANNEL])), "G8.3 preserves river component at %.1f" % distance_m)
			_check(_near(float(sd["component_deltas_m"][Deformation.COMPONENT_EROSION_DEPOSITION]), 0.0), "erosion remains zero at %.1f" % distance_m)
			_check(String(sd["source_semantic_bundle_checksum"]) == String(source["checksum"]), "G8.3 binds same semantic bundle at %.1f" % distance_m)
			_ok(Deformation.validate_against_profile(sd, profile), "G8.3 deformation validates at %.1f" % distance_m)


func _test_determinism_and_profile_control() -> void:
	var profile := Profile.create("geomorphology-profile/g8-banks-floodplain-determinism")
	var source := _bundle(75.0, RIVER_WIDTH_M)
	var first := BanksFloodplain.apply(source, profile)
	var second := BanksFloodplain.apply(source, profile)
	_ok(first, "first deterministic G8.3 sample")
	_ok(second, "second deterministic G8.3 sample")
	if _success(first) and _success(second):
		_check(String(first["details"]["deformation"]["checksum"]) == String(second["details"]["deformation"]["checksum"]), "same inputs produce same G8.3 deformation checksum")

	var custom := Profile.create("geomorphology-profile/g8-banks-floodplain-custom", "1.0.0", 180.0, 35.0, 4.0, 20.0, 6.0, 1.5, 0.35)
	var custom_bank := BanksFloodplain.apply(_bundle_with_valley(75.0, RIVER_WIDTH_M, 0.5), custom)
	var custom_flood := BanksFloodplain.apply(_bundle_with_valley(125.0, RIVER_WIDTH_M, 0.5), custom)
	_ok(custom_bank, "custom bank profile applies")
	_ok(custom_flood, "custom floodplain profile applies")
	if _success(custom_bank):
		_check(_near(float(custom_bank["details"]["deformation"]["component_deltas_m"][Deformation.COMPONENT_BANK]), 2.0), "custom bank max controls bank amplitude")
	if _success(custom_flood):
		_check(_near(float(custom_flood["details"]["deformation"]["component_deltas_m"][Deformation.COMPONENT_FLOODPLAIN]), -10.0), "custom floodplain max controls floodplain amplitude")

	var zero_valley_bank := BanksFloodplain.apply(_bundle_with_valley(75.0, RIVER_WIDTH_M, 0.0), profile)
	var zero_valley_flood := BanksFloodplain.apply(_bundle_with_valley(125.0, RIVER_WIDTH_M, 0.0), profile)
	_ok(zero_valley_bank, "zero valley bank query applies")
	_ok(zero_valley_flood, "zero valley floodplain query applies")
	if _success(zero_valley_bank):
		_check(_near(float(zero_valley_bank["details"]["bank_delta_m"]), 0.0), "zero valley influence suppresses bank shaping")
	if _success(zero_valley_flood):
		_check(_near(float(zero_valley_flood["details"]["floodplain_delta_m"]), 0.0), "zero valley influence suppresses floodplain shaping")


func _test_rejections() -> void:
	var profile := Profile.create("geomorphology-profile/g8-banks-floodplain-rejections")
	var zero_width := BanksFloodplain.apply(_bundle(0.0, 0.0), profile)
	_check(not _success(zero_width), "zero river width rejected")
	_check(String(zero_width.get("error_code", "")) == "G8_3_RIVER_WIDTH_MUST_BE_POSITIVE", "zero width error code")

	var negative_distance := BanksFloodplain.apply(_bundle(-1.0, RIVER_WIDTH_M), profile)
	_check(not _success(negative_distance), "negative river distance rejected")
	_check(String(negative_distance.get("error_code", "")) == "G8_3_RIVER_DISTANCE_MUST_BE_NON_NEGATIVE", "negative distance error code")

	var bad_valley := BanksFloodplain.apply(_bundle_with_valley(75.0, RIVER_WIDTH_M, 1.1), profile)
	_check(not _success(bad_valley), "out-of-range valley influence rejected")
	_check(String(bad_valley.get("error_code", "")) == "G8_3_VALLEY_INFLUENCE_OUT_OF_RANGE", "bad valley influence error code")


func _test_ownership_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/geomorphology/banks_floodplain_shaping_v1.gd")
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
		_check(source.find(forbidden) < 0, "G8.3 source excludes %s" % forbidden)
	_check(source.find("fluid-surface-distance") < 0 and source.find("FLUID_SURFACE_DISTANCE") < 0, "G8.3 does not reinterpret fluid surface distance as elevation")
	_check(source.find("lod") < 0 and source.find("LOD") < 0, "G8.3 source excludes LOD")


func _bundle(river_distance_m: float, river_width_m: float) -> Dictionary:
	return _bundle_with_valley(river_distance_m, river_width_m, VALLEY_INFLUENCE)


func _bundle_with_valley(river_distance_m: float, river_width_m: float, valley_influence: float) -> Dictionary:
	var fields := [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M]
	var query := Query.create(BODY_ID, FRAME_ID, POSITION, fields)
	var provenance := _provenance()
	return Bundle.create(query, {
		Registry.SURFACE_HEIGHT_M: Sample.create(Registry.SURFACE_HEIGHT_M, BODY_ID, FRAME_ID, POSITION, SOURCE_HEIGHT_M, provenance),
		Registry.VALLEY_INFLUENCE: Sample.create(Registry.VALLEY_INFLUENCE, BODY_ID, FRAME_ID, POSITION, valley_influence, provenance),
		Registry.RIVER_DISTANCE_M: Sample.create(Registry.RIVER_DISTANCE_M, BODY_ID, FRAME_ID, POSITION, river_distance_m, provenance),
		Registry.RIVER_WIDTH_M: Sample.create(Registry.RIVER_WIDTH_M, BODY_ID, FRAME_ID, POSITION, river_width_m, provenance),
	})


func _provenance() -> Dictionary:
	return Provenance.create(
		"semantic-field-producer/g8-banks-floodplain-fixture",
		"1.0.0",
		[],
		[],
		GeoUtils.payload_hash({"fixture": "g8.3"})
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
		print("G8.3 Banks and Floodplain Shaping: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("G8.3 FAIL: %s" % failure)
	print("G8.3 Banks and Floodplain Shaping: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
