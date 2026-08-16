extends RefCounted

const TraceContract = preload("res://scripts/labs/ecology/eco_vis2_1_branch_trace_contract.gd")
const TurnoverBridge = preload("res://scripts/labs/ecology/eco_vis1_8a_turnover_bridge.gd")
const LabEnvironmentProvider = preload("res://scripts/labs/ecology/lab_environment_provider.gd")

const STAGE := "ECO.VIS2.1-C"
const BRANCH_ID := "CONTROL"
const EXPERIMENT_ID := "BASELINE"
const ENVIRONMENT_SEED := 73191
const TERRAIN_HALF_M := 250.0
const RNG_DOMAIN := "ECO.VIS2.1/COMMON_RANDOM_NUMBERS"

var _configured := false
var _fork_generation := -1
var _fork_generation_map := {}
var _fork_history: Array[Dictionary] = []
var _generation_cache := {}
var _trace_points: Array[Dictionary] = []
var _max_generation := -1
var _common_random_seed_hash := ""
var _environment_provider: RefCounted = LabEnvironmentProvider.new(ENVIRONMENT_SEED)


func configure_from_fork(fork_generation: int, fork_generation_map: Dictionary, fork_history: Array) -> Dictionary:
	if fork_generation < 0:
		return _failure("invalid_fork_generation")
	var map_validation := _validate_generation_map(fork_generation_map)
	if not bool(map_validation.get("success", false)):
		return map_validation
	var history_copy: Array[Dictionary] = []
	for point_variant in fork_history:
		if typeof(point_variant) != TYPE_DICTIONARY:
			return _failure("invalid_fork_history")
		history_copy.append(Dictionary(point_variant).duplicate(true))

	_fork_generation = fork_generation
	_fork_generation_map = fork_generation_map.duplicate(true)
	_fork_history = history_copy
	_common_random_seed_hash = derive_common_random_seed_hash(fork_generation, _fork_generation_map)
	_configured = _common_random_seed_hash.length() == 64
	if not _configured:
		return _failure("common_random_seed_derivation_failed")
	var restart := restart_from_fork()
	if not bool(restart.get("success", false)):
		_configured = false
		return restart
	return {
		"success": true,
		"stage": STAGE,
		"branch_id": BRANCH_ID,
		"experiment_id": EXPERIMENT_ID,
		"fork_generation": _fork_generation,
		"fork_history_count": _fork_history.size(),
		"common_random_seed_hash": _common_random_seed_hash,
	}


func advance_to(target_generation: int) -> Dictionary:
	if not _configured:
		return _failure("not_configured")
	if target_generation < _fork_generation:
		return _failure("target_before_fork")
	if target_generation <= _max_generation:
		return {"success": true, "generation": target_generation, "advanced": 0}

	var advanced_count := 0
	for next_generation in range(_max_generation + 1, target_generation + 1):
		var previous_map: Dictionary = _generation_cache.get(next_generation - 1, {})
		if previous_map.is_empty():
			return _failure("missing_previous_generation")
		var next_map := {}
		var keys := previous_map.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
		for key_variant in keys:
			var state_variant: Variant = previous_map[key_variant]
			if typeof(state_variant) != TYPE_DICTIONARY:
				return _failure("invalid_population_state")
			var previous_state: Dictionary = state_variant
			var evaluated_records := _evaluate_records(Array(previous_state.get("records", [])))
			if evaluated_records.is_empty():
				return _failure("environment_evaluation_failed")
			var advanced: Dictionary = TurnoverBridge.advance_population(
				evaluated_records,
				int(previous_state.get("base_count", 0)),
				float(previous_state.get("source_biomass_kg", 0.0)),
				next_generation,
				_common_random_seed_hash,
				String(previous_state.get("patch_id", "")),
				String(previous_state.get("population_id", "")),
				Vector2(previous_state.get("patch_center", Vector2.ZERO))
			)
			if advanced.is_empty():
				return _failure("turnover_advance_failed")
			next_map[String(key_variant)] = {
				"patch_id": String(previous_state.get("patch_id", "")),
				"population_id": String(previous_state.get("population_id", "")),
				"base_count": int(previous_state.get("base_count", 0)),
				"source_biomass_kg": float(previous_state.get("source_biomass_kg", 0.0)),
				"patch_center": Vector2(previous_state.get("patch_center", Vector2.ZERO)),
				"records": Array(advanced.get("records", [])).duplicate(true),
				"transition": advanced.duplicate(true),
			}
		if next_map.is_empty():
			return _failure("empty_generation")
		_generation_cache[next_generation] = next_map
		_max_generation = next_generation
		var point := _summarize_generation(next_generation, next_map)
		if point.is_empty():
			_generation_cache.erase(next_generation)
			_max_generation = next_generation - 1
			return _failure("trace_point_invalid")
		_trace_points.append(point)
		advanced_count += 1
	return {"success": true, "generation": _max_generation, "advanced": advanced_count}


func generation_map(generation: int) -> Dictionary:
	if not _configured:
		return {}
	return Dictionary(_generation_cache.get(generation, {})).duplicate(true)


func trace() -> Array[Dictionary]:
	return _trace_points.duplicate(true)


func trace_point(generation: int) -> Dictionary:
	for point in _trace_points:
		if int(point.get("generation", -1)) == generation:
			return point.duplicate(true)
	return {}


func restart_from_fork() -> Dictionary:
	if not _configured:
		return _failure("not_configured")
	_generation_cache.clear()
	_trace_points.clear()
	_generation_cache[_fork_generation] = _fork_generation_map.duplicate(true)
	_max_generation = _fork_generation
	var point := _summarize_generation(_fork_generation, _generation_cache[_fork_generation])
	if point.is_empty():
		_generation_cache.clear()
		_max_generation = -1
		return _failure("fork_trace_point_invalid")
	_trace_points.append(point)
	return {"success": true, "generation": _fork_generation}


func common_random_seed_hash() -> String:
	return _common_random_seed_hash


func baseline_environment_sample_at(world_x: float, world_z: float) -> Dictionary:
	var terrain_y := _sample_terrain_height(world_x, world_z)
	return Dictionary(_environment_provider.call("sample", Vector3(world_x, terrain_y, world_z))).duplicate(true)


static func derive_common_random_seed_hash(fork_generation: int, fork_generation_map: Dictionary) -> String:
	var field_hash := TraceContract.compute_field_hash(fork_generation, fork_generation_map)
	return ("%s|fork=%d|field=%s" % [RNG_DOMAIN, fork_generation, field_hash]).sha256_text()


func _evaluate_records(records: Array) -> Array[Dictionary]:
	var evaluated: Array[Dictionary] = []
	for record_variant in records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			return []
		var record: Dictionary = Dictionary(record_variant).duplicate(true)
		var environment := baseline_environment_sample_at(
			float(record.get("world_x", 0.0)),
			float(record.get("world_z", 0.0))
		)
		if environment.is_empty():
			return []
		var fitness := TurnoverBridge.evaluate_fitness(Dictionary(record.get("genome", {})), environment)
		if not is_finite(fitness):
			return []
		record["current_fitness"] = clampf(fitness, 0.0, 1.0)
		evaluated.append(record)
	return evaluated


func _summarize_generation(generation: int, generation_map_value: Dictionary) -> Dictionary:
	var visual_count := 0
	var birth_count := 0
	var death_count := 0
	var survivor_count := 0
	var fitness_sum := 0.0
	var fitness_count := 0
	var genome_ids := {}
	var alpha_count := 0
	var beta_count := 0
	var represented_biomass := 0.0
	var environment_revision := ""
	for state_variant in generation_map_value.values():
		if typeof(state_variant) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_variant
		var records: Array = state.get("records", [])
		var transition: Dictionary = state.get("transition", {})
		if transition.is_empty():
			survivor_count += records.size()
		else:
			birth_count += int(transition.get("birth_count", 0))
			death_count += int(transition.get("death_count", 0))
			survivor_count += int(transition.get("survivor_count", records.size()))
		for record_variant in records:
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			visual_count += 1
			var fitness := float(record.get("current_fitness", 0.0))
			if is_finite(fitness):
				fitness_sum += clampf(fitness, 0.0, 1.0)
				fitness_count += 1
			represented_biomass += float(record.get("represented_biomass_kg", 0.0))
			var genome: Dictionary = record.get("genome", {})
			var genome_key := String(genome.get("checksum", ""))
			if genome_key.is_empty():
				genome_key = var_to_str(genome).sha256_text()
			genome_ids[genome_key] = true
			var population_id := String(record.get("population_id", state.get("population_id", "")))
			match population_id:
				"alpha": alpha_count += 1
				"beta": beta_count += 1
			if environment_revision.is_empty():
				var sample := baseline_environment_sample_at(
					float(record.get("world_x", 0.0)),
					float(record.get("world_z", 0.0))
				)
				environment_revision = String(sample.get("environment_revision", ""))
	var mean_fitness := fitness_sum / maxf(1.0, float(fitness_count))
	return TraceContract.create_point(
		generation,
		BRANCH_ID,
		EXPERIMENT_ID,
		visual_count,
		birth_count,
		death_count,
		survivor_count,
		mean_fitness,
		genome_ids.size(),
		alpha_count,
		beta_count,
		represented_biomass,
		TraceContract.compute_field_hash(generation, generation_map_value),
		environment_revision
	)


func _validate_generation_map(generation_map_value: Dictionary) -> Dictionary:
	if generation_map_value.is_empty():
		return _failure("empty_fork_generation_map")
	var valid_states := 0
	for state_variant in generation_map_value.values():
		if typeof(state_variant) != TYPE_DICTIONARY:
			return _failure("invalid_population_state")
		var state: Dictionary = state_variant
		if String(state.get("patch_id", "")).is_empty() or String(state.get("population_id", "")).is_empty():
			return _failure("missing_population_identity")
		if int(state.get("base_count", 0)) <= 0 or float(state.get("source_biomass_kg", 0.0)) <= 0.0:
			return _failure("invalid_population_mass_or_count")
		if typeof(state.get("patch_center", null)) != TYPE_VECTOR2:
			return _failure("invalid_patch_center")
		var records: Array = state.get("records", [])
		if records.is_empty():
			return _failure("empty_population_records")
		valid_states += 1
	return {"success": valid_states > 0}


static func _sample_terrain_height(x: float, z: float) -> float:
	# Exact VIS1.0 terrain function. Keeping it pure avoids creating a scene node inside this RefCounted runner.
	var nx: float = clamp(x / TERRAIN_HALF_M, -1.0, 1.0)
	var nz: float = clamp(z / TERRAIN_HALF_M, -1.0, 1.0)
	var rolling: float = 7.5 * sin(nx * PI * 1.65) * cos(nz * PI * 1.35)
	var ridge_dx: float = (nx + 0.28) * 2.15
	var ridge_dz: float = (nz + 0.30) * 1.20
	var ridge: float = 19.0 * exp(-(ridge_dx * ridge_dx + ridge_dz * ridge_dz))
	var basin_dx: float = (nx - 0.34) * 2.20
	var basin_dz: float = (nz - 0.20) * 2.00
	var basin: float = -13.0 * exp(-(basin_dx * basin_dx + basin_dz * basin_dz))
	var broad_slope: float = 5.5 * nx - 2.0 * nz
	return rolling + ridge + basin + broad_slope


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error": code}
