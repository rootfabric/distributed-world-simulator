extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Profiler = preload("res://scripts/ecology/perf/eco_evo7_perf23_simulation_scaling_profiler_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var head := OS.get_environment("ECO_PERF2_TARGET_HEAD").strip_edges()
	var tree := OS.get_environment("ECO_PERF2_TARGET_TREE").strip_edges()
	var host := OS.get_environment("ECO_PERF2_HOST_FINGERPRINT").strip_edges()
	_check(_is_git_sha(head), "runner provides exact PERF2.3 target HEAD")
	_check(_is_git_sha(tree), "runner provides exact PERF2.3 target TREE")
	_check(_is_hash(host), "runner provides exact host fingerprint")
	if not failures.is_empty():
		_finish()
		return

	_check(Contract.REVISION == "ECO.EVO7-PERF2.0-R1", "PERF2.0 measurement contract remains frozen")
	_check(Profiler.ACCEPTED_PERF22_HEAD == "c6bef3d6c20d7b468f88f9aaabade2fe809b63e6", "PERF2.3 binds accepted PERF2.2 exact runtime head")
	_check(Profiler.ACCEPTED_PERF22_TREE == "57d4807095e1e1096a13b665b1ef1a1a90d5dc98", "PERF2.3 binds accepted PERF2.2 exact runtime tree")
	_check(Profiler.PRECONDITION_GENERATIONS == [2, 12, 22], "scaling axis uses frozen generation-age points 2/12/22")
	_check(Profiler.MEASURED_GENERATIONS == 12, "every scaling point measures 12 generations")
	_check(Profiler.REPETITIONS == 3, "every scaling point uses three repetitions")
	_check(Profiler.STREAM_CHUNK_SIZES == [1, 7, 64], "scaling matrix retains chunks 1/7/64")
	_check(Profiler.TOTAL_GENERATION_ADVANCES == 864, "full PERF2.3 campaign has frozen 864 generation advances")

	var profiler = Profiler.new()
	var context := {
		"planet_source_kind": "PROCEDURAL_EARTH_WORLD",
		"world_seed": Workbench.DEFAULT_WORLD_SEED,
		"environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
		"environment_recipe": Profiler.DEFAULT_RECIPE,
		"competition_enabled": true,
		"grid_size": Workbench.GRID_SIZE,
		"cell_size_m": Workbench.CELL_SIZE_M,
	}
	var context_hash: String = profiler.campaign_context_hash(context)
	_check(_is_hash(context_hash), "PERF2.3 campaign context has deterministic hash")

	var parsed_context_value = JSON.parse_string(JSON.stringify(context))
	_check(parsed_context_value is Dictionary, "PERF2.3 campaign context survives JSON parse")
	if parsed_context_value is Dictionary:
		_check(profiler.campaign_context_hash(Dictionary(parsed_context_value)) == context_hash, "campaign context identity survives JSON numeric coercion")

	var target := {
		"head": head,
		"tree": tree,
		"godot_version": Contract.EXPECTED_GODOT,
	}

	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth source initializes for PERF2.3")

	var report: Dictionary = profiler.run_campaign(world, target, host)
	_check(not report.is_empty(), "PERF2.3 full scaling campaign completes")
	if report.is_empty():
		world.queue_free()
		_finish()
		return

	_check(profiler.validate_report(report), "PERF2.3 report validates")
	_check(String(report.get("schema", "")) == Profiler.SCHEMA, "report uses PERF2.3 scaling schema")
	_check(String(report.get("revision", "")) == Profiler.REVISION, "report uses PERF2.3 R1 revision")
	_check(String(Dictionary(report.get("target", {})).get("head", "")) == head, "report binds exact target HEAD")
	_check(String(Dictionary(report.get("target", {})).get("tree", "")) == tree, "report binds exact target TREE")
	_check(String(report.get("host_fingerprint", "")) == host, "report binds host fingerprint")
	_check(String(report.get("campaign_context_hash", "")) == context_hash, "report binds exact campaign context")
	_check(_all_authorities_safe(Dictionary(report.get("authorities", {}))), "PERF2.3 remains measurement-only")

	var policy: Dictionary = Dictionary(report.get("scale_policy", {}))
	_check(String(policy.get("kind", "")) == "GENERATION_AGE_PRECONDITION", "scale policy explicitly uses generation-age preconditioning")
	_check(Array(policy.get("precondition_generations", [])) == [2, 12, 22], "scale policy carries exact precondition points")
	_check(int(policy.get("measured_generations", 0)) == 12, "scale policy carries 12 measured generations")
	_check(int(policy.get("repetitions", 0)) == 3, "scale policy carries three repetitions")
	_check(int(policy.get("total_samples", 0)) == 36, "scale policy carries 36 samples")
	_check(int(policy.get("total_generation_advances", 0)) == 864, "scale policy carries 864 generation advances")
	_check(String(policy.get("audit_alignment", "")) == "ONE_INTERVAL_AUDIT_PER_MEASURED_WINDOW", "scale policy locks audit alignment")
	_check(String(policy.get("load_axis_claim", "")) == "OBSERVED_GENERATION_AGED_POPULATION_NOT_SYNTHETIC_INITIAL_LOAD", "scale axis is not mislabeled as synthetic initial load")

	var samples: Array = Array(report.get("samples", []))
	_check(samples.size() == 36, "report contains 36 scaling samples")
	var groups := {}
	var total_stream_samples := 0
	for value in samples:
		var sample: Dictionary = value
		_check(bool(Contract.validate_sample(sample).get("success", false)), "in-memory scaling sample satisfies frozen PERF2.0 contract")
		_check(bool(sample.get("passed", false)), "scaling sample is passing")
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		var workload: Dictionary = Dictionary(sample.get("workload", {}))
		var scale_id := String(flags.get("scale_id", ""))
		var configuration_id := String(flags.get("configuration_id", ""))
		_check(scale_id in Profiler.SCALE_IDS, "sample scale id recognized")
		_check(configuration_id in Profiler.EXECUTION_CONFIG_IDS, "sample configuration recognized")
		var key := "%s|%s" % [scale_id, configuration_id]
		if not groups.has(key):
			groups[key] = []
		var group: Array = groups[key]
		group.append(sample)
		groups[key] = group

		var scale_index := Profiler.SCALE_IDS.find(scale_id)
		if scale_index >= 0:
			var precondition := Profiler.PRECONDITION_GENERATIONS[scale_index]
			_check(int(workload.get("warmup_generations", -1)) == precondition, "sample workload binds scale precondition")
			_check(int(flags.get("precondition_generations", -1)) == precondition, "sample flags bind scale precondition")
			_check(int(flags.get("measurement_start_generation", -1)) == precondition + 1, "measurement window start is exact")
			_check(int(flags.get("measurement_end_generation", -1)) == precondition + 12, "measurement window end is exact")
			_check(int(flags.get("expected_interval_audit_generation", -1)) == [10, 20, 30][scale_index], "each scale window binds one aligned audit generation")

		var metrics: Dictionary = Dictionary(sample.get("metrics", {}))
		var counts: Dictionary = Dictionary(metrics.get("counts", {}))
		_check(int(counts.get("generation", -1)) == int(workload.get("warmup_generations", 0)) + 12, "sample ends after precondition + measured window")
		_check(int(counts.get("population", -1)) > 0, "sample population remains positive")
		_check(int(counts.get("parent_count", -1)) > 0, "sample final parent load positive")
		_check(int(counts.get("candidate_count", -1)) > 0, "sample final candidate load positive")

		var stream: Dictionary = Dictionary(metrics.get("stream", {}))
		if String(workload.get("execution_mode", "")) == "STREAM1":
			total_stream_samples += 1
			var chunk_size := int(flags.get("stream_chunk_size", 0))
			_check(chunk_size in [1, 7, 64], "STREAM1 sample carries frozen chunk size")
			_check(int(stream.get("stream_calls", -1)) == 12, "STREAM1 measured window has exactly 12 stream calls")
			_check(int(stream.get("serial_audit_calls", -1)) == 1, "STREAM1 measured window has exactly one serial audit")
			_check(int(stream.get("oracle_elided_generations", -1)) == 11, "STREAM1 measured window elides oracle on 11 generations")
			_check(int(counts.get("max_parent_chunk", 0)) <= chunk_size, "STREAM1 parent pressure remains bounded")
			_check(int(counts.get("max_candidate_chunk", 0)) <= chunk_size * 2, "STREAM1 candidate pressure remains bounded")
		else:
			_check(int(stream.get("stream_calls", -1)) == 0, "serial sample has zero stream calls")
			_check(int(counts.get("max_parent_chunk", 0)) >= int(counts.get("parent_count", 0)), "serial parent pressure remains monolithic")
			_check(int(counts.get("max_candidate_chunk", 0)) >= int(counts.get("candidate_count", 0)), "serial candidate pressure remains monolithic")

	_check(groups.size() == 12, "campaign has 12 scale/config groups")
	for key in groups.keys():
		_check(Array(groups[key]).size() == 3, "every scale/config group has three repetitions: %s" % key)
	_check(total_stream_samples == 27, "campaign contains 27 STREAM1 samples")

	var exact_pairs := 0
	for scale_id in Profiler.SCALE_IDS:
		for repetition in range(3):
			var serial := _sample_for(samples, scale_id, "SERIAL_REFERENCE", 0, repetition)
			for chunk_size in [1, 7, 64]:
				var streamed := _sample_for(samples, scale_id, "STREAM1", chunk_size, repetition)
				_check(not serial.is_empty() and not streamed.is_empty(), "serial↔chunk sample pair exists")
				if serial.is_empty() or streamed.is_empty():
					continue
				var parity := Contract.can_compare_execution_modes(serial, streamed)
				_check(bool(parity.get("success", false)), "scaling serial↔STREAM1 pair has exact canonical parity")
				if bool(parity.get("success", false)):
					exact_pairs += 1
	_check(exact_pairs == 27, "PERF2.3 preserves 27/27 exact canonical pairs")
	print("PERF2.3 cross-scale exact result pairs: %d/27" % exact_pairs)

	var points: Array = Array(report.get("scaling_points", []))
	_check(points.size() == 12, "report emits 12 scaling points")
	for value in points:
		var point: Dictionary = value
		_check(String(point.get("scale_id", "")) in Profiler.SCALE_IDS, "scaling point scale recognized")
		_check(String(point.get("configuration_id", "")) in Profiler.EXECUTION_CONFIG_IDS, "scaling point configuration recognized")
		_check(int(point.get("repetitions", 0)) == 3, "scaling point summarizes three repetitions")
		_check(bool(point.get("structural_bound_proven", false)), "scaling point structural bound proven")
		_check(String(point.get("allocator_memory_claim", "")) == "DIAGNOSTIC_ONLY", "allocator memory remains diagnostic-only")
		for key in [
			"wall_ms", "generation_total_ms", "final_population", "final_parent_count",
			"final_candidate_count", "record_proxy_upper_bound", "engine_static_end_bytes",
		]:
			_check(_summary_valid(Dictionary(point.get(key, {}))), "scaling point summary valid: %s" % key)

	var comparisons: Array = Array(report.get("comparisons", []))
	_check(comparisons.size() == 9, "report emits nine scale/chunk comparisons")
	var comparison_pairs := 0
	for value in comparisons:
		var comparison: Dictionary = value
		var scale_id := String(comparison.get("scale_id", ""))
		var chunk_size := int(comparison.get("stream_chunk_size", 0))
		_check(scale_id in Profiler.SCALE_IDS, "comparison scale recognized")
		_check(chunk_size in [1, 7, 64], "comparison chunk recognized")
		_check(int(comparison.get("exact_pairs", 0)) == 3, "comparison binds 3/3 exact pairs")
		comparison_pairs += int(comparison.get("exact_pairs", 0))
		_check(_finite_positive(comparison.get("observed_wall_ratio_serial_over_stream")), "wall ratio finite/positive")
		_check(_finite_positive(comparison.get("observed_generation_ratio_serial_over_stream")), "generation ratio finite/positive")
		_check(_finite_positive(comparison.get("record_proxy_reduction_factor_serial_over_stream")), "record proxy reduction finite/positive")
		_check(float(comparison.get("record_proxy_reduction_factor_serial_over_stream", 0.0)) >= 1.0, "STREAM1 structural proxy does not exceed serial")
		_check(is_equal_approx(float(comparison.get("serial_parent_p50", 0.0)), float(comparison.get("stream_parent_p50", -1.0))), "serial/stream final parent load identical")
		_check(is_equal_approx(float(comparison.get("serial_candidate_p50", 0.0)), float(comparison.get("stream_candidate_p50", -1.0))), "serial/stream final candidate load identical")
		_check(String(comparison.get("observed_faster_side", "")) in ["SERIAL_REFERENCE", "STREAM1", "EQUAL"], "comparison faster-side classification recognized")
		_check(not bool(comparison.get("crossover_claim", true)), "comparison does not promote ratio to crossover claim")
		_check(not bool(comparison.get("optimization_claim", true)), "comparison does not promote ratio to optimization")
		print("PERF2.3 PROFILE scale=%s chunk=%d population=%.0f wall_ratio=%.6f proxy_reduction=%.6f faster=%s" % [
			scale_id,
			chunk_size,
			float(comparison.get("serial_parent_p50", 0.0)),
			float(comparison.get("observed_wall_ratio_serial_over_stream", 0.0)),
			float(comparison.get("record_proxy_reduction_factor_serial_over_stream", 0.0)),
			String(comparison.get("observed_faster_side", "")),
		])
	_check(comparison_pairs == 27, "comparison rows preserve 27/27 exact pairs")

	var trends: Array = Array(report.get("trends", []))
	_check(trends.size() == 4, "report emits four configuration scaling trends")
	for value in trends:
		var trend: Dictionary = value
		_check(String(trend.get("configuration_id", "")) in Profiler.EXECUTION_CONFIG_IDS, "trend configuration recognized")
		_check(_finite_positive(trend.get("population_growth_factor")), "population growth factor finite/positive")
		_check(_finite_positive(trend.get("wall_growth_factor")), "wall growth factor finite/positive")
		_check(_finite_positive(trend.get("generation_time_growth_factor")), "generation-time growth finite/positive")
		_check(_finite_positive(trend.get("record_proxy_growth_factor")), "record proxy growth finite/positive")
		_check(String(trend.get("scaling_observation", "")) == "HOST_LOCAL_DIAGNOSTIC", "trend remains host-local diagnostic")
		_check(not bool(trend.get("optimization_claim", true)), "trend makes no optimization claim")
		print("PERF2.3 TREND config=%s population_growth=%.6f wall_growth=%.6f generation_growth=%.6f proxy_growth=%.6f" % [
			String(trend.get("configuration_id", "")),
			float(trend.get("population_growth_factor", 0.0)),
			float(trend.get("wall_growth_factor", 0.0)),
			float(trend.get("generation_time_growth_factor", 0.0)),
			float(trend.get("record_proxy_growth_factor", 0.0)),
		])

	var crossovers: Array = Array(report.get("crossovers", []))
	_check(crossovers.size() == 3, "report emits one crossover analysis per chunk size")
	for value in crossovers:
		var crossover: Dictionary = value
		_check(int(crossover.get("stream_chunk_size", 0)) in [1, 7, 64], "crossover chunk recognized")
		_check(Array(crossover.get("wall_ratios_serial_over_stream", [])).size() == 3, "crossover analysis has three scale ratios")
		_check(Array(crossover.get("observed_faster_sides", [])).size() == 3, "crossover analysis has three faster-side classifications")
		_check(String(crossover.get("classification", "")) == "HOST_LOCAL_DIAGNOSTIC_ONLY", "crossover classification is host-local only")
		_check(not bool(crossover.get("optimization_claim", true)), "crossover analysis makes no optimization claim")
		print("PERF2.3 CROSSOVER chunk=%d observed=%s transition=%s ratios=%s" % [
			int(crossover.get("stream_chunk_size", 0)),
			str(bool(crossover.get("crossover_observed", false))),
			String(crossover.get("first_observed_transition", "")),
			str(Array(crossover.get("wall_ratios_serial_over_stream", []))),
		])

	var claims: Dictionary = Dictionary(report.get("claims", {}))
	_check(bool(claims.get("simulation_scaling_observation", false)), "simulation scaling observation is enabled")
	_check(String(claims.get("crossover_observation", "")) == "HOST_LOCAL_DIAGNOSTIC_ONLY", "crossover observation is diagnostic-only")
	_check(not bool(claims.get("memory_reduction_claim", true)), "PERF2.3 makes no memory-reduction claim")
	_check(not bool(claims.get("optimization_claim", true)), "PERF2.3 makes no optimization claim")

	var report_path := "res://artifacts/perf2/perf2-3-simulation-scaling-r1.json"
	_check(profiler.write_report(report, report_path), "machine-local PERF2.3 report writes successfully")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	_check(parsed is Dictionary, "written PERF2.3 report parses as JSON")
	if parsed is Dictionary:
		var parsed_report: Dictionary = Dictionary(parsed)
		_check(String(parsed_report.get("report_hash", "")) == String(report.get("report_hash", "")), "written PERF2.3 artifact preserves stored report hash")
		_check(profiler.report_hash(parsed_report) == String(report.get("report_hash", "")), "PERF2.3 report hash survives JSON numeric round-trip")
		_check(profiler.validate_report(parsed_report), "written PERF2.3 artifact round-trips through full validation")

		var tampered: Dictionary = parsed_report.duplicate(true)
		var tampered_comparisons: Array = Array(tampered["comparisons"])
		var first: Dictionary = Dictionary(tampered_comparisons[0])
		first["observed_wall_ratio_serial_over_stream"] = float(first["observed_wall_ratio_serial_over_stream"]) + 0.001
		tampered_comparisons[0] = first
		tampered["comparisons"] = tampered_comparisons
		_check(not profiler.validate_report(tampered), "scaling evidence tamper fails closed")

	_source_guards()
	world.queue_free()
	_finish()


func _sample_for(samples: Array, scale_id: String, execution_mode: String, chunk_size: int, repetition: int) -> Dictionary:
	var suffix := "-r%d" % repetition
	for value in samples:
		var sample: Dictionary = value
		var workload: Dictionary = Dictionary(sample.get("workload", {}))
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		if String(flags.get("scale_id", "")) != scale_id:
			continue
		if String(workload.get("execution_mode", "")) != execution_mode:
			continue
		if execution_mode == "STREAM1" and int(flags.get("stream_chunk_size", -1)) != chunk_size:
			continue
		if String(sample.get("run_id", "")).ends_with(suffix):
			return sample
	return {}


func _all_authorities_safe(authorities: Dictionary) -> bool:
	return (
		authorities == Profiler.AUTHORITIES
		and not bool(authorities.get("canonical", true))
		and not bool(authorities.get("world_write", true))
		and not bool(authorities.get("ecology_truth_write", true))
		and not bool(authorities.get("generation_commit", true))
		and bool(authorities.get("measurement_only", false))
		and bool(authorities.get("side_channel_only", false))
	)


func _source_guards() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_perf23_simulation_scaling_profiler_v1.gd")
	var lower := source.to_lower()
	_check(source.count(".advance_generations(") == 2, "PERF2.3 executes ecology only through public Workbench advance facade")
	_check(source.count("set_generation_stream_executor(") == 1, "PERF2.3 uses exactly one accepted STREAM1 public seam")
	_check(not lower.contains(".core") and not lower.contains("core.") and not lower.contains("records ="), "PERF2.3 owns no private ecology mutation path")
	_check(not lower.contains("reproduce_bundle(") and not lower.contains("mutation_seed(") and not lower.contains("dispersal_seed("), "PERF2.3 owns no biology identity")
	_check(not lower.contains("set_recruitment_executor(") and not lower.contains("set_candidate_executor("), "PERF2.3 cannot swap accepted stage backends")
	_check(source.contains("PRECONDITION_GENERATIONS: Array[int] = [2, 12, 22]"), "PERF2.3 scale axis is source-frozen")
	_check(source.contains("TOTAL_GENERATION_ADVANCES := 864"), "PERF2.3 campaign size is source-frozen")
	_check(source.contains('"crossover_observation": "HOST_LOCAL_DIAGNOSTIC_ONLY"'), "PERF2.3 crossover evidence is explicitly host-local")
	_check(source.contains('"optimization_claim": false'), "PERF2.3 source contains no accepted optimization claim")
	var workbench_source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd").to_lower()
	_check(not workbench_source.contains("perf2.3") and not workbench_source.contains("perf23"), "PERF2.3 fields do not enter accepted Workbench runtime")


func _summary_valid(summary: Dictionary) -> bool:
	if summary.size() != 6:
		return false
	if int(summary.get("count", 0)) != 3:
		return false
	for key in ["p50", "p95", "mean", "min", "max"]:
		if not _finite_nonnegative(summary.get(key)):
			return false
	return (
		float(summary.get("min", 0.0)) <= float(summary.get("p50", 0.0))
		and float(summary.get("p50", 0.0)) <= float(summary.get("p95", 0.0))
		and float(summary.get("p95", 0.0)) <= float(summary.get("max", 0.0)) + 1e-9
	)


func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


func _finite_positive(value) -> bool:
	return _finite_nonnegative(value) and float(value) > 0.0


func _is_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


func _is_git_sha(value: String) -> bool:
	if value.length() != 40:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("PERF2.3 CHECK FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 PERF2.3 Simulation Scaling R1: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PERF2.3 FAIL: %s" % failure)
	print("ECO.EVO7 PERF2.3 Simulation Scaling R1: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)
