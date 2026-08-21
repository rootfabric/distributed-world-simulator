extends RefCounted

const Dynamic = preload("res://scripts/research/ecology/plant_dynamic_abundance_competition_v1.gd")
const S1Competition = preload("res://scripts/research/ecology/plant_strategy_competition_baseline_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1c_niche_cluster_diagnostics.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1C-S3.1"
const DEFAULT_CLUSTER_COUNT := 3
const DEFAULT_EFFECTIVE_SHARE := 0.01
const SUBSTANTIAL_CLUSTER_SHARE := 0.10
const NICHE_ENRICHMENT_SPAN := 0.30
const THIRD_FOUNDER_SEED := 1138703
const DEFAULT_SEEDS: Array[int] = [S1Competition.DEFAULT_FOUNDER_SEED, S1Competition.ALT_FOUNDER_SEED, THIRD_FOUNDER_SEED]
const REGION_NAMES: Array[String] = ["DRY", "WET", "SHADED", "SUNLIT"]
const TRAIT_BOUNDS := {
	"height_m": [0.55, 2.65],
	"growth_rate": [0.30, 0.95],
	"root_depth_m": [0.20, 1.60],
	"water_preference": [0.15, 0.90],
	"water_tolerance_width": [0.08, 0.60],
	"shade_tolerance": [0.05, 0.90],
	"seed_count": [24.0, 160.0],
	"lifespan_years": [1.5, 9.0],
}

static func run_seed(founder_seed: int, uniform_control: bool = false) -> Dictionary:
	var dynamic_result := Dynamic.run(
		Dynamic.DEFAULT_GRID_SIZE,
		Dynamic.DEFAULT_FOUNDER_COUNT,
		Dynamic.DEFAULT_CYCLES,
		Dynamic.DEFAULT_SEASONS_PER_CYCLE,
		founder_seed,
		uniform_control
	)
	if dynamic_result.is_empty():
		return {}
	return diagnose(dynamic_result, founder_seed, DEFAULT_CLUSTER_COUNT, DEFAULT_EFFECTIVE_SHARE)

static func run() -> Dictionary:
	var runs: Array = []
	for seed in DEFAULT_SEEDS:
		var diagnostics := run_seed(seed, false)
		if diagnostics.is_empty():
			return {}
		runs.append(diagnostics)
	var uniform := run_seed(S1Competition.DEFAULT_FOUNDER_SEED, true)
	if uniform.is_empty():
		return {}
	var aggregate := _aggregate(runs, uniform)
	if aggregate.is_empty():
		return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"cluster_count": DEFAULT_CLUSTER_COUNT,
		"effective_share_threshold": DEFAULT_EFFECTIVE_SHARE,
		"substantial_cluster_share_threshold": SUBSTANTIAL_CLUSTER_SHARE,
		"niche_enrichment_span_threshold": NICHE_ENRICHMENT_SPAN,
		"seeds": DEFAULT_SEEDS.duplicate(),
		"runs": runs,
		"uniform_control": uniform,
		"aggregate": aggregate,
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func diagnose(dynamic_result: Dictionary, founder_seed: int, cluster_count: int, effective_share: float) -> Dictionary:
	if dynamic_result.is_empty() or cluster_count < 2 or effective_share <= 0.0:
		return {}
	var founders := S1Competition.create_founder_pool(int(dynamic_result.get("founder_count", 0)), founder_seed)
	if founders.size() != int(dynamic_result.get("founder_count", 0)):
		return {}
	var founder_by_index := {}
	for founder in founders:
		founder_by_index[int(founder["founder_index"])] = founder
	var share_by_index := {}
	for entry in Array(dynamic_result["global_abundance"]["founders"]):
		share_by_index[int(entry["founder_index"])] = float(entry["share"])
	var effective_indices: Array[int] = []
	for founder in founders:
		var fi := int(founder["founder_index"])
		if float(share_by_index.get(fi, 0.0)) >= effective_share:
			effective_indices.append(fi)
	effective_indices.sort()
	if effective_indices.size() < cluster_count:
		return {}
	var vectors: Array = []
	for fi in effective_indices:
		vectors.append(_trait_vector(founder_by_index[fi]["genome"]))
	var clustering := _cluster(vectors, cluster_count)
	if clustering.is_empty():
		return {}
	var assignments: Array[int] = clustering["assignments"]
	var centers: Array = clustering["centers"]
	var silhouette := _silhouette(vectors, assignments, cluster_count)
	var clusters: Array = []
	var substantial_count := 0
	var niche_enriched_count := 0
	for cluster_index in range(cluster_count):
		var members: Array[int] = []
		var global_share := 0.0
		for position in range(effective_indices.size()):
			if assignments[position] == cluster_index:
				var fi := effective_indices[position]
				members.append(fi)
				global_share += float(share_by_index.get(fi, 0.0))
		members.sort()
		if members.is_empty():
			return {}
		var regional_share := {}
		var enrichment := {}
		var enrichment_min := INF
		var enrichment_max := -INF
		var dominant_region := ""
		var dominant_value := -INF
		for region_name in REGION_NAMES:
			var region_founder_share := {}
			for entry in Array(dynamic_result["regional_abundance"][region_name]["founders"]):
				region_founder_share[int(entry["founder_index"])] = float(entry["share"])
			var region_share := 0.0
			for fi in members:
				region_share += float(region_founder_share.get(fi, 0.0))
			var ratio := 0.0 if global_share <= 0.0 else region_share / global_share
			regional_share[region_name] = region_share
			enrichment[region_name] = ratio
			enrichment_min = minf(enrichment_min, ratio)
			enrichment_max = maxf(enrichment_max, ratio)
			if ratio > dominant_value:
				dominant_value = ratio
				dominant_region = region_name
		var niche_span := enrichment_max - enrichment_min
		if global_share >= SUBSTANTIAL_CLUSTER_SHARE:
			substantial_count += 1
		if niche_span >= NICHE_ENRICHMENT_SPAN:
			niche_enriched_count += 1
		clusters.append({
			"cluster_index": cluster_index,
			"members": members,
			"member_count": members.size(),
			"global_biomass_share": global_share,
			"normalized_trait_centroid": centers[cluster_index],
			"raw_trait_centroid": _raw_centroid(members, founder_by_index),
			"regional_biomass_share": regional_share,
			"regional_enrichment": enrichment,
			"niche_enrichment_span": niche_span,
			"dominant_enrichment_region": dominant_region,
		})
	var assignment_tokens := PackedStringArray()
	for position in range(effective_indices.size()):
		assignment_tokens.append("%d=%d" % [effective_indices[position], assignments[position]])
	var diagnostic := {
		"founder_seed": founder_seed,
		"dynamic_result_hash": String(dynamic_result["result_hash"]),
		"founder_pool_hash": String(dynamic_result["founder_pool_hash"]),
		"uniform_control": bool(dynamic_result["uniform_control"]),
		"effective_founders": effective_indices,
		"effective_founder_count": effective_indices.size(),
		"top1_biomass_share": float(dynamic_result["global_abundance"]["top1_biomass_share"]),
		"shannon_biomass_diversity": float(dynamic_result["global_abundance"]["shannon_biomass_diversity"]),
		"cluster_count": cluster_count,
		"silhouette_score": silhouette,
		"substantial_cluster_count": substantial_count,
		"niche_enriched_cluster_count": niche_enriched_count,
		"cluster_assignment_hash": "\n".join(assignment_tokens).sha256_text(),
		"clusters": clusters,
	}
	diagnostic["diagnostic_hash"] = _diagnostic_hash(diagnostic)
	return diagnostic

static func _cluster(vectors: Array, cluster_count: int) -> Dictionary:
	if vectors.size() < cluster_count:
		return {}
	var dimension := Array(vectors[0]).size()
	var mean: Array[float] = []
	mean.resize(dimension)
	for d in range(dimension): mean[d] = 0.0
	for vector in vectors:
		for d in range(dimension): mean[d] += float(vector[d])
	for d in range(dimension): mean[d] /= float(vectors.size())
	var centers: Array = []
	var chosen: Array[int] = []
	var first := 0
	var first_distance := -1.0
	for i in range(vectors.size()):
		var distance := _distance_squared(vectors[i], mean)
		if distance > first_distance:
			first_distance = distance
			first = i
	centers.append(Array(vectors[first]).duplicate())
	chosen.append(first)
	while centers.size() < cluster_count:
		var next_index := -1
		var next_distance := -1.0
		for i in range(vectors.size()):
			if i in chosen:
				continue
			var nearest := INF
			for center in centers:
				nearest = minf(nearest, _distance_squared(vectors[i], center))
			if nearest > next_distance:
				next_distance = nearest
				next_index = i
		if next_index < 0:
			return {}
		centers.append(Array(vectors[next_index]).duplicate())
		chosen.append(next_index)
	var assignments: Array[int] = []
	assignments.resize(vectors.size())
	for i in range(assignments.size()): assignments[i] = -1
	for _iteration in range(64):
		var changed := false
		for i in range(vectors.size()):
			var best_cluster := 0
			var best_distance := INF
			for cluster_index in range(cluster_count):
				var distance := _distance_squared(vectors[i], centers[cluster_index])
				if distance < best_distance - 0.000000000001:
					best_distance = distance
					best_cluster = cluster_index
			if assignments[i] != best_cluster:
				assignments[i] = best_cluster
				changed = true
		var new_centers: Array = []
		for cluster_index in range(cluster_count):
			var center: Array[float] = []
			center.resize(dimension)
			for d in range(dimension): center[d] = 0.0
			var count := 0
			for i in range(vectors.size()):
				if assignments[i] != cluster_index:
					continue
				count += 1
				for d in range(dimension): center[d] += float(vectors[i][d])
			if count == 0:
				return {}
			for d in range(dimension): center[d] /= float(count)
			new_centers.append(center)
		centers = new_centers
		if not changed:
			break
	return {"assignments": assignments, "centers": centers}

static func _silhouette(vectors: Array, assignments: Array[int], cluster_count: int) -> float:
	var total := 0.0
	for i in range(vectors.size()):
		var same_total := 0.0
		var same_count := 0
		for j in range(vectors.size()):
			if i == j or assignments[j] != assignments[i]:
				continue
			same_total += sqrt(_distance_squared(vectors[i], vectors[j]))
			same_count += 1
		var a := 0.0 if same_count == 0 else same_total / float(same_count)
		var b := INF
		for cluster_index in range(cluster_count):
			if cluster_index == assignments[i]:
				continue
			var other_total := 0.0
			var other_count := 0
			for j in range(vectors.size()):
				if assignments[j] != cluster_index:
					continue
				other_total += sqrt(_distance_squared(vectors[i], vectors[j]))
				other_count += 1
			if other_count > 0:
				b = minf(b, other_total / float(other_count))
		var denominator := maxf(a, b)
		if is_finite(denominator) and denominator > 0.0:
			total += (b - a) / denominator
	return total / float(vectors.size())

static func _trait_vector(genome: Dictionary) -> Array:
	var vector: Array[float] = []
	for trait_name in S1Competition.TRAITS:
		var bounds: Array = TRAIT_BOUNDS[trait_name]
		var lo := float(bounds[0])
		var hi := float(bounds[1])
		vector.append((float(genome[trait_name]) - lo) / (hi - lo))
	return vector

static func _raw_centroid(members: Array[int], founder_by_index: Dictionary) -> Dictionary:
	var result := {}
	for trait_name in S1Competition.TRAITS:
		var total := 0.0
		for fi in members:
			total += float(founder_by_index[fi]["genome"][trait_name])
		result[trait_name] = total / float(members.size())
	return result

static func _distance_squared(a: Array, b: Array) -> float:
	var total := 0.0
	for i in range(a.size()):
		var delta := float(a[i]) - float(b[i])
		total += delta * delta
	return total

static func _aggregate(runs: Array, uniform: Dictionary) -> Dictionary:
	if runs.is_empty() or uniform.is_empty():
		return {}
	var min_effective := 1000000
	var max_top_share := 0.0
	var min_shannon := INF
	var min_silhouette := INF
	var min_substantial := 1000000
	var min_niche_enriched := 1000000
	var dynamic_hashes := PackedStringArray()
	for diagnostic in runs:
		min_effective = mini(min_effective, int(diagnostic["effective_founder_count"]))
		max_top_share = maxf(max_top_share, float(diagnostic["top1_biomass_share"]))
		min_shannon = minf(min_shannon, float(diagnostic["shannon_biomass_diversity"]))
		min_silhouette = minf(min_silhouette, float(diagnostic["silhouette_score"]))
		min_substantial = mini(min_substantial, int(diagnostic["substantial_cluster_count"]))
		min_niche_enriched = mini(min_niche_enriched, int(diagnostic["niche_enriched_cluster_count"]))
		dynamic_hashes.append(String(diagnostic["dynamic_result_hash"]))
	var uniform_max_niche_span := 0.0
	for cluster in Array(uniform["clusters"]):
		uniform_max_niche_span = maxf(uniform_max_niche_span, float(cluster["niche_enrichment_span"]))
	return {
		"seed_count": runs.size(),
		"dynamic_result_hashes": dynamic_hashes,
		"minimum_effective_founders_1pct": min_effective,
		"maximum_top1_biomass_share": max_top_share,
		"minimum_shannon_biomass_diversity": min_shannon,
		"minimum_silhouette_score": min_silhouette,
		"minimum_substantial_cluster_count": min_substantial,
		"minimum_niche_enriched_cluster_count": min_niche_enriched,
		"uniform_max_niche_enrichment_span": uniform_max_niche_span,
		"uniform_dynamic_result_hash": String(uniform["dynamic_result_hash"]),
	}

static func _diagnostic_hash(diagnostic: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		str(int(diagnostic["founder_seed"])),
		String(diagnostic["dynamic_result_hash"]),
		String(diagnostic["founder_pool_hash"]),
		str(bool(diagnostic["uniform_control"])),
		String(diagnostic["cluster_assignment_hash"]),
		_format_float(float(diagnostic["silhouette_score"])),
	])
	for cluster in Array(diagnostic["clusters"]):
		tokens.append("C%d|%s|%s|%s" % [
			int(cluster["cluster_index"]),
			str(cluster["members"]),
			_format_float(float(cluster["global_biomass_share"])),
			_format_float(float(cluster["niche_enrichment_span"])),
		])
	return "\n".join(tokens).sha256_text()

static func compute_aggregate_hash(run_diagnostics: Array, uniform_diagnostic: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		str(DEFAULT_CLUSTER_COUNT),
		_format_float(DEFAULT_EFFECTIVE_SHARE),
	])
	for diagnostic in run_diagnostics:
		tokens.append("R|%d|%s" % [int(diagnostic["founder_seed"]), String(diagnostic["diagnostic_hash"])])
	tokens.append("U|%s" % String(uniform_diagnostic["diagnostic_hash"]))
	return "\n".join(tokens).sha256_text()

static func _aggregate_hash(result: Dictionary) -> String:
	return compute_aggregate_hash(Array(result["runs"]), Dictionary(result["uniform_control"]))

static func _format_float(value: float) -> String:
	return "%.9f" % value
