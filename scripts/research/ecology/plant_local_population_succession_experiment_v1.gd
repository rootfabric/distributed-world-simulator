extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const P2_2 = preload("res://scripts/research/ecology/plant_establishment_seed_bank_experiment_v1.gd")
const PopulationEngine = preload("res://scripts/research/ecology/plant_local_population_succession_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_3_local_population_succession_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO1-P2.3.1"
const ACCEPTED_P2_2_HASH := "633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86"
const EARLY := "lineage/p2-3-early"
const BANKED := "lineage/p2-3-banked"

static func run() -> Dictionary:
	var parent := P2_2.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_P2_2_HASH:
		return {}

	var early_genome := Genome.create("plant-genome/p2-3-early", 0.80, 0.90, 0.60, 0.58, 0.30, 0.12, 80, 8.0, 2.5)
	var banked_genome := Genome.create("plant-genome/p2-3-banked", 1.60, 0.45, 1.00, 0.58, 0.35, 0.82, 80, 8.0, 12.0)
	var early_traits := RecruitmentTraits.create("recruitment-traits/p2-3-early", 0.10, 1.5)
	var banked_traits := RecruitmentTraits.create("recruitment-traits/p2-3-banked", 0.85, 5.0)
	if early_genome.is_empty() or banked_genome.is_empty() or early_traits.is_empty() or banked_traits.is_empty():
		return {}

	var strategies := [
		{"lineage_id": EARLY, "genome": early_genome, "recruitment_traits": early_traits, "source_position": Vector2(-1.0, 0.0)},
		{"lineage_id": BANKED, "genome": banked_genome, "recruitment_traits": banked_traits, "source_position": Vector2(1.0, 0.0)},
	]
	var open_environment := _environment("open", 0.58, 0.95, 0.80, 0.04, 17.0)
	var shade_environment := _environment("shade", 0.58, 0.10, 0.80, 0.04, 17.0)
	if open_environment.is_empty() or shade_environment.is_empty():
		return {}

	var open_schedule := [{"year_start": 0, "environment": open_environment}]
	var shift_schedule := [
		{"year_start": 0, "environment": open_environment},
		{"year_start": 4, "environment": shade_environment},
	]
	var shift := PopulationEngine.simulate(strategies, shift_schedule, 12, true)
	var open_control := PopulationEngine.simulate(strategies, open_schedule, 12, true)
	if shift.is_empty() or open_control.is_empty():
		return {}

	var matched_base := Genome.create("plant-genome/p2-3-matched-short", 1.10, 0.55, 0.80, 0.58, 0.32, 0.35, 80, 8.0, 2.0)
	var matched_long := Genome.create("plant-genome/p2-3-matched-long", 1.10, 0.55, 0.80, 0.58, 0.32, 0.35, 80, 8.0, 12.0)
	var matched_traits := RecruitmentTraits.create("recruitment-traits/p2-3-matched", 0.45, 3.0)
	if matched_base.is_empty() or matched_long.is_empty() or matched_traits.is_empty():
		return {}
	var short_run := PopulationEngine.simulate([{"lineage_id": "lineage/p2-3-matched", "genome": matched_base, "recruitment_traits": matched_traits, "source_position": Vector2.ZERO}], open_schedule, 8, false)
	var long_run := PopulationEngine.simulate([{"lineage_id": "lineage/p2-3-matched", "genome": matched_long, "recruitment_traits": matched_traits, "source_position": Vector2.ZERO}], open_schedule, 8, false)
	if short_run.is_empty() or long_run.is_empty():
		return {}

	var shift_initial: Dictionary = shift["history"][0]
	var shift_pre_change: Dictionary = shift["history"][3]
	var shift_final: Dictionary = shift["final_summary"]
	var open_final: Dictionary = open_control["final_summary"]
	var initial_early_share := _share(shift_initial, EARLY)
	var initial_banked_share := _share(shift_initial, BANKED)
	var pre_change_banked_share := _share(shift_pre_change, BANKED)
	var final_banked_share := _share(shift_final, BANKED)
	var open_final_banked_share := _share(open_final, BANKED)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"p2_2_parent_hash": ACCEPTED_P2_2_HASH,
		"shift": shift,
		"open_control": open_control,
		"short_life_control": short_run,
		"long_life_control": long_run,
		"initial_early_share": initial_early_share,
		"initial_banked_share": initial_banked_share,
		"pre_change_banked_share": pre_change_banked_share,
		"final_banked_share": final_banked_share,
		"open_final_banked_share": open_final_banked_share,
		"shade_shift_delta": final_banked_share - open_final_banked_share,
		"banked_gain_after_shift": final_banked_share - pre_change_banked_share,
		"top_lineage_changed": String(shift_initial["top_lineage"]) != String(shift_final["top_lineage"]),
		"shift_reactivated": int(shift["cumulative_bank_reactivated_seed_count"]),
		"shift_reproduction_events": int(shift["reproduction_event_count"]),
		"shift_emitted": int(shift["cumulative_emitted_seed_count"]),
		"short_life_mortality": float(short_run["cumulative_adult_mortality_kg_m2"]),
		"long_life_mortality": float(long_run["cumulative_adult_mortality_kg_m2"]),
		"shift_max_biomass": float(shift["max_total_biomass_kg_m2"]),
		"shift_max_adult_cohorts": int(shift["max_adult_cohort_count"]),
		"shift_max_bank_cohorts": int(shift["max_seed_bank_cohort_count"]),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _environment(suffix: String, moisture: float, sunlight: float, nutrients: float, flood: float, temperature: float) -> Dictionary:
	return EnvironmentSample.create(0.0, 0.0, temperature, moisture, sunlight, nutrients, flood, 2301, "eco-evo1-p2-3-" + suffix)

static func _share(summary: Dictionary, lineage: String) -> float:
	return float(Dictionary(summary.get("lineage_biomass_share", {})).get(lineage, 0.0))

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("p2_2_parent_hash", "")),
		String(Dictionary(result.get("shift", {})).get("result_hash", "")),
		String(Dictionary(result.get("open_control", {})).get("result_hash", "")),
		String(Dictionary(result.get("short_life_control", {})).get("result_hash", "")),
		String(Dictionary(result.get("long_life_control", {})).get("result_hash", "")),
	])
	for field_name in ["initial_early_share", "initial_banked_share", "pre_change_banked_share", "final_banked_share", "open_final_banked_share", "shade_shift_delta", "banked_gain_after_shift", "short_life_mortality", "long_life_mortality", "shift_max_biomass"]:
		tokens.append("%.12f" % float(result.get(field_name, 0.0)))
	for field_name in ["shift_reactivated", "shift_reproduction_events", "shift_emitted", "shift_max_adult_cohorts", "shift_max_bank_cohorts"]:
		tokens.append(str(int(result.get(field_name, 0))))
	tokens.append(str(bool(result.get("top_lineage_changed", false))))
	return "\n".join(tokens).sha256_text()
