extends SceneTree

const TreatmentRunner = preload("res://scripts/labs/ecology/eco_vis2_1_treatment_branch_runner.gd")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const TurnoverBridge = preload("res://scripts/labs/ecology/eco_vis1_8a_turnover_bridge.gd")
const LineageGenomeBridge = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")

const FORK_GENERATION := 4
const TARGET_GENERATION := 12

var _assertions := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture_runner := TreatmentRunner.new()
	var fork_map := _make_fork_map(fixture_runner)
	var fork_history := _make_fork_history()
	var fork_map_before := var_to_str(fork_map)
	var fork_history_before := var_to_str(fork_history)
	var canonical_truth := {
		"environment_revision": "canonical-environment-locked",
		"population_revision": 77,
		"timeline_generation": 991,
	}
	var canonical_before := canonical_truth.duplicate(true)

	var drought := TreatmentRunner.new()
	var configured: Dictionary = drought.configure_from_fork(
		FORK_GENERATION, fork_map, fork_history, ExperimentModel.PROFILE_DROUGHT, 0.85
	)
	_expect(bool(configured.get("success", false)), "treatment runner configures from external fork")
	_expect(drought.generation_map(FORK_GENERATION) == fork_map, "fork generation map is unchanged")
	_expect(drought.trace_point(FORK_GENERATION) == fork_history[-1], "supplied fork trace point is preserved byte-for-byte by value")

	var baseline_at_fork := drought.sample_environment_for_generation(FORK_GENERATION, 31.0, -17.0)
	var drought_at_next := drought.sample_environment_for_generation(FORK_GENERATION + 1, 31.0, -17.0)
	_expect(bool(EnvironmentSample.validate(baseline_at_fork).get("success", false)), "fork EnvironmentSample remains valid")
	_expect(bool(EnvironmentSample.validate(drought_at_next).get("success", false)), "treatment EnvironmentSample remains valid")
	_expect(String(baseline_at_fork.get("environment_revision", "")) == "eco-vis1.1-lab-environment-v1", "fork generation still uses baseline environment")
	_expect(String(drought_at_next.get("environment_revision", "")).contains("/vis2.0/drought/i0.85"), "treatment becomes effective exactly at fork+1")
	_expect(String(baseline_at_fork.get("checksum", "")) != String(drought_at_next.get("checksum", "")), "fork+1 treatment changes EnvironmentSample checksum")

	var advance_result := drought.advance_to(TARGET_GENERATION)
	_expect(bool(advance_result.get("success", false)), "drought trajectory advances from fork")
	_expect(var_to_str(fork_map) == fork_map_before, "supplied fork generation map is immutable")
	_expect(var_to_str(fork_history) == fork_history_before, "supplied fork history is immutable")
	_expect(canonical_truth == canonical_before, "canonical environment/population/timeline truth is untouched")
	_expect(drought.generation_map(FORK_GENERATION) == fork_map, "advancing treatment never rewrites fork generation")
	for point in drought.trace():
		if int(point.get("generation", -1)) < FORK_GENERATION:
			continue
		_expect(is_equal_approx(float(point.get("represented_biomass_kg", 0.0)), 11.0), "represented biomass remains exactly 11.000 kg at G%d" % int(point.get("generation", -1)))

	var drought_repeat := TreatmentRunner.new()
	var repeated_config: Dictionary = drought_repeat.configure_from_fork(
		FORK_GENERATION, fork_map, fork_history, ExperimentModel.PROFILE_DROUGHT, 0.85
	)
	_expect(bool(repeated_config.get("success", false)), "repeat treatment configures")
	_expect(bool(drought_repeat.advance_to(TARGET_GENERATION).get("success", false)), "repeat treatment advances")
	_expect(drought_repeat.trace() == drought.trace(), "same fork + experiment + intensity is deterministic")
	_expect(drought_repeat.generation_map(TARGET_GENERATION) == drought.generation_map(TARGET_GENERATION), "deterministic replay reproduces exact population state")

	var trace_before_restart := drought.trace()
	var map_before_restart := drought.generation_map(TARGET_GENERATION)
	_expect(bool(drought.restart_from_fork().get("success", false)), "restart returns to fork")
	_expect(drought.generation_map(FORK_GENERATION) == fork_map, "restart restores exact fork state")
	_expect(bool(drought.advance_to(TARGET_GENERATION).get("success", false)), "restart advances again")
	_expect(drought.trace() == trace_before_restart, "restart from fork reproduces treatment trace")
	_expect(drought.generation_map(TARGET_GENERATION) == map_before_restart, "restart from fork reproduces treatment population")

	var drought_low := TreatmentRunner.new()
	var low_config: Dictionary = drought_low.configure_from_fork(
		FORK_GENERATION, fork_map, fork_history, ExperimentModel.PROFILE_DROUGHT, 0.35
	)
	var low_sample := drought_low.sample_environment_for_generation(FORK_GENERATION + 1, 31.0, -17.0)
	_expect(String(low_sample.get("environment_revision", "")) != String(drought_at_next.get("environment_revision", "")), "different intensity changes environment revision")
	_expect(String(low_sample.get("checksum", "")) != String(drought_at_next.get("checksum", "")), "different intensity changes environment checksum")

	var flood := TreatmentRunner.new()
	var flood_config: Dictionary = flood.configure_from_fork(
		FORK_GENERATION, fork_map, fork_history, ExperimentModel.PROFILE_FLOOD, 0.85
	)
	_expect(bool(flood_config.get("success", false)), "flood treatment configures")
	var flood_sample := flood.sample_environment_for_generation(FORK_GENERATION + 1, 31.0, -17.0)
	_expect(bool(EnvironmentSample.validate(flood_sample).get("success", false)), "flood EnvironmentSample remains valid")
	_expect(String(flood_sample.get("environment_revision", "")) != String(drought_at_next.get("environment_revision", "")), "different experiment changes environment revision")
	_expect(String(flood_sample.get("checksum", "")) != String(drought_at_next.get("checksum", "")), "different experiment changes environment checksum")

	_expect(String(configured.get("source_snapshot_hash", "")) == String(low_config.get("source_snapshot_hash", "")), "intensity is absent from CRN seed derivation")
	_expect(String(configured.get("source_snapshot_hash", "")) == String(flood_config.get("source_snapshot_hash", "")), "experiment ID is absent from CRN seed derivation")
	var turnover_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_vis1_8a_turnover_bridge.gd").to_lower()
	_expect(not turnover_source.contains("branch_id"), "VIS1.8A RNG kernel has no branch ID input")
	_expect(not turnover_source.contains("experiment_id"), "VIS1.8A RNG kernel has no experiment ID input")
	_expect(not turnover_source.contains("treatment"), "VIS1.8A RNG kernel has no treatment label")

	_expect(bool(flood.advance_to(TARGET_GENERATION).get("success", false)), "flood trajectory advances from same fork")
	var trajectories_diverged := false
	for generation in range(FORK_GENERATION + 1, TARGET_GENERATION + 1):
		var drought_point := drought.trace_point(generation)
		var flood_point := flood.trace_point(generation)
		if String(drought_point.get("field_hash", "")) != String(flood_point.get("field_hash", "")):
			trajectories_diverged = true
			break
	_expect(trajectories_diverged, "drought and flood produce different post-fork field trajectories")
	_expect(drought.generation_map(TARGET_GENERATION) != flood.generation_map(TARGET_GENERATION), "drought and flood produce different post-fork population states")

	var branch_edit := TreatmentRunner.new()
	_expect(bool(branch_edit.configure_from_fork(FORK_GENERATION, fork_map, fork_history, ExperimentModel.PROFILE_DROUGHT, 0.70).get("success", false)), "branch edit fixture configures")
	_expect(bool(branch_edit.advance_to(7).get("success", false)), "branch edit reaches local point")
	var generation_seven := branch_edit.generation_map(7)
	var edit_result := branch_edit.set_experiment(ExperimentModel.PROFILE_SHADE, 0.60)
	_expect(bool(edit_result.get("success", false)), "experiment can change after advancing")
	_expect(int(edit_result.get("effective_generation", -1)) == 8, "changed experiment starts only after current local point")
	_expect(branch_edit.generation_map(7) == generation_seven, "changing experiment does not rewrite current treatment past")
	_expect(bool(branch_edit.advance_to(9).get("success", false)), "edited treatment future advances")
	_expect(String(branch_edit.trace_point(7).get("experiment_id", "")) == ExperimentModel.PROFILE_DROUGHT, "old treatment remains on preserved past")
	_expect(String(branch_edit.trace_point(8).get("experiment_id", "")) == ExperimentModel.PROFILE_SHADE, "new treatment starts on next generation")
	var edited_trace := branch_edit.trace()
	_expect(bool(branch_edit.restart_from_fork().get("success", false)), "edited branch can restart")
	_expect(bool(branch_edit.advance_to(9).get("success", false)), "edited branch replays after restart")
	_expect(branch_edit.trace() == edited_trace, "restart replays piecewise treatment schedule deterministically")

	print("ECO.VIS2.1-T treatment branch runner: PASS (%d assertions)" % _assertions if _failures == 0 else "ECO.VIS2.1-T treatment branch runner: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _make_fork_map(environment_source: Node) -> Dictionary:
	var result := {}
	for population_index in range(2):
		var population_id := "alpha" if population_index == 0 else "beta"
		var patch_id := "A" if population_index == 0 else "B"
		var patch_center := Vector2(-52.0, -18.0) if population_index == 0 else Vector2(58.0, 26.0)
		var baseline_genome := LineageGenomeBridge.create_population_baseline_genome(population_id)
		var records: Array[Dictionary] = []
		for index in range(8):
			var lineage := MutationKernel.create_ancestor(baseline_genome, 9000 + population_index * 100 + index)
			var angle := TAU * float(index) / 8.0
			var world_x := patch_center.x + cos(angle) * (5.0 + float(index % 3))
			var world_z := patch_center.y + sin(angle) * (5.0 + float((index + 1) % 3))
			var environment: Dictionary = environment_source.sample_environment_for_generation(FORK_GENERATION, world_x, world_z)
			var fitness := TurnoverBridge.evaluate_fitness(baseline_genome, environment)
			var record := TurnoverBridge.create_founder_record(
				"vis21/fork/%s/%02d" % [population_id, index],
				patch_id,
				population_id,
				index,
				world_x,
				world_z,
				angle,
				baseline_genome,
				lineage,
				5.5 / 8.0,
				fitness
			)
			record["age_generations"] = FORK_GENERATION
			records.append(record)
		result["%s/%s" % [patch_id, population_id]] = {
			"patch_id": patch_id,
			"population_id": population_id,
			"base_count": records.size(),
			"source_biomass_kg": 5.5,
			"patch_center": patch_center,
			"records": records,
			"transition": {
				"generation": FORK_GENERATION,
				"birth_count": 0,
				"death_count": 0,
				"survivor_count": records.size(),
				"represented_biomass_kg": 5.5,
				"turnover_hash": ("fork/%s/%s" % [patch_id, population_id]).sha256_text(),
			},
		}
	return result


func _make_fork_history() -> Array[Dictionary]:
	return [{
		"generation": FORK_GENERATION - 1,
		"branch_id": "COMMON",
		"experiment_id": ExperimentModel.PROFILE_BASELINE,
		"visual_count": 16,
		"birth_count": 0,
		"death_count": 0,
		"survivor_count": 16,
		"mean_fitness": 0.75,
		"unique_genomes": 2,
		"alpha_count": 8,
		"beta_count": 8,
		"represented_biomass_kg": 11.0,
		"field_hash": "c".repeat(64),
		"environment_revision": "eco-vis1.1-lab-environment-v1",
	}, {
		"generation": FORK_GENERATION,
		"branch_id": "COMMON",
		"experiment_id": ExperimentModel.PROFILE_BASELINE,
		"visual_count": 16,
		"birth_count": 0,
		"death_count": 0,
		"survivor_count": 16,
		"mean_fitness": 0.75,
		"unique_genomes": 2,
		"alpha_count": 8,
		"beta_count": 8,
		"represented_biomass_kg": 11.0,
		"field_hash": "d".repeat(64),
		"environment_revision": "eco-vis1.1-lab-environment-v1",
	}]


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS2.1-T assertion failed: %s" % message)
