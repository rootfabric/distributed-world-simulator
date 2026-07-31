extends SceneTree

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const MassEstimateScript = preload("res://scripts/simulation/matter/contracts/matter_body_mass_estimate.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const FieldScript = preload("res://scripts/simulation/matter/generation/deterministic_field_3d.gd")
const ProfileScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")
const FeatureCatalogScript = preload("res://scripts/simulation/matter/generation/asteroid_feature_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const IntegratorScript = preload("res://scripts/simulation/matter/analysis/matter_body_mass_integrator.gd")

var failures: Array[String] = []
var assertions: int = 0
var manifest: Dictionary = {}
var profile: Dictionary = {}
var material_catalog: Dictionary = {}
var feature_catalog: Dictionary = {}
var body: Dictionary = {}


func _init() -> void:
	_load_fixture()
	_test_manifest()
	_test_profile_contract()
	_test_deterministic_field()
	_test_feature_catalog()
	_test_body_configuration()
	_test_control_fixture()
	_test_closed_shape_and_surface_queries()
	_test_geological_features()
	_test_sampler_properties()
	_test_mass_integration()
	_test_negative_configuration_cases()
	_finish()


func _load_fixture() -> void:
	profile = ProfileScript.default_profile()
	material_catalog = MaterialCatalogScript.default_catalog()
	feature_catalog = FeatureCatalogScript.create(profile)
	body = GeneratorScript.default_body_definition(profile, material_catalog, feature_catalog)
	var path: String = "res://config/matter/mw1-fixed-seed-asteroid.v1.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed


func _test_manifest() -> void:
	_assert(not manifest.is_empty(), "MW1 manifest is missing or invalid")
	if manifest.is_empty():
		return
	_assert(String(manifest.get("schema", "")) == "planet_simulator.mw1_fixed_seed_asteroid_manifest.v1", "MW1 manifest schema changed")
	_assert(String(manifest.get("checkpoint", "")) == "v17.1.0-simulation-mw1-fixed-seed-asteroid", "MW1 checkpoint changed")
	_assert(String(manifest.get("base_checkpoint", "")) == "v17.0.0-simulation-mw0-matter-contracts", "MW1 base checkpoint changed")
	_assert(String(manifest.get("base_delivery", "")) == "fix1", "MW1 base delivery changed")
	_assert(String(manifest.get("recommended_branch", "")) == "feature/mw1-fixed-seed-asteroid", "MW1 branch changed")
	_assert(not bool(manifest.get("runtime_worlds_changed", true)), "MW1 unexpectedly changes runtime worlds")
	_assert(not bool(manifest.get("moon_runtime_changed", true)), "MW1 unexpectedly changes Moon runtime")
	_assert(not bool(manifest.get("mesh_or_collision_added", true)), "MW1 unexpectedly adds mesh or collision")
	var fixture = manifest.get("asteroid_fixture")
	_assert(typeof(fixture) == TYPE_DICTIONARY, "MW1 asteroid fixture is missing")
	if typeof(fixture) == TYPE_DICTIONARY:
		_assert(String(fixture.get("body_id", "")) == GeneratorScript.BODY_ID, "MW1 body ID changed")
		_assert(String(fixture.get("body_frame_id", "")) == GeneratorScript.BODY_FRAME_ID, "MW1 body frame changed")
		_assert(int(fixture.get("generator_seed", 0)) == ProfileScript.DEFAULT_SEED, "MW1 seed changed")
		_assert(absf(float(fixture.get("reference_radius_m", 0.0)) - ProfileScript.DEFAULT_RADIUS_M) < 0.000000001, "MW1 radius changed")
	_assert(int(manifest.get("control_point_count", 0)) == 128, "MW1 control point count changed")
	_assert(MatterUtilsScript.is_lower_hex_64(manifest.get("control_fixture_hash")), "MW1 control fixture hash is invalid")


func _test_profile_contract() -> void:
	_assert_ok(ProfileScript.validate(profile), "Default MW1 profile rejected")
	_assert(ProfileScript.normalize(profile) == profile, "MW1 profile normalization changed canonical value")
	_assert(String(profile["generator_id"]) == ProfileScript.GENERATOR_ID, "MW1 generator ID changed")
	_assert(String(profile["generator_version"]) == ProfileScript.GENERATOR_VERSION, "MW1 generator version changed")
	_assert(int(profile["generator_seed"]) == 2026073101, "MW1 fixed seed changed")
	_assert(typeof(profile["reference_radius_m"]) == TYPE_FLOAT, "MW1 radius lost float type")
	_assert(absf(float(profile["root_bounds_radius_ratio"]) - 1.45) < 0.000000001, "MW1 root bounds changed")
	var replay: Dictionary = ProfileScript.default_profile()
	_assert(replay == profile, "MW1 profile creation is non-deterministic")
	var tampered: Dictionary = profile.duplicate(true)
	tampered["axis_scale"][0] = 0.0
	tampered["checksum"] = MatterUtilsScript.compute_checksum(tampered)
	_assert_fail(ProfileScript.validate(tampered), "Zero asteroid axis scale accepted")
	var bad_shells: Dictionary = profile.duplicate(true)
	bad_shells["surface_regolith_depth_m"] = bad_shells["fractured_shell_depth_m"]
	bad_shells["checksum"] = MatterUtilsScript.compute_checksum(bad_shells)
	_assert_fail(ProfileScript.validate(bad_shells), "Invalid asteroid shell order accepted")
	var runtime_value: Dictionary = profile.duplicate(true)
	runtime_value["axis_scale"] = [1.0, 1.0, RefCounted.new()]
	runtime_value["checksum"] = MatterUtilsScript.compute_checksum(runtime_value)
	_assert_fail(ProfileScript.validate(runtime_value), "Runtime object accepted by asteroid profile")


func _test_deterministic_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7112026
	var changed_channels: int = 0
	for iteration in range(500):
		var point: Vector3 = Vector3(
			rng.randf_range(-2000.0, 2000.0),
			rng.randf_range(-2000.0, 2000.0),
			rng.randf_range(-2000.0, 2000.0)
		)
		var first: float = FieldScript.value_noise_3d(point, 0.0037, ProfileScript.DEFAULT_SEED, 17)
		var second: float = FieldScript.value_noise_3d(point, 0.0037, ProfileScript.DEFAULT_SEED, 17)
		var other_channel: float = FieldScript.value_noise_3d(point, 0.0037, ProfileScript.DEFAULT_SEED, 18)
		_assert(first == second, "Deterministic field changed at iteration %d" % iteration)
		_assert(first >= -1.0 and first <= 1.0, "Deterministic field escaped range at iteration %d" % iteration)
		if first != other_channel:
			changed_channels += 1
	_assert(changed_channels > 450, "Deterministic field channels are insufficiently independent")
	_assert(FieldScript.value_noise_3d(Vector3.ONE, 0.0, 1, 1) == 0.0, "Zero-frequency field is not neutral")


func _test_feature_catalog() -> void:
	_assert_ok(FeatureCatalogScript.validate(feature_catalog), "MW1 feature catalog rejected")
	_assert(feature_catalog["features"].size() == 7, "MW1 feature count changed")
	var expected_ids: Array = manifest.get("stable_feature_ids", [])
	var actual_ids: Array = []
	for feature in feature_catalog["features"]:
		actual_ids.append(String(feature["feature_id"]))
	_assert(actual_ids == expected_ids, "MW1 stable feature IDs changed")
	var replay: Dictionary = FeatureCatalogScript.create(profile)
	_assert(replay == feature_catalog, "MW1 feature catalog is non-deterministic")
	var alternate_profile: Dictionary = ProfileScript.create({"generator_seed": ProfileScript.DEFAULT_SEED + 1})
	var alternate_catalog: Dictionary = FeatureCatalogScript.create(alternate_profile)
	_assert_ok(FeatureCatalogScript.validate(alternate_catalog), "Alternate-seed feature catalog rejected")
	_assert(String(alternate_catalog["catalog_hash"]) != String(feature_catalog["catalog_hash"]), "Different seed produced identical feature catalog")
	for feature in feature_catalog["features"]:
		_assert(MatterUtilsScript.is_canonical_id(feature["feature_id"], 3), "Non-canonical stable feature ID")
		_assert(MatterUtilsScript.is_vector3_array(feature["center_m"]), "Feature center is invalid")
		_assert(MatterUtilsScript.is_vector3_array(feature["radii_m"]), "Feature radii are invalid")
	var mutated: Dictionary = feature_catalog.duplicate(true)
	mutated["features"][0]["center_m"][0] += 1.0
	_assert_fail(FeatureCatalogScript.validate(mutated), "Feature mutation passed catalog hash")


func _test_body_configuration() -> void:
	_assert(not body.is_empty(), "MW1 body definition was not created")
	_assert_ok(GeneratorScript.validate_configuration(body, material_catalog, profile, feature_catalog), "Valid MW1 configuration rejected")
	_assert(String(body["body_id"]) == GeneratorScript.BODY_ID, "MW1 body identity changed")
	_assert(String(body["generator_id"]) == ProfileScript.GENERATOR_ID, "MW1 body generator changed")
	_assert(int(body["generator_seed"]) == ProfileScript.DEFAULT_SEED, "MW1 body seed changed")
	_assert(String(body["metadata"]["generator_profile_checksum"]) == String(profile["checksum"]), "MW1 body did not bind profile checksum")
	_assert(String(body["metadata"]["feature_catalog_hash"]) == String(feature_catalog["catalog_hash"]), "MW1 body did not bind feature hash")
	var replay: Dictionary = GeneratorScript.default_body_definition(profile, material_catalog, feature_catalog)
	_assert(replay == body, "MW1 body definition is non-deterministic")


func _test_control_fixture() -> void:
	var points: Array = GeneratorScript.control_points_m(profile, feature_catalog)
	_assert(points.size() == 128, "MW1 did not produce 128 control points")
	var first_hash: String = GeneratorScript.control_fixture_hash(material_catalog, profile, feature_catalog)
	var second_hash: String = GeneratorScript.control_fixture_hash(material_catalog, profile, feature_catalog)
	_assert(first_hash == second_hash, "MW1 control fixture hash is non-deterministic")
	_assert(first_hash == String(manifest.get("control_fixture_hash", "")), "MW1 golden control fixture hash changed: %s" % first_hash)
	var alternate_profile: Dictionary = ProfileScript.create({"generator_seed": ProfileScript.DEFAULT_SEED + 1})
	var alternate_features: Dictionary = FeatureCatalogScript.create(alternate_profile)
	var alternate_hash: String = GeneratorScript.control_fixture_hash(material_catalog, alternate_profile, alternate_features)
	_assert(alternate_hash != first_hash, "Different seed produced identical control fixture")
	var forward_map: Dictionary = _sample_signature_map(points)
	var reversed_points: Array = points.duplicate()
	reversed_points.reverse()
	var reverse_map: Dictionary = _sample_signature_map(reversed_points)
	_assert(MatterUtilsScript.payload_hash(forward_map) == MatterUtilsScript.payload_hash(reverse_map), "Sampling depends on query order")


func _test_closed_shape_and_surface_queries() -> void:
	var center_distance: float = GeneratorScript.signed_distance_validated(profile, feature_catalog, Vector3.ZERO)
	_assert(center_distance < -100.0, "Asteroid center is not safely occupied")
	var root_bound: float = float(profile["reference_radius_m"]) * float(profile["root_bounds_radius_ratio"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 99173
	for iteration in range(96):
		var direction: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		)
		if direction.length_squared() < 0.01:
			direction = Vector3.RIGHT
		direction = direction.normalized()
		var surface_radius: float = GeneratorScript.surface_radius_validated(profile, feature_catalog, direction)
		var surface_distance: float = GeneratorScript.signed_distance_validated(profile, feature_catalog, direction * surface_radius)
		var inside_distance: float = GeneratorScript.signed_distance_validated(profile, feature_catalog, direction * maxf(surface_radius - 2.0, 0.0))
		var outside_distance: float = GeneratorScript.signed_distance_validated(profile, feature_catalog, direction * (surface_radius + 2.0))
		var root_distance: float = GeneratorScript.signed_distance_validated(profile, feature_catalog, direction * root_bound)
		_assert(surface_radius > 650.0 and surface_radius < root_bound, "Surface radius escaped bounds at direction %d" % iteration)
		_assert(absf(surface_distance) < 0.001, "Surface query did not converge at direction %d" % iteration)
		_assert(inside_distance <= 0.0, "Point inside outer surface is vacuum at direction %d" % iteration)
		_assert(outside_distance >= 0.0, "Point outside outer surface contains matter at direction %d" % iteration)
		_assert(root_distance > 0.0, "Root bound contains matter at direction %d" % iteration)
	var center_sample: Dictionary = GeneratorScript.sample(body, material_catalog, profile, feature_catalog, Vector3.ZERO)
	_assert_ok(SampleScript.validate(center_sample), "Center sample rejected")
	_assert(float(center_sample["occupancy_ratio"]) == 1.0, "Asteroid center is vacuum")
	var far_sample: Dictionary = GeneratorScript.sample(body, material_catalog, profile, feature_catalog, Vector3(root_bound + 100.0, 0.0, 0.0))
	_assert_ok(SampleScript.validate(far_sample), "Far vacuum sample rejected")
	_assert(float(far_sample["occupancy_ratio"]) == 0.0, "Matter exists outside root bounds")


func _test_geological_features() -> void:
	var void_feature: Dictionary = FeatureCatalogScript.feature_by_id(feature_catalog, "matter-feature/asteroid-mw1/natural-void-a")
	var ore_feature: Dictionary = FeatureCatalogScript.feature_by_id(feature_catalog, "matter-feature/asteroid-mw1/ore-lens-a")
	var ice_feature: Dictionary = FeatureCatalogScript.feature_by_id(feature_catalog, "matter-feature/asteroid-mw1/ice-pocket-a")
	_assert(not void_feature.is_empty(), "Natural void feature is missing")
	_assert(not ore_feature.is_empty(), "Ore lens feature is missing")
	_assert(not ice_feature.is_empty(), "Ice pocket feature is missing")
	var void_sample: Dictionary = _sample_at_feature(void_feature)
	_assert_ok(SampleScript.validate(void_sample), "Natural void sample rejected")
	_assert(float(void_sample["occupancy_ratio"]) == 0.0, "Natural void contains matter")
	var void_center: Vector3 = _vector3(void_feature["center_m"])
	var void_radii: Vector3 = _vector3(void_feature["radii_m"])
	var host_rock_sample: Dictionary = GeneratorScript.sample_validated(
		material_catalog,
		profile,
		feature_catalog,
		void_center + Vector3(void_radii.x + 5.0, 0.0, 0.0)
	)
	_assert(float(host_rock_sample["occupancy_ratio"]) == 1.0, "Host rock outside natural void is vacuum")
	_assert(Array(host_rock_sample["flags"]).has("matter-zone/interior"), "Natural void wall was misclassified as external regolith")
	var ore_sample: Dictionary = _sample_at_feature(ore_feature)
	_assert_ok(SampleScript.validate(ore_sample), "Ore lens sample rejected")
	_assert(float(ore_sample["occupancy_ratio"]) == 1.0, "Ore lens center is vacuum")
	_assert(_fraction_for(ore_sample, "matter/iron-nickel-ore") > 0.25, "Ore lens concentration is too low")
	_assert(Array(ore_sample["flags"]).has("matter-resource/iron-nickel"), "Ore lens semantic flag is missing")
	var ice_sample: Dictionary = _sample_at_feature(ice_feature)
	_assert_ok(SampleScript.validate(ice_sample), "Ice pocket sample rejected")
	_assert(float(ice_sample["occupancy_ratio"]) == 1.0, "Ice pocket center is vacuum")
	_assert(_fraction_for(ice_sample, "matter/water-ice") > 0.2, "Ice pocket concentration is too low")
	_assert(Array(ice_sample["flags"]).has("matter-resource/water-ice"), "Ice pocket semantic flag is missing")
	var direction: Vector3 = Vector3(0.31, 0.82, -0.48).normalized()
	var surface_radius: float = GeneratorScript.surface_radius_validated(profile, feature_catalog, direction)
	var surface_shell: Dictionary = GeneratorScript.sample_validated(material_catalog, profile, feature_catalog, direction * (surface_radius - 5.0))
	_assert(Array(surface_shell["flags"]).has("matter-zone/surface-shell"), "Near-surface sample is not regolith shell")
	var fractured_shell: Dictionary = GeneratorScript.sample_validated(material_catalog, profile, feature_catalog, direction * (surface_radius - 40.0))
	_assert(Array(fractured_shell["flags"]).has("matter-zone/fractured-shell"), "Mid-depth sample is not fractured shell")


func _test_sampler_properties() -> void:
	var material_ids: Dictionary = {}
	for material in material_catalog["materials"]:
		material_ids[String(material["material_id"])] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 12062027
	var bound: float = float(profile["reference_radius_m"]) * float(profile["root_bounds_radius_ratio"])
	var occupied_count: int = 0
	var vacuum_count: int = 0
	for iteration in range(600):
		var point: Vector3 = Vector3(
			rng.randf_range(-bound, bound),
			rng.randf_range(-bound, bound),
			rng.randf_range(-bound, bound)
		)
		var first: Dictionary = GeneratorScript.sample(body, material_catalog, profile, feature_catalog, point)
		var second: Dictionary = GeneratorScript.sample(body, material_catalog, profile, feature_catalog, point)
		_assert_ok(SampleScript.validate(first), "Generated sample rejected at iteration %d" % iteration)
		_assert(first == second, "Generated sample changed at iteration %d" % iteration)
		var distance: float = float(first["signed_distance_m"])
		var occupancy: float = float(first["occupancy_ratio"])
		if distance <= 0.0:
			occupied_count += 1
			_assert(occupancy == 1.0, "Inside sample is not occupied at iteration %d" % iteration)
			_assert(float(first["density_kg_m3"]) > 0.0, "Occupied sample has no density at iteration %d" % iteration)
			for component in first["composition"]["components"]:
				_assert(material_ids.has(String(component["material_id"])), "Sample references unknown material at iteration %d" % iteration)
		else:
			vacuum_count += 1
			_assert(occupancy == 0.0, "Outside sample contains matter at iteration %d" % iteration)
	_assert(occupied_count > 80, "Sampler property cloud found too little matter")
	_assert(vacuum_count > 250, "Sampler property cloud found too little vacuum")


func _test_mass_integration() -> void:
	var acceptance: Dictionary = manifest.get("mass_acceptance", {})
	var coarse_resolution: int = int(acceptance.get("coarse_resolution", 16))
	var fine_resolution: int = int(acceptance.get("fine_resolution", 20))
	var coarse: Dictionary = IntegratorScript.integrate(body, material_catalog, profile, feature_catalog, coarse_resolution)
	var replay: Dictionary = IntegratorScript.integrate(body, material_catalog, profile, feature_catalog, coarse_resolution)
	var fine: Dictionary = IntegratorScript.integrate(body, material_catalog, profile, feature_catalog, fine_resolution)
	_assert_ok(MassEstimateScript.validate(coarse), "Coarse MW1 mass estimate rejected")
	_assert(coarse == replay, "MW1 mass integration is non-deterministic")
	_assert_ok(MassEstimateScript.validate(fine), "Fine MW1 mass estimate rejected")
	var coarse_mass: float = float(coarse.get("estimated_mass_kg", 0.0))
	var fine_mass: float = float(fine.get("estimated_mass_kg", 0.0))
	_assert(coarse_mass >= float(acceptance.get("minimum_estimated_mass_kg", 0.0)), "MW1 estimated mass is below acceptance range")
	_assert(coarse_mass <= float(acceptance.get("maximum_estimated_mass_kg", INF)), "MW1 estimated mass is above acceptance range")
	var relative_mass_difference: float = IntegratorScript.relative_difference(coarse_mass, fine_mass)
	_assert(relative_mass_difference <= float(acceptance.get("maximum_relative_mass_difference", 0.1)), "MW1 mass estimate did not converge: %f" % relative_mass_difference)
	var center: Vector3 = _vector3(coarse["center_of_mass_m"])
	_assert(center.length() <= float(acceptance.get("maximum_center_of_mass_offset_m", 250.0)), "MW1 center of mass escaped acceptance range")
	var material_masses: Dictionary = _material_mass_map(fine)
	for required_material in [
		"matter/basalt",
		"matter/fractured-basalt",
		"matter/regolith-compacted",
		"matter/iron-nickel-ore",
		"matter/water-ice",
	]:
		_assert(float(material_masses.get(required_material, 0.0)) > 0.0, "Mass integration missed %s" % required_material)
	_assert(IntegratorScript.integrate(body, material_catalog, profile, feature_catalog, 3).is_empty(), "Invalid low integration resolution accepted")
	_assert(IntegratorScript.integrate(body, material_catalog, profile, feature_catalog, 129).is_empty(), "Invalid high integration resolution accepted")


func _test_negative_configuration_cases() -> void:
	var stale_body: Dictionary = body.duplicate(true)
	stale_body["generator_seed"] = int(stale_body["generator_seed"]) + 1
	stale_body["checksum"] = MatterUtilsScript.compute_checksum(stale_body)
	_assert_fail(GeneratorScript.validate_configuration(stale_body, material_catalog, profile, feature_catalog), "Body/profile seed mismatch accepted")
	_assert(GeneratorScript.sample(stale_body, material_catalog, profile, feature_catalog, Vector3.ZERO).is_empty(), "Invalid configuration produced sample")
	var wrong_catalog: Dictionary = material_catalog.duplicate(true)
	wrong_catalog["materials"][0]["density_kg_m3"] += 1.0
	_assert_fail(GeneratorScript.validate_configuration(body, wrong_catalog, profile, feature_catalog), "Mutated material catalog accepted")
	var wrong_features: Dictionary = feature_catalog.duplicate(true)
	wrong_features["generator_seed"] = int(wrong_features["generator_seed"]) + 1
	wrong_features["checksum"] = MatterUtilsScript.compute_checksum(wrong_features)
	_assert_fail(GeneratorScript.validate_configuration(body, material_catalog, profile, wrong_features), "Feature/profile seed mismatch accepted")
	var estimate: Dictionary = IntegratorScript.integrate(body, material_catalog, profile, feature_catalog, 8)
	var unbalanced: Dictionary = estimate.duplicate(true)
	unbalanced["material_masses"][0]["mass_kg"] += 1000000.0
	unbalanced["checksum"] = MatterUtilsScript.compute_checksum(unbalanced)
	_assert_fail(MassEstimateScript.validate(unbalanced), "Unbalanced material mass estimate accepted")


func _sample_signature_map(points: Array) -> Dictionary:
	var result: Dictionary = {}
	for point_value in points:
		var point: Vector3 = point_value
		var key: String = "%d:%d:%d" % [
			int(round(point.x * 100.0)),
			int(round(point.y * 100.0)),
			int(round(point.z * 100.0)),
		]
		result[key] = GeneratorScript.quantized_sample_signature(
			GeneratorScript.sample_validated(material_catalog, profile, feature_catalog, point)
		)
	return result


func _sample_at_feature(feature: Dictionary) -> Dictionary:
	return GeneratorScript.sample_validated(
		material_catalog,
		profile,
		feature_catalog,
		_vector3(feature["center_m"])
	)


func _fraction_for(sample_value: Dictionary, material_id: String) -> float:
	for component in sample_value["composition"]["components"]:
		if String(component["material_id"]) == material_id:
			return float(component["mass_fraction"])
	return 0.0


func _material_mass_map(estimate: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entry in estimate["material_masses"]:
		result[String(entry["material_id"])] = float(entry["mass_kg"])
	return result


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result.get("error_code", "")])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("MW1 fixed-seed asteroid: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MW1 fixed-seed asteroid: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
