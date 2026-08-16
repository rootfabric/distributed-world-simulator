extends SceneTree

const AggregateModel = preload("res://scripts/labs/ecology/eco_vis2_2_aggregate_effect_model.gd")
const PairSet = preload("res://scripts/labs/ecology/eco_vis2_2_replicate_pair_set.gd")
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
	_test_synthetic_aggregate_contract()
	if _failures > 0:
		_finish()
		return
	await _test_real_replicate_pair_set()
	_finish()


func _test_synthetic_aggregate_contract() -> void:
	var model := AggregateModel.new()
	var configured: Dictionary = model.configure(SYNTH_FORK, REPLICATES)
	_check(bool(configured.get("success", false)), "synthetic model configures")
	_check(int(configured.get("series_window", 0)) == 64, "aggregate window is 64")
	_check(int(configured.get("hash_precision_decimals", 0)) == 12, "aggregate hash precision is 12 decimals")

	var fork_pairs := _synthetic_pairs(SYNTH_FORK, false, ExperimentModel.PROFILE_DROUGHT, 0)
	var fork_append: Dictionary = model.append_generation(fork_pairs)
	_check(bool(fork_append.get("success", false)), "fork aggregate appends")
	var fork_point := model.latest_point()
	_check(int(fork_point.get("generation", -1)) == SYNTH_FORK, "fork aggregate generation")
	_check(_approx(float(fork_point.get("mean_population_delta", 99.0)), 0.0), "fork mean population delta zero")
	_check(_approx(float(fork_point.get("mean_fitness_delta", 99.0)), 0.0), "fork mean fitness delta zero")
	_check(int(fork_point.get("population_zero_count", -1)) == REPLICATES, "fork population zero count")
	_check(int(fork_point.get("fitness_zero_count", -1)) == REPLICATES, "fork fitness zero count")
	_check(String(fork_point.get("population_effect_direction", "")) == "ZERO", "fork population direction zero")
	_check(String(fork_point.get("fitness_effect_direction", "")) == "ZERO", "fork fitness direction zero")
	_check(Array(fork_point.get("replicate_identities", [])).size() == REPLICATES, "fork records all replicate identities")

	var g11_pairs := _synthetic_pairs(SYNTH_FORK + 1, true, ExperimentModel.PROFILE_DROUGHT, 0)
	var g11_append: Dictionary = model.append_generation(g11_pairs)
	_check(bool(g11_append.get("success", false)), "G11 aggregate appends from reverse replicate order")
	var g11 := model.latest_point()
	_check(_approx(float(g11.get("mean_population_delta", 0.0)), 1.0), "population mean = 1")
	_check(_approx(float(g11.get("median_population_delta", 0.0)), 1.0), "population median = 1")
	_check(int(g11.get("min_population_delta", 0)) == -4 and int(g11.get("max_population_delta", 0)) == 6, "population min/max")
	_check(int(g11.get("population_positive_count", 0)) == 2, "population positive count")
	_check(int(g11.get("population_zero_count", 0)) == 1, "population zero count")
	_check(int(g11.get("population_negative_count", 0)) == 1, "population negative count")
	_check(String(g11.get("population_effect_direction", "")) == "POSITIVE", "population dominant direction")
	_check(_approx(float(g11.get("population_consensus_fraction", 0.0)), 0.5), "population dominant fraction")
	_check(_approx(float(g11.get("mean_fitness_delta", 0.0)), 0.05), "fitness mean = 0.05")
	_check(_approx(float(g11.get("median_fitness_delta", 99.0)), 0.0), "fitness median = 0")
	_check(_approx(float(g11.get("min_fitness_delta", 0.0)), -0.2) and _approx(float(g11.get("max_fitness_delta", 0.0)), 0.4), "fitness min/max")
	_check(int(g11.get("fitness_positive_count", 0)) == 2 and int(g11.get("fitness_negative_count", 0)) == 2, "fitness sign counts")
	_check(String(g11.get("fitness_effect_direction", "")) == "MIXED", "fitness tie is MIXED")
	_check(_approx(float(g11.get("mean_unique_genomes_delta", 0.0)), 0.5), "genome mean")
	_check(_approx(float(g11.get("mean_birth_delta", 0.0)), 1.0), "birth mean")
	_check(_approx(float(g11.get("mean_death_delta", 0.0)), 0.5), "death mean")
	_check(_approx(float(g11.get("mean_survivor_delta", 0.0)), 1.0), "survivor mean")
	_check(_approx(float(g11.get("mean_represented_biomass_delta", 1.0)), 0.0), "biomass mean zero")
	_check(_approx(float(g11.get("mean_alpha_share_delta", 0.0)), 0.05), "alpha-share mean")
	var ids: Array = g11.get("replicate_identities", [])
	_check(int(Dictionary(ids[0]).get("replicate_index", -1)) == 0 and int(Dictionary(ids[-1]).get("replicate_index", -1)) == 3, "replicate identities canonicalized by numeric index")
	_check(String(Dictionary(ids[0]).get("pair_hash", "")).length() == 64, "exact paired trace identity hash recorded")
	_check(String(g11.get("point_hash", "")).length() == 64, "aggregate point hash recorded")

	var ordered_model := AggregateModel.new()
	_check(bool(ordered_model.configure(SYNTH_FORK, REPLICATES).get("success", false)), "ordered model configures")
	_check(bool(ordered_model.append_generation(_synthetic_pairs(SYNTH_FORK, false, ExperimentModel.PROFILE_DROUGHT, 0)).get("success", false)), "ordered fork appends")
	_check(bool(ordered_model.append_generation(_synthetic_pairs(SYNTH_FORK + 1, false, ExperimentModel.PROFILE_DROUGHT, 0)).get("success", false)), "ordered G11 appends")
	_check(ordered_model.points() == model.points(), "input replicate ordering cannot change aggregate output")
	_check(ordered_model.series_hash() == model.series_hash(), "input replicate ordering cannot change aggregate hash")

	var history_before_invalid := model.points()
	var duplicate_pairs: Array = _synthetic_pairs(SYNTH_FORK + 2, false, ExperimentModel.PROFILE_DROUGHT, 0)
	duplicate_pairs[3]["replicate_index"] = 2
	var duplicate_result: Dictionary = model.append_generation(duplicate_pairs)
	_check(not bool(duplicate_result.get("success", true)) and String(duplicate_result.get("reason", "")) == "DUPLICATE_REPLICATE_INDEX", "duplicate replicate index rejected")
	_check(model.points() == history_before_invalid, "invalid aggregate input cannot mutate history")
	var bad_root_pairs: Array = _synthetic_pairs(SYNTH_FORK + 2, false, ExperimentModel.PROFILE_DROUGHT, 0)
	bad_root_pairs[0]["root"] = "BAD"
	_check(String(AggregateModel.build_point(bad_root_pairs, SYNTH_FORK, REPLICATES).get("reason", "")) == "INVALID_REPLICATE_ROOT", "invalid replicate root rejected")
	var bad_branch_pairs: Array = _synthetic_pairs(SYNTH_FORK + 2, false, ExperimentModel.PROFILE_DROUGHT, 0)
	bad_branch_pairs[0]["control"]["branch_id"] = "TREATMENT"
	_check(String(AggregateModel.build_point(bad_branch_pairs, SYNTH_FORK, REPLICATES).get("reason", "")) == "INVALID_CONTROL_BRANCH", "wrong control branch rejected")
	var bad_generation_pairs: Array = _synthetic_pairs(SYNTH_FORK + 2, false, ExperimentModel.PROFILE_DROUGHT, 0)
	bad_generation_pairs[0]["treatment"]["generation"] = SYNTH_FORK + 3
	_check(String(AggregateModel.build_point(bad_generation_pairs, SYNTH_FORK, REPLICATES).get("reason", "")) == "PAIR_GENERATION_MISMATCH", "pair generation mismatch rejected")
	var mixed_experiment_pairs: Array = _synthetic_pairs(SYNTH_FORK + 2, false, ExperimentModel.PROFILE_DROUGHT, 0)
	mixed_experiment_pairs[3]["treatment"]["experiment_id"] = ExperimentModel.PROFILE_FLOOD
	_check(String(AggregateModel.build_point(mixed_experiment_pairs, SYNTH_FORK, REPLICATES).get("reason", "")) == "TREATMENT_EXPERIMENT_MISMATCH", "mixed Treatment profiles rejected")

	var bounded := AggregateModel.new()
	_check(bool(bounded.configure(SYNTH_FORK, REPLICATES).get("success", false)), "bounded model configures")
	for generation in range(SYNTH_FORK, SYNTH_FORK + 71):
		var append_result: Dictionary = bounded.append_generation(_synthetic_pairs(generation, generation % 2 == 0, ExperimentModel.PROFILE_DROUGHT, generation))
		if not bool(append_result.get("success", false)):
			_fail("bounded append G%d: %s" % [generation, String(append_result.get("reason", ""))])
			break
	_check(bounded.point_count() == AggregateModel.SERIES_WINDOW, "aggregate history bounded to 64")
	_check(bounded.oldest_generation() == SYNTH_FORK + 7, "aggregate rolling eviction is real")
	_check(bounded.latest_generation() == SYNTH_FORK + 70, "aggregate latest generation retained")
	var bounded_hash := bounded.series_hash()
	_check(bounded_hash.length() == 64, "bounded series hash")
	var bounded_points_before_invalid_truncate := bounded.points()
	var invalid_truncate: Dictionary = bounded.truncate_after(bounded.oldest_generation() - 1)
	_check(not bool(invalid_truncate.get("success", true)) and String(invalid_truncate.get("reason", "")) == "GENERATION_BEFORE_AGGREGATE_CACHE", "truncate before aggregate cache floor rejected")
	_check(bounded.points() == bounded_points_before_invalid_truncate, "invalid truncate cannot destroy bounded history")
	var truncate_result: Dictionary = bounded.truncate_after(SYNTH_FORK + 60)
	_check(bool(truncate_result.get("success", false)), "aggregate truncate_after succeeds")
	_check(bounded.latest_generation() == SYNTH_FORK + 60, "aggregate future truncated")
	_check(bounded.series_hash() != bounded_hash, "truncate changes series hash")


func _test_real_replicate_pair_set() -> void:
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
	pair_set.name = "VIS22BPairSet"
	get_root().add_child(pair_set)
	var config: Dictionary = pair_set.configure_from_fork(
		REAL_FORK,
		fork_map,
		fork_history,
		REPLICATES,
		ExperimentModel.PROFILE_DROUGHT,
		1.0
	)
	_require(bool(config.get("success", false)), "real pair set configures")
	if not bool(config.get("success", false)):
		return
	var roots_before: Array[String] = pair_set.replicate_roots()

	var aggregate := AggregateModel.new()
	_require(bool(aggregate.configure(REAL_FORK, REPLICATES).get("success", false)), "real aggregate configures")
	_require(bool(aggregate.append_generation(_pair_inputs(pair_set, REAL_FORK)).get("success", false)), "real fork aggregate appends")
	for generation in range(REAL_FORK + 1, REAL_TARGET + 1):
		_require(bool(pair_set.advance_to(generation).get("success", false)), "pair set advances G%d" % generation)
		_require(bool(aggregate.append_generation(_pair_inputs(pair_set, generation)).get("success", false)), "aggregate appends G%d" % generation)
		if _failures > 0:
			return

	var real_points := aggregate.points()
	var real_hash := aggregate.series_hash()
	_check(int(Dictionary(real_points[0]).get("generation", -1)) == REAL_FORK, "real aggregate begins at fork")
	_check(int(Dictionary(real_points[-1]).get("generation", -1)) == REAL_TARGET, "real aggregate reaches target")
	_check(_all_zero_at_fork(Dictionary(real_points[0])), "real fork aggregate deltas are zero")
	_check(_has_post_fork_effect(real_points), "real replicated Treatment produces post-fork aggregate effect")
	_check(pair_set.replicate_roots() == roots_before, "aggregation cannot mutate replicate roots")
	_check(fork_map == fork_before and scene.get_spatial_snapshot() == canonical_before, "aggregation cannot mutate canonical fork/environment")

	_require(bool(pair_set.restart_all_from_fork().get("success", false)), "real pair set restart")
	var replay := AggregateModel.new()
	_require(bool(replay.configure(REAL_FORK, REPLICATES).get("success", false)), "replay aggregate configures")
	_require(bool(replay.append_generation(_pair_inputs(pair_set, REAL_FORK)).get("success", false)), "replay fork aggregate")
	for generation in range(REAL_FORK + 1, REAL_TARGET + 1):
		_require(bool(pair_set.advance_to(generation).get("success", false)), "replay pair set G%d" % generation)
		_require(bool(replay.append_generation(_pair_inputs(pair_set, generation)).get("success", false)), "replay aggregate G%d" % generation)
		if _failures > 0:
			return
	_check(replay.points() == real_points, "real restart reproduces byte-identical aggregate points")
	_check(replay.series_hash() == real_hash, "real restart reproduces aggregate series hash")

	for generation in range(REAL_TARGET + 1, REAL_REBRANCH_TARGET + 1):
		_require(bool(pair_set.advance_to(generation).get("success", false)), "pre-rebranch pair set G%d" % generation)
		_require(bool(replay.append_generation(_pair_inputs(pair_set, generation)).get("success", false)), "pre-rebranch aggregate G%d" % generation)
		if _failures > 0:
			return
	var old_future := replay.point_at_generation(REAL_REBRANCH_TARGET)
	var control_future: Array[Dictionary] = []
	for replicate_index in range(REPLICATES):
		control_future.append(pair_set.control_trace_point(replicate_index, REAL_REBRANCH_TARGET))
	var rewind_generation := REAL_REBRANCH_TARGET - 10
	_require(bool(pair_set.rewind_to_cached_generation(rewind_generation).get("success", false)), "real pair set cached rewind")
	_require(bool(replay.truncate_after(rewind_generation).get("success", false)), "aggregate truncates with rewind")
	_require(bool(pair_set.set_treatment(ExperimentModel.PROFILE_FLOOD, 1.0).get("success", false)), "real pair set rebranches to FLOOD")
	for generation in range(rewind_generation + 1, REAL_REBRANCH_TARGET + 1):
		_require(bool(pair_set.advance_to(generation).get("success", false)), "rebranch pair set G%d" % generation)
		_require(bool(replay.append_generation(_pair_inputs(pair_set, generation)).get("success", false)), "rebranch aggregate G%d" % generation)
		if _failures > 0:
			return
	var new_future := replay.point_at_generation(REAL_REBRANCH_TARGET)
	_check(String(new_future.get("point_hash", "")) != String(old_future.get("point_hash", "")), "Treatment rebranch changes future aggregate identity")
	for replicate_index in range(REPLICATES):
		_check(pair_set.control_trace_point(replicate_index, REAL_REBRANCH_TARGET) == control_future[replicate_index], "rebranch keeps Control future R%d" % replicate_index)
	_check(pair_set.replicate_roots() == roots_before, "rebranch preserves all replicate roots")
	_check(String(new_future.get("treatment_experiment_id", "")) == ExperimentModel.PROFILE_FLOOD, "aggregate reports rebranched Treatment profile")
	_check(fork_map == fork_before and scene.get_spatial_snapshot() == canonical_before, "rebranch aggregate path leaves canonical source untouched")

	pair_set.free()
	scene.queue_free()
	await process_frame
	await process_frame


func _pair_inputs(pair_set, generation: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for replicate_index in range(pair_set.replicate_count()):
		result.append({
			"replicate_index": replicate_index,
			"root": pair_set.replicate_root(replicate_index),
			"control": pair_set.control_trace_point(replicate_index, generation),
			"treatment": pair_set.treatment_trace_point(replicate_index, generation),
		})
	return result


func _synthetic_pairs(generation: int, reverse_order: bool, profile: String, variant_shift: int) -> Array[Dictionary]:
	var population_deltas := [-4, 0, 2, 6]
	var fitness_deltas := [-0.2, -0.1, 0.1, 0.4]
	var genome_deltas := [-2, 0, 1, 3]
	var birth_deltas := [-1, 0, 2, 3]
	var death_deltas := [3, 1, 0, -2]
	var alpha_values := [4, 5, 6, 7]
	var indices := [0, 1, 2, 3]
	if reverse_order:
		indices.reverse()
	var result: Array[Dictionary] = []
	for replicate_index_variant in indices:
		var replicate_index := int(replicate_index_variant)
		var at_fork := generation == SYNTH_FORK
		var control_visual := 20 + replicate_index
		var pop_delta := 0 if at_fork else int(population_deltas[replicate_index])
		var control_fitness := 0.4 + 0.05 * float(replicate_index)
		var fitness_delta := 0.0 if at_fork else float(fitness_deltas[replicate_index])
		var control_genomes := 10 + replicate_index
		var genome_delta := 0 if at_fork else int(genome_deltas[replicate_index])
		var control_births := 3 + replicate_index
		var birth_delta := 0 if at_fork else int(birth_deltas[replicate_index])
		var control_deaths := 2 + replicate_index
		var death_delta := 0 if at_fork else int(death_deltas[replicate_index])
		var control_alpha := 5
		var treatment_alpha := control_alpha if at_fork else int(alpha_values[replicate_index])
		var common_field := ("fork|R%d" % replicate_index).sha256_text()
		var control_field := common_field if at_fork else ("control|G%d|R%d|V%d" % [generation, replicate_index, variant_shift]).sha256_text()
		var treatment_field := common_field if at_fork else ("treatment|%s|G%d|R%d|V%d" % [profile, generation, replicate_index, variant_shift]).sha256_text()
		var treatment_profile := ExperimentModel.PROFILE_BASELINE if at_fork else profile
		var control := _trace_point(
			generation, "CONTROL", ExperimentModel.PROFILE_BASELINE,
			control_visual, control_births, control_deaths, control_visual,
			control_fitness, control_genomes, control_alpha, 5, 11.0,
			control_field, "ENV-BASE"
		)
		var treatment := _trace_point(
			generation, "TREATMENT", treatment_profile,
			control_visual + pop_delta, control_births + birth_delta, control_deaths + death_delta, control_visual + pop_delta,
			control_fitness + fitness_delta, control_genomes + genome_delta, treatment_alpha, 10 - treatment_alpha, 11.0,
			treatment_field, "ENV-BASE" if at_fork else "ENV-%s-G%d" % [profile, generation]
		)
		result.append({
			"replicate_index": replicate_index,
			"root": ("VIS22B|root=%d" % replicate_index).sha256_text(),
			"control": control,
			"treatment": treatment,
		})
	return result


func _trace_point(
	generation: int,
	branch_id: String,
	experiment_id: String,
	visual_count: int,
	birth_count: int,
	death_count: int,
	survivor_count: int,
	mean_fitness: float,
	unique_genomes: int,
	alpha_count: int,
	beta_count: int,
	biomass: float,
	field_hash: String,
	environment_revision: String
) -> Dictionary:
	return {
		"generation": generation,
		"branch_id": branch_id,
		"experiment_id": experiment_id,
		"visual_count": visual_count,
		"birth_count": birth_count,
		"death_count": death_count,
		"survivor_count": survivor_count,
		"mean_fitness": mean_fitness,
		"unique_genomes": unique_genomes,
		"alpha_count": alpha_count,
		"beta_count": beta_count,
		"represented_biomass_kg": biomass,
		"field_hash": field_hash,
		"environment_revision": environment_revision,
	}


func _all_zero_at_fork(point: Dictionary) -> bool:
	return (
		_approx(float(point.get("mean_population_delta", 1.0)), 0.0)
		and _approx(float(point.get("mean_fitness_delta", 1.0)), 0.0)
		and _approx(float(point.get("mean_unique_genomes_delta", 1.0)), 0.0)
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


func _approx(actual: float, expected: float, epsilon: float = 0.0000001) -> bool:
	return absf(actual - expected) <= epsilon


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
	push_error("ECO.VIS2.2-B assertion failed: %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS2.2-B aggregate effect model: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		push_error("ECO.VIS2.2-B aggregate effect model: FAIL (%d failures / %d assertions)" % [_failures, _assertions])
		quit(1)
