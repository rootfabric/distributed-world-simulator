extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_local_population_succession_experiment_v1.gd")
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
	_check(String(first.get("p2_2_parent_hash", "")) == Experiment.ACCEPTED_P2_2_HASH, "accepted P2.2 parent exact")
	_check(String(first.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")

	var shift: Dictionary = first["shift"]
	var open_control: Dictionary = first["open_control"]
	var short_run: Dictionary = first["short_life_control"]
	var long_run: Dictionary = first["long_life_control"]
	for run in [shift, open_control, short_run, long_run]:
		_check(String(Dictionary(run).get("result_hash", "")).length() == 64, "run result hash shape")
		_check(float(Dictionary(run).get("max_total_biomass_kg_m2", 999.0)) <= PatchBaseline.MAX_BIOMASS_KG_M2 + 0.000000001, "shared patch capacity never exceeded")
		_check(int(Dictionary(run).get("max_adult_cohort_count", 99999)) <= 64, "adult cohort truth remains bounded")
		_check(int(Dictionary(run).get("max_seed_bank_cohort_count", 99999)) <= 1024, "seed-bank cohort truth remains bounded")
		_check(float(Dictionary(run).get("cumulative_adult_mortality_kg_m2", -1.0)) >= 0.0, "mortality finite nonnegative")
		for summary_value in Array(Dictionary(run).get("history", [])):
			var summary: Dictionary = summary_value
			_check(String(summary.get("summary_hash", "")).length() == 64, "history hash shape")
			_check(float(summary.get("total_biomass_kg_m2", -1.0)) >= 0.0, "history biomass nonnegative")
			_check(float(summary.get("capacity_fraction", 2.0)) <= 1.0 + 0.000000001, "history capacity bounded")

	_check(float(first["initial_early_share"]) > float(first["initial_banked_share"]), "low-dormancy early strategy initially leads")
	_check(float(first["banked_gain_after_shift"]) > 0.02, "banked lineage gains share after environmental transition")
	_check(float(first["shade_shift_delta"]) > 0.01, "shade schedule favours shade-tolerant banked lineage relative to open control")
	_check(int(first["shift_reactivated"]) > 0, "seed-bank history reactivates into adult recruitment")
	_check(int(first["shift_reproduction_events"]) > 0, "adult cohorts generate repeated local reproduction events")
	_check(int(first["shift_emitted"]) > 160, "multi-year run emits seeds beyond initial founder pulse")
	_check(float(first["short_life_mortality"]) > float(first["long_life_mortality"]), "short lifespan increases matched adult turnover")
	_check(float(first["shift_max_biomass"]) <= PatchBaseline.MAX_BIOMASS_KG_M2 + 0.000000001, "succession run respects shared capacity")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_local_population_succession_v1.gd")
	_check(source.find("biome") == -1, "no biome lookup in local population kernel")
	_check(source.find("species_table") == -1, "no species placement table")
	_check(source.find("migration_graph") == -1, "no P2.4 migration graph")

	print("ECO.EVO1-P2.3 early_initial=%.12f banked_initial=%.12f banked_pre_change=%.12f banked_final=%.12f open_banked_final=%.12f" % [float(first["initial_early_share"]), float(first["initial_banked_share"]), float(first["pre_change_banked_share"]), float(first["final_banked_share"]), float(first["open_final_banked_share"])])
	print("ECO.EVO1-P2.3 shade_delta=%.12f banked_gain=%.12f reactivated=%d reproduction_events=%d emitted=%d" % [float(first["shade_shift_delta"]), float(first["banked_gain_after_shift"]), int(first["shift_reactivated"]), int(first["shift_reproduction_events"]), int(first["shift_emitted"])])
	print("ECO.EVO1-P2.3 short_mortality=%.12f long_mortality=%.12f max_biomass=%.12f adult_cohorts=%d bank_cohorts=%d top_changed=%s" % [float(first["short_life_mortality"]), float(first["long_life_mortality"]), float(first["shift_max_biomass"]), int(first["shift_max_adult_cohorts"]), int(first["shift_max_bank_cohorts"]), str(bool(first["top_lineage_changed"]))])
	print("ECO.EVO1-P2.3 Local Population Turnover + Succession: PASS (%d assertions) aggregate_hash=%s p2_2=%s" % [assertions, String(first["aggregate_hash"]), String(first["p2_2_parent_hash"])])
	_finish(true)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.3 assertion failed: " + message)
		quit(1)

func _finish(success: bool) -> void:
	quit(0 if success else 1)
