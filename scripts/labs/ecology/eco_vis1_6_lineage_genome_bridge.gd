extends RefCounted

const VIS16_Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const VIS16_Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const VIS16_Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const VIS16_EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const VIS16_Development = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const VIS16_RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const VIS16_Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")
const VIS16_RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const VIS16_MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const VIS16_LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.vis1_6_lineage_genome_bridge.v1"
const VERSION := "1.0.0"
const MODE := "LAB_DERIVED_LINEAGE_GENOME_LOCAL_ENVIRONMENT"
const ADAPTATION_GENERATIONS := 3
const OFFSPRING_PER_GENERATION := 4

static func create_population_baseline_genome(population_id: String) -> Dictionary:
	match population_id:
		"alpha":
			return VIS16_Genome.create("plant-genome/vis1-6-alpha-lab-baseline", 1.85, 0.72, 1.05, 0.46, 0.27, 0.30, 110, 20.0, 5.5)
		"beta":
			return VIS16_Genome.create("plant-genome/vis1-6-beta-lab-baseline", 1.55, 0.57, 1.35, 0.72, 0.38, 0.68, 78, 11.0, 7.5)
	return {}

static func mutation_policy() -> Dictionary:
	return {
		"mutation_probability": 0.82,
		"water_preference_step": 0.12,
		"root_depth_m_step": 0.75,
		"growth_rate_step": 0.12,
		"shade_tolerance_step": 0.12,
		"seed_dispersal_distance_m_step": 6.0,
	}

static func realize(environment_sample: Dictionary, profile: Dictionary, source_snapshot_hash: String, patch_id: String, population_id: String, instance_index: int) -> Dictionary:
	if source_snapshot_hash.length() != 64 or patch_id.is_empty() or population_id.is_empty() or instance_index < 0:
		return {}
	if not bool(VIS16_EnvironmentSample.validate(environment_sample).get("success", false)):
		return {}
	if not bool(VIS16_RendererProfile.validate(profile).get("success", false)):
		return {}
	var baseline_genome := create_population_baseline_genome(population_id)
	if not bool(VIS16_Genome.validate(baseline_genome).get("success", false)):
		return {}
	var adaptation := adapt_lineage(baseline_genome, environment_sample, source_snapshot_hash, patch_id, population_id, instance_index)
	if adaptation.is_empty():
		return {}
	var genome: Dictionary = adaptation.get("genome", {})
	var lineage: Dictionary = adaptation.get("lineage", {})
	if not bool(VIS16_Genome.validate(genome).get("success", false)) or not bool(VIS16_LineageRecord.validate(lineage).get("success", false)):
		return {}
	var inherited_traits := development_traits_from_genome(genome, population_id)
	if not bool(VIS16_Traits.validate(inherited_traits).get("success", false)):
		return {}
	var envelope := VIS16_Contract.create_seed_envelope(genome, inherited_traits, String(lineage.get("lineage_id", "")), "vis1-6/%s/%s" % [source_snapshot_hash, String(lineage.get("individual_id", ""))], instance_index)
	if envelope.is_empty():
		return {}
	var phenotype := VIS16_Development.realize(envelope, inherited_traits, environment_sample)
	if phenotype.is_empty():
		return {}
	var growth_graph: Dictionary = phenotype.get("growth_graph", {})
	var description := VIS16_RenderDescription.build(growth_graph)
	if description.is_empty():
		return {}
	var materialization := VIS16_Materializer3D.build(description, profile)
	if materialization.is_empty():
		return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"derived_presentation": true,
		"mode": MODE,
		"canonical_genome_truth": false,
		"source_snapshot_hash": source_snapshot_hash,
		"patch_id": patch_id,
		"population_id": population_id,
		"instance_index": instance_index,
		"baseline_genome_id": String(baseline_genome.get("genome_id", "")),
		"baseline_genome_checksum": String(baseline_genome.get("checksum", "")),
		"genome": genome.duplicate(true),
		"genome_id": String(genome.get("genome_id", "")),
		"genome_checksum": String(genome.get("checksum", "")),
		"lineage": lineage.duplicate(true),
		"lineage_id": String(lineage.get("lineage_id", "")),
		"individual_id": String(lineage.get("individual_id", "")),
		"lineage_checksum": String(lineage.get("checksum", "")),
		"generation": int(lineage.get("generation", -1)),
		"adaptation_target": Dictionary(adaptation.get("target", {})).duplicate(true),
		"initial_fitness": float(adaptation.get("initial_fitness", 0.0)),
		"final_fitness": float(adaptation.get("final_fitness", 0.0)),
		"selected_mutation_count": int(adaptation.get("selected_mutation_count", 0)),
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

static func adapt_lineage(baseline_genome: Dictionary, environment_sample: Dictionary, source_snapshot_hash: String, patch_id: String, population_id: String, instance_index: int) -> Dictionary:
	if not bool(VIS16_Genome.validate(baseline_genome).get("success", false)) or not bool(VIS16_EnvironmentSample.validate(environment_sample).get("success", false)):
		return {}
	var target := adaptation_target(environment_sample)
	var lineage_seed := _seed63("ancestor|%s|%s|%s|%d" % [source_snapshot_hash, patch_id, population_id, instance_index])
	var current_lineage := VIS16_MutationKernel.create_ancestor(baseline_genome, lineage_seed)
	if current_lineage.is_empty():
		return {}
	var current_genome := baseline_genome.duplicate(true)
	var initial_fitness := fitness(current_genome, target)
	var current_fitness := initial_fitness
	var selected_mutations := 0
	var policy := mutation_policy()
	var carry_policy := policy.duplicate(true)
	carry_policy["mutation_probability"] = 0.0
	for generation_index in range(ADAPTATION_GENERATIONS):
		var best_result := {}
		var best_score := -INF
		for offspring_index in range(OFFSPRING_PER_GENERATION):
			var candidate_policy := carry_policy if offspring_index == 0 else policy
			var mutation_seed := _seed63("mutation|%s|%s|%s|%d|%d|%d" % [source_snapshot_hash, patch_id, population_id, instance_index, generation_index, offspring_index])
			var candidate := VIS16_MutationKernel.reproduce(current_genome, current_lineage, mutation_seed, offspring_index, candidate_policy)
			if candidate.is_empty() or not bool(VIS16_MutationKernel.validate_result(candidate).get("success", false)):
				continue
			var candidate_score := fitness(Dictionary(candidate.get("genome", {})), target)
			if best_result.is_empty() or candidate_score > best_score + 0.000000000001:
				best_result = candidate
				best_score = candidate_score
		if best_result.is_empty():
			return {}
		current_genome = Dictionary(best_result.get("genome", {})).duplicate(true)
		current_lineage = Dictionary(best_result.get("lineage", {})).duplicate(true)
		current_fitness = best_score
		selected_mutations += int(best_result.get("mutation_count", 0))
	return {"genome": current_genome, "lineage": current_lineage, "target": target, "initial_fitness": initial_fitness, "final_fitness": current_fitness, "selected_mutation_count": selected_mutations}

static func adaptation_target(environment_sample: Dictionary) -> Dictionary:
	var moisture := float(environment_sample.get("soil_moisture", 0.0))
	var sunlight := float(environment_sample.get("sunlight", 0.0))
	var nutrients := float(environment_sample.get("nutrients", 0.0))
	var flood := float(environment_sample.get("flood_frequency", 0.0))
	return {
		"water_preference": clampf(0.10 + 0.65 * moisture + 0.25 * flood, 0.0, 1.0),
		"root_depth_m": clampf(0.50 + 3.0 * (1.0 - moisture) + 1.0 * (1.0 - nutrients), 0.05, 20.0),
		"growth_rate": clampf(0.15 + 0.45 * nutrients + 0.30 * sunlight - 0.25 * flood, 0.0, 1.0),
		"shade_tolerance": clampf(0.10 + 0.80 * (1.0 - sunlight), 0.0, 1.0),
		"seed_dispersal_distance_m": clampf(6.0 + 18.0 * sunlight + 8.0 * (1.0 - flood), 0.0, 100000.0),
	}

static func fitness(genome: Dictionary, target: Dictionary) -> float:
	var water_distance := absf(float(genome.get("water_preference", 0.0)) - float(target.get("water_preference", 0.0)))
	var root_distance := minf(absf(float(genome.get("root_depth_m", 0.0)) - float(target.get("root_depth_m", 0.0))) / 5.0, 1.0)
	var growth_distance := absf(float(genome.get("growth_rate", 0.0)) - float(target.get("growth_rate", 0.0)))
	var shade_distance := absf(float(genome.get("shade_tolerance", 0.0)) - float(target.get("shade_tolerance", 0.0)))
	var dispersal_distance := minf(absf(float(genome.get("seed_dispersal_distance_m", 0.0)) - float(target.get("seed_dispersal_distance_m", 0.0))) / 25.0, 1.0)
	return clampf(1.0 - 0.28 * water_distance - 0.18 * root_distance - 0.22 * growth_distance - 0.22 * shade_distance - 0.10 * dispersal_distance, 0.0, 1.0)

static func development_traits_from_genome(genome: Dictionary, population_id: String) -> Dictionary:
	if not bool(VIS16_Genome.validate(genome).get("success", false)):
		return {}
	var height := float(genome.get("height_m", 1.0))
	var growth := float(genome.get("growth_rate", 0.5))
	var root_depth := float(genome.get("root_depth_m", 1.0))
	var water_width := float(genome.get("water_tolerance_width", 0.3))
	var shade := float(genome.get("shade_tolerance", 0.5))
	var max_height := clampf(height * (1.55 + 0.75 * growth), 0.10, 40.0)
	var internode := clampf(0.18 + 0.24 * (1.0 - growth) + 0.08 * minf(root_depth / 5.0, 1.0), 0.02, 4.0)
	var apical := clampf(0.42 + 0.38 * growth - 0.18 * shade, 0.0, 1.0)
	var branch_probability := clampf(0.25 + 0.42 * shade + 0.14 * (1.0 - growth), 0.0, 1.0)
	var branch_angle := clampf(28.0 + 34.0 * shade + 8.0 * water_width, 0.0, 89.0)
	var branch_length_ratio := clampf(0.52 + 0.34 * shade + 0.22 * water_width, 0.05, 2.0)
	var branching_depth := clampi(1 + int(round(2.0 * growth + 1.5 * shade)), 1, 5)
	var crown_spread := clampf(0.45 + height * 0.34 + shade * 0.85 + water_width * 0.55, 0.05, 30.0)
	return VIS16_Traits.create("plant-development/vis1-6/%s/%s" % [population_id, String(genome.get("checksum", "")).substr(0, 12)], max_height, internode, apical, branch_probability, branch_angle, branch_length_ratio, branching_depth, crown_spread)

static func compute_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, MODE,
		String(result.get("source_snapshot_hash", "")), String(result.get("patch_id", "")), String(result.get("population_id", "")), str(int(result.get("instance_index", -1))),
		String(result.get("baseline_genome_checksum", "")), String(result.get("genome_checksum", "")), String(result.get("lineage_checksum", "")), str(int(result.get("generation", -1))),
		"%.12f" % float(result.get("initial_fitness", 0.0)), "%.12f" % float(result.get("final_fitness", 0.0)),
		String(result.get("inherited_traits_checksum", "")), String(result.get("environment_checksum", "")), String(result.get("phenotype_hash", "")), String(result.get("growth_graph_hash", "")), String(result.get("render_description_hash", "")), String(result.get("geometry_hash", "")),
	])).sha256_text()

static func _seed63(payload: String) -> int:
	return payload.sha256_text().substr(0, 15).hex_to_int()
