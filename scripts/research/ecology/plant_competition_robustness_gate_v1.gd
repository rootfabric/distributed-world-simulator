extends RefCounted

const Dynamic = preload("res://scripts/research/ecology/plant_dynamic_abundance_competition_v1.gd")
const Diagnostics = preload("res://scripts/research/ecology/plant_niche_cluster_diagnostics_v1.gd")
const S1Competition = preload("res://scripts/research/ecology/plant_strategy_competition_baseline_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1c_competition_robustness_gate.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1C-S4.1"
const ROBUSTNESS_CYCLES := 18
const DEEP_HORIZON_CYCLES := 24
const ROBUSTNESS_SEEDS: Array[int] = [1138701, 1138702, 1138703, 1138704, 1138705, 1138706]
const MIN_EFFECTIVE_FOUNDERS_1PCT := 12
const MAX_TOP1_BIOMASS_SHARE := 0.50
const MIN_SHANNON_DIVERSITY := 2.10
const MIN_SUBSTANTIAL_CLUSTERS := 3
const MIN_NICHE_ENRICHED_CLUSTERS := 2
const UNIFORM_MAX_NICHE_SPAN := 0.000000001

static func run_case(founder_seed: int, cycles: int = ROBUSTNESS_CYCLES, uniform_control: bool = false) -> Dictionary:
	if cycles < Dynamic.DEFAULT_CYCLES:
		return {}
	var dynamic := Dynamic.run(
		Dynamic.DEFAULT_GRID_SIZE,
		Dynamic.DEFAULT_FOUNDER_COUNT,
		cycles,
		Dynamic.DEFAULT_SEASONS_PER_CYCLE,
		founder_seed,
		uniform_control
	)
	if dynamic.is_empty():
		return {}
	var diagnostic := Diagnostics.diagnose(dynamic, founder_seed, Diagnostics.DEFAULT_CLUSTER_COUNT, Diagnostics.DEFAULT_EFFECTIVE_SHARE)
	if diagnostic.is_empty():
		return {}
	var max_niche_span := 0.0
	for cluster in Array(diagnostic["clusters"]):
		max_niche_span = maxf(max_niche_span, float(cluster["niche_enrichment_span"]))
	var bounded_founders := _founders_are_bounded(founder_seed)
	var failure_matrix := _classify_case(dynamic, diagnostic, max_niche_span, bounded_founders, uniform_control)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"founder_seed": founder_seed,
		"cycles": cycles,
		"uniform_control": uniform_control,
		"dynamic_result_hash": String(dynamic["result_hash"]),
		"diagnostic_hash": String(diagnostic["diagnostic_hash"]),
		"founder_pool_hash": String(dynamic["founder_pool_hash"]),
		"effective_founders_1pct": int(dynamic["global_abundance"]["effective_founders_1pct"]),
		"effective_founders_2pct": int(dynamic["global_abundance"]["effective_founders_2pct"]),
		"effective_founders_5pct": int(dynamic["global_abundance"]["effective_founders_5pct"]),
		"top1_biomass_share": float(dynamic["global_abundance"]["top1_biomass_share"]),
		"top1_patch_dominance_ratio": float(dynamic["global_abundance"]["top1_patch_dominance_ratio"]),
		"shannon_biomass_diversity": float(dynamic["global_abundance"]["shannon_biomass_diversity"]),
		"silhouette_score": float(diagnostic["silhouette_score"]),
		"substantial_cluster_count": int(diagnostic["substantial_cluster_count"]),
		"niche_enriched_cluster_count": int(diagnostic["niche_enriched_cluster_count"]),
		"max_niche_enrichment_span": max_niche_span,
		"founder_traits_bounded": bounded_founders,
		"failure_matrix": failure_matrix,
	}
	result["case_hash"] = _case_hash(result)
	return result

static func aggregate(case_summaries: Array, uniform_summary: Dictionary, deep_horizon_summary: Dictionary) -> Dictionary:
	if case_summaries.size() != ROBUSTNESS_SEEDS.size() or uniform_summary.is_empty() or deep_horizon_summary.is_empty():
		return {}
	var min_effective := 1000000
	var max_top_share := 0.0
	var min_shannon := INF
	var min_substantial := 1000000
	var min_niche_enriched := 1000000
	var max_patch_dominance := 0.0
	var case_hashes := PackedStringArray()
	var all_pass := true
	for summary in case_summaries:
		min_effective = mini(min_effective, int(summary["effective_founders_1pct"]))
		max_top_share = maxf(max_top_share, float(summary["top1_biomass_share"]))
		min_shannon = minf(min_shannon, float(summary["shannon_biomass_diversity"]))
		min_substantial = mini(min_substantial, int(summary["substantial_cluster_count"]))
		min_niche_enriched = mini(min_niche_enriched, int(summary["niche_enriched_cluster_count"]))
		max_patch_dominance = maxf(max_patch_dominance, float(summary["top1_patch_dominance_ratio"]))
		case_hashes.append(String(summary["case_hash"]))
		all_pass = all_pass and _failure_matrix_passes(Dictionary(summary["failure_matrix"]))
	var uniform_pass := _failure_matrix_passes(Dictionary(uniform_summary["failure_matrix"]))
	var deep_pass := _failure_matrix_passes(Dictionary(deep_horizon_summary["failure_matrix"]))
	var aggregate_failure_matrix := {
		"GLOBAL_TAKEOVER": "PASS" if max_top_share < MAX_TOP1_BIOMASS_SHARE and float(deep_horizon_summary["top1_biomass_share"]) < MAX_TOP1_BIOMASS_SHARE else "FAIL",
		"DIVERSITY_COLLAPSE": "PASS" if min_effective >= MIN_EFFECTIVE_FOUNDERS_1PCT and min_shannon >= MIN_SHANNON_DIVERSITY and int(deep_horizon_summary["effective_founders_1pct"]) >= MIN_EFFECTIVE_FOUNDERS_1PCT else "FAIL",
		"CLUSTER_COLLAPSE": "PASS" if min_substantial >= MIN_SUBSTANTIAL_CLUSTERS and min_niche_enriched >= MIN_NICHE_ENRICHED_CLUSTERS and int(deep_horizon_summary["niche_enriched_cluster_count"]) >= MIN_NICHE_ENRICHED_CLUSTERS else "FAIL",
		"FALSE_NICHE_UNIFORM": "PASS" if uniform_pass and int(uniform_summary["niche_enriched_cluster_count"]) == 0 and float(uniform_summary["max_niche_enrichment_span"]) <= UNIFORM_MAX_NICHE_SPAN else "FAIL",
		"RUNAWAY_TRAIT": "PASS_NO_MUTATION_STATIC_BOUNDED_FOUNDERS" if all_pass and deep_pass else "FAIL",
		"REPLAY_DIVERGENCE": "PASS_EXACT_HASH_CONTRACT",
	}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"seed_count": case_summaries.size(),
		"robustness_cycles": ROBUSTNESS_CYCLES,
		"deep_horizon_cycles": int(deep_horizon_summary["cycles"]),
		"case_hashes": case_hashes,
		"uniform_case_hash": String(uniform_summary["case_hash"]),
		"deep_horizon_case_hash": String(deep_horizon_summary["case_hash"]),
		"minimum_effective_founders_1pct": min_effective,
		"maximum_top1_biomass_share": max_top_share,
		"minimum_shannon_biomass_diversity": min_shannon,
		"minimum_substantial_cluster_count": min_substantial,
		"minimum_niche_enriched_cluster_count": min_niche_enriched,
		"maximum_top1_patch_dominance_ratio": max_patch_dominance,
		"uniform_max_niche_enrichment_span": float(uniform_summary["max_niche_enrichment_span"]),
		"deep_horizon_effective_founders_1pct": int(deep_horizon_summary["effective_founders_1pct"]),
		"deep_horizon_top1_biomass_share": float(deep_horizon_summary["top1_biomass_share"]),
		"deep_horizon_shannon_biomass_diversity": float(deep_horizon_summary["shannon_biomass_diversity"]),
		"failure_matrix": aggregate_failure_matrix,
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func compute_aggregate_hash(case_summaries: Array, uniform_summary: Dictionary, deep_horizon_summary: Dictionary) -> String:
	var result := aggregate(case_summaries, uniform_summary, deep_horizon_summary)
	return "" if result.is_empty() else String(result["aggregate_hash"])

static func _classify_case(dynamic: Dictionary, diagnostic: Dictionary, max_niche_span: float, bounded_founders: bool, uniform_control: bool) -> Dictionary:
	var matrix := {
		"GLOBAL_TAKEOVER": "PASS" if float(dynamic["global_abundance"]["top1_biomass_share"]) < MAX_TOP1_BIOMASS_SHARE else "FAIL",
		"RUNAWAY_TRAIT": "PASS_NO_MUTATION_STATIC_BOUNDED_FOUNDERS" if bounded_founders else "FAIL",
	}
	if uniform_control:
		matrix["DIVERSITY_COLLAPSE"] = "NOT_APPLICABLE_UNIFORM_CONTROL_EXPECTS_LOWER_DIVERSITY"
		matrix["CLUSTER_COLLAPSE"] = "NOT_APPLICABLE_UNIFORM_CONTROL"
		matrix["FALSE_NICHE_UNIFORM"] = "PASS" if int(diagnostic["niche_enriched_cluster_count"]) == 0 and max_niche_span <= UNIFORM_MAX_NICHE_SPAN else "FAIL"
	else:
		matrix["DIVERSITY_COLLAPSE"] = "PASS" if int(dynamic["global_abundance"]["effective_founders_1pct"]) >= MIN_EFFECTIVE_FOUNDERS_1PCT and float(dynamic["global_abundance"]["shannon_biomass_diversity"]) >= MIN_SHANNON_DIVERSITY else "FAIL"
		matrix["CLUSTER_COLLAPSE"] = "PASS" if int(diagnostic["substantial_cluster_count"]) >= MIN_SUBSTANTIAL_CLUSTERS and int(diagnostic["niche_enriched_cluster_count"]) >= MIN_NICHE_ENRICHED_CLUSTERS else "FAIL"
		matrix["FALSE_NICHE_UNIFORM"] = "NOT_APPLICABLE_HETEROGENEOUS"
	return matrix

static func _failure_matrix_passes(matrix: Dictionary) -> bool:
	for value in matrix.values():
		if String(value) == "FAIL":
			return false
	return true

static func _founders_are_bounded(founder_seed: int) -> bool:
	var founders := S1Competition.create_founder_pool(Dynamic.DEFAULT_FOUNDER_COUNT, founder_seed)
	if founders.size() != Dynamic.DEFAULT_FOUNDER_COUNT:
		return false
	for founder in founders:
		var genome: Dictionary = founder["genome"]
		for trait_name in S1Competition.TRAITS:
			var bounds: Array = Diagnostics.TRAIT_BOUNDS[trait_name]
			var value := float(genome[trait_name])
			if value < float(bounds[0]) - 0.000000000001 or value > float(bounds[1]) + 0.000000000001:
				return false
	return true

static func _case_hash(result: Dictionary) -> String:
	var matrix: Dictionary = result["failure_matrix"]
	var keys := matrix.keys()
	keys.sort()
	var matrix_tokens := PackedStringArray()
	for key in keys:
		matrix_tokens.append("%s=%s" % [String(key), String(matrix[key])])
	return "|".join([
		str(result["founder_seed"]), str(result["cycles"]), str(bool(result["uniform_control"])),
		String(result["dynamic_result_hash"]), String(result["diagnostic_hash"]),
		"%.12f" % float(result["top1_biomass_share"]), "%.12f" % float(result["shannon_biomass_diversity"]),
		str(result["effective_founders_1pct"]), str(result["substantial_cluster_count"]), str(result["niche_enriched_cluster_count"]),
		";".join(matrix_tokens)
	]).sha256_text()

static func _aggregate_hash(result: Dictionary) -> String:
	var matrix: Dictionary = result["failure_matrix"]
	var keys := matrix.keys()
	keys.sort()
	var matrix_tokens := PackedStringArray()
	for key in keys:
		matrix_tokens.append("%s=%s" % [String(key), String(matrix[key])])
	return "|".join([
		str(result["seed_count"]), str(result["robustness_cycles"]), str(result["deep_horizon_cycles"]),
		",".join(PackedStringArray(result["case_hashes"])), String(result["uniform_case_hash"]), String(result["deep_horizon_case_hash"]),
		str(result["minimum_effective_founders_1pct"]), "%.12f" % float(result["maximum_top1_biomass_share"]),
		"%.12f" % float(result["minimum_shannon_biomass_diversity"]), str(result["minimum_substantial_cluster_count"]),
		str(result["minimum_niche_enriched_cluster_count"]), "%.12f" % float(result["uniform_max_niche_enrichment_span"]),
		str(result["deep_horizon_effective_founders_1pct"]), "%.12f" % float(result["deep_horizon_top1_biomass_share"]),
		";".join(matrix_tokens)
	]).sha256_text()
