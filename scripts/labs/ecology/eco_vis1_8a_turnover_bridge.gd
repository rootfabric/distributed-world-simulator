extends RefCounted

const VIS18_VIS16 = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")
const VIS18_Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const VIS18_LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const VIS18_MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const VIS18_Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const VIS18_Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const VIS18_EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const VIS18_Development = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const VIS18_RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const VIS18_Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")
const VIS18_RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.vis1_8a_population_turnover_bridge.v1"
const VERSION := "1.0.0"
const MODE := "LAB_DERIVED_FITNESS_TURNOVER_RECRUITMENT"
const FIELD_RADIUS_M := 21.5
const MIN_REPRESENTATIVES := 2
const MAX_REPRESENTATIVES := 24
const SURVIVAL_FITNESS_WEIGHT := 0.84
const SURVIVAL_LOTTERY_WEIGHT := 0.16
const RECRUIT_DISPERSAL_SCALE := 0.35
const RECRUIT_DISPERSAL_MIN_M := 1.5
const RECRUIT_DISPERSAL_MAX_M := 12.0


static func create_founder_record(
	stable_id: String,
	patch_id: String,
	population_id: String,
	founder_index: int,
	world_x: float,
	world_z: float,
	rotation_y: float,
	genome: Dictionary,
	lineage: Dictionary,
	represented_biomass_kg: float,
	current_fitness: float
) -> Dictionary:
	if stable_id.is_empty() or patch_id.is_empty() or population_id.is_empty() or founder_index < 0:
		return {}
	if not bool(VIS18_Genome.validate(genome).get("success", false)):
		return {}
	if not bool(VIS18_LineageRecord.validate(lineage).get("success", false)):
		return {}
	if represented_biomass_kg <= 0.0 or not is_finite(current_fitness):
		return {}
	return {
		"stable_id": stable_id,
		"parent_stable_id": "",
		"patch_id": patch_id,
		"population_id": population_id,
		"founder_index": founder_index,
		"birth_generation": 0,
		"age_generations": 0,
		"last_event": "FOUNDER",
		"world_x": world_x,
		"world_z": world_z,
		"rotation_y": rotation_y,
		"represented_biomass_kg": represented_biomass_kg,
		"current_fitness": clampf(current_fitness, 0.0, 1.0),
		"genome": genome.duplicate(true),
		"lineage": lineage.duplicate(true),
	}


static func evaluate_fitness(genome: Dictionary, environment_sample: Dictionary) -> float:
	if not bool(VIS18_Genome.validate(genome).get("success", false)):
		return 0.0
	if not bool(VIS18_EnvironmentSample.validate(environment_sample).get("success", false)):
		return 0.0
	return VIS18_VIS16.fitness(genome, VIS18_VIS16.adaptation_target(environment_sample))


static func target_count(
	base_count: int,
	mean_fitness: float,
	generation: int,
	patch_id: String,
	population_id: String
) -> int:
	if base_count <= 0:
		return 0
	if generation <= 0:
		return clampi(base_count, MIN_REPRESENTATIVES, MAX_REPRESENTATIVES)
	var phase := TAU * _unit01("turnover-phase|%s|%s" % [patch_id, population_id])
	var wave := sin(float(generation) * 1.13 + phase)
	var wave_delta := int(round(wave * maxf(1.0, float(base_count) * 0.16)))
	var fitness_delta := int(round((clampf(mean_fitness, 0.0, 1.0) - 0.80) * float(base_count) * 0.45))
	var lower: int = maxi(MIN_REPRESENTATIVES, int(floor(float(base_count) * 0.65)))
	var upper: int = mini(MAX_REPRESENTATIVES, maxi(base_count + 1, int(ceil(float(base_count) * 1.30))))
	return clampi(base_count + wave_delta + fitness_delta, lower, upper)


static func advance_population(
	current_records: Array,
	base_count: int,
	source_biomass_kg: float,
	generation: int,
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String,
	patch_center: Vector2
) -> Dictionary:
	if generation <= 0 or source_snapshot_hash.length() != 64:
		return {}
	if patch_id.is_empty() or population_id.is_empty() or base_count <= 0 or source_biomass_kg <= 0.0:
		return {}
	if current_records.is_empty():
		return {}

	var records: Array[Dictionary] = []
	var mean_fitness := 0.0
	for record_variant in current_records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			return {}
		var record: Dictionary = Dictionary(record_variant).duplicate(true)
		var genome: Dictionary = record.get("genome", {})
		var lineage: Dictionary = record.get("lineage", {})
		if not bool(VIS18_Genome.validate(genome).get("success", false)):
			return {}
		if not bool(VIS18_LineageRecord.validate(lineage).get("success", false)):
			return {}
		var fitness := float(record.get("current_fitness", -1.0))
		if not is_finite(fitness) or fitness < 0.0 or fitness > 1.0:
			return {}
		mean_fitness += fitness
		records.append(record)
	mean_fitness /= float(records.size())

	var next_target := target_count(base_count, mean_fitness, generation, patch_id, population_id)
	var retention := clampf(0.52 + 0.42 * mean_fitness, 0.56, 0.90)
	var survivor_target := mini(next_target, maxi(1, int(floor(float(records.size()) * retention))))
	var ranked := _rank_for_survival(records, generation, source_snapshot_hash, patch_id, population_id)
	var survivors: Array[Dictionary] = []
	var deaths: Array[Dictionary] = []
	for index in range(ranked.size()):
		var record: Dictionary = ranked[index]
		if index < survivor_target:
			var survivor := record.duplicate(true)
			survivor["age_generations"] = int(survivor.get("age_generations", 0)) + 1
			survivor["last_event"] = "SURVIVED"
			survivors.append(survivor)
		else:
			deaths.append({
				"stable_id": String(record.get("stable_id", "")),
				"world_x": float(record.get("world_x", 0.0)),
				"world_z": float(record.get("world_z", 0.0)),
				"fitness": float(record.get("current_fitness", 0.0)),
			})

	var next_records: Array[Dictionary] = []
	for survivor in survivors:
		next_records.append(survivor.duplicate(true))
	var births_needed := maxi(0, next_target - next_records.size())
	var parent_pool: Array[Dictionary] = survivors if not survivors.is_empty() else ranked
	var birth_summaries: Array[Dictionary] = []
	var mutation_count := 0
	for birth_index in range(births_needed):
		var parent_index := _parent_index(parent_pool.size(), source_snapshot_hash, patch_id, population_id, generation, birth_index)
		var parent: Dictionary = parent_pool[parent_index]
		var parent_genome: Dictionary = parent.get("genome", {})
		var parent_lineage: Dictionary = parent.get("lineage", {})
		var stable_id := _child_stable_id(parent, generation, birth_index, patch_id, population_id)
		var mutation_seed := _seed63("birth-mutation|%s|%s|%s|%d|%d|%s" % [
			source_snapshot_hash,
			patch_id,
			population_id,
			generation,
			birth_index,
			String(parent.get("stable_id", "")),
		])
		var reproduction := VIS18_MutationKernel.reproduce(
			parent_genome,
			parent_lineage,
			mutation_seed,
			birth_index,
			VIS18_VIS16.mutation_policy()
		)
		if reproduction.is_empty() or not bool(VIS18_MutationKernel.validate_result(reproduction).get("success", false)):
			return {}
		var child_genome: Dictionary = Dictionary(reproduction.get("genome", {})).duplicate(true)
		var child_lineage: Dictionary = Dictionary(reproduction.get("lineage", {})).duplicate(true)
		var position := recruit_position(parent, child_genome, source_snapshot_hash, patch_id, population_id, generation, birth_index, patch_center)
		var child := {
			"stable_id": stable_id,
			"parent_stable_id": String(parent.get("stable_id", "")),
			"patch_id": patch_id,
			"population_id": population_id,
			"founder_index": -1,
			"birth_generation": generation,
			"age_generations": 0,
			"last_event": "BORN",
			"world_x": position.x,
			"world_z": position.y,
			"rotation_y": TAU * _unit01("birth-yaw|%s" % stable_id),
			"represented_biomass_kg": 0.0,
			"current_fitness": float(parent.get("current_fitness", 0.0)),
			"genome": child_genome,
			"lineage": child_lineage,
		}
		next_records.append(child)
		mutation_count += int(reproduction.get("mutation_count", 0))
		birth_summaries.append({
			"stable_id": stable_id,
			"parent_stable_id": String(parent.get("stable_id", "")),
			"world_x": position.x,
			"world_z": position.y,
			"mutation_count": int(reproduction.get("mutation_count", 0)),
		})

	if next_records.is_empty():
		return {}
	var represented_sum := 0.0
	for index in range(next_records.size()):
		var represented := source_biomass_kg / float(next_records.size())
		if index == next_records.size() - 1:
			represented = source_biomass_kg - represented_sum
		next_records[index]["represented_biomass_kg"] = represented
		represented_sum += represented

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"mode": MODE,
		"derived_presentation": true,
		"canonical_population_truth": false,
		"canonical_timeline_truth": false,
		"generation": generation,
		"patch_id": patch_id,
		"population_id": population_id,
		"base_count": base_count,
		"previous_count": records.size(),
		"target_count": next_target,
		"survivor_count": survivors.size(),
		"birth_count": birth_summaries.size(),
		"death_count": deaths.size(),
		"mean_parent_fitness": mean_fitness,
		"selected_birth_mutation_count": mutation_count,
		"source_biomass_kg": source_biomass_kg,
		"represented_biomass_kg": represented_sum,
		"records": next_records,
		"births": birth_summaries,
		"deaths": deaths,
	}
	result["turnover_hash"] = compute_turnover_hash(result, source_snapshot_hash)
	return result


static func recruit_position(
	parent: Dictionary,
	child_genome: Dictionary,
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String,
	generation: int,
	birth_index: int,
	patch_center: Vector2
) -> Vector2:
	var parent_position := Vector2(float(parent.get("world_x", patch_center.x)), float(parent.get("world_z", patch_center.y)))
	var genome_dispersal := float(child_genome.get("seed_dispersal_distance_m", 6.0))
	var effective_max := clampf(genome_dispersal * RECRUIT_DISPERSAL_SCALE, RECRUIT_DISPERSAL_MIN_M, RECRUIT_DISPERSAL_MAX_M)
	var key := "recruit|%s|%s|%s|%d|%d|%s" % [
		source_snapshot_hash,
		patch_id,
		population_id,
		generation,
		birth_index,
		String(parent.get("stable_id", "")),
	]
	var angle := TAU * _unit01(key + "|angle")
	var distance := lerpf(RECRUIT_DISPERSAL_MIN_M, effective_max, sqrt(_unit01(key + "|radius")))
	var candidate := parent_position + Vector2(cos(angle), sin(angle)) * distance
	var from_center := candidate - patch_center
	if from_center.length() > FIELD_RADIUS_M:
		candidate = patch_center + from_center.normalized() * FIELD_RADIUS_M
	return candidate


static func realize_individual(
	record: Dictionary,
	environment_sample: Dictionary,
	profile: Dictionary,
	source_snapshot_hash: String,
	field_generation: int
) -> Dictionary:
	if source_snapshot_hash.length() != 64 or field_generation < 0:
		return {}
	if not bool(VIS18_EnvironmentSample.validate(environment_sample).get("success", false)):
		return {}
	if not bool(VIS18_RendererProfile.validate(profile).get("success", false)):
		return {}
	var genome: Dictionary = record.get("genome", {})
	var lineage: Dictionary = record.get("lineage", {})
	if not bool(VIS18_Genome.validate(genome).get("success", false)):
		return {}
	if not bool(VIS18_LineageRecord.validate(lineage).get("success", false)):
		return {}
	var population_id := String(record.get("population_id", ""))
	var inherited_traits := VIS18_VIS16.development_traits_from_genome(genome, population_id)
	if not bool(VIS18_Traits.validate(inherited_traits).get("success", false)):
		return {}
	var stable_id := String(record.get("stable_id", ""))
	var seed_index := int(_seed63("seed-index|%s" % stable_id) % 2147483647)
	var envelope := VIS18_Contract.create_seed_envelope(
		genome,
		inherited_traits,
		String(lineage.get("lineage_id", "")),
		"vis1-8a/%s/%s" % [source_snapshot_hash, String(lineage.get("individual_id", ""))],
		seed_index
	)
	if envelope.is_empty():
		return {}
	var phenotype := VIS18_Development.realize(envelope, inherited_traits, environment_sample)
	if phenotype.is_empty():
		return {}
	var growth_graph: Dictionary = phenotype.get("growth_graph", {})
	var description := VIS18_RenderDescription.build(growth_graph)
	if description.is_empty():
		return {}
	var materialization := VIS18_Materializer3D.build(description, profile)
	if materialization.is_empty():
		return {}
	var target := VIS18_VIS16.adaptation_target(environment_sample)
	var final_fitness := VIS18_VIS16.fitness(genome, target)
	return {
		"stable_id": stable_id,
		"parent_stable_id": String(record.get("parent_stable_id", "")),
		"birth_generation": int(record.get("birth_generation", 0)),
		"age_generations": int(record.get("age_generations", 0)),
		"last_event": String(record.get("last_event", "")),
		"field_generation": field_generation,
		"genome": genome.duplicate(true),
		"lineage": lineage.duplicate(true),
		"genome_checksum": String(genome.get("checksum", "")),
		"lineage_checksum": String(lineage.get("checksum", "")),
		"lineage_generation": int(lineage.get("generation", 0)),
		"environment_checksum": String(environment_sample.get("checksum", "")),
		"current_fitness": final_fitness,
		"inherited_traits": inherited_traits.duplicate(true),
		"phenotype_hash": String(phenotype.get("phenotype_hash", "")),
		"realized_traits": Dictionary(phenotype.get("realized_development_traits", {})).duplicate(true),
		"render_description": description,
		"materialization": materialization,
		"geometry_hash": String(materialization.get("geometry_hash", "")),
	}


static func compute_turnover_hash(result: Dictionary, source_snapshot_hash: String) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		MODE,
		source_snapshot_hash,
		String(result.get("patch_id", "")),
		String(result.get("population_id", "")),
		str(int(result.get("generation", -1))),
		str(int(result.get("base_count", 0))),
		str(int(result.get("previous_count", 0))),
		str(int(result.get("target_count", 0))),
		str(int(result.get("survivor_count", 0))),
		str(int(result.get("birth_count", 0))),
		str(int(result.get("death_count", 0))),
		"%.12f" % float(result.get("source_biomass_kg", 0.0)),
		"%.12f" % float(result.get("represented_biomass_kg", 0.0)),
	])
	for record_variant in Array(result.get("records", [])):
		var record: Dictionary = record_variant
		var genome: Dictionary = record.get("genome", {})
		var lineage: Dictionary = record.get("lineage", {})
		tokens.append("I|%s|%s|%d|%d|%.9f|%.9f|%.9f|%s|%s" % [
			String(record.get("stable_id", "")),
			String(record.get("parent_stable_id", "")),
			int(record.get("birth_generation", -1)),
			int(record.get("age_generations", -1)),
			float(record.get("world_x", 0.0)),
			float(record.get("world_z", 0.0)),
			float(record.get("represented_biomass_kg", 0.0)),
			String(genome.get("checksum", "")),
			String(lineage.get("checksum", "")),
		])
	return "\n".join(tokens).sha256_text()


static func _rank_for_survival(
	records: Array[Dictionary],
	generation: int,
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String
) -> Array[Dictionary]:
	var remaining: Array[Dictionary] = records.duplicate(true)
	var ranked: Array[Dictionary] = []
	while not remaining.is_empty():
		var best_index := 0
		var best_score := -INF
		var best_id := ""
		for index in range(remaining.size()):
			var record: Dictionary = remaining[index]
			var stable_id := String(record.get("stable_id", ""))
			var score := _survival_score(record, generation, source_snapshot_hash, patch_id, population_id)
			if score > best_score + 0.000000000001 or (absf(score - best_score) <= 0.000000000001 and (best_id.is_empty() or stable_id < best_id)):
				best_index = index
				best_score = score
				best_id = stable_id
		ranked.append(remaining[best_index])
		remaining.remove_at(best_index)
	return ranked


static func _survival_score(
	record: Dictionary,
	generation: int,
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String
) -> float:
	var fitness := clampf(float(record.get("current_fitness", 0.0)), 0.0, 1.0)
	var lottery := _unit01("survival|%s|%s|%s|%d|%s" % [
		source_snapshot_hash,
		patch_id,
		population_id,
		generation,
		String(record.get("stable_id", "")),
	])
	return SURVIVAL_FITNESS_WEIGHT * fitness + SURVIVAL_LOTTERY_WEIGHT * lottery


static func _parent_index(
	pool_size: int,
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String,
	generation: int,
	birth_index: int
) -> int:
	if pool_size <= 1:
		return 0
	var preferred_pool := mini(pool_size, 5)
	var unit := _unit01("parent|%s|%s|%s|%d|%d" % [source_snapshot_hash, patch_id, population_id, generation, birth_index])
	return mini(preferred_pool - 1, int(floor(unit * float(preferred_pool))))


static func _child_stable_id(parent: Dictionary, generation: int, birth_index: int, patch_id: String, population_id: String) -> String:
	var parent_token := String(parent.get("stable_id", "")).sha256_text().substr(0, 10)
	return "vis18/%s/%s/g%02d/b%03d/%s" % [patch_id, population_id, generation, birth_index, parent_token]


static func _unit01(payload: String) -> float:
	return float(payload.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0


static func _seed63(payload: String) -> int:
	return payload.sha256_text().substr(0, 15).hex_to_int()
