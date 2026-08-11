extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const Query = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const Provenance = preload("res://scripts/simulation/procedural/contracts/semantic_field_provenance.gd")
const Sample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Bundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const BanksFloodplain = preload("res://scripts/simulation/procedural/geomorphology/banks_floodplain_shaping_v1.gd")
const ErosionDeposition = preload("res://scripts/simulation/procedural/geomorphology/erosion_deposition_baseline_v1.gd")

const BODY_ID := "body/g8-erosion-deposition-fixture"
const FRAME_ID := "body/g8-erosion-deposition-fixture/fixed"
const POSITION := [6000000.0, 100.0, -200.0]
const SOURCE_HEIGHT_M := 100.0
const VALLEY_INFLUENCE := 0.25
const RIVER_WIDTH_M := 100.0

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest_and_parent()
	_test_signed_lobes()
	_test_parent_composition()
	_test_determinism_profile_and_rejections()
	_test_ownership_boundary()
	_finish()


func _test_manifest_and_parent() -> void:
	var g83 = JSON.parse_string(FileAccess.get_file_as_string("res://validation/g8-3-banks-floodplain-validation.json"))
	_check(g83 is Dictionary, "G8.3 validation parses")
	if g83 is Dictionary:
		_check(String(g83.get("decision", "")) == "ACCEPTED", "G8.3 parent accepted")
		_check(String(g83.get("automated_evidence", {}).get("tested_head", "")) == "ce8b76f5ba46c3ed105ab6d4ee71ab7d8aadaf50", "G8.3 accepted tested head")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/procedural/g8-4-erosion-deposition-baseline.v1.json"))
	_check(parsed is Dictionary, "G8.4 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g8.4-erosion-deposition-baseline", "G8.4 checkpoint")
		_check(String(parsed.get("status", "")) in ["IMPLEMENTED_CANDIDATE", "ACCEPTED"], "G8.4 status supports candidate to accepted transition")
		_check(String(parsed.get("generator_id", "")) == ErosionDeposition.GENERATOR_ID, "manifest generator id")
		_check(Array(parsed.get("inputs", [])) == [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M], "manifest inputs")
		_check(not bool(parsed.get("ownership", {}).get("matter_mutation", true)), "manifest excludes Matter mutation")
		_check(not bool(parsed.get("ownership", {}).get("sediment_inventory_ownership", true)), "manifest excludes sediment inventory ownership")
		_check(not bool(parsed.get("ownership", {}).get("time_integration_ownership", true)), "manifest excludes time integration ownership")


func _test_signed_lobes() -> void:
	var profile := Profile.create("geomorphology-profile/g8-erosion-deposition-default")
	_ok(Profile.validate(profile), "default profile validates")
	var cases := [
		[0.0, 0.0, "channel center zero"],
		[67.5, -1.5, "erosion peak negative"],
		[100.0, 0.0, "handoff zero"],
		[162.5, 1.5, "deposition peak positive"],
		[275.0, 0.0, "outer boundary zero"],
	]
	for entry in cases:
		var result := ErosionDeposition.apply(_bundle(float(entry[0]), RIVER_WIDTH_M), profile)
		_ok(result, String(entry[2]))
		if _success(result):
			var delta := float(result["details"]["deformation"]["component_deltas_m"][Deformation.COMPONENT_EROSION_DEPOSITION])
			_check(_near(delta, float(entry[1])), "%s delta" % String(entry[2]))
			_ok(Deformation.validate_against_profile(result["details"]["deformation"], profile), "%s validates" % String(entry[2]))


func _test_parent_composition() -> void:
	var profile := Profile.create("geomorphology-profile/g8-erosion-deposition-compose")
	for distance_m in [25.0, 67.5, 125.0, 162.5, 300.0]:
		var source := _bundle(distance_m, RIVER_WIDTH_M)
		var parent := BanksFloodplain.apply(source, profile)
		var shaped := ErosionDeposition.apply(source, profile)
		_ok(parent, "G8.3 parent applies at %.1f" % distance_m)
		_ok(shaped, "G8.4 applies at %.1f" % distance_m)
		if _success(parent) and _success(shaped):
			var pd: Dictionary = parent["details"]["deformation"]
			var sd: Dictionary = shaped["details"]["deformation"]
			_check(String(shaped["details"]["banks_floodplain_deformation_checksum"]) == String(pd["checksum"]), "exact G8.3 checksum at %.1f" % distance_m)
			for component in [Deformation.COMPONENT_VALLEY, Deformation.COMPONENT_RIVER_CHANNEL, Deformation.COMPONENT_BANK, Deformation.COMPONENT_FLOODPLAIN]:
				_check(_near(float(sd["component_deltas_m"][component]), float(pd["component_deltas_m"][component])), "preserves %s at %.1f" % [component, distance_m])
			_check(String(sd["source_semantic_bundle_checksum"]) == String(source["checksum"]), "same semantic bundle at %.1f" % distance_m)


func _test_determinism_profile_and_rejections() -> void:
	var profile := Profile.create("geomorphology-profile/g8-erosion-deposition-determinism")
	var source := _bundle(162.5, RIVER_WIDTH_M)
	var first := ErosionDeposition.apply(source, profile)
	var second := ErosionDeposition.apply(source, profile)
	_ok(first, "first deterministic sample")
	_ok(second, "second deterministic sample")
	if _success(first) and _success(second):
		_check(String(first["details"]["deformation"]["checksum"]) == String(second["details"]["deformation"]["checksum"]), "same inputs same deformation checksum")
	var custom := Profile.create("geomorphology-profile/g8-erosion-deposition-custom", "1.0.0", 180.0, 35.0, 8.0, 12.0, 10.0, 1.5, 0.35)
	var custom_erosion := ErosionDeposition.apply(_bundle_with_valley(67.5, RIVER_WIDTH_M, 0.5), custom)
	var custom_deposition := ErosionDeposition.apply(_bundle_with_valley(162.5, RIVER_WIDTH_M, 0.5), custom)
	_ok(custom_erosion, "custom erosion profile applies")
	_ok(custom_deposition, "custom deposition profile applies")
	if _success(custom_erosion):
		_check(_near(float(custom_erosion["details"]["erosion_deposition_delta_m"]), -5.0), "custom erosion amplitude")
	if _success(custom_deposition):
		_check(_near(float(custom_deposition["details"]["erosion_deposition_delta_m"]), 5.0), "custom deposition amplitude")
	var zero_valley := ErosionDeposition.apply(_bundle_with_valley(162.5, RIVER_WIDTH_M, 0.0), profile)
	_ok(zero_valley, "zero valley query applies")
	if _success(zero_valley):
		_check(_near(float(zero_valley["details"]["erosion_deposition_delta_m"]), 0.0), "zero valley suppresses redistribution")
	var zero_width := ErosionDeposition.apply(_bundle(0.0, 0.0), profile)
	_check(not _success(zero_width) and String(zero_width.get("error_code", "")) == "G8_4_RIVER_WIDTH_MUST_BE_POSITIVE", "zero river width rejected")
	var negative_distance := ErosionDeposition.apply(_bundle(-1.0, RIVER_WIDTH_M), profile)
	_check(not _success(negative_distance) and String(negative_distance.get("error_code", "")) == "G8_4_RIVER_DISTANCE_MUST_BE_NON_NEGATIVE", "negative river distance rejected")
	var bad_valley := ErosionDeposition.apply(_bundle_with_valley(67.5, RIVER_WIDTH_M, 1.1), profile)
	_check(not _success(bad_valley) and String(bad_valley.get("error_code", "")) == "G8_4_VALLEY_INFLUENCE_OUT_OF_RANGE", "bad valley influence rejected")


func _test_ownership_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/geomorphology/erosion_deposition_baseline_v1.gd")
	for forbidden in ["SurfaceCellKey", "surface_cell_key", "AuthorityRegion", "InterestRegion", "MaterialDefinitionId", "material_definition_id", "MatterRevision", "ENetMultiplayerPeer", "Camera3D", "FileAccess.open(", "sediment_inventory", "delta_time"]:
		_check(source.find(forbidden) < 0, "G8.4 source excludes %s" % forbidden)
	_check(source.find("fluid-surface-distance") < 0 and source.find("FLUID_SURFACE_DISTANCE") < 0, "G8.4 does not reinterpret fluid surface distance")
	_check(source.find("lod") < 0 and source.find("LOD") < 0, "G8.4 source excludes LOD")


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
	return Provenance.create("semantic-field-producer/g8-erosion-deposition-fixture", "1.0.0", [], [], GeoUtils.payload_hash({"fixture": "g8.4"}))


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
		print("G8.4 Erosion / Deposition Baseline: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("G8.4 FAIL: %s" % failure)
	print("G8.4 Erosion / Deposition Baseline: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
