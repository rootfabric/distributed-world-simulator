extends RefCounted

## ECO.EVO7 live-world SHADOW adapter.
##
## Reads the production EarthRulePipeline + EarthSun surfaces and evaluates an
## immutable EVO7 plant bundle with the accepted FFF6 water-limited fitness
## coupling. It owns no world/ecology/persistence/network write authority and
## never invokes the mutation lineage authority.

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")
const Succession = preload("res://scripts/research/ecology/evo7_succession_bridge_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_live_world_shadow.v1"
const VERSION := "1.0.0"
const MODE := "SHADOW_READ_ONLY"
const CONFIG_PATH := "res://config/ecology/eco-evo7-live-shadow.v1.json"
const DEFAULT_EARTH_SUN_ENERGY := 1.45
const DEFAULT_NEUTRAL_NUTRIENTS := 0.50
const MIN_SHADOW_SUNLIGHT := 0.05

const AUTHORITY := {
	"world_write": false,
	"ecology_write": false,
	"persistence_write": false,
	"network_replication_write": false,
	"mutation_authority": false,
	"xfer_authority": false,
}

static func observe_earth_world(earth_world, direction_value: Vector3, world_time: float, observation_id: String) -> Dictionary:
	if earth_world == null or not earth_world.has_method("get_surface_point"):
		return _failure("ECO_SHADOW_EARTH_WORLD_INVALID")
	var pipeline = earth_world.get("pipeline")
	if pipeline == null:
		return _failure("ECO_SHADOW_PIPELINE_UNAVAILABLE")
	var surface_point: Vector3 = earth_world.call("get_surface_point", direction_value.normalized())
	var light_energy := DEFAULT_EARTH_SUN_ENERGY
	var earth_light = earth_world.get("earth_light")
	if earth_light != null:
		light_energy = float(earth_light.get("light_energy"))
	return observe_pipeline(pipeline, direction_value, world_time, observation_id, surface_point, light_energy)

static func observe_pipeline(
	pipeline,
	direction_value: Vector3,
	world_time: float,
	observation_id: String,
	surface_point: Vector3 = Vector3.ZERO,
	light_energy: float = DEFAULT_EARTH_SUN_ENERGY
) -> Dictionary:
	if pipeline == null or not pipeline.has_method("sample") or not pipeline.has_method("get_active_rule_ids"):
		return _failure("ECO_SHADOW_PIPELINE_INVALID")
	if observation_id.is_empty() or observation_id != observation_id.strip_edges():
		return _failure("ECO_SHADOW_OBSERVATION_ID_INVALID")
	if not is_finite(world_time) or world_time < 0.0:
		return _failure("ECO_SHADOW_WORLD_TIME_INVALID")
	if direction_value.length_squared() < 0.5:
		return _failure("ECO_SHADOW_DIRECTION_INVALID")
	if not is_finite(light_energy) or light_energy < 0.0:
		return _failure("ECO_SHADOW_LIGHT_ENERGY_INVALID")

	var direction := direction_value.normalized()
	var state: Dictionary = pipeline.sample(direction, 0)
	for required in ["temperature_c", "moisture", "tree_density", "water_kind", "river_mask", "lake_mask", "sea_mask", "aridity", "rockiness"]:
		if not state.has(required):
			return _failure("ECO_SHADOW_LIVE_FIELD_MISSING", {"field": required})

	var moisture := clampf(float(state["moisture"]), 0.0, 1.0)
	var tree_density := clampf(float(state["tree_density"]), 0.0, 1.0)
	var open_sunlight := clampf(light_energy / DEFAULT_EARTH_SUN_ENERGY, 0.0, 1.0)
	var sunlight := clampf(open_sunlight * (1.0 - 0.60 * tree_density), MIN_SHADOW_SUNLIGHT, 1.0)
	var flood_frequency := clampf(maxf(float(state["river_mask"]), float(state["lake_mask"])), 0.0, 1.0)
	if int(state["water_kind"]) != 0:
		flood_frequency = maxf(flood_frequency, 0.85)
	var texture := _shadow_texture_proxy(moisture, float(state["aridity"]), float(state["rockiness"]))
	var active_rules: Array[String] = pipeline.get_active_rule_ids()
	var live_state_hash := _live_state_hash(state, direction, surface_point, light_energy, active_rules)
	var observation_seed := Contract.derive_individual_seed("eco-evo7-live-shadow", observation_id, 0, VERSION)
	var env_revision := "%s|live=%s" % [SCHEMA, live_state_hash]
	var environment := EnvironmentSample.create(
		surface_point.x,
		surface_point.z,
		float(state["temperature_c"]),
		moisture,
		sunlight,
		DEFAULT_NEUTRAL_NUTRIENTS,
		flood_frequency,
		observation_seed,
		env_revision
	)
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return _failure("ECO_SHADOW_ENVIRONMENT_INVALID")

	var observation := {
		"schema": SCHEMA,
		"version": VERSION,
		"mode": MODE,
		"observation_id": observation_id,
		"world_time": snappedf(world_time, 1e-9),
		"direction": [snappedf(direction.x, 1e-9), snappedf(direction.y, 1e-9), snappedf(direction.z, 1e-9)],
		"surface_point_m": [snappedf(surface_point.x, 1e-6), snappedf(surface_point.y, 1e-6), snappedf(surface_point.z, 1e-6)],
		"live_state_hash": live_state_hash,
		"active_rule_ids": active_rules,
		"environment_sample": environment,
		"shadow_bindings": {
			"temperature": "EarthRulePipeline.temperature_c",
			"soil_moisture": "EarthRulePipeline.moisture",
			"surface_water": "EarthRulePipeline.water_kind+river_mask+lake_mask+sea_mask",
			"open_light": "ProceduralEarthWorld.EarthSun.light_energy",
			"canopy_light_proxy": "EarthRulePipeline.tree_density",
			"soil_texture": "SHADOW_PROXY_ONLY",
			"nutrients": "NEUTRAL_UNBOUND_0_5",
		},
		"shadow_texture_proxy": texture,
		"open_sunlight": snappedf(open_sunlight, 1e-9),
		"canopy_adjusted_sunlight": snappedf(sunlight, 1e-9),
		"authorities": AUTHORITY.duplicate(true),
	}
	observation["observation_hash"] = _observation_hash(observation)
	return _success(observation)

static func evaluate_bundle(earth_world, bundle: Dictionary, direction: Vector3, world_time: float, observation_id: String) -> Dictionary:
	var observed := observe_earth_world(earth_world, direction, world_time, observation_id)
	if not bool(observed.get("success", false)):
		return observed
	return evaluate_bundle_against_observation(bundle, Dictionary(observed["details"]))

static func evaluate_bundle_against_observation(bundle: Dictionary, observation: Dictionary) -> Dictionary:
	if String(observation.get("schema", "")) != SCHEMA or String(observation.get("mode", "")) != MODE:
		return _failure("ECO_SHADOW_OBSERVATION_SCHEMA_INVALID")
	if String(observation.get("observation_hash", "")) != _observation_hash(observation):
		return _failure("ECO_SHADOW_OBSERVATION_HASH_INVALID")
	for key in ["genome", "dev_traits", "ext_traits", "lineage", "individual_seed", "bundle_checksum"]:
		if not bundle.has(key):
			return _failure("ECO_SHADOW_BUNDLE_FIELD_MISSING", {"field": key})
	var seed_tag := Succession.stable_evaluation_seed_tag(bundle)
	if seed_tag.is_empty():
		return _failure("ECO_SHADOW_EVALUATION_IDENTITY_INVALID")
	var env: Dictionary = Dictionary(observation["environment_sample"])
	var provisional := _functional(bundle, env, seed_tag)
	if provisional.is_empty():
		return _failure("ECO_SHADOW_PROVISIONAL_PHENOTYPE_INVALID")
	var water_record := {
		"identity": "shadow-plant",
		"cell_identity": String(observation.get("observation_id", "shadow-cell")),
		"realized_root_depth_m": float(provisional["realized_root_depth_m"]),
		"realized_root_spread_m": float(provisional["realized_root_spread_m"]),
		"root_shoot_ratio": float(provisional["root_shoot_ratio"]),
		"leaf_area_index_proxy": float(provisional["leaf_area_index_proxy"]),
		"transpiration_demand_ppm": int(provisional["transpiration_demand_ppm"]),
		"shade_output_ppm": int(provisional["shade_output_ppm"]),
		"source_phenotype_hash": String(provisional["phenotype_hash"]),
	}
	var generation := maxi(int(floor(float(observation.get("world_time", 0.0)))), 0)
	var water := WaterField.compute(
		int(round(float(env["soil_moisture"]) * 1000000.0)),
		String(observation["shadow_texture_proxy"]),
		float(env["sunlight"]),
		[water_record],
		generation
	)
	if water.is_empty():
		return _failure("ECO_SHADOW_WATER_FIELD_INVALID")
	var water_item: Dictionary = water["plant_water"]["shadow-plant"]
	var effective_env := EnvironmentSample.create(
		float(env["world_x_m"]), float(env["world_z_m"]), float(env["temperature_c"]),
		float(water_item["effective_soil_moisture"]), float(env["sunlight"]), float(env["nutrients"]),
		float(env["flood_frequency"]), int(env["seed"]), String(env["environment_revision"]) + "|water=" + String(water["field_hash"])
	)
	var phenotype := _functional(bundle, effective_env, seed_tag)
	if phenotype.is_empty():
		return _failure("ECO_SHADOW_FINAL_PHENOTYPE_INVALID")

	var water_satisfaction := float(water_item["water_satisfaction"])
	var water_match := 1.0 - absf(float(bundle["genome"]["water_preference"]) - float(effective_env["soil_moisture"]))
	var open_sunlight := maxf(float(observation.get("open_sunlight", 1.0)), 0.001)
	var light_stress := 1.0 - clampf(float(effective_env["sunlight"]) / open_sunlight, 0.0, 1.0)
	var shade_adaptation := float(bundle["genome"]["shade_tolerance"]) * light_stress * 0.45
	var realized_photosynthetic_gain := float(phenotype["photosynthetic_gain_proxy"]) * (0.15 + 0.85 * water_satisfaction)
	var water_limited_resource := realized_photosynthetic_gain - float(phenotype["maintenance_cost_proxy"])
	var drought_cost := (1.0 - water_satisfaction) * (0.30 + 0.20 * float(phenotype["leaf_area_index_proxy"]))
	var fitness := water_limited_resource + 0.35 * float(phenotype["establishment_capacity"]) + 0.30 * water_match + shade_adaptation - drought_cost
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"mode": MODE,
		"shadow_only": true,
		"authorities": AUTHORITY.duplicate(true),
		"observation_id": String(observation["observation_id"]),
		"observation_hash": String(observation["observation_hash"]),
		"candidate_bundle_hash": String(bundle["bundle_checksum"]),
		"candidate_individual_seed": int(bundle["individual_seed"]),
		"evaluation_identity_tag": seed_tag,
		"environment_hash": String(effective_env["checksum"]),
		"phenotype_hash": String(phenotype["phenotype_hash"]),
		"water_field_hash": String(water["field_hash"]),
		"water_satisfaction": snappedf(water_satisfaction, 1e-9),
		"water_uptake_ppm": int(water_item["water_uptake_ppm"]),
		"effective_soil_moisture": snappedf(float(effective_env["soil_moisture"]), 1e-9),
		"canopy_adjusted_sunlight": snappedf(float(effective_env["sunlight"]), 1e-9),
		"realized_height_m": snappedf(float(phenotype["realized_height_m"]), 1e-9),
		"realized_crown_radius_m": snappedf(float(phenotype["realized_crown_radius_m"]), 1e-9),
		"realized_crown_density": snappedf(float(phenotype["realized_crown_density"]), 1e-9),
		"leaf_area_index_proxy": snappedf(float(phenotype["leaf_area_index_proxy"]), 1e-9),
		"realized_root_depth_m": snappedf(float(phenotype["realized_root_depth_m"]), 1e-9),
		"realized_root_spread_m": snappedf(float(phenotype["realized_root_spread_m"]), 1e-9),
		"root_shoot_ratio": snappedf(float(phenotype["root_shoot_ratio"]), 1e-9),
		"structural_investment": snappedf(float(phenotype["structural_investment"]), 1e-9),
		"water_limited_resource": snappedf(water_limited_resource, 1e-9),
		"shadow_fitness": snappedf(fitness, 1e-9),
	}
	result["shadow_result_hash"] = _evaluation_hash(result)
	return _success(result)

static func request_authoritative_write(_surface: String, _payload: Dictionary = {}) -> Dictionary:
	return _failure("ECO_SHADOW_WRITE_FORBIDDEN", {"mode": MODE, "authorities": AUTHORITY.duplicate(true)})

static func load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

static func _functional(bundle: Dictionary, env: Dictionary, seed_tag: String) -> Dictionary:
	var envelope := Contract.create_seed_envelope(
		bundle["genome"], bundle["dev_traits"], String(bundle["lineage"]["lineage_id"]), seed_tag, 0, 1.25)
	if envelope.is_empty():
		return {}
	var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], env)
	return FunctionalPhenotype.compile({
		"genome": bundle["genome"],
		"ph2_realized": ph2,
		"traits_extension": bundle["ext_traits"],
		"environment_sample": env,
		"age_fraction": 1.0,
	})

static func _shadow_texture_proxy(moisture: float, aridity: float, rockiness: float) -> String:
	if aridity >= 0.62 or (moisture <= 0.28 and rockiness < 0.80):
		return "sand"
	if moisture >= 0.78 and aridity <= 0.38:
		return "clay"
	return "loam"

static func _live_state_hash(state: Dictionary, direction: Vector3, surface_point: Vector3, light_energy: float, active_rules: Array[String]) -> String:
	var rules := active_rules.duplicate()
	rules.sort()
	var tokens := PackedStringArray([
		SCHEMA, VERSION, "live-state",
		"%.9f,%.9f,%.9f" % [direction.x, direction.y, direction.z],
		"%.6f,%.6f,%.6f" % [surface_point.x, surface_point.y, surface_point.z],
		"temperature=%.9f" % float(state.get("temperature_c", 0.0)),
		"moisture=%.9f" % float(state.get("moisture", 0.0)),
		"tree_density=%.9f" % float(state.get("tree_density", 0.0)),
		"water_kind=%d" % int(state.get("water_kind", -1)),
		"river=%.9f" % float(state.get("river_mask", 0.0)),
		"lake=%.9f" % float(state.get("lake_mask", 0.0)),
		"sea=%.9f" % float(state.get("sea_mask", 0.0)),
		"aridity=%.9f" % float(state.get("aridity", 0.0)),
		"rockiness=%.9f" % float(state.get("rockiness", 0.0)),
		"light_energy=%.9f" % light_energy,
		"rules=" + ",".join(rules),
	])
	return "|".join(tokens).sha256_text()

static func _observation_hash(observation: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, MODE,
		String(observation.get("observation_id", "")),
		"%.9f" % float(observation.get("world_time", -1.0)),
		String(observation.get("live_state_hash", "")),
		String(Dictionary(observation.get("environment_sample", {})).get("checksum", "")),
		String(observation.get("shadow_texture_proxy", "")),
		"%.9f" % float(observation.get("open_sunlight", 0.0)),
		"%.9f" % float(observation.get("canopy_adjusted_sunlight", 0.0)),
	])).sha256_text()

static func _evaluation_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, MODE,
		String(result.get("observation_hash", "")),
		String(result.get("candidate_bundle_hash", "")),
		String(result.get("evaluation_identity_tag", "")),
		String(result.get("environment_hash", "")),
		String(result.get("phenotype_hash", "")),
		String(result.get("water_field_hash", "")),
		"%.9f" % float(result.get("water_satisfaction", -1.0)),
		"%.9f" % float(result.get("shadow_fitness", 0.0)),
	])).sha256_text()

static func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
