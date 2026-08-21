extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_disturbance_recovery_experiment_v1.gd")
const PatchBaseline = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")

var assertions := 0

func _init() -> void:
	var first := Experiment.run()
	var second := Experiment.run()
	_check(not first.is_empty(), "experiment result exists")
	_check(not second.is_empty(), "repeat result exists")
	if first.is_empty() or second.is_empty():
		_finish(false)
		return
	_check(String(first.get("aggregate_hash", "")) == String(second.get("aggregate_hash", "")), "same-process aggregate deterministic")
	_check(String(first.get("p2_4_parent_hash", "")) == Experiment.ACCEPTED_P2_4_HASH, "accepted P2.4 parent exact")
	_check(String(first.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")
	_check(bool(first["all_event_ledgers_conserve"]), "all disturbance ledgers conserve")

	_check(float(first["severe_loss"]) > float(first["mild_loss"]), "severe mechanical event destroys more adult biomass than mild")
	_check(int(first["severe_bank_killed"]) > int(first["mild_bank_killed"]), "severe event kills more seed-bank propagules than mild")
	_check(float(first["deep_survival"]) > float(first["shallow_survival"]), "accepted CAL1-D anchoring gives deep-root lineage higher mechanical survival")
	_check(float(first["severe_post_biomass"]) < float(first["initial_biomass"]), "severe event creates immediate biomass loss")
	_check(float(first["severe_recovery_gain"]) > 0.0, "single severe event has positive multi-year recovery")
	_check(float(first["severe_final_biomass"]) > float(first["severe_post_biomass"]), "final severe biomass exceeds immediate post-event biomass")
	_check(int(first["severe_reactivated"]) > 0, "surviving seed-bank cohorts reactivate during recovery")
	_check(float(first["repeated_second_loss"]) > 0.0, "second disturbance causes additional adult damage")
	_check(float(first["repeated_final_biomass"]) < float(first["severe_final_biomass"]), "repeated disturbance suppresses recovery relative to single severe event")
	_check(float(first["mild_final_biomass"]) > 0.0 and float(first["severe_final_biomass"]) > 0.0, "disturbed communities persist through recovery window")

	for run_name in ["control", "mild", "severe", "repeated"]:
		var run: Dictionary = first[run_name]
		_check(String(run.get("result_hash", "")).length() == 64, run_name + " result hash shape")
		_check(int(run.get("cumulative_reactivated_seed_count", -1)) >= 0, run_name + " reactivation count nonnegative")
		for summary_value in Array(run.get("history", [])):
			var summary: Dictionary = summary_value
			_check(String(summary.get("summary_hash", "")).length() == 64, run_name + " history hash shape")
			_check(float(summary.get("total_biomass_kg_m2", -1.0)) >= 0.0, run_name + " biomass nonnegative")
			_check(float(summary.get("total_biomass_kg_m2", 999.0)) <= PatchBaseline.MAX_BIOMASS_KG_M2 + 0.000000001, run_name + " capacity bounded")
			_check(int(summary.get("seed_bank_count", -1)) >= 0, run_name + " seed bank nonnegative")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_disturbance_recovery_v1.gd")
	_check(source.find("biome") == -1, "no biome lookup in disturbance kernel")
	_check(source.find("species_table") == -1, "no species placement table")
	_check(source.find("biogeography") == -1, "no P2.6 biogeography implementation")
	_check(source.find("PopulationTurnover.STRESS_MORTALITY_RATE") >= 0, "P2.3 stress coefficient reused by reference")
	_check(source.find("PopulationTurnover.VEGETATIVE_GROWTH_RATE") >= 0, "P2.3 growth coefficient reused by reference")

	print("ECO.EVO1-P2.5 mild_loss=%.12f severe_loss=%.12f shallow_survival=%.12f deep_survival=%.12f" % [float(first["mild_loss"]), float(first["severe_loss"]), float(first["shallow_survival"]), float(first["deep_survival"])])
	print("ECO.EVO1-P2.5 mild_bank_killed=%d severe_bank_killed=%d severe_post=%.12f severe_final=%.12f recovery_gain=%.12f" % [int(first["mild_bank_killed"]), int(first["severe_bank_killed"]), float(first["severe_post_biomass"]), float(first["severe_final_biomass"]), float(first["severe_recovery_gain"])])
	print("ECO.EVO1-P2.5 reactivated=%d repeated_reactivated=%d repeated_final=%.12f single_severe_final=%.12f second_loss=%.12f" % [int(first["severe_reactivated"]), int(first["repeated_reactivated"]), float(first["repeated_final_biomass"]), float(first["severe_final_biomass"]), float(first["repeated_second_loss"])])
	print("ECO.EVO1-P2.5 Disturbance + Recovery: PASS (%d assertions) aggregate_hash=%s p2_4=%s" % [assertions, String(first["aggregate_hash"]), String(first["p2_4_parent_hash"])])
	_finish(true)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.5 assertion failed: " + message)
		quit(1)

func _finish(success: bool) -> void:
	quit(0 if success else 1)
