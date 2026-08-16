extends RefCounted

const TurnoverBridge = preload("res://scripts/labs/ecology/eco_vis1_8a_turnover_bridge.gd")
const TimelineBridge = preload("res://scripts/labs/ecology/eco_vis1_7_temporal_evolution_bridge.gd")
const VIS16 = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")

const STAGE := "ECO.VIS1.8A-R1"

var generation_cache := {}
var max_cached_generation := 0
var founder_count := 0
var last_simulation_ms := 0.0


func capture_founders(field: Node, ph5_root: Node3D, spatial_snapshot: Dictionary) -> void:
	generation_cache.clear()
	max_cached_generation = 0
	founder_count = 0
	if not is_instance_valid(ph5_root) or spatial_snapshot.is_empty():
		return
	var snapshot_hash := String(spatial_snapshot.get("snapshot_hash", ""))
	var generation_zero := {}
	for patch_variant in Array(spatial_snapshot.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		var patch: Dictionary = patch_variant
		var patch_id := String(patch.get("id", ""))
		var patch_root := ph5_root.get_node_or_null("Patch_%s" % patch_id) as Node3D
		if patch_root == null:
			continue
		var patch_center := Vector2(patch_root.global_position.x, patch_root.global_position.z)
		for population_variant in Array(patch.get("plants", [])):
			if typeof(population_variant) != TYPE_DICTIONARY:
				continue
			var population: Dictionary = population_variant
			var population_id := String(population.get("id", ""))
			var source_biomass := maxf(0.0, float(population.get("final_biomass_kg", 0.0)))
			var population_root := patch_root.get_node_or_null("PH5Population_%s" % population_id) as Node3D
			if population_root == null or population_id.is_empty() or source_biomass <= 0.000001:
				continue
			var baseline_genome := VIS16.create_population_baseline_genome(population_id)
			var founders: Array[Dictionary] = []
			for child in population_root.get_children():
				if not child is Node3D or not String(child.name).begins_with("Plant_"):
					continue
				var plant := child as Node3D
				var founder_index := String(plant.name).trim_prefix("Plant_").to_int()
				var environment: Dictionary = field.call("sample_environment_at", plant.global_position.x, plant.global_position.z)
				var adaptation := TimelineBridge.adapt_lineage_to_generation(
					baseline_genome, environment, snapshot_hash, patch_id, population_id, founder_index, 0
				)
				if adaptation.is_empty():
					continue
				var stable_id := "vis18/%s/%s/founder/%03d" % [patch_id, population_id, founder_index]
				var founder := TurnoverBridge.create_founder_record(
					stable_id, patch_id, population_id, founder_index,
					plant.global_position.x, plant.global_position.z, plant.rotation.y,
					Dictionary(adaptation.get("genome", {})), Dictionary(adaptation.get("lineage", {})),
					float(plant.get_meta("represented_biomass_kg", 0.0)), float(adaptation.get("final_fitness", 0.0))
				)
				if not founder.is_empty():
					founders.append(founder)
			var key := population_key(patch_id, population_id)
			var transition := {
				"generation": 0,
				"patch_id": patch_id,
				"population_id": population_id,
				"base_count": founders.size(),
				"previous_count": founders.size(),
				"target_count": founders.size(),
				"survivor_count": founders.size(),
				"birth_count": 0,
				"death_count": 0,
				"source_biomass_kg": source_biomass,
				"represented_biomass_kg": source_biomass,
				"records": founders.duplicate(true),
				"births": [],
				"deaths": [],
				"turnover_hash": founder_hash(snapshot_hash, patch_id, population_id, founders),
			}
			generation_zero[key] = {
				"patch_id": patch_id,
				"population_id": population_id,
				"base_count": founders.size(),
				"source_biomass_kg": source_biomass,
				"patch_center": patch_center,
				"records": founders.duplicate(true),
				"transition": transition,
			}
			founder_count += founders.size()
	generation_cache[0] = generation_zero


func ensure_generation(field: Node, generation: int, spatial_snapshot: Dictionary) -> void:
	if generation <= max_cached_generation:
		last_simulation_ms = 0.0
		return
	var started := Time.get_ticks_usec()
	var snapshot_hash := String(spatial_snapshot.get("snapshot_hash", ""))
	for next_generation in range(max_cached_generation + 1, generation + 1):
		var previous_map: Dictionary = generation_cache.get(next_generation - 1, {})
		var next_map := {}
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
			next_map[key] = {
				"patch_id": String(previous_state.get("patch_id", "")),
				"population_id": String(previous_state.get("population_id", "")),
				"base_count": int(previous_state.get("base_count", 0)),
				"source_biomass_kg": float(previous_state.get("source_biomass_kg", 0.0)),
				"patch_center": Vector2(previous_state.get("patch_center", Vector2.ZERO)),
				"records": Array(advanced.get("records", [])).duplicate(true),
				"transition": advanced.duplicate(true),
			}
		generation_cache[next_generation] = next_map
		max_cached_generation = next_generation
	last_simulation_ms = float(Time.get_ticks_usec() - started) / 1000.0


func generation_map(generation: int) -> Dictionary:
	return Dictionary(generation_cache.get(generation, {}))


func cumulative_event_count(generation: int, field_name: String) -> int:
	var total := 0
	for generation_index in range(1, generation + 1):
		var state_map: Dictionary = generation_cache.get(generation_index, {})
		for state_variant in state_map.values():
			if typeof(state_variant) != TYPE_DICTIONARY:
				continue
			var transition: Dictionary = Dictionary(state_variant).get("transition", {})
			total += int(transition.get(field_name, 0))
	return total


func evaluate_records(field: Node, records: Array) -> Array[Dictionary]:
	var evaluated: Array[Dictionary] = []
	for record_variant in records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = Dictionary(record_variant).duplicate(true)
		var environment: Dictionary = field.call("sample_environment_at", float(record.get("world_x", 0.0)), float(record.get("world_z", 0.0)))
		record["current_fitness"] = TurnoverBridge.evaluate_fitness(Dictionary(record.get("genome", {})), environment)
		evaluated.append(record)
	return evaluated


static func population_key(patch_id: String, population_id: String) -> String:
	return "%s/%s" % [patch_id, population_id]


static func founder_hash(snapshot_hash: String, patch_id: String, population_id: String, records: Array) -> String:
	var tokens := PackedStringArray([STAGE, snapshot_hash, patch_id, population_id, "generation=0"])
	for record_variant in records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		tokens.append("%s|%.9f|%.9f|%.9f" % [
			String(record.get("stable_id", "")),
			float(record.get("world_x", 0.0)),
			float(record.get("world_z", 0.0)),
			float(record.get("represented_biomass_kg", 0.0)),
		])
	return "\n".join(tokens).sha256_text()
