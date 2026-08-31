extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const StreamExecutor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")
const CandidateKernel = preload("res://scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd")
const RouteKernel = preload("res://scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd")
const Profiler = preload("res://scripts/ecology/perf/eco_evo7_perf24_runtime_optimization_profiler_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var head := OS.get_environment("ECO_PERF2_TARGET_HEAD").strip_edges()
	var tree := OS.get_environment("ECO_PERF2_TARGET_TREE").strip_edges()
	var host := OS.get_environment("ECO_PERF2_HOST_FINGERPRINT").strip_edges()
	_check(_is_git_sha(head), "runner provides exact PERF2.4 target HEAD")
	_check(_is_git_sha(tree), "runner provides exact PERF2.4 target TREE")
	_check(_is_hash(host), "runner provides exact host fingerprint")
	if not failures.is_empty():
		_finish()
		return

	_check(Contract.REVISION == "ECO.EVO7-PERF2.0-R1", "PERF2.0 measurement contract remains frozen")
	_check(Profiler.ACCEPTED_PERF23_HEAD == "34715ac5524d594003236ca6228c0b0ba5bb9e90", "PERF2.4 binds accepted PERF2.3 tested HEAD")
	_check(Profiler.ACCEPTED_PERF23_TREE == "f97deaa1c3e8d31e1e5fc71394b7528426b1f585", "PERF2.4 binds accepted PERF2.3 tested TREE")
	_check(Profiler.TOTAL_SAMPLES == 54, "PERF2.4 A/B campaign freezes 54 samples")
	_check(Profiler.TOTAL_AB_PAIRS == 27, "PERF2.4 A/B campaign freezes 27 exact pairs")
	_check(Profiler.TOTAL_GENERATION_ADVANCES == 1296, "PERF2.4 A/B campaign freezes 1296 generation advances")
	_check(Profiler.MIN_WALL_GEOMEAN_SPEEDUP == 1.02, "wall geomean acceptance threshold frozen at 2 percent")
	_check(Profiler.MIN_STREAM_GEOMEAN_SPEEDUP == 1.03, "stream geomean acceptance threshold frozen at 3 percent")
	_check(Profiler.MIN_POINT_WALL_RATIO == 0.97, "per-point wall regression budget frozen at 3 percent")
	_check(Profiler.MIN_IMPROVED_WALL_POINTS == 6, "minimum improved wall points frozen at six of nine")

	var default_executor = StreamExecutor.new()
	_check(default_executor.setup({
		"parents_per_chunk": 7,
		"audit_interval": 10,
		"audit_generation_1": true,
	}), "default STREAM1 executor setup succeeds")
	_check(String(default_executor.get_telemetry().get("pipeline_mode", "")) == StreamExecutor.PIPELINE_OPTIMIZED, "optimized generation-boundary pipeline is the default runtime path")

	var legacy_executor = StreamExecutor.new()
	_check(legacy_executor.setup({
		"parents_per_chunk": 7,
		"audit_interval": 10,
		"audit_generation_1": true,
		"pipeline_mode": StreamExecutor.PIPELINE_LEGACY,
	}), "legacy A/B pipeline remains explicitly selectable")
	_check(String(legacy_executor.get_telemetry().get("pipeline_mode", "")) == StreamExecutor.PIPELINE_LEGACY, "legacy executor reports exact A/B mode")

	var invalid_executor = StreamExecutor.new()
	_check(not invalid_executor.setup({
		"parents_per_chunk": 7,
		"audit_interval": 10,
		"audit_generation_1": true,
		"pipeline_mode": "UNKNOWN_PIPELINE",
	}), "unknown pipeline mode fails closed")

	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth source initializes for PERF2.4")

	var target := {
		"head": head,
		"tree": tree,
		"godot_version": Contract.EXPECTED_GODOT,
	}
	var profiler = Profiler.new()
	var report: Dictionary = profiler.run_campaign(world, target, host)
	_check(not report.is_empty(), "PERF2.4 full legacy/optimized A/B campaign completes")
	if report.is_empty():
		world.queue_free()
		_finish()
		return

	_check(profiler.validate_report(report), "PERF2.4 report validates")
	_check(String(report.get("schema", "")) == Profiler.SCHEMA, "PERF2.4 report uses exact schema")
	_check(String(report.get("revision", "")) == Profiler.REVISION, "PERF2.4 report uses R1 revision")
	_check(String(Dictionary(report.get("target", {})).get("head", "")) == head, "report binds exact target HEAD")
	_check(String(Dictionary(report.get("target", {})).get("tree", "")) == tree, "report binds exact target TREE")
	_check(String(report.get("host_fingerprint", "")) == host, "report binds host fingerprint")
	_check(_authorities_safe(Dictionary(report.get("authorities", {}))), "PERF2.4 authority remains bounded to optimization measurement")

	var policy: Dictionary = Dictionary(report.get("optimization_policy", {}))
	_check(String(policy.get("baseline_pipeline", "")) == StreamExecutor.PIPELINE_LEGACY, "A/B baseline is legacy per-chunk canonicalization")
	_check(String(policy.get("candidate_pipeline", "")) == StreamExecutor.PIPELINE_OPTIMIZED, "A/B candidate is generation-boundary canonicalization")
	_check(Array(policy.get("scale_points", [])) == [2, 12, 22], "A/B scale points remain aligned with PERF2.3")
	_check(Array(policy.get("stream_chunk_sizes", [])) == [1, 7, 64], "A/B chunks remain aligned with PERF2.3")
	_check(int(policy.get("total_samples", 0)) == 54, "A/B policy records 54 samples")
	_check(int(policy.get("exact_ab_pairs_required", 0)) == 27, "A/B policy requires 27 exact pairs")
	_check(String(policy.get("balanced_order", "")) == "R0_LEGACY_FIRST__R1_OPTIMIZED_FIRST__R2_LEGACY_FIRST", "A/B execution order balances warm-cache bias")
	_check(not bool(policy.get("serial_crossover_required", true)), "PERF2.4 optimization does not require serial crossover")
	_check(bool(policy.get("canonical_parity_required", false)), "PERF2.4 requires exact canonical parity")
	_check(not bool(policy.get("bounded_working_set_regression_allowed", true)), "PERF2.4 forbids working-set regression")

	var samples: Array = Array(report.get("samples", []))
	_check(samples.size() == 54, "report contains 54 A/B samples")
	var legacy_samples := 0
	var optimized_samples := 0
	var exact_ab_pairs := 0

	for value in samples:
		var sample: Dictionary = value
		_check(bool(Contract.validate_sample(sample).get("success", false)), "A/B sample satisfies frozen PERF2.0 contract")
		_check(bool(sample.get("passed", false)), "A/B sample is passing")
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		var pipeline_mode := String(flags.get("pipeline_mode", ""))
		var chunk_size := int(flags.get("stream_chunk_size", 0))
		_check(pipeline_mode in StreamExecutor.PIPELINE_MODES, "sample pipeline mode recognized")
		_check(chunk_size in [1, 7, 64], "sample chunk size recognized")
		_check(String(flags.get("scale_id", "")) in Profiler.SCALE_IDS, "sample scale id recognized")

		var metrics: Dictionary = Dictionary(sample.get("metrics", {}))
		var counts: Dictionary = Dictionary(metrics.get("counts", {}))
		var stream: Dictionary = Dictionary(metrics.get("stream", {}))
		var operations: Dictionary = Dictionary(flags.get("optimization_operations", {}))
		_check(int(stream.get("stream_calls", -1)) == 12, "measured A/B sample has 12 STREAM1 calls")
		_check(int(stream.get("serial_audit_calls", -1)) == 1, "measured A/B sample has one audit")
		_check(int(stream.get("oracle_elided_generations", -1)) == 11, "measured A/B sample elides oracle on eleven generations")
		_check(int(counts.get("max_parent_chunk", 0)) <= chunk_size, "parent working-set bound preserved")
		_check(int(counts.get("max_candidate_chunk", 0)) <= chunk_size * 2, "candidate working-set bound preserved")
		_check(int(operations.get("generation_boundary_sorts", -1)) == 36, "every measured sample canonicalizes three full arrays per generation")

		if pipeline_mode == StreamExecutor.PIPELINE_LEGACY:
			legacy_samples += 1
			_check(int(operations.get("legacy_generation_calls", -1)) == 12, "legacy sample executes 12 legacy generations")
			_check(int(operations.get("optimized_generation_calls", -1)) == 0, "legacy sample executes zero optimized generations")
			var chunks := int(stream.get("chunks_processed", 0))
			_check(chunks > 0, "legacy sample processes positive chunk count")
			for key in [
				"chunk_local_parent_sorts", "chunk_local_candidate_sorts",
				"chunk_local_route_sorts", "chunk_local_recruitment_sorts",
				"recruitment_context_builds",
			]:
				_check(int(operations.get(key, -1)) == chunks, "legacy operation count follows chunk count: %s" % key)
		else:
			optimized_samples += 1
			_check(int(operations.get("legacy_generation_calls", -1)) == 0, "optimized sample executes zero legacy generations")
			_check(int(operations.get("optimized_generation_calls", -1)) == 12, "optimized sample executes 12 optimized generations")
			for key in [
				"chunk_local_parent_sorts", "chunk_local_candidate_sorts",
				"chunk_local_route_sorts", "chunk_local_recruitment_sorts",
			]:
				_check(int(operations.get(key, -1)) == 0, "optimized sample eliminates chunk-local sort: %s" % key)
			_check(int(operations.get("recruitment_context_builds", -1)) == 12, "optimized sample builds one recruitment context per generation")

	_check(legacy_samples == 27, "campaign contains 27 legacy samples")
	_check(optimized_samples == 27, "campaign contains 27 optimized samples")

	for scale_id in Profiler.SCALE_IDS:
		for chunk_size in [1, 7, 64]:
			for repetition in range(3):
				var legacy: Dictionary = _find_sample(samples, scale_id, chunk_size, StreamExecutor.PIPELINE_LEGACY, repetition)
				var optimized: Dictionary = _find_sample(samples, scale_id, chunk_size, StreamExecutor.PIPELINE_OPTIMIZED, repetition)
				_check(not legacy.is_empty() and not optimized.is_empty(), "matched legacy/optimized sample pair exists")
				if legacy.is_empty() or optimized.is_empty():
					continue
				var comparison := Contract.can_compare(legacy, optimized)
				_check(bool(comparison.get("success", false)), "legacy/optimized pair is exact canonical parity")
				if bool(comparison.get("success", false)):
					exact_ab_pairs += 1
				var legacy_counts: Dictionary = Dictionary(Dictionary(legacy.get("metrics", {})).get("counts", {}))
				var optimized_counts: Dictionary = Dictionary(Dictionary(optimized.get("metrics", {})).get("counts", {}))
				_check(int(legacy_counts.get("max_parent_chunk", -1)) == int(optimized_counts.get("max_parent_chunk", -2)), "A/B parent structural bound identical")
				_check(int(legacy_counts.get("max_candidate_chunk", -1)) == int(optimized_counts.get("max_candidate_chunk", -2)), "A/B candidate structural bound identical")

	_check(exact_ab_pairs == 27, "PERF2.4 preserves 27/27 exact legacy/optimized pairs")
	print("PERF2.4 exact A/B canonical pairs: %d/27" % exact_ab_pairs)

	var comparisons: Array = Array(report.get("comparisons", []))
	_check(comparisons.size() == 9, "report emits nine scale/chunk A/B comparisons")
	var improved_points := 0
	var nonregressed_points := 0
	for value in comparisons:
		var comparison: Dictionary = value
		var scale_id := String(comparison.get("scale_id", ""))
		var chunk_size := int(comparison.get("stream_chunk_size", 0))
		var wall_speedup := float(comparison.get("wall_speedup_legacy_over_optimized", 0.0))
		var stream_speedup := float(comparison.get("stream_speedup_legacy_over_optimized", 0.0))
		_check(scale_id in Profiler.SCALE_IDS, "comparison scale recognized")
		_check(chunk_size in [1, 7, 64], "comparison chunk recognized")
		_check(int(comparison.get("exact_pairs", 0)) == 3, "comparison binds 3/3 exact A/B pairs")
		_check(_finite_positive(wall_speedup), "wall A/B speedup finite/positive")
		_check(_finite_positive(stream_speedup), "stream A/B speedup finite/positive")
		_check(bool(comparison.get("bounded_working_set_preserved", false)), "comparison preserves bounded working set")
		_check(bool(comparison.get("operation_reduction_proven", false)), "comparison proves deterministic operation reduction")
		_check(float(comparison.get("optimized_chunk_local_sorts_p50", -1.0)) == 0.0, "optimized comparison has zero chunk-local sorts")
		_check(float(comparison.get("context_build_reduction_factor", 0.0)) >= 1.0, "optimized comparison never builds more recruitment contexts than legacy")
		if bool(comparison.get("wall_point_improved", false)):
			improved_points += 1
		if bool(comparison.get("wall_point_nonregressed", false)):
			nonregressed_points += 1
		print("PERF2.4 PROFILE scale=%s chunk=%d wall_speedup=%.6f stream_speedup=%.6f context_reduction=%.6f legacy_chunk_sorts=%.0f optimized_chunk_sorts=%.0f" % [
			scale_id,
			chunk_size,
			wall_speedup,
			stream_speedup,
			float(comparison.get("context_build_reduction_factor", 0.0)),
			float(comparison.get("legacy_chunk_local_sorts_p50", 0.0)),
			float(comparison.get("optimized_chunk_local_sorts_p50", 0.0)),
		])

	var summary: Dictionary = Dictionary(report.get("optimization_summary", {}))
	_check(int(summary.get("exact_pairs", 0)) == 27, "optimization summary preserves 27 exact pairs")
	_check(int(summary.get("comparison_points", 0)) == 9, "optimization summary covers nine points")
	_check(int(summary.get("improved_wall_points", 0)) == improved_points, "optimization summary improved-point count exact")
	_check(int(summary.get("nonregressed_wall_points", 0)) == nonregressed_points, "optimization summary nonregression count exact")
	_check(bool(summary.get("operation_reduction_proven", false)), "optimization summary proves operation reduction")
	_check(bool(summary.get("bounded_working_set_preserved", false)), "optimization summary preserves bounded working set")
	_check(float(summary.get("wall_geomean_speedup", 0.0)) >= Profiler.MIN_WALL_GEOMEAN_SPEEDUP, "wall geomean reaches PERF2.4 acceptance threshold")
	_check(float(summary.get("stream_geomean_speedup", 0.0)) >= Profiler.MIN_STREAM_GEOMEAN_SPEEDUP, "stream geomean reaches PERF2.4 acceptance threshold")
	_check(int(summary.get("improved_wall_points", 0)) >= Profiler.MIN_IMPROVED_WALL_POINTS, "at least six of nine wall points improve")
	_check(int(summary.get("nonregressed_wall_points", 0)) == 9, "no wall point regresses beyond three-percent budget")
	_check(bool(summary.get("optimization_claim", false)), "PERF2.4 optimization claim is earned by frozen A/B thresholds")

	print("PERF2.4 SUMMARY wall_geomean=%.6f stream_geomean=%.6f improved=%d/9 nonregressed=%d/9 optimization_claim=%s" % [
		float(summary.get("wall_geomean_speedup", 0.0)),
		float(summary.get("stream_geomean_speedup", 0.0)),
		int(summary.get("improved_wall_points", 0)),
		int(summary.get("nonregressed_wall_points", 0)),
		str(bool(summary.get("optimization_claim", false))),
	])

	var claims: Dictionary = Dictionary(report.get("claims", {}))
	_check(bool(claims.get("canonical_parity", false)), "report claims exact canonical parity only after 27/27")
	_check(bool(claims.get("bounded_working_set_preserved", false)), "report claims bounded working set preserved")
	_check(bool(claims.get("deterministic_operation_reduction", false)), "report claims deterministic operation reduction")
	_check(not bool(claims.get("serial_crossover_claim", true)), "PERF2.4 does not claim serial crossover")
	_check(bool(claims.get("optimization_claim", false)), "PERF2.4 report carries earned optimization claim")

	var report_path := "res://artifacts/perf2/perf2-4-runtime-optimization-r1.json"
	_check(profiler.write_report(report, report_path), "machine-local PERF2.4 report writes successfully")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	_check(parsed is Dictionary, "written PERF2.4 report parses as JSON")
	if parsed is Dictionary:
		var parsed_report: Dictionary = Dictionary(parsed)
		_check(String(parsed_report.get("report_hash", "")) == String(report.get("report_hash", "")), "written PERF2.4 artifact preserves stored report hash")
		_check(profiler.report_hash(parsed_report) == String(report.get("report_hash", "")), "PERF2.4 report hash survives JSON numeric round-trip")
		_check(profiler.validate_report(parsed_report), "written PERF2.4 artifact round-trips through full validation")

		var tampered: Dictionary = parsed_report.duplicate(true)
		var tampered_comparisons: Array = Array(tampered["comparisons"])
		var first: Dictionary = Dictionary(tampered_comparisons[0])
		first["wall_speedup_legacy_over_optimized"] = float(first["wall_speedup_legacy_over_optimized"]) + 0.01
		tampered_comparisons[0] = first
		tampered["comparisons"] = tampered_comparisons
		_check(not profiler.validate_report(tampered), "PERF2.4 performance evidence tamper fails closed")

	_source_guards()
	world.queue_free()
	_finish()


func _find_sample(
	samples: Array,
	scale_id: String,
	chunk_size: int,
	pipeline_mode: String,
	repetition: int
) -> Dictionary:
	var suffix := "-r%d" % repetition
	for value in samples:
		if not value is Dictionary:
			continue
		var sample: Dictionary = value
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		if String(flags.get("scale_id", "")) != scale_id:
			continue
		if int(flags.get("stream_chunk_size", 0)) != chunk_size:
			continue
		if String(flags.get("pipeline_mode", "")) != pipeline_mode:
			continue
		if String(sample.get("run_id", "")).ends_with(suffix):
			return sample
	return {}


func _source_guards() -> void:
	var executor_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")
	var candidate_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd")
	var route_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd")
	var ls33_source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd").to_lower()

	_check(executor_source.contains('const PIPELINE_OPTIMIZED := "OPTIMIZED_GENERATION_BOUNDARY_CANONICALIZATION"'), "optimized pipeline identifier source-frozen")
	_check(executor_source.contains('config.get("pipeline_mode", PIPELINE_OPTIMIZED)'), "optimized pipeline is default setup mode")
	_check(candidate_source.contains("static func build_presorted_unsorted("), "candidate kernel exposes presorted unsorted chunk seam")
	_check(route_source.contains("static func build_in_input_order("), "route kernel exposes input-order chunk seam")
	_check(executor_source.contains("_evaluate_recruitment_chunk_input_order("), "executor uses aligned recruitment chunk seam")
	_check(executor_source.contains("generation_boundary_sorts += 1"), "generation-boundary canonicalization remains explicit")
	_check(executor_source.contains("_monolithic_oracle("), "independent monolithic audit oracle remains present")
	_check(not ls33_source.contains("perf2.4") and not ls33_source.contains("perf24"), "PERF2.4 fields do not enter LS3.3 authority")
	_check(not candidate_source.to_lower().contains("time.") and not route_source.to_lower().contains("time."), "pure candidate/route kernels remain free of wall-clock identity")


func _authorities_safe(authorities: Dictionary) -> bool:
	return (
		authorities == Profiler.AUTHORITIES
		and not bool(authorities.get("canonical", true))
		and not bool(authorities.get("world_write", true))
		and not bool(authorities.get("ecology_truth_write", true))
		and not bool(authorities.get("generation_commit", true))
		and bool(authorities.get("measurement_only", false))
		and bool(authorities.get("side_channel_only", false))
		and bool(authorities.get("runtime_optimization_candidate", false))
	)


func _finite_positive(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number > 0.0


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
	push_error("PERF2.4 CHECK FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 PERF2.4 Runtime Optimization R1: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PERF2.4 FAIL: %s" % failure)
	print("ECO.EVO7 PERF2.4 Runtime Optimization R1: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)
