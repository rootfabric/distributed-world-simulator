extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")

const BODY_ID := "body/g8-fixture"
const FRAME_ID := "body/g8-fixture/fixed"
const POSITION := [6000000.0, 125.0, -250.0]
const PROFILE_ID := "geomorphology-profile/g8-earthlike-fixture"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_parent_and_manifest()
	_test_profile_contract()
	_test_deformation_contract()
	_test_profile_bounds()
	_test_identity_and_ownership_boundary()
	_finish()


func _test_parent_and_manifest() -> void:
	var parent = JSON.parse_string(FileAccess.get_file_as_string("res://validation/g7-full-acceptance-validation.json"))
	_check(parent is Dictionary, "G7 full acceptance record parses")
	if parent is Dictionary:
		_check(String(parent.get("decision", "")) == "ACCEPTED", "G7 parent is accepted")
		_check(String(parent.get("tested_head", "")) == "a75a60b6da739cc759e1fb40510a98942bce4cde", "G7 accepted tested head")

	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://config/procedural/g8-0-geomorphology-contracts.v1.json"))
	_check(manifest is Dictionary, "G8.0 manifest parses")
	if not manifest is Dictionary:
		return
	_check(String(manifest.get("checkpoint", "")) == "g8.0-geomorphology-contracts", "G8.0 checkpoint")
	_check(String(manifest.get("status", "")) == "ACCEPTED", "G8.0 accepted status")
	_check(String(manifest.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-10-R2", "architecture revision")
	_check(String(manifest.get("control_plane_revision", "")) == "PC0-2026-08-10-R1", "control revision")
	_check(String(manifest.get("branch", "")) == "feature/g8-geomorphology", "G8 branch")
	_check(String(manifest.get("parent", {}).get("decision", "")) == "ACCEPTED", "manifest parent accepted")
	_check(String(manifest.get("composition_rule", "")) == "resolved_surface_height_m = source_surface_height_m + sum(component_deltas_m)", "composition rule")
	_check(Array(manifest.get("deformation_components", [])).size() == 5, "five deformation components")
	for key in manifest.get("invariants", {}).keys():
		_check(not bool(manifest["invariants"][key]), "ownership invariant false: %s" % String(key))

	var acceptance: Dictionary = manifest.get("acceptance", {})
	_check(String(acceptance.get("tested_head", "")) == "7a34c5d58b5a766fd8f4da46073dfcea29673fe9", "G8.0 accepted tested head")
	_check(String(acceptance.get("focused_contracts", "")) == "PASS", "G8.0 focused evidence retained")
	_check(String(acceptance.get("full_world_regression", "")) == "PASS", "G8.0 full regression evidence retained")
	_check(String(acceptance.get("working_tree", "")) == "CLEAN", "G8.0 clean-tree evidence retained")

	var planned_inputs: Array = manifest.get("planned_g8_1_inputs", [])
	_check(planned_inputs.size() == 2, "G8.1 has exactly two planned semantic inputs")
	for field_id in [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE]:
		_check(planned_inputs.has(field_id), "planned G8.1 input %s" % field_id)
	for field_id in [Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M, Registry.FLUID_SURFACE_DISTANCE_M]:
		_check(not planned_inputs.has(field_id), "future river/fluid input not prematurely owned by G8.1: %s" % field_id)

	var future_inputs: Array = manifest.get("future_g8_inputs", [])
	_check(future_inputs.size() == 3, "three future G8 river/fluid semantic inputs")
	for field_id in [Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M, Registry.FLUID_SURFACE_DISTANCE_M]:
		_check(future_inputs.has(field_id), "future G8 input %s" % field_id)


func _test_profile_contract() -> void:
	var profile := Profile.create(PROFILE_ID)
	_ok(Profile.validate(profile), "default profile validates")
	_check(String(profile["schema"]) == Profile.SCHEMA, "profile schema")
	_check(String(profile["profile_id"]) == PROFILE_ID, "profile id")
	_check(String(profile["version"]) == "1.0.0", "profile version")
	_check(GeoUtils.is_lower_hex_64(profile["checksum"]), "profile checksum shape")
	var repeated := Profile.create(PROFILE_ID)
	_check(String(repeated["checksum"]) == String(profile["checksum"]), "profile deterministic checksum")

	var invalid_depth := profile.duplicate(true)
	invalid_depth["river_max_depth_m"] = -1.0
	invalid_depth["checksum"] = GeoUtils.compute_checksum(invalid_depth)
	_check(not _success(Profile.validate(invalid_depth)), "negative profile magnitude rejected")

	var invalid_ratio := profile.duplicate(true)
	invalid_ratio["river_edge_softness_ratio"] = 1.5
	invalid_ratio["checksum"] = GeoUtils.compute_checksum(invalid_ratio)
	_check(not _success(Profile.validate(invalid_ratio)), "invalid profile ratio rejected")

	var with_lod := profile.duplicate(true)
	with_lod["lod"] = 3
	with_lod["checksum"] = GeoUtils.compute_checksum(with_lod)
	_check(String(Profile.validate(with_lod).get("error_code", "")) == "UNEXPECTED_FIELD", "profile rejects LOD injection")


func _test_deformation_contract() -> void:
	var profile := Profile.create(PROFILE_ID)
	var source_bundle_checksum := GeoUtils.payload_hash({"fixture": "g8.0", "semantic": 1})
	var components := {
		Deformation.COMPONENT_VALLEY: -120.0,
		Deformation.COMPONENT_RIVER_CHANNEL: -20.0,
		Deformation.COMPONENT_BANK: 3.0,
		Deformation.COMPONENT_FLOODPLAIN: -4.0,
		Deformation.COMPONENT_EROSION_DEPOSITION: 1.0,
	}
	var sample := Deformation.create(BODY_ID, FRAME_ID, POSITION, profile, source_bundle_checksum, 450.0, components)
	_ok(Deformation.validate(sample), "deformation sample validates")
	_ok(Deformation.validate_against_profile(sample, profile), "deformation sample validates against profile")
	_check(GeoUtils.approximately_equal(float(sample["total_delta_height_m"]), -140.0), "component sum")
	_check(GeoUtils.approximately_equal(float(sample["resolved_surface_height_m"]), 310.0), "resolved height")
	_check(String(sample["profile_checksum"]) == String(profile["checksum"]), "sample binds profile checksum")
	_check(String(sample["source_semantic_bundle_checksum"]) == source_bundle_checksum, "sample binds semantic bundle checksum")
	_check(sample["body_fixed_position_m"] == POSITION, "sample preserves body-fixed position")
	_check(GeoUtils.is_lower_hex_64(sample["checksum"]), "sample checksum shape")

	var reordered := {
		Deformation.COMPONENT_EROSION_DEPOSITION: 1.0,
		Deformation.COMPONENT_BANK: 3.0,
		Deformation.COMPONENT_RIVER_CHANNEL: -20.0,
		Deformation.COMPONENT_FLOODPLAIN: -4.0,
		Deformation.COMPONENT_VALLEY: -120.0,
	}
	var repeated := Deformation.create(BODY_ID, FRAME_ID, POSITION, profile, source_bundle_checksum, 450.0, reordered)
	_check(String(repeated["checksum"]) == String(sample["checksum"]), "component insertion order does not change checksum")

	var positive_valley := sample.duplicate(true)
	positive_valley["component_deltas_m"][Deformation.COMPONENT_VALLEY] = 1.0
	positive_valley["total_delta_height_m"] = -19.0
	positive_valley["resolved_surface_height_m"] = 431.0
	positive_valley["checksum"] = GeoUtils.compute_checksum(positive_valley)
	_check(String(Deformation.validate(positive_valley).get("error_code", "")) == "G8_0_VALLEY_COMPONENT_MUST_NOT_RAISE_SURFACE", "valley cannot raise surface")

	var positive_river := sample.duplicate(true)
	positive_river["component_deltas_m"][Deformation.COMPONENT_RIVER_CHANNEL] = 2.0
	positive_river["total_delta_height_m"] = -118.0
	positive_river["resolved_surface_height_m"] = 332.0
	positive_river["checksum"] = GeoUtils.compute_checksum(positive_river)
	_check(String(Deformation.validate(positive_river).get("error_code", "")) == "G8_0_RIVER_COMPONENT_MUST_NOT_RAISE_SURFACE", "river channel cannot raise surface")

	var bad_total := sample.duplicate(true)
	bad_total["total_delta_height_m"] = -139.0
	bad_total["checksum"] = GeoUtils.compute_checksum(bad_total)
	_check(String(Deformation.validate(bad_total).get("error_code", "")) == "G8_0_DEFORMATION_COMPONENT_SUM_MISMATCH", "component sum mismatch rejected")

	var with_lod := sample.duplicate(true)
	with_lod["lod"] = 4
	with_lod["checksum"] = GeoUtils.compute_checksum(with_lod)
	_check(String(Deformation.validate(with_lod).get("error_code", "")) == "UNEXPECTED_FIELD", "deformation rejects LOD injection")

	var bad_source := sample.duplicate(true)
	bad_source["source_semantic_bundle_checksum"] = "not-a-checksum"
	bad_source["checksum"] = GeoUtils.compute_checksum(bad_source)
	_check(String(Deformation.validate(bad_source).get("error_code", "")) == "INVALID_G8_0_DEFORMATION_SOURCE_BUNDLE_CHECKSUM", "invalid semantic source checksum rejected")

	var zeros := Deformation.zero_components()
	_check(zeros.keys().size() == 5, "zero components complete")
	var zero_sample := Deformation.create(BODY_ID, FRAME_ID, POSITION, profile, source_bundle_checksum, 450.0, zeros)
	_ok(Deformation.validate_against_profile(zero_sample, profile), "zero deformation valid")
	_check(GeoUtils.approximately_equal(float(zero_sample["resolved_surface_height_m"]), 450.0), "zero deformation preserves height")


func _test_profile_bounds() -> void:
	var profile := Profile.create(PROFILE_ID)
	var source_bundle_checksum := GeoUtils.payload_hash({"fixture": "bounds"})
	var components := Deformation.zero_components()
	components[Deformation.COMPONENT_VALLEY] = -(float(profile["valley_max_depth_m"]) + 0.001)
	var too_deep := Deformation.create(BODY_ID, FRAME_ID, POSITION, profile, source_bundle_checksum, 0.0, components)
	_check(String(Deformation.validate_against_profile(too_deep, profile).get("error_code", "")) == "G8_0_VALLEY_DEPTH_EXCEEDS_PROFILE", "valley profile bound")

	components = Deformation.zero_components()
	components[Deformation.COMPONENT_RIVER_CHANNEL] = -(float(profile["river_max_depth_m"]) + 0.001)
	var river_too_deep := Deformation.create(BODY_ID, FRAME_ID, POSITION, profile, source_bundle_checksum, 0.0, components)
	_check(String(Deformation.validate_against_profile(river_too_deep, profile).get("error_code", "")) == "G8_0_RIVER_DEPTH_EXCEEDS_PROFILE", "river profile bound")

	components = Deformation.zero_components()
	components[Deformation.COMPONENT_BANK] = float(profile["bank_max_delta_m"]) + 0.001
	var bank_too_high := Deformation.create(BODY_ID, FRAME_ID, POSITION, profile, source_bundle_checksum, 0.0, components)
	_check(String(Deformation.validate_against_profile(bank_too_high, profile).get("error_code", "")) == "G8_0_BANK_DELTA_EXCEEDS_PROFILE", "bank profile bound")


func _test_identity_and_ownership_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
	source += FileAccess.get_file_as_string("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
	for forbidden in [
		"SurfaceCellKey",
		"surface_cell_key.gd",
		"AuthorityRegion",
		"InterestRegion",
		"WorldAddress",
		"MaterialDefinitionId",
		"material_definition_id",
		"Camera3D",
		"ImmediateMesh",
		"ENetMultiplayerPeer",
		"FileAccess.open(",
		"WorldQuery",
	]:
		_check(source.find(forbidden) < 0, "G8.0 contracts exclude %s" % forbidden)
	for key in ["surface_cell_key", "lod", "authority_region_id", "interest_region_id", "material_definition_id", "matter_revision", "network_peer_id"]:
		var profile := Profile.create(PROFILE_ID)
		var sample := Deformation.create(BODY_ID, FRAME_ID, POSITION, profile, GeoUtils.payload_hash({"source": 1}), 10.0, Deformation.zero_components())
		_check(not sample.has(key), "deformation schema excludes %s" % key)


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
		print("G8.0 Geomorphology Contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("G8.0 FAIL: %s" % failure)
	print("G8.0 Geomorphology Contracts: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
