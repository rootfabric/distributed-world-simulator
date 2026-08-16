extends SceneTree

const PairSet = preload("res://scripts/labs/ecology/eco_vis2_2_replicate_pair_set.gd")
const ControlReplicateRunner = preload("res://scripts/labs/ecology/eco_vis2_2_control_replicate_runner.gd")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const VIS20Scene = preload("res://scenes/labs/ecology/eco_vis2_0_evolution_experiment_lab.tscn")

const FORK_GENERATION := 6
const HORIZON := 18
const EVICT_GENERATION := 74
const REPLICATE_COUNT := 4
const WINDOW := 64

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = VIS20Scene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	scene.set_realtime_turnover_generation(FORK_GENERATION)
	await process_frame

	var source_model := scene.get("_vis18r_model") as RefCounted
	_require(source_model != null, "source realtime model available")
	if source_model == null:
		return

	var fork_map: Dictionary = Dictionary(source_model.call("generation_map", FORK_GENERATION)).duplicate(true)
	var fork_history: Array = scene.get_continuous_history().duplicate(true)
	var fork_map_before := fork_map.duplicate(true)
	var fork_history_before := fork_history.duplicate(true)
	var canonical_before: Dictionary = scene.get_spatial_snapshot().duplicate(true)
	_require(not fork_map.is_empty(), "fork map captured")

	_check(PairSet.DEFAULT_REPLICATE_COUNT == 8, "default replicate count is eight")
	_check(PairSet.MIN_REPLICATE_COUNT == 2 and PairSet.MAX_REPLICATE_COUNT == 16, "replicate bounds are 2..16")
	_check(PairSet.BRANCH_CACHE_WINDOW == WINDOW, "branch cache window is 64")

	var invalid_set = PairSet.new()
	_check(not bool(invalid_set.configure_from_fork(FORK_GENERATION, fork_map, fork_history, 1).get("success", true)), "replicate count below minimum rejected")
	_check(not bool(invalid_set.configure_from_fork(FORK_GENERATION, fork_map, fork_history, 17).get("success", true)), "replicate count above maximum rejected")
	invalid_set.free()

	var invalid_control = ControlReplicateRunner.new()
	_check(not bool(invalid_control.configure_from_fork_with_root(FORK_GENERATION, fork_map, fork_history, "bad-root").get("success", true)), "control replicate rejects malformed root")

	var pairs = PairSet.new()
	pairs.name = "VIS22ReplicatePairSet"
	get_root().add_child(pairs)
	var configured: Dictionary = pairs.configure_from_fork(
		FORK_GENERATION,
		fork_map,
		fork_history,
		REPLICATE_COUNT,
		ExperimentModel.PROFILE_DROUGHT,
		1.0
	)
	_require(bool(configured.get("success", false)), "replicate pair set configures")
	if not bool(configured.get("success", false)):
		return

	_check(pairs.replicate_count() == REPLICATE_COUNT, "configured replicate count")
	_check(pairs.get_child_count() == REPLICATE_COUNT, "only Treatment Node runners are children")
	_check(fork_map == fork_map_before and fork_history == fork_history_before, "configuration does not mutate supplied fork inputs")
	_check(pairs.fork_generation() == FORK_GENERATION and pairs.current_generation() == FORK_GENERATION, "cursor starts at immutable fork")
	_check(_sha(pairs.base_fork_root()), "base fork root is SHA-256")

	var roots: Array[String] = pairs.replicate_roots()
	var unique_roots := {}
	_check(roots.size() == REPLICATE_COUNT, "one root per replicate")
	for replicate_index in range(REPLICATE_COUNT):
		var expected_root := PairSet.derive_replicate_root(FORK_GENERATION, fork_map_before, replicate_index)
		var root := pairs.replicate_root(replicate_index)
		var control = pairs.control_runner(replicate_index)
		var treatment = pairs.treatment_runner(replicate_index)
		_require(control != null and is_instance_valid(treatment), "pair %d runners exist" % replicate_index)
		if control == null or not is_instance_valid(treatment):
			return
		unique_roots[root] = true
		_check(_sha(root) and root == expected_root, "replicate %d deterministic root" % replicate_index)
		_check(control.common_random_seed_hash() == root and treatment.common_random_seed_hash() == root, "replicate %d Control/Treatment share CRN root" % replicate_index)
		_check(treatment.get_parent() == pairs and treatment.get_child_count() == 0, "replicate %d Treatment is data-only owned child" % replicate_index)
		_check(pairs.control_generation_map(replicate_index, FORK_GENERATION) == fork_map_before, "replicate %d Control fork identical" % replicate_index)
		_check(pairs.treatment_generation_map(replicate_index, FORK_GENERATION) == fork_map_before, "replicate %d Treatment fork identical" % replicate_index)
	_check(unique_roots.size() == REPLICATE_COUNT, "distinct replicate indexes have distinct deterministic roots")

	var control0 = pairs.control_runner(0)
	var treatment0 = pairs.treatment_runner(0)
	var baseline: Dictionary = control0.baseline_environment_sample_at(0.0, 0.0)
	var treatment_at_fork: Dictionary = treatment0.sample_environment_for_generation(FORK_GENERATION, 0.0, 0.0)
	var treatment_after_fork: Dictionary = treatment0.sample_environment_for_generation(FORK_GENERATION + 1, 0.0, 0.0)
	_check(String(treatment_at_fork.get("checksum", "")) == String(baseline.get("checksum", "")), "Treatment remains baseline at fork generation")
	_check(String(treatment_after_fork.get("checksum", "")) != String(baseline.get("checksum", "")), "Treatment forcing begins at fork+1")

	var advance_horizon: Dictionary = pairs.advance_to(HORIZON)
	_require(bool(advance_horizon.get("success", false)), "all replicate pairs advance to horizon")
	if not bool(advance_horizon.get("success", false)):
		return
	_check(pairs.current_generation() == HORIZON, "shared generation cursor advances")

	var diverged_pairs := 0
	for replicate_index in range(REPLICATE_COUNT):
		var root := roots[replicate_index]
		var control = pairs.control_runner(replicate_index)
		var treatment = pairs.treatment_runner(replicate_index)
		_check(control.common_random_seed_hash() == root and treatment.common_random_seed_hash() == root, "replicate %d root stable after advance" % replicate_index)
		if pairs.control_generation_map(replicate_index, HORIZON) != pairs.treatment_generation_map(replicate_index, HORIZON):
			diverged_pairs += 1
	_check(diverged_pairs > 0, "environment Treatment creates post-fork divergence in at least one replicate")

	var replay_pairs = PairSet.new()
	replay_pairs.name = "VIS22ReplayPairSet"
	get_root().add_child(replay_pairs)
	var replay_config: Dictionary = replay_pairs.configure_from_fork(
		FORK_GENERATION,
		fork_map,
		fork_history,
		REPLICATE_COUNT,
		ExperimentModel.PROFILE_DROUGHT,
		1.0
	)
	_require(bool(replay_config.get("success", false)), "second replicate set configures")
	_require(bool(replay_pairs.advance_to(HORIZON).get("success", false)), "second replicate set advances")
	_check(replay_pairs.replicate_roots() == roots, "independent replicate set derives identical root manifest")
	for replicate_index in range(REPLICATE_COUNT):
		_check(replay_pairs.control_generation_map(replicate_index, HORIZON) == pairs.control_generation_map(replicate_index, HORIZON), "replicate %d Control replay deterministic" % replicate_index)
		_check(replay_pairs.treatment_generation_map(replicate_index, HORIZON) == pairs.treatment_generation_map(replicate_index, HORIZON), "replicate %d Treatment replay deterministic" % replicate_index)
	replay_pairs.free()
	await process_frame

	var bounded: Dictionary = pairs.advance_to(EVICT_GENERATION)
	_require(bool(bounded.get("success", false)), "replicate set reaches boundedness generation")
	if not bool(bounded.get("success", false)):
		return
	var expected_floor := EVICT_GENERATION - WINDOW + 1
	_check(pairs.common_oldest_cached_generation() == expected_floor and expected_floor > FORK_GENERATION, "common cache floor advances after eviction")

	var control_at_evict: Array[Dictionary] = []
	var treatment_at_evict: Array[Dictionary] = []
	for replicate_index in range(REPLICATE_COUNT):
		var cache_state: Dictionary = pairs.pair_cache_state(replicate_index)
		_check(int(cache_state.get("control_cached_generation_count", 999)) <= WINDOW, "replicate %d Control generation cache bounded" % replicate_index)
		_check(int(cache_state.get("control_cached_trace_point_count", 999)) <= WINDOW, "replicate %d Control trace cache bounded" % replicate_index)
		_check(int(cache_state.get("treatment_cached_generation_count", 999)) <= WINDOW, "replicate %d Treatment generation cache bounded" % replicate_index)
		_check(int(cache_state.get("treatment_cached_trace_point_count", 999)) <= WINDOW, "replicate %d Treatment trace cache bounded" % replicate_index)
		_check(int(cache_state.get("control_oldest_cached_generation", -1)) == expected_floor and int(cache_state.get("treatment_oldest_cached_generation", -1)) == expected_floor, "replicate %d real rolling eviction" % replicate_index)
		_check(pairs.control_generation_map(replicate_index, FORK_GENERATION) == fork_map_before and pairs.treatment_generation_map(replicate_index, FORK_GENERATION) == fork_map_before, "replicate %d immutable fork survives eviction" % replicate_index)
		control_at_evict.append(pairs.control_generation_map(replicate_index, EVICT_GENERATION))
		treatment_at_evict.append(pairs.treatment_generation_map(replicate_index, EVICT_GENERATION))

	var rewind_generation := EVICT_GENERATION - 10
	var rewind_result: Dictionary = pairs.rewind_to_cached_generation(rewind_generation)
	_require(bool(rewind_result.get("success", false)), "Treatment replicates rewind inside common cache")
	if not bool(rewind_result.get("success", false)):
		return
	_check(pairs.current_generation() == rewind_generation, "shared cursor rewinds")
	for replicate_index in range(REPLICATE_COUNT):
		var treatment = pairs.treatment_runner(replicate_index)
		_check(not treatment.is_generation_cached(EVICT_GENERATION), "replicate %d Treatment future erased on rewind" % replicate_index)
		_check(pairs.control_generation_map(replicate_index, EVICT_GENERATION) == control_at_evict[replicate_index], "replicate %d Control future remains untouched" % replicate_index)
		_check(pairs.replicate_root(replicate_index) == roots[replicate_index], "replicate %d root stable on rewind" % replicate_index)

	var switched: Dictionary = pairs.set_treatment(ExperimentModel.PROFILE_FLOOD, 1.0)
	_require(bool(switched.get("success", false)), "all Treatment replicates rebranch from cached cursor")
	_check(int(switched.get("effective_generation", -1)) == rewind_generation + 1, "rebranch treatment starts at visible generation+1")
	_require(bool(pairs.advance_to(EVICT_GENERATION).get("success", false)), "rebranched Treatment replicates return to horizon")

	var changed_treatments := 0
	for replicate_index in range(REPLICATE_COUNT):
		_check(pairs.control_generation_map(replicate_index, EVICT_GENERATION) == control_at_evict[replicate_index], "replicate %d rebranch does not recompute Control" % replicate_index)
		if pairs.treatment_generation_map(replicate_index, EVICT_GENERATION) != treatment_at_evict[replicate_index]:
			changed_treatments += 1
		_check(pairs.replicate_root(replicate_index) == roots[replicate_index], "replicate %d root stable after rebranch" % replicate_index)
	_check(changed_treatments > 0, "rebranch changes Treatment future in at least one replicate")

	var restart_result: Dictionary = pairs.restart_all_from_fork()
	_require(bool(restart_result.get("success", false)), "all replicates restart from immutable fork")
	_require(bool(pairs.advance_to(HORIZON).get("success", false)), "restarted FLOOD replicates advance")
	var flood_control_a: Array[Dictionary] = []
	var flood_treatment_a: Array[Dictionary] = []
	for replicate_index in range(REPLICATE_COUNT):
		flood_control_a.append(pairs.control_generation_map(replicate_index, HORIZON))
		flood_treatment_a.append(pairs.treatment_generation_map(replicate_index, HORIZON))
		_check(pairs.replicate_root(replicate_index) == roots[replicate_index], "replicate %d root stable after restart" % replicate_index)

	_require(bool(pairs.restart_all_from_fork().get("success", false)), "second restart succeeds")
	_require(bool(pairs.advance_to(HORIZON).get("success", false)), "second FLOOD replay advances")
	for replicate_index in range(REPLICATE_COUNT):
		_check(pairs.control_generation_map(replicate_index, HORIZON) == flood_control_a[replicate_index], "replicate %d Control restart replay exact" % replicate_index)
		_check(pairs.treatment_generation_map(replicate_index, HORIZON) == flood_treatment_a[replicate_index], "replicate %d Treatment restart replay exact" % replicate_index)

	_check(fork_map == fork_map_before and fork_history == fork_history_before, "all operations preserve caller fork inputs")
	_check(scene.get_spatial_snapshot() == canonical_before, "replicate orchestration never mutates canonical VIS source state")

	var treatment_refs: Array = []
	for replicate_index in range(REPLICATE_COUNT):
		treatment_refs.append(pairs.treatment_runner(replicate_index))
	pairs.free()
	await process_frame
	var all_treatments_freed := true
	for treatment in treatment_refs:
		if is_instance_valid(treatment):
			all_treatments_freed = false
	_check(all_treatments_freed, "all Treatment Node runners are freed with pair-set owner")

	scene.queue_free()
	await process_frame
	if _failures == 0:
		print("ECO.VIS2.2-A replicated causal runner set: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		push_error("ECO.VIS2.2-A replicated causal runner set: FAIL (%d failures / %d assertions)" % [_failures, _assertions])
		quit(1)


func _sha(value: String) -> bool:
	if value.length() != 64:
		return false
	for byte_value in value.to_ascii_buffer():
		var is_digit := byte_value >= 48 and byte_value <= 57
		var is_lower_hex := byte_value >= 97 and byte_value <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true


func _require(condition: bool, label: String) -> void:
	_check(condition, label)
	if not condition:
		push_error("ECO.VIS2.2-A required condition failed: %s" % label)
		quit(1)


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS2.2-A assertion failed: %s" % label)
