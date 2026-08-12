extends RefCounted

const P2_5 = preload("res://scripts/research/ecology/plant_disturbance_recovery_experiment_v1.gd")
const Biogeography = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")
const DisturbanceRecovery = preload("res://scripts/research/ecology/plant_disturbance_recovery_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PopulationTurnover = preload("res://scripts/research/ecology/plant_local_population_succession_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_6_long_horizon_biogeography_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO1-P2.6.1"
const ACCEPTED_P2_5_HASH := "292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696"
const SHORT := "lineage/p2-6-persistent-short"
const LONG := "lineage/p2-6-fragile-long"
const SOURCE := "patch/source"
const NEAR := "patch/near"
const FAR := "patch/far"
const YEARS := 30

static func run() -> Dictionary:
	var parent := P2_5.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_P2_5_HASH:
		return {}

	var environment := EnvironmentSample.create(0.0, 0.0, 17.0, 0.58, 0.94, 0.82, 0.02, 2606, "eco-evo1-p2-6-favourable")
	if environment.is_empty():
		return {}
	var source_patch := PatchMigration.create_patch(SOURCE, Rect2(-10.0, -10.0, 20.0, 20.0), environment)
	var near_patch := PatchMigration.create_patch(NEAR, Rect2(11.0, -20.0, 24.0, 40.0), environment)
	var far_patch := PatchMigration.create_patch(FAR, Rect2(50.0, -40.0, 80.0, 80.0), environment)
	if source_patch.is_empty() or near_patch.is_empty() or far_patch.is_empty():
		return {}

	var short_genome := Genome.create("plant-genome/p2-6-persistent-short", 1.60, 0.55, 1.20, 0.58, 0.30, 0.55, 160, 5.0, 30.0)
	var long_genome := Genome.create("plant-genome/p2-6-fragile-long", 3.00, 0.70, 0.05, 0.58, 0.30, 0.40, 160, 20.0, 30.0)
	var short_traits := RecruitmentTraits.create("recruitment-traits/p2-6-persistent-short", 0.65, 5.0)
	var long_traits := RecruitmentTraits.create("recruitment-traits/p2-6-fragile-long", 0.25, 2.0)
	if short_genome.is_empty() or long_genome.is_empty() or short_traits.is_empty() or long_traits.is_empty():
		return {}
	var strategies := {
		SHORT: {"genome": short_genome, "recruitment_traits": short_traits},
		LONG: {"genome": long_genome, "recruitment_traits": long_traits},
	}

	var source_short := DisturbanceRecovery.create_adult(SHORT, short_genome, 5.0, 0.08, float(short_genome["height_m"]), "p2-6/source/short-adult".sha256_text())
	var source_long := DisturbanceRecovery.create_adult(LONG, long_genome, 5.0, 0.08, float(long_genome["height_m"]), "p2-6/source/long-adult".sha256_text())
	var source_short_bank := DisturbanceRecovery.create_seed_bank(SHORT, short_genome, short_traits, environment, 160, 0.0, "p2-6/source/short-bank".sha256_text())
	var source_long_bank := DisturbanceRecovery.create_seed_bank(LONG, long_genome, long_traits, environment, 160, 0.0, "p2-6/source/long-bank".sha256_text())
	if source_short.is_empty() or source_long.is_empty() or source_short_bank.is_empty() or source_long_bank.is_empty():
		return {}

	var initial_patch_states := [
		{"patch": source_patch, "state": {"adults": [source_short, source_long], "banks": [source_short_bank, source_long_bank]}},
		{"patch": near_patch, "state": {"adults": [], "banks": []}},
		{"patch": far_patch, "state": {"adults": [], "banks": []}},
	]
	var transport_schedule := [
		{"year_start": 1, "transport_vector": Vector2(1.0, 0.0), "turbulence": 0.20},
		{"year_start": 15, "transport_vector": Vector2(-1.0, 0.0), "turbulence": 0.20},
		{"year_start": 19, "transport_vector": Vector2(1.0, 0.0), "turbulence": 0.20},
	]
	var far_events: Array = []
	for year in range(15, 19):
		var event := DisturbanceRecovery.create_event("p2-6/far/severe/%d" % year, year, 1.0, 1.0)
		if event.is_empty():
			return {}
		far_events.append(event)

	var control := Biogeography.simulate(initial_patch_states, strategies, YEARS, [SOURCE], transport_schedule, {})
	var disturbed := Biogeography.simulate(initial_patch_states, strategies, YEARS, [SOURCE], transport_schedule, {FAR: far_events})
	if control.is_empty() or disturbed.is_empty():
		return {}

	var far_colonization_year := Biogeography.transition_year(disturbed, FAR, LONG, "COLONIZATION")
	var far_extinction_year := Biogeography.transition_year(disturbed, FAR, LONG, "LOCAL_ADULT_EXTINCTION", 14)
	var far_recolonization_year := Biogeography.transition_year(disturbed, FAR, LONG, "RECOLONIZATION", far_extinction_year)
	var control_far_extinction_after_14 := Biogeography.transition_year(control, FAR, LONG, "LOCAL_ADULT_EXTINCTION", 14)
	var long_patch_years := Biogeography.lineage_patch_years(disturbed, LONG)
	var short_patch_years := Biogeography.lineage_patch_years(disturbed, SHORT)
	var far_long_patch_years := Biogeography.patch_years_adult_occupied(disturbed, FAR, LONG)
	var far_short_patch_years := Biogeography.patch_years_adult_occupied(disturbed, FAR, SHORT)
	var control_far_long_patch_years := Biogeography.patch_years_adult_occupied(control, FAR, LONG)
	var event_window_absence_years := _window_absence_years(disturbed, FAR, LONG, 15, 18)
	var control_event_window_absence_years := _window_absence_years(control, FAR, LONG, 15, 18)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"p2_5_parent_hash": ACCEPTED_P2_5_HASH,
		"control": control,
		"disturbed": disturbed,
		"far_colonization_year": far_colonization_year,
		"far_extinction_year": far_extinction_year,
		"far_recolonization_year": far_recolonization_year,
		"control_far_extinction_after_14": control_far_extinction_after_14,
		"long_max_range": Biogeography.max_adult_range(disturbed, LONG),
		"short_max_range": Biogeography.max_adult_range(disturbed, SHORT),
		"long_patch_years": long_patch_years,
		"short_patch_years": short_patch_years,
		"far_long_patch_years": far_long_patch_years,
		"far_short_patch_years": far_short_patch_years,
		"control_far_long_patch_years": control_far_long_patch_years,
		"event_window_absence_years": event_window_absence_years,
		"control_event_window_absence_years": control_event_window_absence_years,
		"regional_long_never_absent": Biogeography.regional_adult_never_absent(disturbed, LONG),
		"final_far_long_reoccupied": Biogeography.final_patch_adult_occupied(disturbed, FAR, LONG),
		"migration_conservation": bool(disturbed["migration_all_conserve"]) and bool(control["migration_all_conserve"]),
		"disturbance_conservation": bool(disturbed["disturbance_all_conserve"]) and bool(control["disturbance_all_conserve"]),
		"disturbance_event_count": Array(disturbed["disturbance_log"]).size(),
		"max_adult_cohorts": maxi(int(disturbed["max_adult_cohorts"]), int(control["max_adult_cohorts"])),
		"max_bank_cohorts": maxi(int(disturbed["max_bank_cohorts"]), int(control["max_bank_cohorts"])),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _window_absence_years(result: Dictionary, patch_id: String, lineage_id: String, year_start: int, year_end: int) -> int:
	var absent := 0
	for value in Array(result.get("history", [])):
		var summary: Dictionary = value
		var year := int(summary.get("year", -1))
		if year < year_start or year > year_end:
			continue
		var found := false
		for patch_value in Array(summary.get("patch_summaries", [])):
			var patch: Dictionary = patch_value
			if String(patch.get("patch_id", "")) != patch_id:
				continue
			found = true
			if float(Dictionary(patch.get("adult_biomass_by_lineage", {})).get(lineage_id, 0.0)) <= PopulationTurnover.EXTINCTION_BIOMASS_KG_M2:
				absent += 1
			break
		if not found:
			return -1
	return absent

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("p2_5_parent_hash", "")),
		String(Dictionary(result.get("control", {})).get("result_hash", "")),
		String(Dictionary(result.get("disturbed", {})).get("result_hash", "")),
	])
	for field_name in ["far_colonization_year", "far_extinction_year", "far_recolonization_year", "control_far_extinction_after_14", "long_max_range", "short_max_range", "long_patch_years", "short_patch_years", "far_long_patch_years", "far_short_patch_years", "control_far_long_patch_years", "event_window_absence_years", "control_event_window_absence_years", "disturbance_event_count", "max_adult_cohorts", "max_bank_cohorts"]:
		tokens.append(str(int(result.get(field_name, 0))))
	for field_name in ["regional_long_never_absent", "final_far_long_reoccupied", "migration_conservation", "disturbance_conservation"]:
		tokens.append(str(bool(result.get(field_name, false))))
	return "\n".join(tokens).sha256_text()
