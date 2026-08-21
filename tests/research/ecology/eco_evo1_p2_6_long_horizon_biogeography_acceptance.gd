extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_experiment_v1.gd")
const Biogeography = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_v1.gd")

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
	_check(String(first.get("p2_5_parent_hash", "")) == Experiment.ACCEPTED_P2_5_HASH, "accepted P2.5 parent exact")
	_check(String(first.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")
	_check(bool(first["migration_conservation"]), "all P2.4 migration ledgers conserve")
	_check(bool(first["disturbance_conservation"]), "all P2.5 disturbance ledgers conserve")
	_check(int(first["disturbance_event_count"]) == 4, "four far-patch disturbance events executed")

	_check(int(first["far_colonization_year"]) > 0 and int(first["far_colonization_year"]) < 15, "far patch colonized before disturbance interval")
	_check(int(first["far_extinction_year"]) >= 15 and int(first["far_extinction_year"]) <= 18, "far long lineage reaches local adult extinction during disturbance interval")
	_check(int(first["far_recolonization_year"]) > int(first["far_extinction_year"]), "far long lineage recolonizes after local extinction")
	_check(int(first["control_far_extinction_after_14"]) == -1, "same transport history without disturbance has no far local extinction after year 14")
	_check(bool(first["regional_long_never_absent"]), "long lineage persists regionally while far population goes locally extinct")
	_check(bool(first["final_far_long_reoccupied"]), "far patch is occupied again by long lineage at horizon end")
	_check(int(first["event_window_absence_years"]) > int(first["control_event_window_absence_years"]), "disturbance creates additional far-patch absence relative to control")
	_check(int(first["far_long_patch_years"]) > int(first["far_short_patch_years"]), "isolated far patch is occupied more persistently by long disperser")
	_check(int(first["long_patch_years"]) > int(first["short_patch_years"]), "regional patch-year occupancy favours the broader disperser")
	_check(int(first["long_max_range"]) >= 2, "long lineage expands beyond source patch")
	_check(int(first["control_far_long_patch_years"]) > int(first["far_long_patch_years"]), "disturbance reduces far long-lineage persistence vs control")
	_check(int(first["max_adult_cohorts"]) <= 64, "adult cohort count remains bounded")
	_check(int(first["max_bank_cohorts"]) <= 256, "seed-bank cohort count remains bounded")

	for run_name in ["control", "disturbed"]:
		var run: Dictionary = first[run_name]
		_check(String(run.get("result_hash", "")).length() == 64, run_name + " result hash shape")
		_check(int(run.get("years", 0)) == Experiment.YEARS, run_name + " horizon exact")
		_check(int(run.get("patch_count", 0)) == 3, run_name + " patch count exact")
		_check(bool(run.get("migration_all_conserve", false)), run_name + " migration conservation")
		_check(bool(run.get("disturbance_all_conserve", false)), run_name + " disturbance conservation")
		for summary_value in Array(run.get("history", [])):
			var summary: Dictionary = summary_value
			_check(String(summary.get("summary_hash", "")).length() == 64, run_name + " history hash shape")
			for lineage in [Experiment.SHORT, Experiment.LONG]:
				var range_count := int(Dictionary(summary.get("adult_range_patch_count", {})).get(lineage, -1))
				_check(range_count >= 0 and range_count <= 3, run_name + " range bounded for " + lineage)

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_long_horizon_biogeography_v1.gd")
	_check(source.find("biome") == -1, "no biome lookup in biogeography kernel")
	_check(source.find("species_table") == -1, "no species placement table")
	_check(source.find("PatchMigration.migrate_reproduction_event") >= 0, "accepted P2.4 migration reused directly")
	_check(source.find("DisturbanceRecovery.apply_event") >= 0, "accepted P2.5 disturbance response reused directly")
	_check(source.find("DisturbanceRecovery.advance_year") >= 0, "accepted P2.5 local recovery reused directly")
	_check(source.find("PopulationTurnover.EXTINCTION_BIOMASS_KG_M2") >= 0, "accepted P2.3 extinction threshold reused by reference")

	print("ECO.EVO1-P2.6 colonized=%d extinct=%d recolonized=%d control_extinction=%d" % [int(first["far_colonization_year"]), int(first["far_extinction_year"]), int(first["far_recolonization_year"]), int(first["control_far_extinction_after_14"])])
	print("ECO.EVO1-P2.6 long_patch_years=%d short_patch_years=%d far_long=%d far_short=%d long_max_range=%d short_max_range=%d" % [int(first["long_patch_years"]), int(first["short_patch_years"]), int(first["far_long_patch_years"]), int(first["far_short_patch_years"]), int(first["long_max_range"]), int(first["short_max_range"])])
	print("ECO.EVO1-P2.6 event_absence=%d control_absence=%d control_far_years=%d final_reoccupied=%s regional_persist=%s" % [int(first["event_window_absence_years"]), int(first["control_event_window_absence_years"]), int(first["control_far_long_patch_years"]), str(bool(first["final_far_long_reoccupied"])), str(bool(first["regional_long_never_absent"]))])
	print("ECO.EVO1-P2.6 Long-Horizon Biogeography: PASS (%d assertions) aggregate_hash=%s p2_5=%s" % [assertions, String(first["aggregate_hash"]), String(first["p2_5_parent_hash"])])
	_finish(true)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.6 assertion failed: " + message)
		quit(1)

func _finish(success: bool) -> void:
	quit(0 if success else 1)
