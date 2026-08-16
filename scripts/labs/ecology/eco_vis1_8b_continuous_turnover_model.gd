extends "res://scripts/labs/ecology/eco_vis1_8a_realtime_turnover_model.gd"

const VIS18B_STAGE := "ECO.VIS1.8B"
const ROLLING_CACHE_WINDOW := 32
const HISTORY_WINDOW := 64

var cache_floor_generation := 0
var generation_stats := {}
var history_points: Array[Dictionary] = []
var founder_generation_map := {}
var cumulative_births := 0
var cumulative_deaths := 0
var cumulative_survivals := 0
var peak_visual_count := 0


func capture_founders(field: Node, ph5_root: Node3D, spatial_snapshot: Dictionary) -> void:
	super.capture_founders(field, ph5_root, spatial_snapshot)
	founder_generation_map = generation_cache.get(0, {}).duplicate(true)
	cache_floor_generation = 0
	cumulative_births = 0
	cumulative_deaths = 0
	cumulative_survivals = 0
	peak_visual_count = founder_count
	generation_stats.clear()
	history_points.clear()
	var initial := _summarize_generation(0, generation_cache.get(0, {}), 0, 0, 0)
	generation_stats[0] = initial
	history_points.append(initial.duplicate(true))


func ensure_generation(field: Node, generation: int, spatial_snapshot: Dictionary) -> void:
	if generation < 0:
		last_simulation_ms = 0.0
		return
	if generation_cache.has(generation):
		last_simulation_ms = 0.0
		return
	if generation <= max_cached_generation:
		# Old generations outside the rolling window are intentionally unavailable.
		last_simulation_ms = 0.0
		return
	var started := Time.get_ticks_usec()
	var snapshot_hash := String(spatial_snapshot.get("snapshot_hash", ""))
	for next_generation in range(max_cached_generation + 1, generation + 1):
		var previous_map: Dictionary = generation_cache.get(next_generation - 1, {})
		if previous_map.is_empty():
			break
		var next_map := {}
		var generation_births := 0
		var generation_deaths := 0
		var generation_survivors := 0
		var keys := previous_map.keys()
		keys.sort()
		for key_variant in keys:
			var key := String(key_variant)
			var previous_state: Dictionary = previous_map[key_variant]
			var evaluated_records := evaluate_records(field, Array(previous_state.get("records", [])))
			var advanced := TurnoverBridge.advance_population(
				evaluated_records,
				int(previous_state.get("base_count", 0)),
				float(previous_state.get("source_biomass_kg", 0.0)),
				next_generation,
				snapshot_hash,
				String(previous_state.get("patch_id", "")),
				String(previous_state.get("population_id", "")),
				Vector2(previous_state.get("patch_center", Vector2.ZERO))
			)
			if advanced.is_empty():
				continue
			generation_births += int(advanced.get("birth_count", 0))
			generation_deaths += int(advanced.get("death_count", 0))
			generation_survivors += int(advanced.get("survivor_count", 0))
			next_map[key] = {
				"patch_id": String(previous_state.get("patch_id", "")),
				"population_id": String(previous_state.get("population_id", "")),
				"base_count": int(previous_state.get("base_count", 0)),
				"source_biomass_kg": float(previous_state.get("source_biomass_kg", 0.0)),
				"patch_center": Vector2(previous_state.get("patch_center", Vector2.ZERO)),
				"records": Array(advanced.get("records", [])).duplicate(true),
				"transition": advanced.duplicate(true),
			}
		if next_map.is_empty():
			break
		generation_cache[next_generation] = next_map
		max_cached_generation = next_generation
		cumulative_births += generation_births
		cumulative_deaths += generation_deaths
		cumulative_survivals += generation_survivors
		var stats := _summarize_generation(next_generation, next_map, generation_births, generation_deaths, generation_survivors)
		generation_stats[next_generation] = stats
		peak_visual_count = maxi(peak_visual_count, int(stats.get("visual_count", 0)))
		history_points.append(stats.duplicate(true))
		while history_points.size() > HISTORY_WINDOW:
			history_points.pop_front()
		_trim_rolling_cache()
	last_simulation_ms = float(Time.get_ticks_usec() - started) / 1000.0


func restart_from_founders() -> void:
	generation_cache.clear()
	generation_cache[0] = founder_generation_map.duplicate(true)
	max_cached_generation = 0
	cache_floor_generation = 0
	cumulative_births = 0
	cumulative_deaths = 0
	cumulative_survivals = 0
	peak_visual_count = founder_count
	generation_stats.clear()
	history_points.clear()
	var initial := _summarize_generation(0, generation_cache[0], 0, 0, 0)
	generation_stats[0] = initial
	history_points.append(initial.duplicate(true))
	last_simulation_ms = 0.0


func oldest_rewind_generation() -> int:
	if max_cached_generation <= 0:
		return 0
	return cache_floor_generation


func is_generation_cached(generation: int) -> bool:
	return generation_cache.has(generation)


func cached_generation_count() -> int:
	return generation_cache.size()


func stats_for_generation(generation: int) -> Dictionary:
	return Dictionary(generation_stats.get(generation, {})).duplicate(true)


func recent_history() -> Array[Dictionary]:
	return history_points.duplicate(true)


func cumulative_event_count(generation: int, field_name: String) -> int:
	var stats := generation_stats.get(generation, {}) as Dictionary
	if stats.is_empty():
		if generation == max_cached_generation:
			match field_name:
				"birth_count": return cumulative_births
				"death_count": return cumulative_deaths
				"survivor_count": return cumulative_survivals
		return 0
	match field_name:
		"birth_count": return int(stats.get("cumulative_births", 0))
		"death_count": return int(stats.get("cumulative_deaths", 0))
		"survivor_count": return int(stats.get("cumulative_survivals", 0))
	return 0


func _trim_rolling_cache() -> void:
	var desired_floor := maxi(1, max_cached_generation - ROLLING_CACHE_WINDOW + 1)
	if max_cached_generation < ROLLING_CACHE_WINDOW:
		desired_floor = 1
	var remove_generations: Array[int] = []
	for generation_variant in generation_cache.keys():
		var generation := int(generation_variant)
		if generation != 0 and generation < desired_floor:
			remove_generations.append(generation)
	for generation in remove_generations:
		generation_cache.erase(generation)
		generation_stats.erase(generation)
	cache_floor_generation = 0 if max_cached_generation == 0 else desired_floor


func _summarize_generation(
	generation: int,
	generation_map: Dictionary,
	births: int,
	deaths: int,
	survivors: int
) -> Dictionary:
	var visual_count := 0
	var fitness_sum := 0.0
	var fitness_count := 0
	var genome_ids := {}
	var alpha_count := 0
	var beta_count := 0
	var represented_biomass := 0.0
	for state_variant in generation_map.values():
		if typeof(state_variant) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_variant
		for record_variant in Array(state.get("records", [])):
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			visual_count += 1
			var fitness := float(record.get("current_fitness", 0.0))
			fitness_sum += fitness
			fitness_count += 1
			represented_biomass += float(record.get("represented_biomass_kg", 0.0))
			var genome: Dictionary = record.get("genome", {})
			var genome_key := String(genome.get("checksum", ""))
			if genome_key.is_empty():
				genome_key = var_to_str(genome).sha256_text()
			genome_ids[genome_key] = true
			match String(record.get("population_id", "")):
				"alpha": alpha_count += 1
				"beta": beta_count += 1
	var mean_fitness := fitness_sum / maxf(1.0, float(fitness_count))
	return {
		"generation": generation,
		"visual_count": visual_count,
		"birth_count": births,
		"death_count": deaths,
		"survivor_count": survivors if generation > 0 else visual_count,
		"cumulative_births": cumulative_births,
		"cumulative_deaths": cumulative_deaths,
		"cumulative_survivals": cumulative_survivals,
		"mean_fitness": mean_fitness,
		"unique_genomes": genome_ids.size(),
		"alpha_count": alpha_count,
		"beta_count": beta_count,
		"represented_biomass_kg": represented_biomass,
	}
