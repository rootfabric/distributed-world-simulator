extends SceneTree

const AggregateModel = preload("res://scripts/labs/ecology/eco_vis2_2_aggregate_effect_model.gd")
const PairSet = preload("res://scripts/labs/ecology/eco_vis2_2_replicate_pair_set.gd")
const PairTraceAdapter = preload("res://scripts/labs/ecology/eco_vis2_2_pair_trace_adapter.gd")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const VIS20Scene = preload("res://scenes/labs/ecology/eco_vis2_0_evolution_experiment_lab.tscn")

const REAL_FORK := 20
const REAL_TARGET := 36
const REAL_REBRANCH_TARGET := 50
const REPLICATES := 4

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_real_pair_set_with_canonical_adapter()
	_finish()


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
	_require_result(pair_set.rewind_to_cached_generation(rewind_generation), "cached Treatment rewind")
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
