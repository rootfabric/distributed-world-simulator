extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Profiler = preload("res://scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var head := OS.get_environment("ECO_PERF2_TARGET_HEAD").strip_edges()
	var tree := OS.get_environment("ECO_PERF2_TARGET_TREE").strip_edges()
	var host := OS.get_environment("ECO_PERF2_HOST_FINGERPRINT").strip_edges()
	_check(_is_git_sha(head), "runner provides exact target HEAD")
	_check(_is_git_sha(tree), "runner provides exact target TREE")
	_check(not host.is_empty(), "runner provides host fingerprint")
	if not failures.is_empty():
		_finish()
		return

	var contract := Contract.load_contract()
	_check(bool(Contract.validate_contract(contract).get("success", false)), "accepted PERF2.0 contract validates")
	_check(Contract.REVISION == "ECO.EVO7-PERF2.0-R1", "PERF2.0 measurement revision remains frozen")

	var profiler = Profiler.new()
	var config := profiler.default_campaign_config()
	_check(bool(profiler.validate_campaign_config(config).get("success", false)), "default PERF2.1 campaign config validates")
	_check(Array(config["recipes"]) == ["MIXED_PHYSICAL_HETEROGENEITY"], "R1 focused campaign uses one frozen physical recipe")
	_check(int(config["warmup_generations"]) == 2, "campaign uses accepted two-generation warmup")
	_check(int(config["measured_generations"]) == 12, "campaign measures accepted twelve generations")
	_check(int(config["repetitions"]) == 3, "campaign uses accepted three repetitions")
	_check(int(config["initial_records"]) == 64, "campaign keeps accepted initial population")
	_check(int(config["parents_per_chunk"]) == 64, "campaign keeps accepted STREAM1 chunk size")

	var unsupported := config.duplicate(true)
	unsupported["founder_seed"] = int(unsupported["founder_seed"]) + 1
	_check(not bool(profiler.validate_campaign_config(unsupported).get("success", true)),
		"PERF2.1 refuses to mutate Workbench founder semantics for benchmark convenience")

	var target := {
		"head": head,
		"tree": tree,
		"godot_version": Contract.EXPECTED_GODOT,
	}

	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth source initializes for PERF2.1")

	var report := profiler.run_campaign(world, config, target, host)
	_check(not report.is_empty(), "real PERF2.1 profiling campaign completes")
	if report.is_empty():
		world.queue_free()
		_finish()
		return

	_check(profiler.validate_report(report), "PERF2.1 report validates")
	_check(String(report.get("accepted_measurement_contract_revision", "")) == Contract.REVISION,
		"report binds accepted measurement revision")
	_check(String(report.get("accepted_measurement_contract_blob_sha", "")) == Profiler.FROZEN_PERF2_CONTRACT_BLOB_SHA,
		"report binds frozen measurement-contract Git blob")
	_check(String(Dictionary(report.get("target", {})).get("head", "")) == head, "report binds exact target HEAD")
	_check(String(Dictionary(report.get("target", {})).get("tree", "")) == tree, "report binds exact target TREE")
	_check(String(report.get("host_fingerprint", "")) == host, "report binds exact host fingerprint")
	_check(_all_authorities_safe(Dictionary(report.get("authorities", {}))), "report remains measurement-only and non-authoritative")

	var samples: Array = Array(report.get("samples", []))
	_check(samples.size() == 6, "focused campaign produces 3 serial + 3 STREAM1 samples")
	var serial_samples: Array[Dictionary] = []
	var stream_samples: Array[Dictionary] = []
	for value in samples:
		var sample: Dictionary = value
		_check(bool(Contract.validate_sample(sample).get("success", false)), "every emitted sample satisfies PERF2.0 contract")
		_check(bool(sample.get("passed", false)), "every report sample is a passing sample")
		var workload: Dictionary = Dictionary(sample.get("workload", {}))
		_check(int(workload.get("warmup_generations", 0)) >= 1, "sample records warmup policy")
		_check(int(workload.get("measured_generations", 0)) >= 12, "sample records minimum measured generations")
		_check(int(workload.get("repetitions", 0)) >= 3, "sample records minimum repetition policy")
		var metrics: Dictionary = Dictionary(sample.get("metrics", {}))
		var timings: Dictionary = Dictionary(metrics.get("timings_ms", {}))
		for key in [
			"wall_ms", "generation_total_ms", "ls33_total_ms", "stream_total_ms",
			"candidate_build_ms", "route_build_ms", "recruitment_eval_ms", "audit_ms",
		]:
			_check(_finite_nonnegative(timings.get(key)), "sample timing %s is finite/nonnegative" % key)
		var counts: Dictionary = Dictionary(metrics.get("counts", {}))
		for key in [
			"generation", "population", "parent_count", "candidate_count",
			"chunk_count", "max_parent_chunk", "max_candidate_chunk",
		]:
			_check(typeof(counts.get(key)) == TYPE_INT and int(counts.get(key, -1)) >= 0,
				"sample count %s is nonnegative integer" % key)
		var stream: Dictionary = Dictionary(metrics.get("stream", {}))
		for key in ["stream_calls", "chunks_processed", "serial_audit_calls", "oracle_elided_generations"]:
			_check(typeof(stream.get(key)) == TYPE_INT and int(stream.get(key, -1)) >= 0,
				"sample stream telemetry %s is nonnegative integer" % key)
		if String(workload.get("execution_mode", "")) == "SERIAL_REFERENCE":
			serial_samples.append(sample)
			_check(int(stream.get("stream_calls", -1)) == 0, "serial sample has zero STREAM1 calls")
			_check(float(timings.get("stream_total_ms", -1.0)) == 0.0, "serial sample has zero STREAM1-only time")
		elif String(workload.get("execution_mode", "")) == "STREAM1":
			stream_samples.append(sample)
			_check(int(stream.get("stream_calls", 0)) == 12, "STREAM1 telemetry counts measured generations only")
			_check(int(counts.get("max_parent_chunk", 0)) <= 64, "STREAM1 measured parent working set stays bounded")
			_check(int(counts.get("max_candidate_chunk", 0)) <= 128, "STREAM1 measured candidate working set stays bounded")
		else:
			_check(false, "sample execution mode is recognized")

	_check(serial_samples.size() == 3, "three serial repetitions retained")
	_check(stream_samples.size() == 3, "three STREAM1 repetitions retained")
	_check(Contract.minimum_repetitions_satisfied(serial_samples), "serial summary satisfies accepted minimum repetitions")
	_check(Contract.minimum_repetitions_satisfied(stream_samples), "STREAM1 summary satisfies accepted minimum repetitions")

	var exact_pairs := 0
	for repetition in range(3):
		var serial: Dictionary = _sample_for_repetition(serial_samples, repetition)
		var streamed: Dictionary = _sample_for_repetition(stream_samples, repetition)
		_check(not serial.is_empty() and not streamed.is_empty(), "cross-mode repetition %d is present" % repetition)
		if serial.is_empty() or streamed.is_empty():
			continue
		var serial_workload: Dictionary = Dictionary(serial["workload"])
		var stream_workload: Dictionary = Dictionary(streamed["workload"])
		_check(Contract.workload_hash(serial_workload) != Contract.workload_hash(stream_workload),
			"cross-mode repetition %d keeps exact backend workload identities distinct" % repetition)
		_check(Contract.simulation_workload_hash(serial_workload) == Contract.simulation_workload_hash(stream_workload),
			"cross-mode repetition %d shares exact simulation workload" % repetition)
		var parity := Contract.can_compare_execution_modes(serial, streamed)
		_check(bool(parity.get("success", false)), "cross-mode repetition %d has exact canonical parity" % repetition)
		if bool(parity.get("success", false)):
			exact_pairs += 1
	_check(exact_pairs == 3, "SERIAL_REFERENCE↔STREAM1 exact result pairs: 3/3")
	print("PERF2.1 cross-mode exact result pairs: %d/3" % exact_pairs)

	var summaries: Array = Array(report.get("summaries", []))
	_check(summaries.size() == 12, "report contains 2 modes × 6 frozen metric summaries")
	var summary_paths := {}
	for value in summaries:
		var summary: Dictionary = value
		print("PERF2.1 PROFILE recipe=%s mode=%s metric=%s count=%d p50=%.6f p95=%.6f mean=%.6f" % [
			String(summary.get("environment_recipe", "")),
			String(summary.get("execution_mode", "")),
			String(summary.get("metric_path", "")),
			int(summary.get("count", 0)),
			float(summary.get("p50", 0.0)),
			float(summary.get("p95", 0.0)),
			float(summary.get("mean", 0.0)),
		])
		_check(int(summary.get("count", 0)) == 3, "every summary uses all three passing repetitions")
		for key in ["p50", "p95", "mean", "min", "max"]:
			_check(_finite_nonnegative(summary.get(key)), "summary statistic %s is finite/nonnegative" % key)
		_check(float(summary.get("min", 0.0)) <= float(summary.get("p50", 0.0)), "summary min <= p50")
		_check(float(summary.get("p50", 0.0)) <= float(summary.get("p95", 0.0)), "summary p50 <= p95")
		_check(float(summary.get("p95", 0.0)) <= float(summary.get("max", 0.0)) + 1e-9, "summary p95 <= max")
		summary_paths["%s|%s" % [String(summary.get("execution_mode", "")), String(summary.get("metric_path", ""))]] = true
	for mode in Profiler.EXECUTION_MODES:
		for path in Profiler.REQUIRED_METRICS:
			_check(summary_paths.has("%s|%s" % [mode, path]), "summary exists for %s %s" % [mode, path])

	var report_path := "res://artifacts/perf2/perf2-1-generation-profile-focused.json"
	_check(profiler.write_report(report, report_path), "machine-local PERF2.1 report writes successfully")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	_check(parsed is Dictionary, "written PERF2.1 report parses as JSON")
	if parsed is Dictionary:
		var parsed_report: Dictionary = Dictionary(parsed)
		_check(String(parsed_report.get("report_hash", "")) == String(report.get("report_hash", "")),
			"written artifact preserves report evidence hash")
		_check(profiler.validate_report(parsed_report), "written artifact round-trips through full report validation")
		var tampered: Dictionary = parsed_report.duplicate(true)
		var tampered_samples: Array = Array(tampered["samples"])
		var tampered_sample: Dictionary = Dictionary(tampered_samples[0])
		var tampered_metrics: Dictionary = Dictionary(tampered_sample["metrics"])
		var tampered_timings: Dictionary = Dictionary(tampered_metrics["timings_ms"])
		tampered_timings["generation_total_ms"] = float(tampered_timings["generation_total_ms"]) + 0.001
		tampered_metrics["timings_ms"] = tampered_timings
		tampered_sample["metrics"] = tampered_metrics
		tampered_samples[0] = tampered_sample
		tampered["samples"] = tampered_samples
		_check(not profiler.validate_report(tampered), "raw timing tamper invalidates PERF2.1 report evidence hash")

	_source_guards()
	world.queue_free()
	_finish()

func _sample_for_repetition(samples: Array[Dictionary], repetition: int) -> Dictionary:
	var suffix := "-r%d" % repetition
	for sample in samples:
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
	var profiler_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd")
	var lower := profiler_source.to_lower()
	_check(profiler_source.count(".advance_generations(") == 2,
		"PERF2.1 executes ecology only through public Workbench advance facade")
	_check(not lower.contains(".core") and not lower.contains("core.") and not lower.contains("records ="),
		"PERF2.1 profiler has no private core/population mutation path")
	_check(not lower.contains("reproduce_bundle(") and not lower.contains("mutation_seed(") and not lower.contains("dispersal_seed("),
		"PERF2.1 profiler owns no biology identity")
	_check(not lower.contains("set_recruitment_executor(") and not lower.contains("set_candidate_executor("),
		"PERF2.1 cannot swap accepted stage backends")
	_check(profiler_source.count("set_generation_stream_executor(") == 1,
		"PERF2.1 uses exactly one accepted STREAM1 public seam")
	var workbench_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd").to_lower()
	_check(not workbench_source.contains("perf2.1") and not workbench_source.contains("perf21"),
		"PERF2.1 fields do not enter canonical Workbench implementation")
	var contract_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
	_check(contract_source.contains('const REVISION := "ECO.EVO7-PERF2.0-R1"'),
		"PERF2.1 consumes the frozen PERF2.0 contract revision")

func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0

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
		print("ECO.EVO7 PERF2.1 STREAM1 Generation Profiling: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PERF2.1 FAIL: %s" % failure)
	print("ECO.EVO7 PERF2.1 STREAM1 Generation Profiling: FAIL (%d/%d assertions failed)" % [
		failures.size(), assertions
	])
	quit(1)
