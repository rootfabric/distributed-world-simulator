extends RefCounted

const P2_4 = preload("res://scripts/research/ecology/plant_patch_colonization_experiment_v1.gd")
const DisturbanceRecovery = preload("res://scripts/research/ecology/plant_disturbance_recovery_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_5_disturbance_recovery_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO1-P2.5.1"
const ACCEPTED_P2_4_HASH := "78273550a6a5dcb3597aa7c176683ed6b58f7238c7e51418a27f72c52f3c6c97"
const SHALLOW := "lineage/p2-5-shallow-fast"
const DEEP := "lineage/p2-5-deep-banked"

static func run() -> Dictionary:
	var parent := P2_4.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_P2_4_HASH:
		return {}

	var environment := EnvironmentSample.create(0.0, 0.0, 17.0, 0.58, 0.88, 0.82, 0.04, 2505, "eco-evo1-p2-5-favourable")
	var shallow_genome := Genome.create("plant-genome/p2-5-shallow-fast", 3.0, 0.75, 0.30, 0.58, 0.30, 0.40, 80, 10.0, 5.0)
	var deep_genome := Genome.create("plant-genome/p2-5-deep-banked", 1.5, 0.45, 1.50, 0.58, 0.30, 0.55, 80, 10.0, 12.0)
	var shallow_traits := RecruitmentTraits.create("recruitment-traits/p2-5-shallow-fast", 0.20, 2.0)
	var deep_traits := RecruitmentTraits.create("recruitment-traits/p2-5-deep-banked", 0.75, 6.0)
	if environment.is_empty() or shallow_genome.is_empty() or deep_genome.is_empty() or shallow_traits.is_empty() or deep_traits.is_empty():
		return {}

	var strategies := {
		SHALLOW: {"genome": shallow_genome, "recruitment_traits": shallow_traits},
		DEEP: {"genome": deep_genome, "recruitment_traits": deep_traits},
	}
	var shallow_adult := DisturbanceRecovery.create_adult(SHALLOW, shallow_genome, 3.0, 0.08, float(shallow_genome["height_m"]), "p2-5-founder-shallow".sha256_text())
	var deep_adult := DisturbanceRecovery.create_adult(DEEP, deep_genome, 3.0, 0.08, float(deep_genome["height_m"]), "p2-5-founder-deep".sha256_text())
	var shallow_bank := DisturbanceRecovery.create_seed_bank(SHALLOW, shallow_genome, shallow_traits, environment, 100, 0.0, "p2-5-bank-shallow".sha256_text())
	var deep_bank := DisturbanceRecovery.create_seed_bank(DEEP, deep_genome, deep_traits, environment, 100, 0.0, "p2-5-bank-deep".sha256_text())
	if shallow_adult.is_empty() or deep_adult.is_empty() or shallow_bank.is_empty() or deep_bank.is_empty():
		return {}
	var initial_state := {"adults": [shallow_adult, deep_adult], "banks": [shallow_bank, deep_bank]}

	var mild_event := DisturbanceRecovery.create_event("p2-5/mild/year-1", 1, 0.35, 0.10)
	var severe_event := DisturbanceRecovery.create_event("p2-5/severe/year-1", 1, 0.85, 0.35)
	var repeat_event := DisturbanceRecovery.create_event("p2-5/repeated/year-6", 6, 0.75, 0.30)
	if mild_event.is_empty() or severe_event.is_empty() or repeat_event.is_empty():
		return {}

	var control := DisturbanceRecovery.simulate(initial_state, strategies, environment, 8, [])
	var mild := DisturbanceRecovery.simulate(initial_state, strategies, environment, 8, [mild_event])
	var severe := DisturbanceRecovery.simulate(initial_state, strategies, environment, 8, [severe_event])
	var repeated := DisturbanceRecovery.simulate(initial_state, strategies, environment, 8, [severe_event, repeat_event])
	if control.is_empty() or mild.is_empty() or severe.is_empty() or repeated.is_empty():
		return {}

	var mild_record: Dictionary = Array(mild["event_log"])[0]
	var severe_record: Dictionary = Array(severe["event_log"])[0]
	var repeated_second_record: Dictionary = Array(repeated["event_log"])[1]
	var severe_final: Dictionary = severe["final_summary"]
	var repeated_final: Dictionary = repeated["final_summary"]
	var mild_final: Dictionary = mild["final_summary"]
	var control_final: Dictionary = control["final_summary"]
	var severe_survival: Dictionary = severe_record["lineage_survival_fraction"]

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"p2_4_parent_hash": ACCEPTED_P2_4_HASH,
		"control": control,
		"mild": mild,
		"severe": severe,
		"repeated": repeated,
		"initial_biomass": 0.16,
		"mild_loss": float(mild_record["destroyed_adult_biomass_kg_m2"]),
		"severe_loss": float(severe_record["destroyed_adult_biomass_kg_m2"]),
		"mild_bank_killed": int(mild_record["killed_seed_bank_count"]),
		"severe_bank_killed": int(severe_record["killed_seed_bank_count"]),
		"shallow_survival": float(severe_survival.get(SHALLOW, 0.0)),
		"deep_survival": float(severe_survival.get(DEEP, 0.0)),
		"severe_post_biomass": float(severe_record["adult_biomass_after_kg_m2"]),
		"severe_final_biomass": float(severe_final["total_biomass_kg_m2"]),
		"mild_final_biomass": float(mild_final["total_biomass_kg_m2"]),
		"control_final_biomass": float(control_final["total_biomass_kg_m2"]),
		"repeated_final_biomass": float(repeated_final["total_biomass_kg_m2"]),
		"severe_recovery_gain": float(severe_final["total_biomass_kg_m2"]) - float(severe_record["adult_biomass_after_kg_m2"]),
		"severe_reactivated": int(severe["cumulative_reactivated_seed_count"]),
		"repeated_reactivated": int(repeated["cumulative_reactivated_seed_count"]),
		"severe_final_deep_share": float(Dictionary(severe_final["lineage_biomass_share"]).get(DEEP, 0.0)),
		"repeated_second_loss": float(repeated_second_record["destroyed_adult_biomass_kg_m2"]),
		"all_event_ledgers_conserve": _all_event_ledgers_conserve([mild, severe, repeated]),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _all_event_ledgers_conserve(runs: Array) -> bool:
	for run_value in runs:
		var run: Dictionary = run_value
		for record_value in Array(run["event_log"]):
			var record: Dictionary = record_value
			if not bool(record.get("adult_conservation_ok", false)) or not bool(record.get("seed_bank_conservation_ok", false)):
				return false
	return true

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("p2_4_parent_hash", "")),
		String(Dictionary(result.get("control", {})).get("result_hash", "")),
		String(Dictionary(result.get("mild", {})).get("result_hash", "")),
		String(Dictionary(result.get("severe", {})).get("result_hash", "")),
		String(Dictionary(result.get("repeated", {})).get("result_hash", "")),
	])
	for field_name in ["mild_loss", "severe_loss", "shallow_survival", "deep_survival", "severe_post_biomass", "severe_final_biomass", "mild_final_biomass", "control_final_biomass", "repeated_final_biomass", "severe_recovery_gain", "severe_final_deep_share", "repeated_second_loss"]:
		tokens.append("%.12f" % float(result.get(field_name, 0.0)))
	for field_name in ["mild_bank_killed", "severe_bank_killed", "severe_reactivated", "repeated_reactivated"]:
		tokens.append(str(int(result.get(field_name, 0))))
	tokens.append(str(bool(result.get("all_event_ledgers_conserve", false))))
	return "\n".join(tokens).sha256_text()
