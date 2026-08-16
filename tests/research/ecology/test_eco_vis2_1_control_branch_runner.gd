extends SceneTree

const TraceContract = preload("res://scripts/labs/ecology/eco_vis2_1_branch_trace_contract.gd")
const ControlRunner = preload("res://scripts/labs/ecology/eco_vis2_1_control_branch_runner.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const VIS20_Model = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const VIS20_Scene = preload("res://scenes/labs/ecology/eco_vis2_0_evolution_experiment_lab.tscn")

const FORK_GENERATION := 6
const TARGET_GENERATION := 12
const BIOMASS_KG := 11.0

var _assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := VIS20_Scene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	_check(String(scene.get_experiment_state().get("profile", "")) == VIS20_Model.PROFILE_BASELINE, "source experiment starts BASELINE")
	scene.set_realtime_turnover_generation(FORK_GENERATION)
	await process_frame
	var canonical_before: Dictionary = scene.get_spatial_snapshot().duplicate(true)
	var source_model := scene.get("_vis18r_model") as RefCounted
	_check(source_model != null, "continuous turnover model available at fork")
	if source_model == null:
		return
	var fork_map: Dictionary = Dictionary(source_model.call("generation_map", FORK_GENERATION)).duplicate(true)
	var fork_history: Array = scene.get_continuous_history().duplicate(true)
	_check(not fork_map.is_empty(), "fork generation map captured")
	_check(_generation_biomass(fork_map) > 0.0, "fork population has represented biomass")
	_check(absf(_generation_biomass(fork_map) - BIOMASS_KG) < 0.000001, "fork biomass is 11.000 kg")
	var fork_map_before := fork_map.duplicate(true)
	var fork_history_before := fork_history.duplicate(true)

	var runner_a := ControlRunner.new()
	var runner_b := ControlRunner.new()
	var configured_a: Dictionary = runner_a.configure_from_fork(FORK_GENERATION, fork_map, fork_history)
	var configured_b: Dictionary = runner_b.configure_from_fork(FORK_GENERATION, fork_map, fork_history)
	_check(bool(configured_a.get("success", false)), "CONTROL A configures from fork")
	_check(bool(configured_b.get("success", false)), "CONTROL B configures from fork")
	_check(fork_map == fork_map_before, "configure does not mutate fork generation map")
	_check(fork_history == fork_history_before, "configure does not mutate fork history")
	_check(runner_a.generation_map(FORK_GENERATION) == fork_map_before, "G(N) equals supplied fork state")

	var fork_field_hash := TraceContract.compute_field_hash(FORK_GENERATION, fork_map_before)
	var expected_common_rng := ("%s|fork=%d|field=%s" % [
		ControlRunner.RNG_DOMAIN,
		FORK_GENERATION,
		fork_field_hash,
	]).sha256_text()
	_check(runner_a.common_random_seed_hash() == expected_common_rng, "RNG root derives only from common fork generation and field state")
	_check(runner_b.common_random_seed_hash() == expected_common_rng, "independent CONTROL uses same common random numbers")

	var probe_x := 140.0
	var probe_z := 85.0
	var source_probe: Dictionary = scene.get_experiment_probe(probe_x, probe_z)
	var source_baseline: Dictionary = source_probe.get("baseline", {})
	var source_experimental: Dictionary = source_probe.get("experimental", {})
	var runner_baseline: Dictionary = runner_a.baseline_environment_sample_at(probe_x, probe_z)
	_check(bool(EnvironmentSample.validate(runner_baseline).get("success", false)), "runner BASELINE EnvironmentSample validates")
	_check(String(runner_baseline.get("checksum", "")) == String(source_baseline.get("checksum", "")), "runner baseline matches existing VIS lab baseline")
	_check(String(runner_baseline.get("checksum", "")) == String(source_experimental.get("checksum", "")), "VIS2.0 BASELINE experiment preserves existing EnvironmentSample")
	_check(String(runner_baseline.get("environment_revision", "")) == String(source_baseline.get("environment_revision", "")), "baseline environment revision is preserved")

	var advance_a: Dictionary = runner_a.advance_to(TARGET_GENERATION)
	var advance_b: Dictionary = runner_b.advance_to(TARGET_GENERATION)
	_check(bool(advance_a.get("success", false)), "CONTROL A advances after fork")
	_check(bool(advance_b.get("success", false)), "CONTROL B advances after fork")
	_check(not runner_a.generation_map(FORK_GENERATION + 1).is_empty(), "G(N+1) advances normally")
	_check(runner_a.generation_map(TARGET_GENERATION) == runner_b.generation_map(TARGET_GENERATION), "independent CONTROL generation maps are identical")
	_check(runner_a.trace() == runner_b.trace(), "independent CONTROL traces are identical")
	for generation in range(FORK_GENERATION, TARGET_GENERATION + 1):
		var point_a: Dictionary = runner_a.trace_point(generation)
		var point_b: Dictionary = runner_b.trace_point(generation)
		_check(not point_a.is_empty(), "trace point G%d exists" % generation)
		_check(String(point_a.get("field_hash", "")) == String(point_b.get("field_hash", "")), "field hash G%d deterministic" % generation)
		_check(absf(float(point_a.get("represented_biomass_kg", 0.0)) - BIOMASS_KG) < 0.000001, "represented biomass G%d remains 11.000 kg" % generation)
		_check(String(point_a.get("branch_id", "")) == ControlRunner.BRANCH_ID, "trace G%d branch id" % generation)
		_check(String(point_a.get("experiment_id", "")) == ControlRunner.EXPERIMENT_ID, "trace G%d experiment is BASELINE" % generation)
	var trace_validation: Dictionary = TraceContract.validate_trace(runner_a.trace())
	_check(bool(trace_validation.get("success", false)), "branch trace contract validates")
	var invalid_missing := runner_a.trace_point(FORK_GENERATION)
	invalid_missing.erase("field_hash")
	_check(not bool(TraceContract.validate(invalid_missing).get("success", true)), "trace contract rejects missing field")
	var invalid_count := runner_a.trace_point(FORK_GENERATION)
	invalid_count["visual_count"] = -1
	_check(not bool(TraceContract.validate(invalid_count).get("success", true)), "trace contract rejects invalid field")

	var final_map := runner_a.generation_map(TARGET_GENERATION)
	var final_trace := runner_a.trace()
	var restart: Dictionary = runner_a.restart_from_fork()
	_check(bool(restart.get("success", false)), "restart from fork succeeds")
	_check(runner_a.generation_map(FORK_GENERATION) == fork_map_before, "restart restores exact G(N)")
	var replay: Dictionary = runner_a.advance_to(TARGET_GENERATION)
	_check(bool(replay.get("success", false)), "restart replay advances")
	_check(runner_a.generation_map(TARGET_GENERATION) == final_map, "restart replay generation map is deterministic")
	_check(runner_a.trace() == final_trace, "restart replay trace is deterministic")

	_check(fork_map == fork_map_before, "advance/restart never mutate supplied fork map")
	_check(fork_history == fork_history_before, "advance/restart never mutate supplied fork history")
	_check(scene.get_spatial_snapshot() == canonical_before, "CONTROL never mutates canonical VIS1.2 state")

	var total_events := 0
	for point in runner_a.trace():
		if int(point.get("generation", 0)) > FORK_GENERATION:
			total_events += int(point.get("birth_count", 0)) + int(point.get("death_count", 0))
	_check(total_events > 0, "post-fork generations perform normal turnover")

	scene.queue_free()
	await process_frame
	print("ECO.VIS2.1-C control branch runner: PASS (%d assertions)" % _assertions)
	quit(0)


func _generation_biomass(generation_map: Dictionary) -> float:
	var total := 0.0
	for state_variant in generation_map.values():
		if typeof(state_variant) != TYPE_DICTIONARY:
			continue
		for record_variant in Array(Dictionary(state_variant).get("records", [])):
			if typeof(record_variant) == TYPE_DICTIONARY:
				total += float(Dictionary(record_variant).get("represented_biomass_kg", 0.0))
	return total


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	push_error("ECO.VIS2.1-C assertion failed: %s" % label)
	quit(1)
