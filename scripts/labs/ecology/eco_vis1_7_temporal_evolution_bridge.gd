extends RefCounted

const VIS17_VIS16 = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")
const VIS17_Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const VIS17_Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const VIS17_Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const VIS17_EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const VIS17_Development = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const VIS17_RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const VIS17_Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")
const VIS17_RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const VIS17_MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const VIS17_LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.vis1_7_temporal_evolution_bridge.v1"
const VERSION := "1.0.0"
const MODE := "LAB_DERIVED_TEMPORAL_LINEAGE_SCRUBBER"
const DEFAULT_GENERATION := 3
const MAX_GENERATION := 12

static func realize_at_generation(
	environment_sample: Dictionary,
	profile: Dictionary,
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String,
	instance_index: int,
	generation_count: int
) -> Dictionary:
	if source_snapshot_hash.length() != 64 or patch_id.is_empty() or population_id.is_empty() or instance_index < 0:
		return {}
	if generation_count < 0 or generation_count > MAX_GENERATION:
		return {}
	if not bool(VIS17_EnvironmentSample.validate(environment_sample).get("success", false)):
		return {}
	if not bool(VIS17_RendererProfile.validate(profile).get("success", false)):
		return {}
	var baseline_genome := VIS17_VIS16.create_population_baseline_genome(population_id)
	if not bool(VIS17_Genome.validate(baseline_genome).get("success", false)):
		return {}
	var adaptation := adapt_lineage_to_generation(
		baseline_genome,
		environment_sample,
		source_snapshot_hash,
		patch_id,
		population_id,
		instance_index,
		generation_count
	)
	if adaptation.is_empty():
		return {}
	var genome: Dictionary = adaptation.get("genome", {})
	var lineage: Dictionary = adaptation.get("lineage", {})
	if not bool(VIS17_Genome.validate(genome).get("success", false)):
		return {}
	if not bool(VIS17_LineageRecord.validate(lineage).get("success", false)):
		return {}
	var inherited_traits := VIS17_VIS16.development_traits_from_genome(genome, population_id)
	if not bool(VIS17_Traits.validate(inherited_traits).get("success", false)):
		return {}
	var envelope := VIS17_Contract.create_seed_envelope(
		genome,
		inherited_traits,
		String(lineage.get("lineage_id", "")),
		"vis1-6/%s/%s" % [source_snapshot_hash, String(lineage.get("individual_id", ""))],
		instance_index
	)
	if envelope.is_empty():
		return {}
	var phenotype := VIS17_Development.realize(envelope, inherited_traits, environment_sample)
	if phenotype.is_empty():
		return {}
	var growth_graph: Dictionary = phenotype.get("growth_graph", {})
	var description := VIS17_RenderDescription.build(growth_graph)
	if description.is_empty():
		return {}
	var materialization := VIS17_Materializer3D.build(description, profile)
	if materialization.is_empty():
		return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"derived_presentation": true,
		"mode": MODE,
		"canonical_genome_truth": false,
		"canonical_timeline_truth": false,
		"source_snapshot_hash": source_snapshot_hash,
		"patch_id": patch_id,
		"population_id": population_id,
		"instance_index": instance_index,
		"generation": generation_count,
		"baseline_genome_id": String(baseline_genome.get("genome_id", "")),
		"baseline_genome_checksum": String(baseline_genome.get("checksum", "")),
		"genome": genome.duplicate(true),
		"genome_id": String(genome.get("genome_id", "")),
		"genome_checksum": String(genome.get("checksum", "")),
		"lineage": lineage.duplicate(true),
		"lineage_id": String(lineage.get("lineage_id", "")),
		"individual_id": String(lineage.get("individual_id", "")),
		"lineage_checksum": String(lineage.get("checksum", "")),
		"adaptation_target": Dictionary(adaptation.get("target", {})).duplicate(true),
		"initial_fitness": float(adaptation.get("initial_fitness", 0.0)),
		"final_fitness": float(adaptation.get("final_fitness", 0.0)),
		"selected_mutation_count": int(adaptation.get("selected_mutation_count", 0)),
		"trajectory": Array(adaptation.get("trajectory", [])).duplicate(true),
		"trajectory_hash": String(adaptation.get("trajectory_hash", "")),
		"inherited_traits": inherited_traits.duplicate(true),
		"inherited_traits_checksum": String(inherited_traits.get("checksum", "")),
		"environment_checksum": String(environment_sample.get("checksum", "")),
		"phenotype_hash": String(phenotype.get("phenotype_hash", "")),
		"growth_graph_hash": String(growth_graph.get("graph_hash", "")),
		"render_description_hash": String(description.get("render_description_hash", "")),
		"geometry_hash": String(materialization.get("geometry_hash", "")),
		"response": Dictionary(phenotype.get("response", {})).duplicate(true),
		"realized_traits": Dictionary(phenotype.get("realized_development_traits", {})).duplicate(true),
		"render_description": description,
		"materialization": materialization,
	}
	result["bridge_hash"] = compute_hash(result)
	return result

static func adapt_lineage_to_generation(
	baseline_genome: Dictionary,
	environment_sample: Dictionary,
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String,
	instance_index: int,
	generation_count: int
) -> Dictionary:
	if generation_count < 0 or generation_count > MAX_GENERATION:
		return {}
	if not bool(VIS17_Genome.validate(baseline_genome).get("success", false)):
		return {}
	if not bool(VIS17_EnvironmentSample.validate(environment_sample).get("success", false)):
		return {}
	var target := VIS17_VIS16.adaptation_target(environment_sample)
	var lineage_seed := _seed63("ancestor|%s|%s|%s|%d" % [source_snapshot_hash, patch_id, population_id, instance_index])
	var current_lineage := VIS17_MutationKernel.create_ancestor(baseline_genome, lineage_seed)
	if current_lineage.is_empty():
		return {}
	var current_genome := baseline_genome.duplicate(true)
	var initial_fitness := VIS17_VIS16.fitness(current_genome, target)
	var current_fitness := initial_fitness
	var selected_mutations := 0
	var trajectory: Array[Dictionary] = [{
		"generation": 0,
		"fitness": initial_fitness,
		"genome_checksum": String(current_genome.get("checksum", "")),
		"lineage_checksum": String(current_lineage.get("checksum", "")),
		"selected_mutation_count": 0,
	}]
	var policy := VIS17_VIS16.mutation_policy()
	var carry_policy := policy.duplicate(true)
	carry_policy["mutation_probability"] = 0.0
	for generation_index in range(generation_count):
		var best_result := {}
		var best_score := -INF
		for offspring_index in range(VIS17_VIS16.OFFSPRING_PER_GENERATION):
			var candidate_policy := carry_policy if offspring_index == 0 else policy
			var mutation_seed := _seed63("mutation|%s|%s|%s|%d|%d|%d" % [
				source_snapshot_hash,
				patch_id,
				population_id,
				instance_index,
				generation_index,
				offspring_index,
			])
			var candidate := VIS17_MutationKernel.reproduce(
				current_genome,
				current_lineage,
				mutation_seed,
				offspring_index,
				candidate_policy
			)
			if candidate.is_empty() or not bool(VIS17_MutationKernel.validate_result(candidate).get("success", false)):
				continue
			var candidate_score := VIS17_VIS16.fitness(Dictionary(candidate.get("genome", {})), target)
			if best_result.is_empty() or candidate_score > best_score + 0.000000000001:
				best_result = candidate
				best_score = candidate_score
		if best_result.is_empty():
			return {}
		current_genome = Dictionary(best_result.get("genome", {})).duplicate(true)
		current_lineage = Dictionary(best_result.get("lineage", {})).duplicate(true)
		current_fitness = best_score
		selected_mutations += int(best_result.get("mutation_count", 0))
		trajectory.append({
			"generation": generation_index + 1,
			"fitness": current_fitness,
			"genome_checksum": String(current_genome.get("checksum", "")),
			"lineage_checksum": String(current_lineage.get("checksum", "")),
			"selected_mutation_count": int(best_result.get("mutation_count", 0)),
		})
	var trajectory_hash := compute_trajectory_hash(
		source_snapshot_hash,
		patch_id,
		population_id,
		instance_index,
		trajectory
	)
	return {
		"genome": current_genome,
		"lineage": current_lineage,
		"target": target,
		"initial_fitness": initial_fitness,
		"final_fitness": current_fitness,
		"selected_mutation_count": selected_mutations,
		"trajectory": trajectory,
		"trajectory_hash": trajectory_hash,
	}

static func compute_trajectory_hash(
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String,
	instance_index: int,
	trajectory: Array
) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		MODE,
		source_snapshot_hash,
		patch_id,
		population_id,
		str(instance_index),
	])
	for entry_variant in trajectory:
		var entry: Dictionary = entry_variant
		tokens.append("%d|%.12f|%s|%s|%d" % [
			int(entry.get("generation", -1)),
			float(entry.get("fitness", 0.0)),
			String(entry.get("genome_checksum", "")),
			String(entry.get("lineage_checksum", "")),
			int(entry.get("selected_mutation_count", 0)),
		])
	return "\n".join(tokens).sha256_text()

static func compute_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		MODE,
		String(result.get("source_snapshot_hash", "")),
		String(result.get("patch_id", "")),
		String(result.get("population_id", "")),
		str(int(result.get("instance_index", -1))),
		str(int(result.get("generation", -1))),
		String(result.get("baseline_genome_checksum", "")),
		String(result.get("genome_checksum", "")),
		String(result.get("lineage_checksum", "")),
		String(result.get("trajectory_hash", "")),
		"%.12f" % float(result.get("initial_fitness", 0.0)),
		"%.12f" % float(result.get("final_fitness", 0.0)),
		String(result.get("inherited_traits_checksum", "")),
		String(result.get("environment_checksum", "")),
		String(result.get("phenotype_hash", "")),
		String(result.get("geometry_hash", "")),
	])).sha256_text()

static func _seed63(payload: String) -> int:
	return payload.sha256_text().substr(0, 15).hex_to_int()
