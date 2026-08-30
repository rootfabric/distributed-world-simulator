extends SceneTree

const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Probe = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd")
const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const StreamExecutor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var contract := Contract.load_contract()
	_check(not contract.is_empty(), "PERF2.0 contract loads")
	var validation := Contract.validate_contract(contract)
	_check(bool(validation.get("success", false)), "PERF2.0 contract validates: %s" % validation)

	var workload := _default_workload(contract)
	_check(bool(Contract.validate_workload(workload, contract).get("success", false)), "default PERF2 workload validates")
	var hash_a := Contract.workload_hash(workload)
	_check(_is_hash(hash_a), "workload identity is SHA-256")

	var reordered := {}
	for key in [
		"environment_seed", "evolution_seed", "placement_seed", "founder_seed",
		"audit_generation_1", "audit_interval_generations", "parents_per_chunk",
		"initial_records", "repetitions", "measured_generations", "warmup_generations",
		"environment_recipe", "execution_mode", "workload_id"
	]:
		reordered[key] = workload[key]
	_check(Contract.workload_hash(reordered) == hash_a, "workload hash ignores Dictionary insertion order")
	var changed_chunk := workload.duplicate(true)
	changed_chunk["parents_per_chunk"] = int(workload["parents_per_chunk"]) + 1
	_check(Contract.workload_hash(changed_chunk) != hash_a, "workload hash changes when controlled chunk size changes")

	_test_probe()
	_test_real_stream_identity()

	var base := _valid_sample(workload, 10.0, "a".repeat(40))
	_check(bool(Contract.validate_sample(base, contract).get("success", false)), "valid measurement sample accepted")
	var base_key := Contract.comparison_key(base)
	_check(_is_hash(base_key), "comparison key is SHA-256")

	var timing_only := base.duplicate(true)
	var timing_metrics: Dictionary = Dictionary(timing_only["metrics"])
	var timing_values: Dictionary = Dictionary(timing_metrics["timings_ms"])
	timing_values["wall_ms"] = 999.0
	timing_metrics["timings_ms"] = timing_values
	timing_only["metrics"] = timing_metrics
	_check(Contract.comparison_key(timing_only) == base_key, "timing values do not enter comparison key")

	var different_target := base.duplicate(true)
	var changed_target: Dictionary = Dictionary(different_target["target"])
	changed_target["head"] = "b".repeat(40)
	changed_target["tree"] = "c".repeat(40)
	different_target["target"] = changed_target
	_check(Contract.comparison_key(different_target) == base_key, "source target is excluded from comparison key for before/after optimization")

	var different_host := base.duplicate(true)
	different_host["host_fingerprint"] = "different-host"
	_check(Contract.comparison_key(different_host) != base_key, "host fingerprint fences incomparable machines")

	var negative := base.duplicate(true)
	var negative_metrics: Dictionary = Dictionary(negative["metrics"])
	var negative_timings: Dictionary = Dictionary(negative_metrics["timings_ms"])
	negative_timings["wall_ms"] = -1.0
	negative_metrics["timings_ms"] = negative_timings
	negative["metrics"] = negative_metrics
	_check(not bool(Contract.validate_sample(negative, contract).get("success", true)), "negative timing fails closed")

	var changed_result := base.duplicate(true)
	var divergent_result: Dictionary = Dictionary(changed_result["canonical_result"])
	divergent_result["final_population_hash"] = "d".repeat(64)
	changed_result["canonical_result"] = divergent_result
	_check(not bool(Contract.can_compare(base, changed_result).get("success", true)), "canonical result divergence blocks optimization comparison")

	var failed_sample := base.duplicate(true)
	failed_sample["passed"] = false
	_check(not bool(Contract.can_compare(base, failed_sample).get("success", true)), "failed sample is excluded from comparison claims")

	var samples: Array[Dictionary] = []
	var sample_values := [10.0, 20.0, 30.0]
	var sample_heads := ["a".repeat(40), "b".repeat(40), "c".repeat(40)]
	for index in range(3):
		samples.append(_valid_sample(workload, float(sample_values[index]), String(sample_heads[index])))
	_check(Contract.minimum_repetitions_satisfied(samples, contract), "three repetitions satisfy minimum evidence")
	var summary := Contract.summarize(samples, "timings_ms.wall_ms")
	_check(not summary.is_empty(), "summary builds only from comparable passing samples")
	_check(int(summary.get("count", 0)) == 3, "summary count is 3")
	_check(is_equal_approx(float(summary.get("p50", -1.0)), 20.0), "p50 uses frozen interpolation rule")
	_check(is_equal_approx(float(summary.get("p95", -1.0)), 29.0), "p95 uses frozen interpolation rule")
	_check(is_equal_approx(float(summary.get("mean", -1.0)), 20.0), "summary mean is deterministic")
	_check(is_equal_approx(float(summary.get("min", -1.0)), 10.0), "summary min retained as diagnostic only")
	_check(is_equal_approx(float(summary.get("max", -1.0)), 30.0), "summary max retained as diagnostic only")

	var too_few: Array[Dictionary] = [samples[0], samples[1]]
	_check(not Contract.minimum_repetitions_satisfied(too_few, contract), "two runs cannot support PERF2 optimization claim")

	_source_guards()
	_finish()


func _test_probe() -> void:
	var probe := Probe.new()
	var started := probe.begin()
	_check(bool(started.get("success", false)), "measurement probe starts")
	_check(probe.is_active(), "measurement probe reports active")
	OS.delay_msec(1)
	var finished := probe.finish()
	_check(bool(finished.get("success", false)), "measurement probe finishes")
	_check(not probe.is_active(), "measurement probe clears active state")
	_check(_finite_nonnegative(finished.get("wall_ms")), "probe wall time is finite/nonnegative")
	var memory: Dictionary = Dictionary(finished.get("memory_bytes", {}))
	_check(int(memory.get("engine_static_bytes", -1)) >= 0, "probe captures engine static memory")
	_check(int(memory.get("engine_static_peak_bytes", -1)) >= 0, "probe captures engine static peak memory")
	_check(memory.get("process_rss_bytes") == null and memory.get("process_peak_rss_bytes") == null, "process RSS remains explicitly optional/external")


func _test_real_stream_identity() -> void:
	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth initializes for PERF2.0 smoke")

	var streamed = Workbench.new()
	var serial = Workbench.new()
	_check(streamed.setup(world), "streamed Workbench initializes")
	_check(serial.setup(world), "serial oracle Workbench initializes")
	var before_a: Dictionary = streamed.get_workbench_snapshot()
	var before_b: Dictionary = serial.get_workbench_snapshot()
	_check(String(before_a.get("workbench_hash", "")) == String(before_b.get("workbench_hash", "")), "PERF2 smoke starts from exact same canonical state")

	var executor := StreamExecutor.new()
	_check(executor.setup({
		"parents_per_chunk": 64,
		"audit_interval": 10,
		"audit_generation_1": true,
	}), "accepted STREAM1 executor config initializes")
	_check(streamed.set_generation_stream_executor(executor), "STREAM1 injected only through public Workbench facade")

	var probe := Probe.new()
	_check(bool(probe.begin().get("success", false)), "real STREAM1 smoke probe starts")
	var streamed_result: Dictionary = streamed.advance_generations(1)
	var observed := probe.finish()
	var serial_result: Dictionary = serial.advance_generations(1)
	_check(not streamed_result.is_empty() and not serial_result.is_empty(), "streamed and serial one-generation smoke complete")
	_check(bool(observed.get("success", false)), "real STREAM1 smoke observation completes")

	for key in ["workbench_hash", "ecology_state_hash", "population_hash", "classification_hash"]:
		_check(String(streamed_result.get(key, "")) == String(serial_result.get(key, "")), "measurement+STREAM1 preserves canonical %s parity" % key)

	var profile: Dictionary = streamed.get_last_generation_profile()
	var eco: Dictionary = Dictionary(profile.get("ecology", {}))
	var ls33: Dictionary = Dictionary(eco.get("ls33", {}))
	_check(String(ls33.get("stream_mode", "")) == "STREAM1_BOUNDED_PROPOSAL", "PERF2 smoke consumes accepted STREAM1 path")
	_check(_finite_nonnegative(ls33.get("total_ms")), "existing PERF1 LS3.3 timing remains available")
	var stream_timings: Dictionary = Dictionary(ls33.get("timings_ms", {}))
	for key in ["candidate_build_ms", "route_build_ms", "recruitment_eval_ms", "audit_ms", "total_ms"]:
		_check(_finite_nonnegative(stream_timings.get(key)), "STREAM1 timing %s is reusable by PERF2" % key)
	var telemetry := executor.get_telemetry()
	_check(int(telemetry.get("stream_calls", 0)) == 1, "STREAM1 telemetry records exactly one smoke generation")
	_check(int(telemetry.get("max_parent_chunk_seen", 0)) <= 64, "STREAM1 parent working set remains bounded")
	_check(int(telemetry.get("max_candidate_chunk_seen", 0)) <= 128, "STREAM1 candidate working set remains bounded")

	world.queue_free()


func _default_workload(contract: Dictionary) -> Dictionary:
	var defaults: Dictionary = Dictionary(Dictionary(contract["workload_contract"]).get("default_stream1", {}))
	return {
		"workload_id": "PERF2_STREAM1_STANDARD_R1",
		"execution_mode": "STREAM1",
		"environment_recipe": "MIXED_PHYSICAL_HETEROGENEITY",
		"warmup_generations": int(defaults["warmup_generations"]),
		"measured_generations": int(defaults["measured_generations"]),
		"repetitions": int(defaults["repetitions"]),
		"initial_records": int(defaults["initial_records"]),
		"parents_per_chunk": int(defaults["parents_per_chunk"]),
		"audit_interval_generations": int(defaults["audit_interval_generations"]),
		"audit_generation_1": bool(defaults["audit_generation_1"]),
		"founder_seed": 20260832,
		"placement_seed": 320032,
		"evolution_seed": 330033,
		"environment_seed": 20260831,
	}


func _valid_sample(workload: Dictionary, wall_ms: float, target_head: String) -> Dictionary:
	var target_tree := target_head.sha256_text().substr(0, 40)
	var result_hash := "1".repeat(64)
	return {
		"schema": Contract.SAMPLE_SCHEMA,
		"version": Contract.VERSION,
		"revision": Contract.REVISION,
		"run_id": "run-%s" % target_head.substr(0, 8),
		"target": {
			"head": target_head,
			"tree": target_tree,
			"godot_version": Contract.EXPECTED_GODOT,
		},
		"host_fingerprint": "windows-double-reference-host",
		"measurement_method_revision": Contract.REVISION,
		"workload": workload.duplicate(true),
		"workload_hash": Contract.workload_hash(workload),
		"passed": true,
		"canonical_result": {
			"final_workbench_hash": result_hash,
			"final_ecology_state_hash": "2".repeat(64),
			"final_population_hash": "3".repeat(64),
			"final_classification_hash": "4".repeat(64),
		},
		"metrics": {
			"timings_ms": {
				"wall_ms": wall_ms,
				"generation_total_ms": wall_ms,
				"ls33_total_ms": wall_ms * 0.5,
				"stream_total_ms": wall_ms * 0.45,
				"candidate_build_ms": wall_ms * 0.15,
				"route_build_ms": wall_ms * 0.05,
				"recruitment_eval_ms": wall_ms * 0.20,
				"audit_ms": 0.0,
			},
			"counts": {
				"generation": 12,
				"population": 96,
				"parent_count": 96,
				"candidate_count": 192,
				"chunk_count": 2,
				"max_parent_chunk": 64,
				"max_candidate_chunk": 128,
			},
			"memory_bytes": {
				"engine_static_bytes": 1000000,
				"engine_static_peak_bytes": 1200000,
				"process_rss_bytes": null,
				"process_peak_rss_bytes": null,
			},
			"stream": {
				"stream_calls": 12,
				"chunks_processed": 24,
				"serial_audit_calls": 2,
				"oracle_elided_generations": 10,
			},
		},
		"flags": {
			"canonical": false,
			"side_channel_only": true,
			"measurement_only": true,
		},
	}


func _source_guards() -> void:
	var contract_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd").to_lower()
	var probe_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd").to_lower()
	var workbench_source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd").to_lower()
	_check(not contract_source.contains("advance_generations(") and not contract_source.contains("step_generation("), "measurement contract owns no ecology execution")
	_check(not probe_source.contains("workbench") and not probe_source.contains("ls33"), "process probe has no ecology authority reference")
	_check(not workbench_source.contains('"perf2"') and not workbench_source.contains('"measurement_report"'), "PERF2 fields do not enter canonical Workbench snapshot source")


func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


func _is_hash(value: String) -> bool:
	return value.length() == 64


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("PERF2.0 CHECK FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 PERF2.0 Measurement Contract: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PERF2.0 FAIL: %s" % failure)
	print("ECO.EVO7 PERF2.0 Measurement Contract: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)
