extends RefCounted

const TraceContract = preload("res://scripts/labs/ecology/eco_vis2_1_branch_trace_contract.gd")


static func from_generation_map(
	generation: int,
	generation_map: Dictionary,
	branch_id: String,
	experiment_id: String,
	environment_revision: String
) -> Dictionary:
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

	for state_variant in generation_map.values():
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
			represented_biomass_kg += maxf(0.0, float(record.get("represented_biomass_kg", 0.0)))

			var genome: Dictionary = record.get("genome", {})
			var genome_key := String(genome.get("checksum", ""))
			if genome_key.is_empty():
				genome_key = var_to_str(genome).sha256_text()
			unique_genomes[genome_key] = true

			match String(record.get("population_id", state.get("population_id", ""))):
				"alpha":
					alpha_count += 1
				"beta":
					beta_count += 1

	if generation_map.is_empty():
		return {}
	var mean_fitness := fitness_sum / maxf(1.0, float(fitness_count))
	return TraceContract.create_point(
		generation,
		branch_id,
		experiment_id,
		visual_count,
		birth_count,
		death_count,
		survivor_count,
		mean_fitness,
		unique_genomes.size(),
		alpha_count,
		beta_count,
		represented_biomass_kg,
		TraceContract.compute_field_hash(generation, generation_map),
		environment_revision
	)
