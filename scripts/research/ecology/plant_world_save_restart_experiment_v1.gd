extends RefCounted

const P2_7 = preload("res://scripts/research/ecology/plant_lineage_divergence_experiment_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_world_persistence_v1.gd")
const Biogeography = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")
const DisturbanceRecovery = preload("res://scripts/research/ecology/plant_disturbance_recovery_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_8_save_restart_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO1-P2.8.1"
const ACCEPTED_P2_7_HASH := "7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe"
const SHORT := "lineage/p2-6-persistent-short"
const LONG := "lineage/p2-6-fragile-long"
const SOURCE := "patch/source"
const NEAR := "patch/near"
const FAR := "patch/far"
const YEARS := 30
const CUT_A_YEAR := 14
const CUT_B_YEAR := 18
const CHECKPOINT_PATH := "user://eco_evo1_p2_8_plant_world_checkpoint.json"

static func run(write_fresh_checkpoint: bool = true) -> Dictionary:
	var parent := P2_7.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_P2_7_HASH:
		return {}
	var fixture := _fixture(parent)
	if fixture.is_empty():
		return {}
	var baseline := Biogeography.simulate(
		fixture["initial_patch_states"],
		fixture["strategies"],
		YEARS,
		fixture["source_patch_ids"],
		fixture["transport_schedule"],
		fixture["disturbance_schedule"]
	)
	if baseline.is_empty():
		return {}
	var expected_result_hash := String(baseline.get("result_hash", ""))
	var expected_state_hash := Persistence.value_hash(baseline.get("final_states", {}))
	var expected_diagnostics_hash := Persistence.value_hash(parent)
	if expected_result_hash.length() != 64 or expected_state_hash.length() != 64 or expected_diagnostics_hash.length() != 64:
		return {}

	var uninterrupted := Persistence.create_world(
		fixture["initial_patch_states"], fixture["strategies"], YEARS,
		fixture["source_patch_ids"], fixture["transport_schedule"], fixture["disturbance_schedule"], parent
	)
	uninterrupted = Persistence.advance_to(uninterrupted, YEARS)
	var uninterrupted_result := Persistence.to_biogeography_result(uninterrupted)
	if uninterrupted_result.is_empty():
		return {}
	var uninterrupted_hash := String(uninterrupted_result.get("result_hash", ""))
	if uninterrupted_hash != expected_result_hash:
		return {}

	var evidence_context := {
		"accepted_p2_7_aggregate_hash": ACCEPTED_P2_7_HASH,
		"expected_p2_6_result_hash": expected_result_hash,
		"expected_final_state_hash": expected_state_hash,
		"expected_lineage_diagnostics_hash": expected_diagnostics_hash,
		"cut_a_year": CUT_A_YEAR,
		"cut_b_year": CUT_B_YEAR,
		"total_years": YEARS,
	}
	var restarted := Persistence.create_world(
		fixture["initial_patch_states"], fixture["strategies"], YEARS,
		fixture["source_patch_ids"], fixture["transport_schedule"], fixture["disturbance_schedule"], parent
	)
	restarted = Persistence.advance_to(restarted, CUT_A_YEAR)
	if restarted.is_empty():
		return {}
	var checkpoint_a := Persistence.serialize_checkpoint(restarted, evidence_context)
	var checkpoint_a_document := Persistence.deserialize_checkpoint(checkpoint_a)
	if checkpoint_a_document.is_empty():
		return {}
	var checkpoint_a_hash := String(checkpoint_a_document.get("checkpoint_hash", ""))
	var after_a: Dictionary = checkpoint_a_document["world"]
	after_a = Persistence.advance_to(after_a, CUT_B_YEAR)
	if after_a.is_empty():
		return {}
	var checkpoint_b := Persistence.serialize_checkpoint(after_a, evidence_context)
	var checkpoint_b_document := Persistence.deserialize_checkpoint(checkpoint_b)
	if checkpoint_b_document.is_empty():
		return {}
	var checkpoint_b_hash := String(checkpoint_b_document.get("checkpoint_hash", ""))
	var after_b: Dictionary = checkpoint_b_document["world"]
	after_b = Persistence.advance_to(after_b, YEARS)
	var restarted_result := Persistence.to_biogeography_result(after_b)
	if restarted_result.is_empty():
		return {}
	var restarted_hash := String(restarted_result.get("result_hash", ""))
	var final_state_hash := Persistence.value_hash(restarted_result.get("final_states", {}))
	var diagnostics_hash := Persistence.value_hash(after_b.get("lineage_diagnostics", {}))

	var altered_parent_hash := "0" + ACCEPTED_P2_7_HASH.substr(1)
	var tampered := checkpoint_a.replace(ACCEPTED_P2_7_HASH, altered_parent_hash)
	var tamper_rejected := Persistence.deserialize_checkpoint(tampered).is_empty()
	var checkpoint_written := true
	if write_fresh_checkpoint:
		checkpoint_written = Persistence.write_checkpoint(CHECKPOINT_PATH, checkpoint_a)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"p2_7_parent_hash": ACCEPTED_P2_7_HASH,
		"baseline_result_hash": expected_result_hash,
		"uninterrupted_result_hash": uninterrupted_hash,
		"resumed_result_hash": restarted_hash,
		"final_state_hash": final_state_hash,
		"diagnostics_hash": diagnostics_hash,
		"checkpoint_a_hash": checkpoint_a_hash,
		"checkpoint_b_hash": checkpoint_b_hash,
		"checkpoint_a_bytes": checkpoint_a.to_utf8_buffer().size(),
		"checkpoint_b_bytes": checkpoint_b.to_utf8_buffer().size(),
		"cut_a_year": CUT_A_YEAR,
		"cut_b_year": CUT_B_YEAR,
		"total_years": YEARS,
		"baseline_match": uninterrupted_hash == expected_result_hash,
		"restart_match": restarted_hash == expected_result_hash,
		"state_match": final_state_hash == expected_state_hash,
		"diagnostics_preserved": diagnostics_hash == expected_diagnostics_hash,
		"tamper_rejected": tamper_rejected,
		"checkpoint_written": checkpoint_written,
		"migration_conservation": bool(restarted_result.get("migration_all_conserve", false)),
		"disturbance_conservation": bool(restarted_result.get("disturbance_all_conserve", false)),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func resume_persisted_checkpoint() -> Dictionary:
	var document := Persistence.read_checkpoint(CHECKPOINT_PATH)
	if document.is_empty():
		return {}
	var evidence: Dictionary = document.get("evidence_context", {})
	if String(evidence.get("accepted_p2_7_aggregate_hash", "")) != ACCEPTED_P2_7_HASH:
		return {}
	if int(evidence.get("cut_a_year", -1)) != CUT_A_YEAR or int(evidence.get("cut_b_year", -1)) != CUT_B_YEAR or int(evidence.get("total_years", -1)) != YEARS:
		return {}
	var expected_result_hash := String(evidence.get("expected_p2_6_result_hash", ""))
	var expected_state_hash := String(evidence.get("expected_final_state_hash", ""))
	var expected_diagnostics_hash := String(evidence.get("expected_lineage_diagnostics_hash", ""))
	if expected_result_hash.length() != 64 or expected_state_hash.length() != 64 or expected_diagnostics_hash.length() != 64:
		return {}
	var checkpoint_a_hash := String(document.get("checkpoint_hash", ""))
	var world: Dictionary = document["world"]
	if int(world.get("current_year", -1)) != CUT_A_YEAR:
		return {}
	world = Persistence.advance_to(world, CUT_B_YEAR)
	if world.is_empty():
		return {}
	var checkpoint_b := Persistence.serialize_checkpoint(world, evidence)
	var checkpoint_b_document := Persistence.deserialize_checkpoint(checkpoint_b)
	if checkpoint_b_document.is_empty():
		return {}
	var checkpoint_b_hash := String(checkpoint_b_document.get("checkpoint_hash", ""))
	world = Persistence.advance_to(Dictionary(checkpoint_b_document["world"]), YEARS)
	var final_result := Persistence.to_biogeography_result(world)
	if final_result.is_empty():
		return {}
	var final_hash := String(final_result.get("result_hash", ""))
	var final_state_hash := Persistence.value_hash(final_result.get("final_states", {}))
	var diagnostics_hash := Persistence.value_hash(world.get("lineage_diagnostics", {}))
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"p2_7_parent_hash": ACCEPTED_P2_7_HASH,
		"baseline_result_hash": expected_result_hash,
		"uninterrupted_result_hash": expected_result_hash,
		"resumed_result_hash": final_hash,
		"final_state_hash": final_state_hash,
		"diagnostics_hash": diagnostics_hash,
		"checkpoint_a_hash": checkpoint_a_hash,
		"checkpoint_b_hash": checkpoint_b_hash,
		"cut_a_year": CUT_A_YEAR,
		"cut_b_year": CUT_B_YEAR,
		"total_years": YEARS,
		"baseline_match": true,
		"restart_match": final_hash == expected_result_hash,
		"state_match": final_state_hash == expected_state_hash,
		"diagnostics_preserved": diagnostics_hash == expected_diagnostics_hash,
		"migration_conservation": bool(final_result.get("migration_all_conserve", false)),
		"disturbance_conservation": bool(final_result.get("disturbance_all_conserve", false)),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _fixture(lineage_diagnostics: Dictionary) -> Dictionary:
	if lineage_diagnostics.is_empty():
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
	return {
		"initial_patch_states": initial_patch_states,
		"strategies": strategies,
		"source_patch_ids": [SOURCE],
		"transport_schedule": transport_schedule,
		"disturbance_schedule": {FAR: far_events},
	}

static func _aggregate_hash(result: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("p2_7_parent_hash", "")),
		String(result.get("baseline_result_hash", "")),
		String(result.get("uninterrupted_result_hash", "")),
		String(result.get("resumed_result_hash", "")),
		String(result.get("final_state_hash", "")),
		String(result.get("diagnostics_hash", "")),
		String(result.get("checkpoint_a_hash", "")),
		String(result.get("checkpoint_b_hash", "")),
		str(int(result.get("cut_a_year", 0))),
		str(int(result.get("cut_b_year", 0))),
		str(int(result.get("total_years", 0))),
		str(bool(result.get("baseline_match", false))),
		str(bool(result.get("restart_match", false))),
		str(bool(result.get("state_match", false))),
		str(bool(result.get("diagnostics_preserved", false))),
		str(bool(result.get("migration_conservation", false))),
		str(bool(result.get("disturbance_conservation", false))),
	])).sha256_text()
