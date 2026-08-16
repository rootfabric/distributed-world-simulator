extends Node

const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const RealtimeModel = preload("res://scripts/labs/ecology/eco_vis1_8a_realtime_turnover_model.gd")
const TurnoverBridge = preload("res://scripts/labs/ecology/eco_vis1_8a_turnover_bridge.gd")
const LabEnvironmentProvider = preload("res://scripts/labs/ecology/lab_environment_provider.gd")

const STAGE := "ECO.VIS2.1-T"
const BRANCH_ID := "TREATMENT"
const FIELD_HASH_STAGE := "ECO.VIS1.8A-R1"
const FIELD_HASH_MODE := "REALTIME_TURNOVER_PROXY_PRESENTATION"
const TREATMENT_PROFILES: Array[String] = [
	ExperimentModel.PROFILE_DROUGHT,
	ExperimentModel.PROFILE_FLOOD,
	ExperimentModel.PROFILE_NUTRIENT,
	ExperimentModel.PROFILE_SHADE,
]

var _environment_provider := LabEnvironmentProvider.new(LabEnvironmentProvider.DEFAULT_SEED)
var _realtime_model := RealtimeModel.new()
var _configured := false
var _fork_generation := -1
var _fork_generation_map: Dictionary = {}
var _fork_history: Array[Dictionary] = []
var _generation_cache: Dictionary = {}
var _trace_cache: Dictionary = {}
var _experiment_schedule: Array[Dictionary] = []
var _current_generation := -1
var _sample_generation := -1
var _common_random_seed_hash := ""


func configure_from_fork(
	fork_generation: int,
	fork_generation_map: Dictionary,
	fork_history: Array,
	experiment_id: String,
	intensity: float,
	common_random_seed_hash: String = ""
) -> Dictionary:
	if common_random_seed_hash.is_empty():
		_clear_configuration()
		return {"success": false, "reason": "COMMON_RANDOM_SEED_REQUIRED"}
	if not _is_valid_common_random_seed_hash(common_random_seed_hash):
		_clear_configuration()
		return {"success": false, "reason": "INVALID_COMMON_RANDOM_SEED"}

	var normalized_experiment := ExperimentModel.normalize_profile(experiment_id)
	if fork_generation < 0 or fork_generation_map.is_empty():
		return {"success": false, "reason": "INVALID_FORK"}
	if normalized_experiment not in TREATMENT_PROFILES:
		return {"success": false, "reason": "INVALID_TREATMENT_EXPERIMENT"}

	var normalized_map := _population_map_only(fork_generation_map)
	if normalized_map.is_empty():
		return {"success": false, "reason": "EMPTY_FORK_POPULATION"}

	_fork_generation = fork_generation
	_fork_generation_map = normalized_map.duplicate(true)
	_fork_history = _history_through_fork(fork_history, fork_generation)
	_common_random_seed_hash = common_random_seed_hash

	_experiment_schedule = [{
		"effective_generation": fork_generation + 1,
		"experiment_id": normalized_experiment,
		"intensity": ExperimentModel.normalize_intensity(normalized_experiment, intensity),
	}]
	_configured = true
	restart_from_fork()
	return {
		"success": true,
		"stage": STAGE,
		"branch_id": BRANCH_ID,
		"fork_generation": _fork_generation,
		"common_random_seed_hash": _common_random_seed_hash,
		"experiment_id": normalized_experiment,
		"intensity": ExperimentModel.normalize_intensity(normalized_experiment, intensity),
	}


func advance_to(target_generation: int) -> Dictionary:
	if not _configured:
		return {"success": false, "reason": "NOT_CONFIGURED"}
	if target_generation < _fork_generation:
		return {"success": false, "reason": "BEFORE_FORK"}
	if target_generation <= _current_generation:
		return {"success": true, "generation": _current_generation}

	for next_generation in range(_current_generation + 1, target_generation + 1):
		var previous_map: Dictionary = _generation_cache.get(next_generation - 1, {})
		if previous_map.is_empty():
			return {"success": false, "reason": "MISSING_PREVIOUS_GENERATION", "generation": next_generation}
		_sample_generation = next_generation
		var next_map := _advance_generation(previous_map, next_generation)
		if next_map.is_empty():
			_sample_generation = _current_generation
			return {"success": false, "reason": "ADVANCE_FAILED", "generation": next_generation}
		_generation_cache[next_generation] = next_map
		_current_generation = next_generation
		_sample_generation = _current_generation
		_trace_cache[next_generation] = _make_trace_point(next_generation, next_map)

	return {"success": true, "generation": _current_generation}


func generation_map(generation: int) -> Dictionary:
	if not _configured or generation < _fork_generation:
		return {}
	if generation > _current_generation:
		var result := advance_to(generation)
		if not bool(result.get("success", false)):
			return {}
	return Dictionary(_generation_cache.get(generation, {})).duplicate(true)


func trace() -> Array[Dictionary]:
	if not _configured:
		return []
	var generations := _trace_cache.keys()
	generations.sort()
	var result: Array[Dictionary] = []
	for generation_variant in generations:
		var generation := int(generation_variant)
		if generation > _current_generation:
			continue
		result.append(Dictionary(_trace_cache[generation_variant]).duplicate(true))
	return result


func trace_point(generation: int) -> Dictionary:
	if not _configured:
		return {}
	if generation > _current_generation:
		var result := advance_to(generation)
		if not bool(result.get("success", false)):
			return {}
	return Dictionary(_trace_cache.get(generation, {})).duplicate(true)


func restart_from_fork() -> Dictionary:
	if not _configured:
		return {"success": false, "reason": "NOT_CONFIGURED"}
	_generation_cache.clear()
	_generation_cache[_fork_generation] = _fork_generation_map.duplicate(true)
	_trace_cache.clear()
	for point in _fork_history:
		var generation := int(point.get("generation", -1))
		if generation >= 0 and generation <= _fork_generation:
			_trace_cache[generation] = point.duplicate(true)
	if not _trace_cache.has(_fork_generation):
		_trace_cache[_fork_generation] = _make_trace_point(_fork_generation, _fork_generation_map)
	_current_generation = _fork_generation
	_sample_generation = _fork_generation
	return {"success": true, "generation": _current_generation}


func common_random_seed_hash() -> String:
	return _common_random_seed_hash


func set_experiment(experiment_id: String, intensity: float) -> Dictionary:
	if not _configured:
		return {"success": false, "reason": "NOT_CONFIGURED"}
	var normalized_experiment := ExperimentModel.normalize_profile(experiment_id)
	if normalized_experiment not in TREATMENT_PROFILES:
		return {"success": false, "reason": "INVALID_TREATMENT_EXPERIMENT"}
	var normalized_intensity := ExperimentModel.normalize_intensity(normalized_experiment, intensity)
	var effective_generation := _current_generation + 1
	var retained: Array[Dictionary] = []
	for entry in _experiment_schedule:
		if int(entry.get("effective_generation", 0)) < effective_generation:
			retained.append(entry.duplicate(true))
	retained.append({
		"effective_generation": effective_generation,
		"experiment_id": normalized_experiment,
		"intensity": normalized_intensity,
	})
	_experiment_schedule = retained
	_truncate_future_after(_current_generation)
	return {
		"success": true,
		"effective_generation": effective_generation,
		"experiment_id": normalized_experiment,
		"intensity": normalized_intensity,
	}


func sample_environment_at(world_x: float, world_z: float) -> Dictionary:
	return sample_environment_for_generation(_sample_generation, world_x, world_z)


func sample_environment_for_generation(generation: int, world_x: float, world_z: float) -> Dictionary:
	var terrain_y := sample_terrain_height(world_x, world_z)
	var baseline: Dictionary = _environment_provider.sample(Vector3(world_x, terrain_y, world_z))
	if not _configured or generation <= _fork_generation:
		return baseline
	var experiment := _experiment_for_generation(generation)
	return ExperimentModel.apply(
		baseline,
		String(experiment.get("experiment_id", ExperimentModel.PROFILE_BASELINE)),
		float(experiment.get("intensity", 0.0)),
		generation
	)


func sample_terrain_height(world_x: float, world_z: float) -> float:
	# Exact VIS1.0 proving-ground height function. Keeping this runner headless avoids
	# instantiating the visual lab while preserving the VIS1.1 environment input.
	var nx := clampf(world_x / 250.0, -1.0, 1.0)
	var nz := clampf(world_z / 250.0, -1.0, 1.0)
	var rolling := 7.5 * sin(nx * PI * 1.65) * cos(nz * PI * 1.35)
	var ridge_dx := (nx + 0.28) * 2.15
	var ridge_dz := (nz + 0.30) * 1.20
	var ridge := 19.0 * exp(-(ridge_dx * ridge_dx + ridge_dz * ridge_dz))
	var basin_dx := (nx - 0.34) * 2.20
	var basin_dz := (nz - 0.20) * 2.00
	var basin := -13.0 * exp(-(basin_dx * basin_dx + basin_dz * basin_dz))
	var broad_slope := 5.5 * nx - 2.0 * nz
	return rolling + ridge + basin + broad_slope


func _advance_generation(previous_map: Dictionary, generation: int) -> Dictionary:
	var next_map := {}
	var keys := previous_map.keys()
	keys.sort()
	for key_variant in keys:
		var previous_state_variant = previous_map[key_variant]
		if typeof(previous_state_variant) != TYPE_DICTIONARY:
			continue
		var previous_state: Dictionary = previous_state_variant
		if not previous_state.has("records"):
			continue
		var evaluated_records := _realtime_model.evaluate_records(self, Array(previous_state.get("records", [])))
		var advanced := TurnoverBridge.advance_population(
			evaluated_records,
			int(previous_state.get("base_count", 0)),
			float(previous_state.get("source_biomass_kg", 0.0)),
			generation,
			_common_random_seed_hash,
			String(previous_state.get("patch_id", "")),
			String(previous_state.get("population_id", "")),
			Vector2(previous_state.get("patch_center", Vector2.ZERO))
		)
		if advanced.is_empty():
			return {}
		next_map[key_variant] = {
			"patch_id": String(previous_state.get("patch_id", "")),
			"population_id": String(previous_state.get("population_id", "")),
			"base_count": int(previous_state.get("base_count", 0)),
			"source_biomass_kg": float(previous_state.get("source_biomass_kg", 0.0)),
			"patch_center": Vector2(previous_state.get("patch_center", Vector2.ZERO)),
			"records": Array(advanced.get("records", [])).duplicate(true),
			"transition": advanced.duplicate(true),
		}
	return next_map


func _make_trace_point(generation: int, generation_map_value: Dictionary) -> Dictionary:
	var visual_count := 0
	var birth_count := 0
	var death_count := 0
	var survivor_count := 0
	var fitness_sum := 0.0
	var fitness_count := 0
	var unique_genomes := {}
	var alpha_count := 0
	var beta_count := 0
	var represented_biomass_kg := 0.0
	for state_variant in generation_map_value.values():
		if typeof(state_variant) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_variant
		if not state.has("records"):
			continue
		var transition: Dictionary = state.get("transition", {})
		birth_count += int(transition.get("birth_count", 0))
		death_count += int(transition.get("death_count", 0))
		survivor_count += int(transition.get("survivor_count", 0))
		for record_variant in Array(state.get("records", [])):
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			visual_count += 1
			fitness_sum += float(record.get("current_fitness", 0.0))
			fitness_count += 1
			represented_biomass_kg += float(record.get("represented_biomass_kg", 0.0))
			var genome: Dictionary = record.get("genome", {})
			var genome_key := String(genome.get("checksum", ""))
			if genome_key.is_empty():
				genome_key = var_to_str(genome).sha256_text()
			unique_genomes[genome_key] = true
			match String(record.get("population_id", "")):
				"alpha": alpha_count += 1
				"beta": beta_count += 1
	if generation == _fork_generation and survivor_count == 0:
		survivor_count = visual_count
	var experiment := _experiment_for_generation(generation)
	var environment := sample_environment_for_generation(generation, 0.0, 0.0)
	return {
		"generation": generation,
		"branch_id": BRANCH_ID,
		"experiment_id": String(experiment.get("experiment_id", ExperimentModel.PROFILE_BASELINE)),
		"visual_count": visual_count,
		"birth_count": birth_count,
		"death_count": death_count,
		"survivor_count": survivor_count,
		"mean_fitness": fitness_sum / maxf(1.0, float(fitness_count)),
		"unique_genomes": unique_genomes.size(),
		"alpha_count": alpha_count,
		"beta_count": beta_count,
		"represented_biomass_kg": represented_biomass_kg,
		"field_hash": _field_hash(generation, generation_map_value),
		"environment_revision": String(environment.get("environment_revision", "")),
	}


func _experiment_for_generation(generation: int) -> Dictionary:
	if generation <= _fork_generation:
		return {"experiment_id": ExperimentModel.PROFILE_BASELINE, "intensity": 0.0}
	var selected := {"experiment_id": ExperimentModel.PROFILE_BASELINE, "intensity": 0.0}
	for entry in _experiment_schedule:
		if int(entry.get("effective_generation", _fork_generation + 1)) <= generation:
			selected = entry
		else:
			break
	return selected


func _field_hash(generation: int, generation_map_value: Dictionary) -> String:
	var tokens := PackedStringArray([FIELD_HASH_STAGE, FIELD_HASH_MODE, "generation=%d" % generation])
	var keys := generation_map_value.keys()
	keys.sort()
	for key_variant in keys:
		var state_variant = generation_map_value[key_variant]
		if typeof(state_variant) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_variant
		for record_variant in Array(state.get("records", [])):
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			tokens.append("%s|%s|%.9f|%.9f|g=%d|age=%d" % [
				String(record.get("stable_id", "")),
				String(record.get("parent_stable_id", "")),
				float(record.get("world_x", 0.0)),
				float(record.get("world_z", 0.0)),
				int(record.get("birth_generation", 0)),
				int(record.get("age_generations", 0)),
			])
	return "\n".join(tokens).sha256_text()


func _population_map_only(source: Dictionary) -> Dictionary:
	var result := {}
	for key_variant in source.keys():
		var state_variant = source[key_variant]
		if typeof(state_variant) == TYPE_DICTIONARY and Dictionary(state_variant).has("records"):
			result[key_variant] = Dictionary(state_variant).duplicate(true)
	return result


func _history_through_fork(source: Array, fork_generation: int) -> Array[Dictionary]:
	var by_generation := {}
	for point_variant in source:
		if typeof(point_variant) != TYPE_DICTIONARY:
			continue
		var point: Dictionary = point_variant
		var generation := int(point.get("generation", -1))
		if generation >= 0 and generation <= fork_generation:
			by_generation[generation] = point.duplicate(true)
	var generations := by_generation.keys()
	generations.sort()
	var result: Array[Dictionary] = []
	for generation_variant in generations:
		result.append(Dictionary(by_generation[generation_variant]).duplicate(true))
	return result


func _is_valid_common_random_seed_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


func _truncate_future_after(generation: int) -> void:
	for generation_variant in _generation_cache.keys():
		if int(generation_variant) > generation:
			_generation_cache.erase(generation_variant)
	for generation_variant in _trace_cache.keys():
		if int(generation_variant) > generation:
			_trace_cache.erase(generation_variant)


func _clear_configuration() -> void:
	_configured = false
	_fork_generation = -1
	_fork_generation_map.clear()
	_fork_history.clear()
	_generation_cache.clear()
	_trace_cache.clear()
	_experiment_schedule.clear()
	_current_generation = -1
	_sample_generation = -1
	_common_random_seed_hash = ""
