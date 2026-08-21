extends RefCounted

const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const PatchSimulator = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")
const S2Selection = preload("res://scripts/research/ecology/plant_spatial_selection_baseline_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1b_regional_population_field.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1B-S3.1"
const DEFAULT_GRID_SIZE := 7
const DEFAULT_GENERATIONS := 8
const DEFAULT_POPULATION_SIZE := 6
const DEFAULT_OFFSPRING_PER_PARENT := 2
const DEFAULT_LINEAGE_SEED := 918221
const ALT_LINEAGE_SEED := 918222
const TRAITS: Array[String] = ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"]
const REGION_NAMES: Array[String] = ["DRY", "WET", "SHADED", "SUNLIT"]
const CORRELATION_KEYS: Array[String] = ["water_preference_vs_moisture", "root_depth_vs_moisture", "shade_tolerance_vs_sunlight", "growth_rate_vs_moisture"]

static func run(
	grid_size: int = DEFAULT_GRID_SIZE,
	generations: int = DEFAULT_GENERATIONS,
	population_size: int = DEFAULT_POPULATION_SIZE,
	offspring_per_parent: int = DEFAULT_OFFSPRING_PER_PARENT,
	lineage_seed: int = DEFAULT_LINEAGE_SEED,
	neutral_control: bool = false
) -> Dictionary:
	if grid_size < 5 or generations <= 0 or population_size < 4 or offspring_per_parent < 2:
		return {}
	var ancestor_genome := PlantGenome.create_default()
	var ancestor_lineage := MutationKernel.create_ancestor(ancestor_genome, lineage_seed)
	if ancestor_lineage.is_empty():
		return {}
	var patches: Array = []
	var patch_index := 0
	for iz in range(grid_size):
		for ix in range(grid_size):
			var position := Fixture.grid_position(ix, iz, grid_size)
			var environment := Fixture.sample_at(position.x, position.y)
			var founders := _create_patch_founders(ancestor_genome, ancestor_lineage, population_size, lineage_seed, patch_index)
			if founders.size() != population_size:
				return {}
			patches.append({
				"patch_index": patch_index,
				"ix": ix,
				"iz": iz,
				"world_x_m": position.x,
				"world_z_m": position.y,
				"environment": environment,
				"population": founders,
			})
			patch_index += 1
	var neutral_environment := _neutral_environment(patches)
	if neutral_environment.is_empty():
		return {}
	var diagnostic_regions := _diagnostic_regions(patches)
	var initial_field := _field_summary(patches, neutral_environment if neutral_control else {}, 0)
	if initial_field.is_empty():
		return {}
	var history: Array = [initial_field]
	var regional_history: Array = [{"generation": 0, "regions": _regional_stats(patches, diagnostic_regions)}]
	for generation in range(1, generations + 1):
		for patch in patches:
			var selection_environment: Dictionary = neutral_environment if neutral_control else patch["environment"]
			var next_result := _next_population(
				patch["population"],
				selection_environment,
				generation,
				int(patch["patch_index"]),
				population_size,
				offspring_per_parent,
				lineage_seed
			)
			if next_result.is_empty() or Array(next_result.get("population", [])).size() != population_size:
				return {}
			patch["population"] = next_result["population"]
			if generation == 1:
				patch["first_candidate_pool_hash"] = String(next_result["candidate_pool_hash"])
				patch["first_selected_population_hash"] = String(next_result["selected_population_hash"])
		var generation_summary := _field_summary(patches, neutral_environment if neutral_control else {}, generation)
		if generation_summary.is_empty():
			return {}
		history.append(generation_summary)
		regional_history.append({"generation": generation, "regions": _regional_stats(patches, diagnostic_regions)})
	var regional_stats := _regional_stats(patches, diagnostic_regions)
	var correlations := _trait_environment_correlations(patches)
	var final_patch_summaries := _patch_summaries(patches)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"grid_size": grid_size,
		"patch_count": patches.size(),
		"generations": generations,
		"population_size": population_size,
		"offspring_per_parent": offspring_per_parent,
		"lineage_seed": lineage_seed,
		"neutral_control": neutral_control,
		"ancestor_genome_checksum": String(ancestor_genome["checksum"]),
		"ancestor_lineage_id": String(ancestor_lineage["lineage_id"]),
		"ancestor_lineage_checksum": String(ancestor_lineage["checksum"]),
		"mutation_policy_hash": MutationKernel.policy_hash(S2Selection.selection_mutation_policy()),
		"initial_field": initial_field,
		"final_field": history[history.size() - 1],
		"history": history,
		"regional_history": regional_history,
		"diagnostic_regions": diagnostic_regions,
		"regional_stats": regional_stats,
		"correlations": correlations,
		"patches": final_patch_summaries,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _create_patch_founders(ancestor_genome: Dictionary, ancestor_lineage: Dictionary, population_size: int, lineage_seed: int, patch_index: int) -> Array:
	var policy := MutationKernel.default_policy()
	policy["mutation_probability"] = 0.0
	var founders: Array = []
	for local_index in range(population_size):
		var birth_index := patch_index * population_size + local_index
		var seed := _stable_seed("founder", lineage_seed, patch_index, 0, birth_index, String(ancestor_lineage["individual_id"]))
		var reproduction := MutationKernel.reproduce(ancestor_genome, ancestor_lineage, seed, birth_index, policy)
		if reproduction.is_empty():
			return []
		founders.append({"genome": reproduction["genome"], "lineage": reproduction["lineage"]})
	return founders

static func _next_population(population: Array, environment: Dictionary, generation: int, patch_index: int, population_size: int, offspring_per_parent: int, lineage_seed: int) -> Dictionary:
	var candidates: Array = []
	var policy := S2Selection.selection_mutation_policy()
	for parent_index in range(population.size()):
		var parent: Dictionary = population[parent_index]
		for child_index in range(offspring_per_parent):
			var offspring_index := parent_index * offspring_per_parent + child_index
			var mutation_seed := _stable_seed(
				"mutation",
				lineage_seed,
				patch_index,
				generation,
				offspring_index,
				String(parent["lineage"]["individual_id"])
			)
			var reproduction := MutationKernel.reproduce(parent["genome"], parent["lineage"], mutation_seed, offspring_index, policy)
			if reproduction.is_empty():
				return {}
			var balance := ResourceModel.evaluate(environment, reproduction["genome"], PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
			if balance.is_empty():
				return {}
			candidates.append({
				"genome": reproduction["genome"],
				"lineage": reproduction["lineage"],
				"net": float(balance["net_resource_balance"]),
			})
	var candidate_tokens := PackedStringArray()
	for candidate in candidates:
		candidate_tokens.append("%s|%s" % [String(candidate["lineage"]["checksum"]), String(candidate["genome"]["checksum"])])
	var candidate_pool_hash := "\n".join(candidate_tokens).sha256_text()
	candidates.sort_custom(_candidate_before)
	var selected_population: Array = []
	var selected_tokens := PackedStringArray()
	for index in range(population_size):
		selected_population.append({"genome": candidates[index]["genome"], "lineage": candidates[index]["lineage"]})
		selected_tokens.append("%s|%s" % [String(candidates[index]["lineage"]["checksum"]), String(candidates[index]["genome"]["checksum"])])
	return {
		"population": selected_population,
		"candidate_pool_hash": candidate_pool_hash,
		"selected_population_hash": "\n".join(selected_tokens).sha256_text(),
	}

static func _candidate_before(a: Dictionary, b: Dictionary) -> bool:
	var av := float(a["net"])
	var bv := float(b["net"])
	if absf(av - bv) > 0.000000000001:
		return av > bv
	return String(a["lineage"]["checksum"]) < String(b["lineage"]["checksum"])

static func _neutral_environment(patches: Array) -> Dictionary:
	if patches.is_empty():
		return {}
	var sums := {"temperature_c": 0.0, "soil_moisture": 0.0, "sunlight": 0.0, "nutrients": 0.0, "flood_frequency": 0.0}
	for patch in patches:
		var env: Dictionary = patch["environment"]
		for key in sums.keys():
			sums[key] = float(sums[key]) + float(env[key])
	var count := float(patches.size())
	return preload("res://scripts/research/ecology/environment_sample_v1.gd").create(
		0.0,
		0.0,
		float(sums["temperature_c"]) / count,
		float(sums["soil_moisture"]) / count,
		float(sums["sunlight"]) / count,
		float(sums["nutrients"]) / count,
		float(sums["flood_frequency"]) / count,
		Fixture.DEFAULT_SEED,
		Fixture.ENVIRONMENT_REVISION
	)

static func _field_summary(patches: Array, neutral_environment: Dictionary, generation: int) -> Dictionary:
	var total_net := 0.0
	var total_count := 0
	var trait_sums := {}
	for trait_name in TRAITS:
		trait_sums[trait_name] = 0.0
	var tokens := PackedStringArray()
	for patch in patches:
		var environment: Dictionary = neutral_environment if not neutral_environment.is_empty() else patch["environment"]
		for entry in patch["population"]:
			var genome: Dictionary = entry["genome"]
			var lineage: Dictionary = entry["lineage"]
			if not bool(PlantGenome.validate(genome).get("success", false)) or not bool(LineageRecord.validate(lineage).get("success", false)):
				return {}
			var balance := ResourceModel.evaluate(environment, genome, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
			if balance.is_empty():
				return {}
			total_net += float(balance["net_resource_balance"])
			total_count += 1
			for trait_name in TRAITS:
				trait_sums[trait_name] = float(trait_sums[trait_name]) + float(genome[trait_name])
			tokens.append("%d|%s|%s|%s" % [int(patch["patch_index"]), String(lineage["checksum"]), String(genome["checksum"]), String(balance["checksum"])])
	var means := {}
	for trait_name in TRAITS:
		means[trait_name] = float(trait_sums[trait_name]) / float(total_count)
	return {
		"generation": generation,
		"individual_count": total_count,
		"average_net_resource_balance": total_net / float(total_count),
		"trait_means": means,
		"field_population_hash": "\n".join(tokens).sha256_text(),
	}

static func _diagnostic_regions(patches: Array) -> Dictionary:
	var moisture_values: Array[float] = []
	var light_values: Array[float] = []
	for patch in patches:
		moisture_values.append(float(patch["environment"]["soil_moisture"]))
		light_values.append(float(patch["environment"]["sunlight"]))
	moisture_values.sort()
	light_values.sort()
	var low_m := _quantile_sorted(moisture_values, 0.25)
	var high_m := _quantile_sorted(moisture_values, 0.75)
	var low_l := _quantile_sorted(light_values, 0.25)
	var high_l := _quantile_sorted(light_values, 0.75)
	var regions := {"DRY": [], "WET": [], "SHADED": [], "SUNLIT": []}
	for patch in patches:
		var index := int(patch["patch_index"])
		var moisture := float(patch["environment"]["soil_moisture"])
		var light := float(patch["environment"]["sunlight"])
		if moisture <= low_m:
			regions["DRY"].append(index)
		if moisture >= high_m:
			regions["WET"].append(index)
		if light <= low_l:
			regions["SHADED"].append(index)
		if light >= high_l:
			regions["SUNLIT"].append(index)
	return {
		"thresholds": {"moisture_q25": low_m, "moisture_q75": high_m, "sunlight_q25": low_l, "sunlight_q75": high_l},
		"patches": regions,
	}

static func _regional_stats(patches: Array, diagnostic_regions: Dictionary) -> Dictionary:
	var by_index := {}
	for patch in patches:
		by_index[int(patch["patch_index"])] = patch
	var result := {}
	var region_patches: Dictionary = diagnostic_regions["patches"]
	for region_name in REGION_NAMES:
		var indices: Array = region_patches[region_name]
		var trait_values := {}
		for trait_name in TRAITS:
			trait_values[trait_name] = []
		var env_sums := {"soil_moisture": 0.0, "sunlight": 0.0}
		var avg_net := 0.0
		var individual_count := 0
		for index in indices:
			var patch: Dictionary = by_index[int(index)]
			env_sums["soil_moisture"] = float(env_sums["soil_moisture"]) + float(patch["environment"]["soil_moisture"])
			env_sums["sunlight"] = float(env_sums["sunlight"]) + float(patch["environment"]["sunlight"])
			for entry in patch["population"]:
				var genome: Dictionary = entry["genome"]
				var balance := ResourceModel.evaluate(patch["environment"], genome, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
				avg_net += float(balance["net_resource_balance"])
				individual_count += 1
				for trait_name in TRAITS:
					trait_values[trait_name].append(float(genome[trait_name]))
		var stats := {}
		for trait_name in TRAITS:
			stats[trait_name] = _mean_variance(trait_values[trait_name])
		result[region_name] = {
			"patch_count": indices.size(),
			"individual_count": individual_count,
			"mean_soil_moisture": float(env_sums["soil_moisture"]) / float(indices.size()),
			"mean_sunlight": float(env_sums["sunlight"]) / float(indices.size()),
			"average_net_resource_balance": avg_net / float(individual_count),
			"traits": stats,
		}
	return result

static func _trait_environment_correlations(patches: Array) -> Dictionary:
	var moisture: Array[float] = []
	var sunlight: Array[float] = []
	var trait_patch_means := {}
	for trait_name in TRAITS:
		trait_patch_means[trait_name] = []
	for patch in patches:
		moisture.append(float(patch["environment"]["soil_moisture"]))
		sunlight.append(float(patch["environment"]["sunlight"]))
		for trait_name in TRAITS:
			var total := 0.0
			for entry in patch["population"]:
				total += float(entry["genome"][trait_name])
			trait_patch_means[trait_name].append(total / float(patch["population"].size()))
	return {
		"water_preference_vs_moisture": _pearson(trait_patch_means["water_preference"], moisture),
		"root_depth_vs_moisture": _pearson(trait_patch_means["root_depth_m"], moisture),
		"shade_tolerance_vs_sunlight": _pearson(trait_patch_means["shade_tolerance"], sunlight),
		"growth_rate_vs_moisture": _pearson(trait_patch_means["growth_rate"], moisture),
	}

static func _patch_summaries(patches: Array) -> Array:
	var result: Array = []
	for patch in patches:
		var means := {}
		for trait_name in TRAITS:
			var total := 0.0
			for entry in patch["population"]:
				total += float(entry["genome"][trait_name])
			means[trait_name] = total / float(patch["population"].size())
		var pop_tokens := PackedStringArray()
		var lineage_ids := {}
		for entry in patch["population"]:
			pop_tokens.append("%s|%s" % [String(entry["lineage"]["checksum"]), String(entry["genome"]["checksum"])])
			lineage_ids[String(entry["lineage"]["lineage_id"])] = true
		result.append({
			"patch_index": int(patch["patch_index"]),
			"ix": int(patch["ix"]),
			"iz": int(patch["iz"]),
			"world_x_m": float(patch["world_x_m"]),
			"world_z_m": float(patch["world_z_m"]),
			"environment_checksum": String(patch["environment"]["checksum"]),
			"soil_moisture": float(patch["environment"]["soil_moisture"]),
			"sunlight": float(patch["environment"]["sunlight"]),
			"trait_means": means,
			"population_hash": "\n".join(pop_tokens).sha256_text(),
			"lineage_id_count": lineage_ids.size(),
			"lineage_id": String(lineage_ids.keys()[0]) if lineage_ids.size() == 1 else "",
			"first_candidate_pool_hash": String(patch.get("first_candidate_pool_hash", "")),
			"first_selected_population_hash": String(patch.get("first_selected_population_hash", "")),
		})
	return result

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		str(int(result["grid_size"])),
		str(int(result["generations"])),
		str(int(result["population_size"])),
		str(int(result["offspring_per_parent"])),
		str(int(result["lineage_seed"])),
		"1" if bool(result["neutral_control"]) else "0",
		String(result["ancestor_genome_checksum"]),
		String(result["ancestor_lineage_id"]),
		String(result["mutation_policy_hash"]),
	])
	for summary in result["history"]:
		tokens.append("g%d|%s|%s" % [int(summary["generation"]), _format_float(float(summary["average_net_resource_balance"])), String(summary["field_population_hash"])])
	for generation_regions in result["regional_history"]:
		tokens.append("regional_generation=%d" % int(generation_regions["generation"]))
		for history_region_name in REGION_NAMES:
			var history_region: Dictionary = generation_regions["regions"][history_region_name]
			for history_trait_name in TRAITS:
				tokens.append("rh:%d:%s:%s=%s/%s" % [int(generation_regions["generation"]), history_region_name, history_trait_name, _format_float(float(history_region["traits"][history_trait_name]["mean"])), _format_float(float(history_region["traits"][history_trait_name]["variance"]))])
	for region_name in REGION_NAMES:
		var region: Dictionary = result["regional_stats"][region_name]
		tokens.append("region:%s:%d:%s:%s" % [region_name, int(region["patch_count"]), _format_float(float(region["average_net_resource_balance"])), _format_float(float(region["mean_soil_moisture"]))])
		for trait_name in TRAITS:
			tokens.append("%s:%s=%s/%s" % [region_name, trait_name, _format_float(float(region["traits"][trait_name]["mean"])), _format_float(float(region["traits"][trait_name]["variance"]))])
	for correlation_key in CORRELATION_KEYS:
		tokens.append("corr:%s=%s" % [correlation_key, _format_float(float(result["correlations"][correlation_key]))])
	for patch in result["patches"]:
		tokens.append("patch:%d=%s|%s|%s" % [int(patch["patch_index"]), String(patch["population_hash"]), String(patch["first_candidate_pool_hash"]), String(patch["first_selected_population_hash"])])
	return "\n".join(tokens).sha256_text()

static func _stable_seed(kind: String, lineage_seed: int, patch_index: int, generation: int, local_index: int, parent_id: String) -> int:
	var payload := "%s|%s|%d|%d|%d|%d|%s" % [EXPERIMENT_REVISION, kind, lineage_seed, patch_index, generation, local_index, parent_id]
	return int(payload.sha256_text().substr(0, 8).hex_to_int())

static func _quantile_sorted(values: Array[float], q: float) -> float:
	if values.is_empty():
		return 0.0
	var index := int(round((values.size() - 1) * clampf(q, 0.0, 1.0)))
	return values[index]

static func _mean_variance(values: Array) -> Dictionary:
	if values.is_empty():
		return {"mean": 0.0, "variance": 0.0}
	var mean := 0.0
	for value in values:
		mean += float(value)
	mean /= float(values.size())
	var variance := 0.0
	for value in values:
		var delta := float(value) - mean
		variance += delta * delta
	variance /= float(values.size())
	return {"mean": mean, "variance": variance}

static func _pearson(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.size() < 2:
		return 0.0
	var mean_a := 0.0
	var mean_b := 0.0
	for i in range(a.size()):
		mean_a += float(a[i])
		mean_b += float(b[i])
	mean_a /= float(a.size())
	mean_b /= float(b.size())
	var numerator := 0.0
	var da2 := 0.0
	var db2 := 0.0
	for i in range(a.size()):
		var da := float(a[i]) - mean_a
		var db := float(b[i]) - mean_b
		numerator += da * db
		da2 += da * da
		db2 += db * db
	if da2 <= 0.000000000000001 or db2 <= 0.000000000000001:
		return 0.0
	return numerator / sqrt(da2 * db2)

static func _format_float(value: float) -> String:
	return "%.9f" % value
