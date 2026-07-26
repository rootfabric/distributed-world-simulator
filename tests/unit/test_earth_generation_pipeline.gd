extends SceneTree

const PipelineScript = preload(
	"res://scripts/world/planetary/earth_rule_pipeline.gd"
)
const CelestialSystemScript = preload(
	"res://scripts/world/planetary/celestial_system.gd"
)

const REQUIRED_FIELDS := [
	"continentalness",
	"land_mask",
	"base_elevation_m",
	"mountain_mask",
	"mountain_elevation_m",
	"hill_elevation_m",
	"local_relief_m",
	"water_kind",
	"river_mask",
	"lake_mask",
	"temperature_c",
	"moisture",
	"biome_code",
	"snow_mask",
	"tree_density",
	"grass_density",
	"rock_density",
	"elevation_m",
	"surface_color",
]

var failures: Array[String] = []


func _init() -> void:
	_test_pipeline_contract()
	_test_generated_world_rules()
	_test_conflict_detection()
	_test_real_scale_body_contract()

	if failures.is_empty():
		print("Earth generation pipeline tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Earth generation pipeline tests: FAIL (%d)" % failures.size())
	quit(1)


func _test_pipeline_contract() -> void:
	var pipeline = PipelineScript.new()
	_assert(pipeline.setup(), "Earth rule pipeline setup failed.")
	_assert(
		pipeline.get_active_rule_ids() == [
			"continental_relief",
			"hydrology",
			"climate",
			"biomes",
			"surface_composer",
		],
		"Earth rules are missing or ordered incorrectly."
	)
	var state: Dictionary = pipeline.sample(Vector3(0.72, 0.33, -0.61), 0)
	for field_name in REQUIRED_FIELDS:
		_assert(state.has(field_name), "Generated state misses field: %s" % field_name)
	_assert(state["surface_color"] is Color, "Surface composer did not return a Color.")
	_assert(
		float(state["tree_density"]) >= 0.0 and float(state["tree_density"]) <= 1.0,
		"Tree density is outside [0, 1]."
	)
	_assert(
		float(state["grass_density"]) >= 0.0 and float(state["grass_density"]) <= 1.0,
		"Grass density is outside [0, 1]."
	)


func _test_generated_world_rules() -> void:
	var pipeline = PipelineScript.new()
	if not pipeline.setup():
		_assert(false, "Cannot sample Earth because the pipeline is invalid.")
		return
	var found_biomes: Dictionary = {}
	var found_river_or_lake: bool = false
	var found_high_snow: bool = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260726
	for _sample_index in range(12000):
		var direction: Vector3 = _random_unit_direction(rng)
		var state: Dictionary = pipeline.sample(direction, 0)
		var biome_code: int = int(state.get("biome_code", -1))
		found_biomes[biome_code] = true
		var water_kind: int = int(state.get("water_kind", 0))
		if water_kind == 2 or water_kind == 3:
			found_river_or_lake = true
		if (
			float(state.get("elevation_m", 0.0)) > 2500.0
			and float(state.get("snow_mask", 0.0)) > 0.15
		):
			found_high_snow = true
		if water_kind != 0:
			_assert(
				float(state.get("tree_density", 0.0)) == 0.0,
				"Trees were generated on water."
			)
			_assert(
				float(state.get("grass_density", 0.0)) == 0.0,
				"Grass was generated on water."
			)
		if biome_code == 2 or biome_code == 3:
			_assert(
				float(state.get("tree_density", 0.0)) == 0.0,
				"Desert or tundra unexpectedly contains trees."
			)
			_assert(
				float(state.get("grass_density", 0.0)) == 0.0,
				"Desert or tundra unexpectedly contains grass."
			)
		if float(state.get("snow_mask", 0.0)) > 0.22:
			_assert(
				float(state.get("tree_density", 0.0)) < 0.000001,
				"Trees were generated above the snow cutoff."
			)
	var required_biomes := {
		0: "ocean",
		2: "desert",
		3: "tundra",
		4: "forest",
		5: "grassland",
		6: "alpine_snow",
	}
	for biome_code in required_biomes:
		_assert(
			found_biomes.has(biome_code),
			"Required biome was not found: %s" % required_biomes[biome_code]
		)
	_assert(found_river_or_lake, "No procedural river or lake sample was found.")
	_assert(found_high_snow, "No high-altitude snow sample was found.")


func _test_conflict_detection() -> void:
	var conflict_path: String = "user://earth_rule_conflict_test.json"
	var config := {
		"schema": "planet_simulator.rule_pipeline.v1",
		"seed": 20260726,
		"rules": [
			{
				"id": "relief_a",
				"script": "res://scripts/world/planetary/rules/continental_relief_rule.gd",
				"enabled": true,
				"stage": 100,
				"lod_max": 2,
			},
			{
				"id": "relief_b",
				"script": "res://scripts/world/planetary/rules/continental_relief_rule.gd",
				"enabled": true,
				"stage": 110,
				"lod_max": 2,
			},
		],
	}
	var file := FileAccess.open(conflict_path, FileAccess.WRITE)
	_assert(file != null, "Cannot create conflict test config.")
	if file == null:
		return
	file.store_string(JSON.stringify(config, "  "))
	file.close()
	var pipeline = PipelineScript.new()
	_assert(not pipeline.setup(conflict_path), "Duplicate rule writers were not rejected.")
	var error_text: String = "\n".join(pipeline.get_validation_errors())
	_assert(
		error_text.contains("written by both"),
		"Duplicate writer validation returned an unexpected error."
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(conflict_path))


func _test_real_scale_body_contract() -> void:
	var system = CelestialSystemScript.new()
	_assert(system.setup(), "Celestial system config failed to load.")
	_assert(
		is_equal_approx(system.get_body_radius("earth"), 6_371_000.0),
		"Earth radius is not real scale."
	)
	_assert(
		is_equal_approx(system.get_body_radius("moon"), 1_737_400.0),
		"Moon radius changed unexpectedly."
	)
	_assert(
		absf(system.get_distance_between("earth", "moon") - 384_400_000.0) < 0.5,
		"Earth-Moon center distance is not 384,400 km."
	)
	var earth_local := Vector3(6_371_450.0, 20.0, -30.0)
	var absolute_position: Vector3 = system.to_space(earth_local, "earth")
	_assert(
		system.to_body_local(absolute_position, "earth").is_equal_approx(earth_local),
		"Shared-space body-local conversion is not reversible."
	)
	_assert(
		system.get_nearest_body_id(absolute_position) == "earth",
		"Shared-space nearest-body selection failed near Earth."
	)
	system.free()


func _random_unit_direction(rng: RandomNumberGenerator) -> Vector3:
	var y_value: float = rng.randf_range(-1.0, 1.0)
	var angle: float = rng.randf_range(0.0, TAU)
	var horizontal: float = sqrt(maxf(0.0, 1.0 - y_value * y_value))
	return Vector3(
		horizontal * cos(angle),
		y_value,
		horizontal * sin(angle)
	).normalized()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
