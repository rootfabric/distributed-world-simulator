extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Profiler = preload("res://scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var head := OS.get_environment("ECO_PERF2_TARGET_HEAD").strip_edges()
	var tree := OS.get_environment("ECO_PERF2_TARGET_TREE").strip_edges()
	var host := OS.get_environment("ECO_PERF2_HOST_FINGERPRINT").strip_edges()
	_check(_is_git_sha(head), "runner provides exact target HEAD")
	_check(_is_git_sha(tree), "runner provides exact target TREE")
	_check(_is_hash(host), "runner provides hashed host fingerprint")
	if not failures.is_empty():
		_finish()
		return

	var contract := Contract.load_contract()
	_check(bool(Contract.validate_contract(contract).get("success", false)), "accepted PERF2.0 contract validates")
	_check(Contract.REVISION == "ECO.EVO7-PERF2.0-R1", "PERF2.0 measurement revision remains frozen")

	var profiler = Profiler.new()
	var config := profiler.default_campaign_config()
	_check(bool(profiler.validate_campaign_config(config).get("success", false)), "default PERF2.1 R2 campaign config validates")
	_check(Array(config["recipes"]) == ["MIXED_PHYSICAL_HETEROGENEITY"], "R2 uses one frozen physical recipe")
	_check(int(config["warmup_generations"]) == 2, "R2 uses two-generation warmup")
	_check(int(config["measured_generations"]) == 12, "R2 measures twelve generations")
	_check(int(config["repetitions"]) == 3, "R2 uses three repetitions")
	_check(Array(config["stream_chunk_sizes"]) == [1, 7, 64], "R2 sweeps STREAM1 chunk sizes 1/7/64")
	_check(int(config["world_seed"]) == Workbench.DEFAULT_WORLD_SEED, "R2 binds exact Workbench world seed")
	_check(bool(config["competition_enabled"]), "R2 binds competition enabled")
	_check(int(config["grid_size"]) == Workbench.GRID_SIZE, "R2 binds exact Workbench grid size")
	_check(is_equal_approx(float(config["cell_size_m"]), Workbench.CELL_SIZE_M), "R2 binds exact Workbench cell size")

	var context := profiler.campaign_context(config)
	var context_hash := profiler.campaign_context_hash(context)
	_check(context.size() == Profiler.CONTEXT_FIELDS.size(), "campaign context has frozen exact field set")
	_check(_is_hash(context_hash), "campaign context has deterministic SHA-256 identity")

	var changed_world := config.duplicate(true)
	changed_world["world_seed"] = int(changed_world["world_seed"]) + 1
	_check(not bool(profiler.validate_campaign_config(changed_world).get("success", true)), "world-seed drift fails closed")

	var changed_competition := config.duplicate(true)
	changed_competition["competition_enabled"] = false
	_check(not bool(profiler.validate_campaign_config(changed_competition).get("success", true)), "competition-mode drift fails closed")

	var changed_chunks := config.duplicate(true)
	changed_chunks["stream_chunk_sizes"] = [64]
	_check(not bool(profiler.validate_campaign_config(changed_chunks).get("success", true)), "chunk-sweep drift fails closed")

	var target := {
		"head": head,
		"tree": tree,
		"godot_version": Contract.EXPECTED_GODOT,
	}

	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth source initializes for PERF2.1")

	var report := profiler.run_campaign(world, config, target, host)
	_check(not report.is_empty(), "real PERF2.1 R2 profiling campaign completes")
	if report.is_empty():
		world.queue_free()
		_finish()
		return

	_check(profiler.validate_report(report), "PERF2.1 R2 report validates")
	_check(String(report.get("schema", "")) == Contract.REPORT_SCHEMA, "report uses accepted PERF2 measurement-report schema")
	_check(String(report.get("profile_schema", "")) == Profiler.PROFILE_SCHEMA, "report declares PERF2.1 profile subtype")
	_check(String(report.get("accepted_measurement_contract_revision", "")) == Contract.REVISION, "report binds accepted measurement revision")
	_check(String(report.get("accepted_measurement_contract_blob_sha", "")) == Profiler.FROZEN_PERF2_CONTRACT_BLOB_SHA, "report binds frozen measurement-contract Git blob")
	_check(String(Dictionary(report.get("target", {})).get("head", "")) == head, "report binds exact target HEAD")
	_check(String(Dictionary(report.get("target", {})).get("tree", "")) == tree, "report binds exact target TREE")
	_check(String(report.get("host_fingerprint", "")) == host, "report binds hashed host fingerprint")
	_check(String(report.get("campaign_context_hash", "")) == context_hash, "report binds frozen campaign context")
	_check(_all_authorities_safe(Dictionary(report.get("authorities", {}))), "report remains measurement-only and non-authoritative")

	var samples: Array = Array(report.get("samples", []))
	_check(samples.size() == 12, "campaign produces 3 serial + 9 STREAM1 samples")
	var groups := {
		"SERIAL_REFERENCE": [],
		"STREAM1_CHUNK_1": [],
		"STREAM1_CHUNK_7": [],
		"STREAM1_CHUNK_64": [],
	}
	for value in samples:
		var sample: Dictionary = value
		_check(bool(Contract.validate_sample(sample).get("success", false)), "every sample satisfies frozen PERF2.0 contract")
		_check(bool(sample.get("passed", false)), "every report sample is passing")
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		var configuration_id := String(flags.get("configuration_id", ""))
		_check(groups.has(configuration_id), "sample configuration id is recognized: %s" % configuration_id)
		if groups.has(configuration_id):
			Array(groups[configuration_id]).append(sample)
		_check(String(flags.get("campaign_context_hash", "")) == context_hash, "sample carries exact campaign context identity")
		_check(String(flags.get("timing_aggregation", "")) == "MEAN_PER_MEASURED_GENERATION", "sample timing aggregation is explicit")

		var workload: Dictionary = Dictionary(sample.get("workload", {}))
		_check(int(workload.get("warmup_generations", 0)) == 2, "sample records exact warmup")
		_check(int(workload.get("measured_generations", 0)) == 12, "sample records exact measured window")
		_check(int(workload.get("repetitions", 0)) == 3, "sample records exact repetition policy")
		_check(int(workload.get("founder_seed", 0)) == Workbench.FOUNDER_SEED, "sample binds real Workbench founder seed")
		_check(int(workload.get("placement_seed", 0)) == Workbench.PLACEMENT_SEED, "sample binds real Workbench placement seed")
		_check(int(workload.get("evolution_seed", 0)) == Workbench.EVOLUTION_SEED, "sample binds real Workbench evolution seed")
		_check(int(workload.get("environment_seed", 0)) == Workbench.DEFAULT_ENVIRONMENT_SEED, "sample binds real Workbench environment seed")

		var metrics: Dictionary = Dictionary(sample.get("metrics", {}))
		var timings: Dictionary = Dictionary(metrics.get("timings_ms", {}))
		for key in [
			"wall_ms", "generation_total_ms", "ls33_total_ms", "stream_total_ms",
			"candidate_build_ms", "route_build_ms", "recruitment_eval_ms", "audit_ms",
		]:
			_check(_finite_nonnegative(timings.get(key)), "sample timing %s is finite/nonnegative" % key)
		var window: Dictionary = Dictionary(metrics.get("window", {}))
		_check(int(window.get("measured_generations", 0)) == 12, "sample window records 12 generations")
		_check(_finite_nonnegative(window.get("total_wall_ms")), "sample window wall time is finite/nonnegative")
		_check(float(window.get("total_wall_ms", 0.0)) + 0.001 >= float(timings.get("wall_ms", 0.0)) * 12.0, "mean wall timing is consistent with measured window")

		var counts: Dictionary = Dictionary(metrics.get("counts", {}))
		_check(int(counts.get("generation", -1)) == 14, "sample ends after 2 warmup + 12 measured generations")
		_check(int(counts.get("population", -1)) >= 0, "sample final population is nonnegative")
		_check(int(counts.get("parent_count", -1)) > 0, "sample final parent count is positive")
		_check(int(counts.get("candidate_count", -1)) > 0, "sample final candidate count is positive")
		_check(int(counts.get("chunk_count", -1)) > 0, "sample final chunk count is positive")
		_check(int(counts.get("max_parent_chunk", -1)) > 0, "sample measured parent working set is positive")
		_check(int(counts.get("max_candidate_chunk", -1)) > 0, "sample measured candidate working set is positive")

		var stream: Dictionary = Dictionary(metrics.get("stream", {}))
		if String(workload.get("execution_mode", "")) == "SERIAL_REFERENCE":
			_check(int(stream.get("stream_calls", -1)) == 0, "serial sample has zero STREAM1 calls")
			_check(float(timings.get("stream_total_ms", -1.0)) == 0.0, "serial sample has zero STREAM1-only time")
			_check(int(counts.get("chunk_count", 0)) == 1, "serial sample is represented as one monolithic working set")
			_check(int(counts.get("max_parent_chunk", 0)) >= int(counts.get("parent_count", 0)), "serial measured parent working set covers final parents")
			_check(int(counts.get("max_candidate_chunk", 0)) >= int(counts.get("candidate_count", 0)), "serial measured candidate working set covers final candidates")
		else:
			var chunk_size := int(flags.get("stream_chunk_size", 0))
			_check(chunk_size in [1, 7, 64], "STREAM1 sample carries frozen chunk size")
			_check(int(stream.get("stream_calls", 0)) == 12, "STREAM1 telemetry counts measured generations only")
			_check(int(stream.get("serial_audit_calls", 0)) == 1, "STREAM1 measured window contains exact gen10 audit")
			_check(int(stream.get("oracle_elided_generations", 0)) == 11, "STREAM1 measured window elides oracle on other 11 generations")
			_check(int(counts.get("max_parent_chunk", 0)) <= chunk_size, "STREAM1 parent chunk stays bounded")
			_check(int(counts.get("max_candidate_chunk", 0)) <= chunk_size * 2, "STREAM1 candidate chunk stays bounded")

	for configuration_id in groups.keys():
		var group: Array = groups[configuration_id]
		_check(group.size() == 3, "%s retains all three repetitions" % configuration_id)

	var exact_pairs := 0
	for repetition in range(3):
		var serial := _sample_for(groups["SERIAL_REFERENCE"], repetition)
		for chunk_size in [1, 7, 64]:
			var streamed := _sample_for(groups["STREAM1_CHUNK_%d" % chunk_size], repetition)
			_check(not serial.is_empty() and not streamed.is_empty(), "serial↔chunk%d repetition %d exists" % [chunk_size, repetition])
			if serial.is_empty() or streamed.is_empty():
				continue
			_check(Contract.workload_hash(Dictionary(serial["workload"])) != Contract.workload_hash(Dictionary(streamed["workload"])), "backend configuration keeps exact workload identity distinct")
			_check(Contract.simulation_workload_hash(Dictionary(serial["workload"])) == Contract.simulation_workload_hash(Dictionary(streamed["workload"])), "serial↔chunk%d shares exact simulation workload" % chunk_size)
			var parity := Contract.can_compare_execution_modes(serial, streamed)
			_check(bool(parity.get("success", false)), "serial↔chunk%d repetition %d canonical parity" % [chunk_size, repetition])
			if bool(parity.get("success", false)):
				exact_pairs += 1
	_check(exact_pairs == 9, "SERIAL_REFERENCE↔STREAM1 exact result pairs: 9/9")
	print("PERF2.1 cross-configuration exact result pairs: %d/9" % exact_pairs)

	var summaries: Array = Array(report.get("summaries", []))
	_check(summaries.size() == 32, "report contains 4 configs × 8 metric summaries")
	var summary_paths := {}
	for value in summaries:
		var summary: Dictionary = value
		var key := "%s|%s" % [String(summary.get("configuration_id", "")), String(summary.get("metric_path", ""))]
		summary_paths[key] = true
		_check(int(summary.get("count", 0)) == 3, "every summary uses all three repetitions")
		for stat in ["p50", "p95", "mean", "min", "max"]:
			_check(_finite_nonnegative(summary.get(stat)), "summary statistic %s is finite/nonnegative" % stat)
		_check(float(summary.get("min", 0.0)) <= float(summary.get("p50", 0.0)), "summary min <= p50")
		_check(float(summary.get("p50", 0.0)) <= float(summary.get("p95", 0.0)), "summary p50 <= p95")
		_check(float(summary.get("p95", 0.0)) <= float(summary.get("max", 0.0)) + 1e-9, "summary p95 <= max")
	for configuration_id in Profiler.EXECUTION_CONFIG_IDS:
		for metric_path in Profiler.REQUIRED_METRICS:
			_check(summary_paths.has("%s|%s" % [configuration_id, metric_path]), "summary exists for %s %s" % [configuration_id, metric_path])

	var comparisons: Array = Array(report.get("comparisons", []))
	_check(comparisons.size() == 3, "report emits one observed comparison per STREAM1 chunk size")
	for value in comparisons:
		var comparison: Dictionary = value
		_check(int(comparison.get("exact_pairs", 0)) == 3, "comparison binds 3/3 canonical pairs")
		_check(int(comparison.get("stream_chunk_size", 0)) in [1, 7, 64], "comparison chunk size recognized")
		_check(_finite_nonnegative(comparison.get("observed_wall_ratio_serial_over_stream")), "observed wall ratio is finite/nonnegative")
		_check(_finite_nonnegative(comparison.get("observed_generation_ratio_serial_over_stream")), "observed generation ratio is finite/nonnegative")
		_check(not bool(comparison.get("optimization_claim", true)), "PERF2.1 never turns profile ratio into optimization acceptance")
		print("PERF2.1 PROFILE chunk=%d wall_ratio=%.6f generation_ratio=%.6f" % [
			int(comparison.get("stream_chunk_size", 0)),
			float(comparison.get("observed_wall_ratio_serial_over_stream", 0.0)),
			float(comparison.get("observed_generation_ratio_serial_over_stream", 0.0)),
		])

	var report_path := "res://artifacts/perf2/perf2-1-generation-profile-r2.json"
	_check(profiler.write_report(report, report_path), "machine-local PERF2.1 R2 report writes successfully")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	_check(parsed is Dictionary, "written PERF2.1 report parses as JSON")
	if parsed is Dictionary:
		var parsed_report: Dictionary = Dictionary(parsed)
		_check(String(parsed_report.get("report_hash", "")) == String(report.get("report_hash", "")), "written artifact preserves report evidence hash")
		_check(profiler.validate_report(parsed_report), "written artifact round-trips through full report validation")
		var tampered := parsed_report.duplicate(true)
		var tampered_context: Dictionary = Dictionary(tampered["campaign_context"])
		tampered_context["world_seed"] = int(tampered_context["world_seed"]) + 1
		tampered["campaign_context"] = tampered_context
		_check(not profiler.validate_report(tampered), "campaign-context tamper fails closed")

	_source_guards()
	world.queue_free()
	_finish()


func _sample_for(samples_value, repetition: int) -> Dictionary:
	for value in Array(samples_value):
		var sample: Dictionary = value
		if String(sample.get("run_id", "")).ends_with("-r%d" % repetition):
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
	var profiler_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd")
	var lower := profiler_source.to_lower()
	_check(profiler_source.count(".advance_generations(") == 2, "PERF2.1 executes ecology only through public Workbench advance facade")
	_check(not lower.contains(".core") and not lower.contains("core.") and not lower.contains("records ="), "PERF2.1 profiler has no private core/population mutation path")
	_check(not lower.contains("reproduce_bundle(") and not lower.contains("mutation_seed(") and not lower.contains("dispersal_seed("), "PERF2.1 profiler owns no biology identity")
	_check(not lower.contains("set_recruitment_executor(") and not lower.contains("set_candidate_executor("), "PERF2.1 cannot swap accepted stage backends")
	_check(profiler_source.count("set_generation_stream_executor(") == 1, "PERF2.1 uses exactly one accepted STREAM1 public seam")
	_check(profiler_source.contains('requested_spec["world_seed"]'), "PERF2.1 explicitly binds world seed into measured runtime")
	_check(profiler_source.contains('requested_spec["competition_enabled"]'), "PERF2.1 explicitly binds competition mode into measured runtime")
	var contract_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
	_check(contract_source.contains('const REVISION := "ECO.EVO7-PERF2.0-R1"'), "PERF2.1 consumes frozen PERF2.0 contract revision")
	var workbench_source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd").to_lower()
	_check(not workbench_source.contains("perf2.1") and not workbench_source.contains("perf21"), "PERF2.1 fields do not enter canonical Workbench implementation")


func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


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
	push_error("PERF2.1 CHECK FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 PERF2.1 STREAM1 Generation Profiling R2: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PERF2.1 FAIL: %s" % failure)
	print("ECO.EVO7 PERF2.1 STREAM1 Generation Profiling R2: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)
