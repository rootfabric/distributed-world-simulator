extends RefCounted

const P2_6 = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_experiment_v1.gd")
const Diagnostics = preload("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_7_lineage_divergence_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO1-P2.7.1"
const ACCEPTED_P2_6_HASH := "3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c"
const ROOT := "lineage/p2-7/root"
const SPLIT_YEAR := 5
const END_YEAR := 30

static func run() -> Dictionary:
	var parent := P2_6.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_P2_6_HASH:
		return {}

	var source_environment := EnvironmentSample.create(0.0, 0.0, 17.0, 0.58, 0.88, 0.82, 0.02, 2707, "eco-evo1-p2-7-source")
	var far_environment := EnvironmentSample.create(80.0, 0.0, 22.0, 0.30, 0.95, 0.60, 0.02, 2708, "eco-evo1-p2-7-far")
	if source_environment.is_empty() or far_environment.is_empty():
		return {}

	var source_genome := Genome.create("plant-genome/p2-7-source", 1.60, 0.55, 1.20, 0.58, 0.30, 0.55, 160, 5.0, 30.0)
	var far_genome := Genome.create("plant-genome/p2-7-far", 3.20, 0.72, 0.35, 0.35, 0.45, 0.25, 220, 25.0, 16.0)
	var similar_genome := Genome.create("plant-genome/p2-7-similar", 1.65, 0.56, 1.18, 0.57, 0.31, 0.54, 164, 5.2, 29.0)
	var source_traits := RecruitmentTraits.create("recruitment-traits/p2-7-source", 0.65, 5.0)
	var far_traits := RecruitmentTraits.create("recruitment-traits/p2-7-far", 0.20, 1.5)
	var similar_traits := RecruitmentTraits.create("recruitment-traits/p2-7-similar", 0.63, 4.8)
	if source_genome.is_empty() or far_genome.is_empty() or similar_genome.is_empty() or source_traits.is_empty() or far_traits.is_empty() or similar_traits.is_empty():
		return {}

	var source_geo := _constant_geography("patch/source")
	var far_geo := _constant_geography("patch/far")
	var source_ecology := _constant_ecology(source_environment)
	var far_ecology := _constant_ecology(far_environment)

	var source_observation := Diagnostics.create_observation(
		"lineage/p2-7/source-branch",
		[ROOT, "lineage/p2-7/source-branch"],
		SPLIT_YEAR,
		source_genome,
		source_traits,
		source_geo,
		source_ecology
	)
	var far_observation := Diagnostics.create_observation(
		"lineage/p2-7/far-branch",
		[ROOT, "lineage/p2-7/far-branch"],
		SPLIT_YEAR,
		far_genome,
		far_traits,
		far_geo,
		far_ecology
	)
	var similar_observation := Diagnostics.create_observation(
		"lineage/p2-7/similar-isolated",
		[ROOT, "lineage/p2-7/similar-isolated"],
		SPLIT_YEAR,
		similar_genome,
		similar_traits,
		far_geo,
		source_ecology
	)
	var recent_left := Diagnostics.create_observation(
		"lineage/p2-7/recent-left",
		["lineage/p2-7/recent-root", "lineage/p2-7/recent-left"],
		27,
		source_genome,
		source_traits,
		source_geo,
		source_ecology
	)
	var recent_right := Diagnostics.create_observation(
		"lineage/p2-7/recent-right",
		["lineage/p2-7/recent-root", "lineage/p2-7/recent-right"],
		27,
		far_genome,
		far_traits,
		far_geo,
		far_ecology
	)
	if source_observation.is_empty() or far_observation.is_empty() or similar_observation.is_empty() or recent_left.is_empty() or recent_right.is_empty():
		return {}

	var isolated_diverged := Diagnostics.diagnose_pair(source_observation, far_observation, [])
	var connected_diverged := Diagnostics.diagnose_pair(source_observation, far_observation, _years(SPLIT_YEAR + 1, END_YEAR))
	var isolated_similar := Diagnostics.diagnose_pair(source_observation, similar_observation, [])
	var recent_diverged := Diagnostics.diagnose_pair(recent_left, recent_right, [])
	if isolated_diverged.is_empty() or connected_diverged.is_empty() or isolated_similar.is_empty() or recent_diverged.is_empty():
		return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"p2_6_parent_hash": ACCEPTED_P2_6_HASH,
		"isolated_diverged": isolated_diverged,
		"connected_diverged": connected_diverged,
		"isolated_similar": isolated_similar,
		"recent_diverged": recent_diverged,
		"candidate": bool(isolated_diverged["speciation_candidate"]),
		"connected_candidate": bool(connected_diverged["speciation_candidate"]),
		"similar_candidate": bool(isolated_similar["speciation_candidate"]),
		"recent_candidate": bool(recent_diverged["speciation_candidate"]),
		"candidate_split_age": int(isolated_diverged["split_age_years"]),
		"candidate_isolation": float(isolated_diverged["isolation_fraction"]),
		"candidate_connection": float(isolated_diverged["connection_fraction"]),
		"candidate_genome_distance": float(isolated_diverged["genome_distance"]),
		"candidate_recruitment_distance": float(isolated_diverged["recruitment_trait_distance"]),
		"candidate_ecology_distance": float(isolated_diverged["ecological_history_distance"]),
		"connected_connection": float(connected_diverged["connection_fraction"]),
		"similar_genome_distance": float(isolated_similar["genome_distance"]),
		"similar_ecology_distance": float(isolated_similar["ecological_history_distance"]),
		"recent_split_age": int(recent_diverged["split_age_years"]),
		"no_canonical_species_declaration": not bool(isolated_diverged["canonical_species_declared"]),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _constant_geography(patch_id: String) -> Array:
	var result: Array = []
	for year in range(1, END_YEAR + 1):
		result.append({"year": year, "patch_ids": [patch_id]})
	return result

static func _constant_ecology(environment: Dictionary) -> Array:
	var result: Array = []
	for year in range(1, END_YEAR + 1):
		result.append({"year": year, "environment": environment})
	return result

static func _years(first_year: int, last_year: int) -> Array:
	var result: Array = []
	for year in range(first_year, last_year + 1):
		result.append(year)
	return result

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("p2_6_parent_hash", "")),
		String(Dictionary(result.get("isolated_diverged", {})).get("result_hash", "")),
		String(Dictionary(result.get("connected_diverged", {})).get("result_hash", "")),
		String(Dictionary(result.get("isolated_similar", {})).get("result_hash", "")),
		String(Dictionary(result.get("recent_diverged", {})).get("result_hash", "")),
		str(bool(result.get("candidate", false))),
		str(bool(result.get("connected_candidate", true))),
		str(bool(result.get("similar_candidate", true))),
		str(bool(result.get("recent_candidate", true))),
		str(int(result.get("candidate_split_age", 0))),
		"%.12f" % float(result.get("candidate_isolation", 0.0)),
		"%.12f" % float(result.get("candidate_connection", 0.0)),
		"%.12f" % float(result.get("candidate_genome_distance", 0.0)),
		"%.12f" % float(result.get("candidate_recruitment_distance", 0.0)),
		"%.12f" % float(result.get("candidate_ecology_distance", 0.0)),
		"%.12f" % float(result.get("connected_connection", 0.0)),
		"%.12f" % float(result.get("similar_genome_distance", 0.0)),
		"%.12f" % float(result.get("similar_ecology_distance", 0.0)),
		str(int(result.get("recent_split_age", 0))),
		str(bool(result.get("no_canonical_species_declaration", false))),
	])
	return "\n".join(tokens).sha256_text()
