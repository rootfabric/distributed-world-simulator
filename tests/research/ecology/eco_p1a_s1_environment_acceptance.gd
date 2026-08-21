extends SceneTree

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const EXPECTED_ENVIRONMENT_HASH := "b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7"
const SEAM_EPSILON_M := 0.0001
const RATIO_SEAM_TOLERANCE := 0.00001
const TEMPERATURE_SEAM_TOLERANCE_C := 0.00005

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_sample_contract()
	_test_fixture_determinism()
	_test_control_point_causality()
	_test_seam_continuity()
	_test_resolution_independence()
	_test_ownership_boundary()
	_finish()


func _test_manifest() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://config/ecology/eco-p1a-s1-environment-baseline.v1.json"))
	_check(manifest is Dictionary, "manifest parses")
	if not manifest is Dictionary:
		return
	_check(String(manifest.get("checkpoint", "")) == "ECO.P1A-S1", "checkpoint id")
	_check(String(manifest.get("status", "")) == "FOCUSED_ACCEPTED", "focused accepted status")
	_check(String(manifest.get("branch", "")) == "feature/eco-evolutionary-ecology", "branch id")
	_check(String(manifest.get("architecture_revision", "")) == "GLOBAL-P0-2026-08-10-R2", "architecture revision")
	_check(String(manifest.get("control_plane_revision", "")) == "PC0-2026-08-10-R1", "control revision")
	_check(Array(manifest.get("fields", [])).size() == 5, "five environment fields")
	_check(Array(manifest.get("control_points", [])).size() == 8, "eight control points")


func _test_sample_contract() -> void:
	var sample := Fixture.sample_at(123.5, -456.25)
	_ok(EnvironmentSample.validate(sample), "sample validates")
	_check(String(sample["schema"]) == EnvironmentSample.SCHEMA, "sample schema")
	_check(String(sample["version"]) == EnvironmentSample.VERSION, "sample version")
	_check(String(sample["environment_revision"]) == Fixture.ENVIRONMENT_REVISION, "environment revision")
	_check(int(sample["seed"]) == Fixture.DEFAULT_SEED, "sample seed")
	_check(sample.keys().size() == EnvironmentSample.FIELD_NAMES.size(), "sample exact field count")
	for forbidden in ["lod", "camera_id", "surface_cell_key", "authority_region_id", "interest_region_id", "biome", "biome_id"]:
		_check(not sample.has(forbidden), "sample excludes %s" % forbidden)

	var tampered := sample.duplicate(true)
	tampered["soil_moisture"] = 2.0
	tampered["checksum"] = EnvironmentSample.compute_checksum(tampered)
	_check(String(EnvironmentSample.validate(tampered).get("error_code", "")) == "ECO_ENV_SAMPLE_INVALID_RATIO", "invalid ratio rejected")

	var with_lod := sample.duplicate(true)
	with_lod["lod"] = 3
	with_lod["checksum"] = EnvironmentSample.compute_checksum(with_lod)
	_check(String(EnvironmentSample.validate(with_lod).get("error_code", "")) == "ECO_ENV_SAMPLE_FIELD_COUNT_MISMATCH", "LOD injection rejected")


func _test_fixture_determinism() -> void:
	var first := Fixture.sample_at(777.25, -111.75)
	var second := Fixture.sample_at(777.25, -111.75)
	_check(String(first["checksum"]) == String(second["checksum"]), "same coordinate deterministic sample checksum")
	_check(first == second, "same coordinate deterministic full sample")

	var hash_a := Fixture.environment_hash()
	var hash_b := Fixture.environment_hash()
	print("ECO.P1A-S1 environment_hash=%s" % hash_a)
	_check(hash_a == hash_b, "same seed deterministic fixture hash")
	_check(hash_a == EXPECTED_ENVIRONMENT_HASH, "fixture hash matches accepted baseline")
	var other_seed_hash := Fixture.environment_hash(Fixture.LOGICAL_GRID_SIZE, Fixture.DEFAULT_SEED + 1)
	_check(other_seed_hash != hash_a, "different seed changes fixture hash")


func _test_control_point_causality() -> void:
	var river_bank := Fixture.control_point("river_bank")
	var floodplain := Fixture.control_point("floodplain")
	var wet_lowland := Fixture.control_point("wet_lowland")
	var sunny_slope := Fixture.control_point("sunny_slope")
	var shaded_slope := Fixture.control_point("shaded_slope")
	var plateau := Fixture.control_point("plateau")
	var dry_ridge := Fixture.control_point("dry_ridge")
	for sample in [river_bank, floodplain, wet_lowland, sunny_slope, shaded_slope, plateau, dry_ridge]:
		_ok(EnvironmentSample.validate(sample), "control point validates")

	_check(float(river_bank["soil_moisture"]) > float(dry_ridge["soil_moisture"]), "river bank wetter than dry ridge")
	_check(float(wet_lowland["soil_moisture"]) > float(plateau["soil_moisture"]), "wet lowland wetter than plateau")
	_check(float(floodplain["flood_frequency"]) > float(plateau["flood_frequency"]), "floodplain floods more than plateau")
	_check(float(river_bank["nutrients"]) > float(dry_ridge["nutrients"]), "river bank richer than dry ridge")
	_check(float(sunny_slope["sunlight"]) > float(shaded_slope["sunlight"]), "sunny slope receives more light than shaded slope")


func _test_seam_continuity() -> void:
	for boundary_index in [17, 41, 64, 95, 111]:
		var x := Fixture.logical_cell_boundary_x(boundary_index)
		var left := Fixture.sample_at(x - SEAM_EPSILON_M, 321.5)
		var right := Fixture.sample_at(x + SEAM_EPSILON_M, 321.5)
		_assert_samples_continuous(left, right, "x boundary %d" % boundary_index)

	for boundary_index in [13, 37, 64, 89, 116]:
		var z := Fixture.logical_cell_boundary_z(boundary_index)
		var below := Fixture.sample_at(-517.25, z - SEAM_EPSILON_M)
		var above := Fixture.sample_at(-517.25, z + SEAM_EPSILON_M)
		_assert_samples_continuous(below, above, "z boundary %d" % boundary_index)


func _test_resolution_independence() -> void:
	var probes := [
		Vector2(-2000.0, -2000.0),
		Vector2(-750.5, 310.25),
		Vector2(0.0, 0.0),
		Vector2(999.25, -1234.75),
		Vector2(2000.0, 2000.0),
	]
	for probe in probes:
		var canonical := Fixture.sample_at(probe.x, probe.y)
		var repeated := Fixture.sample_at(probe.x, probe.y)
		_check(String(canonical["checksum"]) == String(repeated["checksum"]), "canonical coordinate independent from presentation resolution at %s" % probe)

	var coarse_center := Fixture.grid_position(16, 16, 33)
	var fine_center := Fixture.grid_position(32, 32, 65)
	_check(coarse_center.is_equal_approx(fine_center), "coarse/fine grids share exact center coordinate")
	var coarse_sample := Fixture.sample_at(coarse_center.x, coarse_center.y)
	var fine_sample := Fixture.sample_at(fine_center.x, fine_center.y)
	_check(String(coarse_sample["checksum"]) == String(fine_sample["checksum"]), "shared coordinate has identical sample across grid resolutions")


func _test_ownership_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/environment_sample_v1.gd")
	source += FileAccess.get_file_as_string("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
	for forbidden in [
		"Camera3D",
		"SurfaceCellKey",
		"surface_cell_key.gd",
		"AuthorityRegion",
		"InterestRegion",
		"MaterialDefinitionId",
		"ENetMultiplayerPeer",
		"WorldAddress",
		"FileAccess.open(",
	]:
		_check(source.find(forbidden) < 0, "research environment excludes %s" % forbidden)
	_check(source.find("DESERT_PLANT") < 0, "no hardcoded desert plant role")
	_check(source.find("RIVER_PLANT") < 0, "no hardcoded river plant role")
	_check(source.find("FOREST_TREE") < 0, "no hardcoded forest tree role")


func _assert_samples_continuous(a: Dictionary, b: Dictionary, label: String) -> void:
	_check(absf(float(a["temperature_c"]) - float(b["temperature_c"])) <= TEMPERATURE_SEAM_TOLERANCE_C, "%s temperature continuity" % label)
	for field_name in EnvironmentSample.RATIO_FIELDS:
		_check(absf(float(a[field_name]) - float(b[field_name])) <= RATIO_SEAM_TOLERANCE, "%s %s continuity" % [label, field_name])


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
		print("ECO.P1A-S1 Environment Baseline: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1A-S1 FAIL: %s" % failure)
	print("ECO.P1A-S1 Environment Baseline: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
