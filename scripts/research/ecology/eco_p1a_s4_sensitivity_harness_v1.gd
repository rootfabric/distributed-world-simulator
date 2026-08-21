extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const PatchSimulator = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1a_s4_sensitivity_run.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1A-S4.1"
const DEFAULT_GRID_SIZE := 17
const DEFAULT_SEASONS := 48
const CONFIG_KEYS: Array[String] = [
	"moisture_amplitude_scale",
	"sunlight_amplitude_scale",
	"root_cost_scale",
	"maintenance_cost_scale",
	"flood_penalty_scale",
	"root_depth_scale",
	"shade_tolerance_delta",
]


static func baseline_config() -> Dictionary:
	return {
		"moisture_amplitude_scale": 1.0,
		"sunlight_amplitude_scale": 1.0,
		"root_cost_scale": 1.0,
		"maintenance_cost_scale": 1.0,
		"flood_penalty_scale": 1.0,
		"root_depth_scale": 1.0,
		"shade_tolerance_delta": 0.0,
	}


static func with_override(field_name: String, value: float) -> Dictionary:
	var config := baseline_config()
	if field_name in CONFIG_KEYS:
		config[field_name] = value
	return config


static func validate_config(config: Dictionary) -> Dictionary:
	if config.keys().size() != CONFIG_KEYS.size():
		return {"success": false, "error_code": "ECO_P1A_S4_CONFIG_FIELD_COUNT"}
	for key in CONFIG_KEYS:
		if not config.has(key):
			return {"success": false, "error_code": "ECO_P1A_S4_CONFIG_MISSING", "details": {"field": key}}
		if typeof(config[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(config[key])):
			return {"success": false, "error_code": "ECO_P1A_S4_CONFIG_NON_FINITE", "details": {"field": key}}
	for key in ["moisture_amplitude_scale", "sunlight_amplitude_scale", "root_cost_scale", "maintenance_cost_scale", "flood_penalty_scale", "root_depth_scale"]:
		if float(config[key]) <= 0.0 or float(config[key]) > 4.0:
			return {"success": false, "error_code": "ECO_P1A_S4_CONFIG_SCALE_RANGE", "details": {"field": key}}
	if absf(float(config["shade_tolerance_delta"])) > 0.5:
		return {"success": false, "error_code": "ECO_P1A_S4_CONFIG_SHADE_RANGE"}
	return {"success": true, "error_code": ""}


static func run(
	config: Dictionary = {},
	grid_size: int = DEFAULT_GRID_SIZE,
	seasons: int = DEFAULT_SEASONS,
	seed: int = Fixture.DEFAULT_SEED
) -> Dictionary:
	var effective_config := baseline_config() if config.is_empty() else config.duplicate(true)
	if not bool(validate_config(effective_config).get("success", false)) or grid_size < 3 or seasons <= 0:
		return {}
	var genome := _perturbed_genome(effective_config)
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}

	var total_biomass_series: Array[float] = []
	total_biomass_series.resize(seasons + 1)
	for i in range(total_biomass_series.size()):
		total_biomass_series[i] = 0.0
	var viability_counts := {"FAVOURABLE": 0, "MARGINAL": 0, "UNSUSTAINABLE": 0}
	var limiting_counts := {"LIGHT": 0, "WATER": 0, "NUTRIENT": 0, "TEMPERATURE": 0, "FLOOD": 0}
	var zone_summary := {}
	var total_initial_net := 0.0
	var total_final_biomass := 0.0
	var total_peak_biomass := 0.0
	var record_tokens := PackedStringArray()
	var patch_count := grid_size * grid_size

	for iz in range(grid_size):
		for ix in range(grid_size):
			var position := Fixture.grid_position(ix, iz, grid_size)
			var base_environment := Fixture.sample_at(position.x, position.y, seed)
			var environment := _perturbed_environment(base_environment, effective_config)
			var balance := _evaluate_experiment(environment, genome, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2, effective_config)
			var simulation := _simulate_experiment(environment, genome, seasons, effective_config)
			if balance.is_empty() or simulation.is_empty():
				return {}

			var viability := String(balance["viability_class"])
			viability_counts[viability] = int(viability_counts.get(viability, 0)) + 1
			var limiting := String(balance["dominant_limiting_factor"])
			limiting_counts[limiting] = int(limiting_counts.get(limiting, 0)) + 1
			total_initial_net += float(balance["net_resource_balance"])
			total_final_biomass += float(simulation["final_biomass_kg_m2"])
			total_peak_biomass += float(simulation["peak_biomass_kg_m2"])
			var series: Array = simulation["biomass_series"]
			for season_index in range(series.size()):
				total_biomass_series[season_index] += float(series[season_index])
			var zone := _zone_id(position.x, position.y)
			if not zone_summary.has(zone):
				zone_summary[zone] = {"patches": 0, "net_sum": 0.0, "biomass_sum": 0.0}
			zone_summary[zone]["patches"] = int(zone_summary[zone]["patches"]) + 1
			zone_summary[zone]["net_sum"] = float(zone_summary[zone]["net_sum"]) + float(balance["net_resource_balance"])
			zone_summary[zone]["biomass_sum"] = float(zone_summary[zone]["biomass_sum"]) + float(simulation["final_biomass_kg_m2"])
			record_tokens.append("%d,%d:%s:%s:%s" % [ix, iz, String(environment["checksum"]), String(balance["checksum"]), String(simulation["checksum"])])

	for zone in zone_summary.keys():
		var count: int = maxi(1, int(zone_summary[zone]["patches"]))
		zone_summary[zone]["avg_net"] = float(zone_summary[zone]["net_sum"]) / float(count)
		zone_summary[zone]["avg_final_biomass"] = float(zone_summary[zone]["biomass_sum"]) / float(count)
		zone_summary[zone].erase("net_sum")
		zone_summary[zone].erase("biomass_sum")

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"seed": seed,
		"grid_size": grid_size,
		"seasons": seasons,
		"config": effective_config,
		"config_hash": config_hash(effective_config),
		"accepted_environment_hash": Fixture.environment_hash(Fixture.LOGICAL_GRID_SIZE, seed),
		"genome_checksum": String(genome["checksum"]),
		"patch_count": patch_count,
		"average_initial_net": total_initial_net / float(patch_count),
		"average_final_biomass": total_final_biomass / float(patch_count),
		"average_peak_biomass": total_peak_biomass / float(patch_count),
		"total_biomass_series": total_biomass_series,
		"total_biomass_series_hash": _float_series_hash(total_biomass_series),
		"viability_counts": viability_counts,
		"limiting_counts": limiting_counts,
		"zone_summary": zone_summary,
	}
	result["result_hash"] = _result_hash(result, record_tokens)
	return result


static func sensitivity_summary(
	config: Dictionary = {},
	grid_size: int = DEFAULT_GRID_SIZE,
	seed: int = Fixture.DEFAULT_SEED
) -> Dictionary:
	var effective_config := baseline_config() if config.is_empty() else config.duplicate(true)
	if not bool(validate_config(effective_config).get("success", false)) or grid_size < 3:
		return {}
	var genome := _perturbed_genome(effective_config)
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	var viability_counts := {"FAVOURABLE": 0, "MARGINAL": 0, "UNSUSTAINABLE": 0}
	var limiting_counts := {"LIGHT": 0, "WATER": 0, "NUTRIENT": 0, "TEMPERATURE": 0, "FLOOD": 0}
	var total_net := 0.0
	var tokens := PackedStringArray()
	var patch_count := grid_size * grid_size
	for iz in range(grid_size):
		for ix in range(grid_size):
			var position := Fixture.grid_position(ix, iz, grid_size)
			var environment := _perturbed_environment(Fixture.sample_at(position.x, position.y, seed), effective_config)
			var balance := _evaluate_experiment(environment, genome, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2, effective_config)
			if balance.is_empty():
				return {}
			var viability := String(balance["viability_class"])
			viability_counts[viability] = int(viability_counts.get(viability, 0)) + 1
			var limiting := String(balance["dominant_limiting_factor"])
			limiting_counts[limiting] = int(limiting_counts.get(limiting, 0)) + 1
			total_net += float(balance["net_resource_balance"])
			tokens.append("%d,%d:%s:%s" % [ix, iz, String(environment["checksum"]), String(balance["checksum"])])
	var result := {
		"experiment_revision": EXPERIMENT_REVISION,
		"seed": seed,
		"grid_size": grid_size,
		"config": effective_config,
		"config_hash": config_hash(effective_config),
		"patch_count": patch_count,
		"average_initial_net": total_net / float(patch_count),
		"viability_counts": viability_counts,
		"limiting_counts": limiting_counts,
	}
	result["summary_hash"] = "|".join(PackedStringArray([
		EXPERIMENT_REVISION, str(seed), str(grid_size), String(result["config_hash"]),
		_format_float(float(result["average_initial_net"])), "\n".join(tokens),
	])).sha256_text()
	return result


static func control_point(point_name: String, config: Dictionary = {}) -> Dictionary:
	if not Fixture.CONTROL_POINTS.has(point_name):
		return {}
	var effective_config := baseline_config() if config.is_empty() else config.duplicate(true)
	if not bool(validate_config(effective_config).get("success", false)):
		return {}
	var genome := _perturbed_genome(effective_config)
	var position: Vector2 = Fixture.CONTROL_POINTS[point_name]
	var environment := _perturbed_environment(Fixture.sample_at(position.x, position.y), effective_config)
	var balance := _evaluate_experiment(environment, genome, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2, effective_config)
	var simulation := _simulate_experiment(environment, genome, DEFAULT_SEASONS, effective_config)
	return {
		"point": point_name,
		"environment": environment,
		"genome": genome,
		"balance": balance,
		"simulation": simulation,
	}


static func config_hash(config: Dictionary) -> String:
	var tokens := PackedStringArray([EXPERIMENT_REVISION])
	for key in CONFIG_KEYS:
		tokens.append("%s=%s" % [key, _format_float(float(config.get(key, 0.0)))])
	return "|".join(tokens).sha256_text()


static func _perturbed_environment(base: Dictionary, config: Dictionary) -> Dictionary:
	var moisture := clampf(float(base["soil_moisture"]) * float(config["moisture_amplitude_scale"]), 0.0, 1.0)
	var sunlight := clampf(float(base["sunlight"]) * float(config["sunlight_amplitude_scale"]), 0.0, 1.0)
	var revision := "%s/%s/%s" % [String(base["environment_revision"]), EXPERIMENT_REVISION, config_hash(config).substr(0, 12)]
	return EnvironmentSample.create(
		float(base["world_x_m"]),
		float(base["world_z_m"]),
		float(base["temperature_c"]),
		moisture,
		sunlight,
		float(base["nutrients"]),
		float(base["flood_frequency"]),
		int(base["seed"]),
		revision
	)


static func _perturbed_genome(config: Dictionary) -> Dictionary:
	var base := PlantGenome.create_default()
	var root_depth := clampf(float(base["root_depth_m"]) * float(config["root_depth_scale"]), 0.05, 20.0)
	var shade_tolerance := clampf(float(base["shade_tolerance"]) + float(config["shade_tolerance_delta"]), 0.0, 1.0)
	return PlantGenome.create(
		"%s/%s/%s" % [String(base["genome_id"]), EXPERIMENT_REVISION, config_hash(config).substr(0, 12)],
		float(base["height_m"]),
		float(base["growth_rate"]),
		root_depth,
		float(base["water_preference"]),
		float(base["water_tolerance_width"]),
		shade_tolerance,
		int(base["seed_count"]),
		float(base["seed_dispersal_distance_m"]),
		float(base["lifespan_years"])
	)


static func _simulate_experiment(environment: Dictionary, genome: Dictionary, seasons: int, config: Dictionary) -> Dictionary:
	# Full biomass dynamics are intentionally delegated to the accepted S2 simulator.
	# Cost-coefficient perturbations are evaluated only in sensitivity_summary(),
	# so S4 never forks or rewrites the accepted population update kernel.
	if not _cost_scales_are_baseline(config):
		return {}
	return PatchSimulator.simulate(environment, genome, seasons, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)


static func _cost_scales_are_baseline(config: Dictionary) -> bool:
	return (
		absf(float(config["root_cost_scale"]) - 1.0) <= 0.000000001
		and absf(float(config["maintenance_cost_scale"]) - 1.0) <= 0.000000001
		and absf(float(config["flood_penalty_scale"]) - 1.0) <= 0.000000001
	)


static func _evaluate_experiment(environment: Dictionary, genome: Dictionary, biomass: float, config: Dictionary) -> Dictionary:
	var balance := ResourceModel.evaluate(environment, genome, biomass)
	if balance.is_empty():
		return {}
	return _apply_cost_overrides(balance, config)


static func _apply_cost_overrides(balance: Dictionary, config: Dictionary) -> Dictionary:
	var adjusted := balance.duplicate(true)
	adjusted["root_cost"] = float(balance["root_cost"]) * float(config["root_cost_scale"])
	adjusted["maintenance_cost"] = float(balance["maintenance_cost"]) * float(config["maintenance_cost_scale"])
	adjusted["flood_penalty"] = float(balance["flood_penalty"]) * float(config["flood_penalty_scale"])
	adjusted["flood_limitation"] = clampf(float(balance["flood_limitation"]) * float(config["flood_penalty_scale"]), 0.0, 1.0)
	var total_cost := (
		float(adjusted["maintenance_cost"])
		+ float(adjusted["root_cost"])
		+ float(adjusted["structural_cost"])
		+ float(adjusted["growth_allocation_cost"])
		+ float(adjusted["reproduction_allocation_cost"])
		+ float(adjusted["water_stress_penalty"])
		+ float(adjusted["flood_penalty"])
		+ float(adjusted["density_cost"])
	)
	adjusted["net_resource_balance"] = float(adjusted["gross_photosynthetic_income"]) - total_cost
	adjusted["viability_class"] = _viability_class(float(adjusted["net_resource_balance"]))
	adjusted["dominant_limiting_factor"] = _dominant_limiting_factor(adjusted)
	adjusted["checksum"] = ResourceModel.compute_checksum(adjusted)
	return adjusted


static func _dominant_limiting_factor(balance: Dictionary) -> String:
	var entries: Array = [
		["LIGHT", float(balance["light_limitation"])],
		["WATER", float(balance["water_limitation"])],
		["NUTRIENT", float(balance["nutrient_limitation"])],
		["TEMPERATURE", float(balance["temperature_limitation"])],
		["FLOOD", float(balance["flood_limitation"])],
	]
	var best: Array = Array(entries[0])
	for entry_value in entries:
		var entry: Array = Array(entry_value)
		if float(entry[1]) > float(best[1]):
			best = entry
	return String(best[0])


static func _viability_class(net: float) -> String:
	if net >= ResourceModel.FAVOURABLE_THRESHOLD:
		return "FAVOURABLE"
	if net >= ResourceModel.MARGINAL_THRESHOLD:
		return "MARGINAL"
	return "UNSUSTAINABLE"


static func _zone_id(x: float, z: float) -> String:
	if x < 0.0 and z < 0.0:
		return "SW"
	if x >= 0.0 and z < 0.0:
		return "SE"
	if x < 0.0 and z >= 0.0:
		return "NW"
	return "NE"


static func _float_series_hash(series: Array[float]) -> String:
	var tokens := PackedStringArray()
	for value in series:
		tokens.append(_format_float(value))
	return "\n".join(tokens).sha256_text()


static func _result_hash(result: Dictionary, record_tokens: PackedStringArray) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(result["experiment_revision"]),
		str(int(result["seed"])),
		str(int(result["grid_size"])),
		str(int(result["seasons"])),
		String(result["config_hash"]),
		String(result["accepted_environment_hash"]),
		String(result["genome_checksum"]),
		_format_float(float(result["average_initial_net"])),
		_format_float(float(result["average_final_biomass"])),
		String(result["total_biomass_series_hash"]),
		"\n".join(record_tokens),
	])
	return "|".join(tokens).sha256_text()


static func _format_float(value: float) -> String:
	return "%.9f" % value
