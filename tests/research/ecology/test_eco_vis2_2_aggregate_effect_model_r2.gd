extends SceneTree

const AggregateModel = preload("res://scripts/labs/ecology/eco_vis2_2_aggregate_effect_model.gd")
const PairSet = preload("res://scripts/labs/ecology/eco_vis2_2_replicate_pair_set.gd")
const PairTraceAdapter = preload("res://scripts/labs/ecology/eco_vis2_2_pair_trace_adapter.gd")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const VIS20Scene = preload("res://scenes/labs/ecology/eco_vis2_0_evolution_experiment_lab.tscn")

const SYNTH_FORK := 10
const REAL_FORK := 20
const REAL_TARGET := 36
const REAL_REBRANCH_TARGET := 50
const REPLICATES := 4

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_aggregate_window_and_floor()
	if _failures > 0:
		_finish()
		return
	await _test_real_pair_set_with_canonical_adapter()
	_finish()


func _test_aggregate_window_and_floor() -> void:
	var bounded := AggregateModel.new()
	_require_result(bounded.configure(SYNTH_FORK, REPLICATES), "bounded aggregate configures")
	for generation in range(SYNTH_FORK, SYNTH_FORK + 71):
		var append_result := bounded.append_generation(_synthetic_pairs(generation, generation % 2 == 0))
		_require_result(append_result, "bounded aggregate append G%d" % generation)
		if _failures > 0:
			return
	_check(bounded.point_count() == AggregateModel.SERIES_WINDOW, "aggregate history is exactly bounded to 64")
	_check(bounded.oldest_generation() == SYNTH_FORK + 7, "aggregate rolling eviction advances oldest generation")
	_check(bounded.latest_generation() == SYNTH_FORK + 70, "aggregate rolling eviction retains latest generation")
	var before_invalid := bounded.points()
	var hash_before_invalid := bounded.series_hash()
	var invalid := bounded.truncate_after(bounded.oldest_generation() - 1)
	_check(not bool(invalid.get("success", true)), "truncate below aggregate floor is rejected")
	_check(String(invalid.get("reason", "")) == "GENERATION_BEFORE_AGGREGATE_CACHE", "truncate below floor reports exact reason")
	_check(bounded.points() == before_invalid, "invalid truncate cannot mutate aggregate points")
	_check(bounded.series_hash() == hash_before_invalid, "invalid truncate cannot mutate aggregate hash")
	var floor := bounded.oldest_generation()
	_require_result(bounded.truncate_after(floor), "truncate at aggregate floor succeeds")
	_check(bounded.point_count() == 1 and bounded.latest_generation() == floor, "truncate at floor retains exact floor point")


func _test_real_pair_set_with_canonical_adapter() -> void:
	var scene = VIS20Scene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	scene.set_realtime_turnover_generation(REAL_FORK)
	await process_frame

	var source = scene.get("_vis18r_model") as RefCounted
	_require(source != null, "real source model available")
	if source == null:
		return
	var fork_map: Dictionary = Dictionary(source.call("generation_map", REAL_FORK)).duplicate(true)
	var fork_history: Array = scene.get_continuous_history().duplicate(true)
	var fork_before := fork_map.duplicate(true)
	var canonical_before: Dictionary = scene.get_spatial_snapshot().duplicate(true)

	var pair_set = PairSet.new()
	pair_set.name = "VIS22BR2PairSet"
	get_root().add_child(pair_set)
	var configured: Dictionary = pair_set.configure_from_fork(
		REAL_FORK,
		fork_map,
		fork_history,
		REPLICATES,
		ExperimentModel.PROFILE_DROUGHT,
		1.0
	)
	_require_result(configured, "real pair set configures")
	if _failures > 0:
		_cleanup(pair_set, scene)
		return
	var roots_before: Array[String] = pair_set.replicate_roots()

	# Negative control for the original B defect: the raw Treatment fork trace is
	# inherited source history, not the canonical VIS2.1 TREATMENT trace contract.
	var raw_treatment_fork: Dictionary = pair_set.treatment_trace_point(0, REAL_FORK)
	_check(String(raw_treatment_fork.get("branch_id", "")) != "TREATMENT", "raw Treatment fork trace is intentionally non-canonical")

	var fork_inputs_result := PairTraceAdapter.build_generation_inputs(
		pair_set,
		REAL_FORK,
		ExperimentModel.PROFILE_DROUGHT
	)
	_require_result(fork_inputs_result, "canonical adapter builds fork inputs")
	if _failures > 0:
		_cleanup(pair_set, scene)
		return
	var fork_inputs: Array = fork_inputs_result.get("pairs", [])
	_check(fork_inputs.size() == REPLICATES, "canonical adapter returns every replicate")
	for pair_variant in fork_inputs:
		var pair: Dictionary = pair_variant
		var control: Dictionary = pair.get("control", {})
		var treatment: Dictionary = pair.get("treatment", {})
		_check(String(control.get("branch_id", "")) == "CONTROL", "canonical fork Control branch")
		_check(String(treatment.get("branch_id", "")) == "TREATMENT", "canonical fork Treatment branch")
		_check(String(treatment.get("experiment_id", "")) == ExperimentModel.PROFILE_BASELINE, "fork Treatment is BASELINE")
		_check(String(control.get("field_hash", "")) == String(treatment.get("field_hash", "")), "fork field hashes equal")
		_check(String(control.get("environment_revision", "")) == String(treatment.get("environment_revision", "")), "fork environment revisions equal")

	var aggregate := AggregateModel.new()
	_require_result(aggregate.configure(REAL_FORK, REPLICATES), "aggregate configures")
	_require_result(aggregate.append_generation(fork_inputs), "canonical fork aggregate appends")
	if _failures > 0:
		_cleanup(pair_set, scene)
		return

	for generation in range(REAL_FORK + 1, REAL_TARGET + 1):
		_require_result(pair_set.advance_to(generation), "pair set advances G%d" % generation)
		if _failures > 0:
			break
		var inputs_result := PairTraceAdapter.build_generation_inputs(pair_set, generation, ExperimentModel.PROFILE_DROUGHT)
		_require_result(inputs_result, "canonical adapter G%d" % generation)
		if _failures > 0:
			break
		_require_result(aggregate.append_generation(inputs_result.get("pairs", [])), "aggregate appends G%d" % generation)
		if _failures > 0:
			break
	if _failures > 0:
		_cleanup(pair_set, scene)
		return

	var first_run_points := aggregate.points()
	var first_run_hash := aggregate.series_hash()
	_check(int(Dictionary(first_run_points.front()).get("generation", -1)) == REAL_FORK, "aggregate begins at fork")
	_check(int(Dictionary(first_run_points.back()).get("generation", -1)) == REAL_TARGET, "aggregate reaches target")
	_check(_all_zero_at_fork(Dictionary(first_run_points.front())), "canonical fork aggregate is zero")
	_check(_has_post_fork_effect(first_run_points), "DROUGHT produces post-fork aggregate effect")
	_check(pair_set.replicate_roots() == roots_before, "aggregation preserves replicate roots")
	_check(fork_map == fork_before and scene.get_spatial_snapshot() == canonical_before, "aggregation preserves canonical source")

	_require_result(pair_set.restart_all_from_fork(), "pair set restarts")
	if _failures > 0:
		_cleanup(pair_set, scene)
		return
	var replay := AggregateModel.new()
	_require_result(replay.configure(REAL_FORK, REPLICATES), "replay aggregate configures")
	var replay_fork := PairTraceAdapter.build_generation_inputs(pair_set, REAL_FORK, ExperimentModel.PROFILE_DROUGHT)
	_require_result(replay_fork, "replay canonical fork adapter")
	_require_result(replay.append_generation(replay_fork.get("pairs", [])), "replay fork aggregate")
	for generation in range(REAL_FORK + 1, REAL_TARGET + 1):
		_require_result(pair_set.advance_to(generation), "replay pair set G%d" % generation)
		var replay_inputs := PairTraceAdapter.build_generation_inputs(pair_set, generation, ExperimentModel.PROFILE_DROUGHT)
		_require_result(replay_inputs, "replay adapter G%d" % generation)
		_require_result(replay.append_generation(replay_inputs.get("pairs", [])), "replay aggregate G%d" % generation)
		if _failures > 0:
			break
	if _failures > 0:
		_cleanup(pair_set, scene)
		return
	_check(replay.points() == first_run_points, "restart reproduces aggregate points")
	_check(replay.series_hash() == first_run_hash, "restart reproduces aggregate hash")

	for generation in range(REAL_TARGET + 1, REAL_REBRANCH_TARGET + 1):
		_require_result(pair_set.advance_to(generation), "pre-rebranch pair set G%d" % generation)
		var inputs := PairTraceAdapter.build_generation_inputs(pair_set, generation, ExperimentModel.PROFILE_DROUGHT)
		_require_result(inputs, "pre-rebranch adapter G%d" % generation)
		_require_result(replay.append_generation(inputs.get("pairs", [])), "pre-rebranch aggregate G%d" % generation)
		if _failures > 0:
			break
	if _failures > 0:
		_cleanup(pair_set, scene)
		return

	var old_future := replay.point_at_generation(REAL_REBRANCH_TARGET)
	var control_future: Array[Dictionary] = []
	for replicate_index in range(REPLICATES):
		control_future.append(pair_set.control_generation_map(replicate_index, REAL_REBRANCH_TARGET))

	var rewind_generation := REAL_REBRANCH_TARGET - 10
	var rewind_result: Dictionary = pair_set.rewind_to_cached_generation(rewind_generation)
	_require_result(rewind_result, "cached Treatment rewind")
	_check(not bool(rewind_result.get("clamped", true)), "in-cache rewind does not clamp")
	_require_result(replay.truncate_after(rewind_generation), "aggregate truncates at rewind")
	_require_result(pair_set.set_treatment(ExperimentModel.PROFILE_FLOOD, 1.0), "Treatment rebranches to FLOOD")
	if _failures > 0:
		_cleanup(pair_set, scene)
		return

	for generation in range(rewind_generation + 1, REAL_REBRANCH_TARGET + 1):
		_require_result(pair_set.advance_to(generation), "FLOOD pair set G%d" % generation)
		var flood_inputs := PairTraceAdapter.build_generation_inputs(pair_set, generation, ExperimentModel.PROFILE_FLOOD)
		_require_result(flood_inputs, "FLOOD adapter G%d" % generation)
		_require_result(replay.append_generation(flood_inputs.get("pairs", [])), "FLOOD aggregate G%d" % generation)
		if _failures > 0:
			break
	if _failures > 0:
		_cleanup(pair_set, scene)
		return

	var new_future := replay.point_at_generation(REAL_REBRANCH_TARGET)
	_check(String(new_future.get("point_hash", "")) != String(old_future.get("point_hash", "")), "Treatment rebranch changes future aggregate identity")
	_check(String(new_future.get("treatment_experiment_id", "")) == ExperimentModel.PROFILE_FLOOD, "aggregate reports FLOOD")
	for replicate_index in range(REPLICATES):
		_check(pair_set.control_generation_map(replicate_index, REAL_REBRANCH_TARGET) == control_future[replicate_index], "Control future preserved R%d" % replicate_index)
	_check(pair_set.replicate_roots() == roots_before, "rebranch preserves roots")
	_check(fork_map == fork_before and scene.get_spatial_snapshot() == canonical_before, "rebranch preserves canonical source")

	_cleanup(pair_set, scene)
	await process_frame
	await process_frame


func _synthetic_pairs(generation: int, reverse_order: bool) -> Array[Dictionary]:
	var population_deltas := [-4, 0, 2, 6]
	var fitness_deltas := [-0.2, -0.1, 0.1, 0.4]
	var indices := [0, 1, 2, 3]
	if reverse_order:
		indices.reverse()
	var result: Array[Dictionary] = []
	for index_variant in indices:
		var replicate_index := int(index_variant)
		var at_fork := generation == SYNTH_FORK
		var control_population := 20 + replicate_index
		var population_delta := 0 if at_fork else int(population_deltas[replicate_index])
		var control_fitness := 0.4 + 0.05 * float(replicate_index)
		var fitness_delta := 0.0 if at_fork else float(fitness_deltas[replicate_index])
		var common_field := ("fork|R%d" % replicate_index).sha256_text()
		var control_field := common_field if at_fork else ("control|G%d|R%d" % [generation, replicate_index]).sha256_text()
		var treatment_field := common_field if at_fork else ("treatment|G%d|R%d" % [generation, replicate_index]).sha256_text()
		result.append({
			"replicate_index": replicate_index,
			"root": ("VIS22BR2|root=%d" % replicate_index).sha256_text(),
			"control": _trace_point(generation, "CONTROL", ExperimentModel.PROFILE_BASELINE, control_population, control_fitness, control_field, "ENV-BASE"),
			"treatment": _trace_point(generation, "TREATMENT", ExperimentModel.PROFILE_BASELINE if at_fork else ExperimentModel.PROFILE_DROUGHT, control_population + population_delta, control_fitness + fitness_delta, treatment_field, "ENV-BASE" if at_fork else "ENV-DROUGHT"),
		})
	return result


func _trace_point(generation: int, branch_id: String, experiment_id: String, population: int, fitness: float, field_hash: String, environment_revision: String) -> Dictionary:
	return {
		"generation": generation,
		"branch_id": branch_id,
		"experiment_id": experiment_id,
		"visual_count": population,
		"birth_count": 3,
		"death_count": 2,
		"survivor_count": population,
		"mean_fitness": fitness,
		"unique_genomes": population,
		"alpha_count": int(population / 2),
		"beta_count": population - int(population / 2),
		"represented_biomass_kg": 11.0,
		"field_hash": field_hash,
		"environment_revision": environment_revision,
	}


func _cleanup(pair_set: Node, scene: Node) -> void:
	if is_instance_valid(pair_set):
		pair_set.free()
	if is_instance_valid(scene):
		scene.queue_free()


func _all_zero_at_fork(point: Dictionary) -> bool:
	return (
		absf(float(point.get("mean_population_delta", 1.0))) <= 0.0000001
		and absf(float(point.get("mean_fitness_delta", 1.0))) <= 0.0000001
		and int(point.get("population_zero_count", 0)) == REPLICATES
		and int(point.get("fitness_zero_count", 0)) == REPLICATES
	)


func _has_post_fork_effect(points: Array[Dictionary]) -> bool:
	for point in points:
		if int(point.get("generation", -1)) <= REAL_FORK:
			continue
		if absf(float(point.get("mean_population_delta", 0.0))) > 0.000001:
			return true
		if absf(float(point.get("mean_fitness_delta", 0.0))) > 0.000001:
			return true
	return false


func _require_result(result: Dictionary, label: String) -> void:
	var success := bool(result.get("success", false))
	_check(success, "%s%s" % [label, "" if success else " -> %s" % var_to_str(result)])
	if not success:
		quit(1)


func _require(condition: bool, label: String) -> void:
	_check(condition, label)
	if not condition:
		quit(1)


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	push_error("ECO.VIS2.2-B R2 assertion failed: %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS2.2-B R2 canonical aggregate effect model: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		push_error("ECO.VIS2.2-B R2 canonical aggregate effect model: FAIL (%d failures / %d assertions)" % [_failures, _assertions])
		quit(1)
