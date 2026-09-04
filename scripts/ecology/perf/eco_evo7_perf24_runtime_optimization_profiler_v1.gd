extends RefCounted

## ECO.EVO7 PERF2.4 R1 — STREAM1 runtime optimization A/B profiler.
##
## Compares the retained legacy per-chunk canonicalization path against the
## optimized generation-boundary canonicalization path on the same exact
## runtime subject, host, workload, chunk sizes and generation-age scale.
##
## This profiler does not compare old Git commits. Keeping both pipeline modes
## in one executor lets A/B evidence share exact formulas, Godot build, host
## fingerprint and code revision.

const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Probe = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd")
const StreamExecutor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_perf2_4.runtime_optimization_report.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PERF2.4-R1"
const MODE := "RESEARCH_SHADOW_RUNTIME_OPTIMIZATION"

const FROZEN_PERF2_CONTRACT_REVISION := "ECO.EVO7-PERF2.0-R1"
const FROZEN_PERF2_CONTRACT_BLOB_SHA := "b076784f6b4016a0191e937c4e6ada1fe90c783b"
const ACCEPTED_PERF23_HEAD := "34715ac5524d594003236ca6228c0b0ba5bb9e90"
const ACCEPTED_PERF23_TREE := "f97deaa1c3e8d31e1e5fc71394b7528426b1f585"

const DEFAULT_RECIPE := "MIXED_PHYSICAL_HETEROGENEITY"
const PRECONDITION_GENERATIONS: Array[int] = [2, 12, 22]
const SCALE_IDS: Array[String] = ["AGE_2", "AGE_12", "AGE_22"]
const STREAM_CHUNK_SIZES: Array[int] = [1, 7, 64]
const PIPELINE_MODES: Array[String] = [
	StreamExecutor.PIPELINE_LEGACY,
	StreamExecutor.PIPELINE_OPTIMIZED,
]
const MEASURED_GENERATIONS := 12
const REPETITIONS := 3
const AUDIT_INTERVAL_GENERATIONS := 10
const AUDIT_GENERATION_1 := true

const TOTAL_SAMPLES := 54
const TOTAL_AB_PAIRS := 27
const TOTAL_GENERATION_ADVANCES := 1296

const MIN_WALL_GEOMEAN_SPEEDUP := 1.02
const MIN_STREAM_GEOMEAN_SPEEDUP := 1.03
const MIN_POINT_WALL_RATIO := 0.97
const MIN_IMPROVED_WALL_POINTS := 6

const AUTHORITIES := {
	"canonical": false,
	"world_write": false,
	"ecology_truth_write": false,
	"generation_commit": false,
	"biology_write": false,
	"persistence_truth_write": false,
	"network_write": false,
	"measurement_only": true,
	"side_channel_only": true,
	"runtime_optimization_candidate": true,
}

const OPTIMIZATION_POLICY := {
	"baseline_pipeline": "LEGACY_PER_CHUNK_CANONICALIZATION",
	"candidate_pipeline": "OPTIMIZED_GENERATION_BOUNDARY_CANONICALIZATION",
	"scale_points": [2, 12, 22],
	"stream_chunk_sizes": [1, 7, 64],
	"measured_generations": 12,
	"repetitions": 3,
	"total_samples": 54,
	"exact_ab_pairs_required": 27,
	"balanced_order": "R0_LEGACY_FIRST__R1_OPTIMIZED_FIRST__R2_LEGACY_FIRST",
	"min_wall_geomean_speedup": 1.02,
	"min_stream_geomean_speedup": 1.03,
	"min_point_wall_ratio": 0.97,
	"min_improved_wall_points": 6,
	"serial_crossover_required": false,
	"canonical_parity_required": true,
	"bounded_working_set_regression_allowed": false,
}


func run_campaign(planet_source, target: Dictionary, host_fingerprint: String) -> Dictionary:
	if planet_source == null:
		return _failure("PLANET_SOURCE", [])
	if not _valid_target(target):
		return _failure("TARGET", [])
	if not _is_hash(host_fingerprint):
		return _failure("HOST_FINGERPRINT", [])
	if Contract.REVISION != FROZEN_PERF2_CONTRACT_REVISION:
		return _failure("PERF2_CONTRACT_REVISION_DRIFT", [])

	var context: Dictionary = _campaign_context()
	var context_hash: String = campaign_context_hash(context)
	if context.is_empty() or not _is_hash(context_hash):
		return _failure("CAMPAIGN_CONTEXT", [])

	var samples: Array[Dictionary] = []
	for scale_index in range(SCALE_IDS.size()):
		var scale_id: String = SCALE_IDS[scale_index]
		var precondition: int = PRECONDITION_GENERATIONS[scale_index]
		for chunk_size in STREAM_CHUNK_SIZES:
			for repetition in range(REPETITIONS):
				var order: Array[String] = _pipeline_order(repetition)
				for pipeline_mode in order:
					var sample: Dictionary = _run_repetition(
						planet_source, target, host_fingerprint, context_hash,
						scale_id, precondition, chunk_size, pipeline_mode, repetition)
					if sample.is_empty():
						return _failure("SAMPLE_FAILED", [scale_id, chunk_size, pipeline_mode, repetition])
					samples.append(sample)

	if samples.size() != TOTAL_SAMPLES:
		return _failure("SAMPLE_COUNT", [samples.size()])

	var comparisons: Array[Dictionary] = _build_comparisons(samples)
	if comparisons.size() != 9:
		return _failure("COMPARISON_COUNT", [comparisons.size()])

	var summary: Dictionary = _build_optimization_summary(comparisons)
	if summary.is_empty():
		return _failure("OPTIMIZATION_SUMMARY", [])

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"target": target.duplicate(true),
		"host_fingerprint": host_fingerprint,
		"accepted_predecessor": {
			"perf2_3_head": ACCEPTED_PERF23_HEAD,
			"perf2_3_tree": ACCEPTED_PERF23_TREE,
			"perf2_contract_revision": FROZEN_PERF2_CONTRACT_REVISION,
			"perf2_contract_blob_sha": FROZEN_PERF2_CONTRACT_BLOB_SHA,
		},
		"campaign_context": context,
		"campaign_context_hash": context_hash,
		"optimization_policy": OPTIMIZATION_POLICY.duplicate(true),
		"samples": samples,
		"comparisons": comparisons,
		"optimization_summary": summary,
		"authorities": AUTHORITIES.duplicate(true),
		"claims": {
			"canonical_parity": int(summary.get("exact_pairs", 0)) == TOTAL_AB_PAIRS,
			"bounded_working_set_preserved": bool(summary.get("bounded_working_set_preserved", false)),
			"deterministic_operation_reduction": bool(summary.get("operation_reduction_proven", false)),
			"serial_crossover_claim": false,
			"optimization_claim": bool(summary.get("optimization_claim", false)),
		},
	}
	report["report_hash"] = report_hash(report)
	if not validate_report(report):
		return _failure("REPORT_VALIDATION", [])
	return report


func validate_report(report: Dictionary) -> bool:
	var required := [
		"schema", "version", "revision", "mode", "target", "host_fingerprint",
		"accepted_predecessor", "campaign_context", "campaign_context_hash",
		"optimization_policy", "samples", "comparisons", "optimization_summary",
		"authorities", "claims", "report_hash",
	]
	if report.size() != required.size():
		return false
	for key in required:
		if not report.has(key):
			return false
	if String(report["schema"]) != SCHEMA or String(report["version"]) != VERSION:
		return false
	if String(report["revision"]) != REVISION or String(report["mode"]) != MODE:
		return false
	if not _valid_target(Dictionary(report["target"])):
		return false
	if not _is_hash(String(report["host_fingerprint"])):
		return false

	var predecessor: Dictionary = Dictionary(report["accepted_predecessor"])
	if String(predecessor.get("perf2_3_head", "")) != ACCEPTED_PERF23_HEAD:
		return false
	if String(predecessor.get("perf2_3_tree", "")) != ACCEPTED_PERF23_TREE:
		return false
	if String(predecessor.get("perf2_contract_revision", "")) != FROZEN_PERF2_CONTRACT_REVISION:
		return false
	if String(predecessor.get("perf2_contract_blob_sha", "")) != FROZEN_PERF2_CONTRACT_BLOB_SHA:
		return false

	var context: Dictionary = Dictionary(report["campaign_context"])
	var context_hash: String = campaign_context_hash(context)
	if not _is_hash(context_hash) or String(report["campaign_context_hash"]) != context_hash:
		return false
	if not _validate_optimization_policy(Dictionary(report["optimization_policy"])):
		return false
	if Dictionary(report["authorities"]) != AUTHORITIES:
		return false

	var samples: Array = Array(report["samples"])
	if samples.size() != TOTAL_SAMPLES:
		return false
	var normalized_samples: Array[Dictionary] = []
	for value in samples:
		if not value is Dictionary:
			return false
		var sample: Dictionary = _normalize_sample_for_contract(Dictionary(value))
		if sample.is_empty():
			return false
		if not bool(Contract.validate_sample(sample).get("success", false)):
			return false
		if not bool(sample.get("passed", false)):
			return false
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		if String(flags.get("campaign_context_hash", "")) != context_hash:
			return false
		if not _validate_sample_flags(flags):
			return false
		normalized_samples.append(sample)

	if not _validate_exact_ab_pairs(normalized_samples):
		return false

	var comparisons: Array = Array(report["comparisons"])
	if comparisons.size() != 9:
		return false
	var seen := {}
	for value in comparisons:
		if not value is Dictionary:
			return false
		var comparison: Dictionary = value
		if not _validate_comparison(comparison):
			return false
		var key := "%s|%d" % [String(comparison["scale_id"]), int(comparison["stream_chunk_size"])]
		if seen.has(key):
			return false
		seen[key] = true
	if seen.size() != 9:
		return false

	var recomputed_comparisons: Array[Dictionary] = _build_comparisons(normalized_samples)
	if recomputed_comparisons.size() != comparisons.size():
		return false
	for index in range(comparisons.size()):
		if _comparison_hash(Dictionary(comparisons[index])) != _comparison_hash(recomputed_comparisons[index]):
			return false

	var summary: Dictionary = Dictionary(report["optimization_summary"])
	if not _validate_optimization_summary(summary, comparisons):
		return false

	var claims: Dictionary = Dictionary(report["claims"])
	if claims.size() != 5:
		return false
	if bool(claims.get("canonical_parity", false)) != (int(summary["exact_pairs"]) == TOTAL_AB_PAIRS):
		return false
	if bool(claims.get("bounded_working_set_preserved", false)) != bool(summary["bounded_working_set_preserved"]):
		return false
	if bool(claims.get("deterministic_operation_reduction", false)) != bool(summary["operation_reduction_proven"]):
		return false
	if bool(claims.get("serial_crossover_claim", true)):
		return false
	if bool(claims.get("optimization_claim", false)) != bool(summary["optimization_claim"]):
		return false

	return String(report["report_hash"]) == report_hash(report)


func write_report(report: Dictionary, path: String) -> bool:
	if path.strip_edges().is_empty() or not validate_report(report):
		return false
	var parent: String = path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "  ", false) + "\n")
	file.close()
	return true


func campaign_context_hash(context: Dictionary) -> String:
	var required := [
		"planet_source_kind", "world_seed", "environment_seed", "environment_recipe",
		"competition_enabled", "grid_size", "cell_size_m",
	]
	if context.size() != required.size():
		return ""
	for key in required:
		if not context.has(key):
			return ""
	if not _is_integral_number(context["world_seed"]) or not _is_integral_number(context["environment_seed"]):
		return ""
	if not _is_integral_number(context["grid_size"]):
		return ""
	if typeof(context["competition_enabled"]) != TYPE_BOOL:
		return ""
	var cell_size := float(context["cell_size_m"])
	if not is_finite(cell_size) or cell_size <= 0.0:
		return ""
	return "|".join(PackedStringArray([
		"PERF2_4_CONTEXT_R1",
		String(context["planet_source_kind"]),
		str(int(context["world_seed"])),
		str(int(context["environment_seed"])),
		String(context["environment_recipe"]),
		"true" if bool(context["competition_enabled"]) else "false",
		str(int(context["grid_size"])),
		"%.9f" % cell_size,
	])).sha256_text()


func report_hash(report: Dictionary) -> String:
	var sample_hashes := PackedStringArray()
	for value in Array(report.get("samples", [])):
		sample_hashes.append(_sample_hash(Dictionary(value)))
	var comparison_hashes := PackedStringArray()
	for value in Array(report.get("comparisons", [])):
		comparison_hashes.append(_comparison_hash(Dictionary(value)))
	var target: Dictionary = Dictionary(report.get("target", {}))
	return "|".join(PackedStringArray([
		"PERF2_4_REPORT_R1",
		String(target.get("head", "")),
		String(target.get("tree", "")),
		String(target.get("godot_version", "")),
		String(report.get("host_fingerprint", "")),
		String(report.get("campaign_context_hash", "")),
		ACCEPTED_PERF23_HEAD,
		FROZEN_PERF2_CONTRACT_BLOB_SHA,
		";".join(sample_hashes),
		";".join(comparison_hashes),
		_summary_hash(Dictionary(report.get("optimization_summary", {}))),
	])).sha256_text()


func _campaign_context() -> Dictionary:
	return {
		"planet_source_kind": "PROCEDURAL_EARTH_WORLD",
		"world_seed": Workbench.DEFAULT_WORLD_SEED,
		"environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
		"environment_recipe": DEFAULT_RECIPE,
		"competition_enabled": true,
		"grid_size": Workbench.GRID_SIZE,
		"cell_size_m": Workbench.CELL_SIZE_M,
	}


func _pipeline_order(repetition: int) -> Array[String]:
	if repetition == 1:
		return [StreamExecutor.PIPELINE_OPTIMIZED, StreamExecutor.PIPELINE_LEGACY]
	return [StreamExecutor.PIPELINE_LEGACY, StreamExecutor.PIPELINE_OPTIMIZED]


func _run_repetition(
	planet_source,
	target: Dictionary,
	host_fingerprint: String,
	context_hash: String,
	scale_id: String,
	precondition_generations: int,
	chunk_size: int,
	pipeline_mode: String,
	repetition: int
) -> Dictionary:
	var workload := {
		"workload_id": "PERF2_4_STREAM1_RUNTIME_OPTIMIZATION_R1",
		"execution_mode": "STREAM1",
		"environment_recipe": DEFAULT_RECIPE,
		"warmup_generations": precondition_generations,
		"measured_generations": MEASURED_GENERATIONS,
		"repetitions": REPETITIONS,
		"initial_records": Workbench.INITIAL_RECORDS,
		"parents_per_chunk": chunk_size,
		"audit_interval_generations": AUDIT_INTERVAL_GENERATIONS,
		"audit_generation_1": AUDIT_GENERATION_1,
		"founder_seed": Workbench.FOUNDER_SEED,
		"placement_seed": Workbench.PLACEMENT_SEED,
		"evolution_seed": Workbench.EVOLUTION_SEED,
		"environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
	}
	if not bool(Contract.validate_workload(workload).get("success", false)):
		return {}

	var wb = Workbench.new()
	var requested_spec: Dictionary = Workbench.default_spec()
	requested_spec["world_seed"] = Workbench.DEFAULT_WORLD_SEED
	requested_spec["environment_seed"] = Workbench.DEFAULT_ENVIRONMENT_SEED
	requested_spec["environment_recipe"] = DEFAULT_RECIPE
	requested_spec["competition_enabled"] = true
	if not wb.setup(planet_source, requested_spec):
		return {}

	var executor = StreamExecutor.new()
	if not executor.setup({
		"parents_per_chunk": chunk_size,
		"audit_interval": AUDIT_INTERVAL_GENERATIONS,
		"audit_generation_1": AUDIT_GENERATION_1,
		"pipeline_mode": pipeline_mode,
	}):
		return {}
	if not wb.set_generation_stream_executor(executor):
		return {}

	for _warmup in range(precondition_generations):
		if wb.advance_generations(1).is_empty():
			return {}

	var telemetry_before: Dictionary = executor.get_telemetry()
	var probe := Probe.new()
	if not bool(probe.begin().get("success", false)):
		return {}

	var timing_sums := {
		"generation_total_ms": 0.0,
		"ls33_total_ms": 0.0,
		"stream_total_ms": 0.0,
		"candidate_build_ms": 0.0,
		"route_build_ms": 0.0,
		"recruitment_eval_ms": 0.0,
		"audit_ms": 0.0,
	}
	var final_ls33: Dictionary = {}
	var max_parent_chunk := 0
	var max_candidate_chunk := 0
	for _measured in range(MEASURED_GENERATIONS):
		if wb.advance_generations(1).is_empty():
			return {}
		var profile: Dictionary = wb.get_last_generation_profile()
		var ecology_profile: Dictionary = Dictionary(profile.get("ecology", {}))
		var ls33: Dictionary = Dictionary(ecology_profile.get("ls33", {}))
		var stream_timings: Dictionary = Dictionary(ls33.get("timings_ms", {}))
		if profile.is_empty() or ls33.is_empty() or stream_timings.is_empty():
			return {}
		timing_sums["generation_total_ms"] += float(profile.get("total_ms", -1.0))
		timing_sums["ls33_total_ms"] += float(ecology_profile.get("ls33_total_ms", -1.0))
		timing_sums["stream_total_ms"] += float(stream_timings.get("total_ms", -1.0))
		timing_sums["candidate_build_ms"] += float(ls33.get("candidate_build_ms", -1.0))
		timing_sums["route_build_ms"] += float(ls33.get("route_build_ms", -1.0))
		timing_sums["recruitment_eval_ms"] += float(ls33.get("recruitment_eval_ms", -1.0))
		timing_sums["audit_ms"] += float(stream_timings.get("audit_ms", -1.0))
		max_parent_chunk = maxi(max_parent_chunk, int(ls33.get("stream_max_parent_chunk", 0)))
		max_candidate_chunk = maxi(max_candidate_chunk, int(ls33.get("stream_max_candidate_chunk", 0)))
		final_ls33 = ls33.duplicate(true)

	var observed: Dictionary = probe.finish()
	if not bool(observed.get("success", false)):
		return {}

	var telemetry_after: Dictionary = executor.get_telemetry()
	var operation_delta: Dictionary = _telemetry_delta(telemetry_before, telemetry_after)
	if operation_delta.is_empty():
		return {}
	if String(telemetry_after.get("pipeline_mode", "")) != pipeline_mode:
		return {}

	var measured_count := float(MEASURED_GENERATIONS)
	var timings := {
		"wall_ms": float(observed.get("wall_ms", -1.0)) / measured_count,
		"generation_total_ms": float(timing_sums["generation_total_ms"]) / measured_count,
		"ls33_total_ms": float(timing_sums["ls33_total_ms"]) / measured_count,
		"stream_total_ms": float(timing_sums["stream_total_ms"]) / measured_count,
		"candidate_build_ms": float(timing_sums["candidate_build_ms"]) / measured_count,
		"route_build_ms": float(timing_sums["route_build_ms"]) / measured_count,
		"recruitment_eval_ms": float(timing_sums["recruitment_eval_ms"]) / measured_count,
		"audit_ms": float(timing_sums["audit_ms"]) / measured_count,
	}
	for value in timings.values():
		if not _finite_nonnegative(value):
			return {}

	var snapshot: Dictionary = wb.get_workbench_snapshot()
	var ecology_snapshot: Dictionary = wb.get_ecology_snapshot()
	if snapshot.is_empty() or ecology_snapshot.is_empty():
		return {}

	var memory: Dictionary = Dictionary(observed.get("memory_bytes", {}))
	var sample := {
		"schema": Contract.SAMPLE_SCHEMA,
		"version": Contract.VERSION,
		"revision": Contract.REVISION,
		"run_id": "perf2-4-r1-%s-chunk%d-%s-r%d" % [
			scale_id.to_lower(), chunk_size, _pipeline_short(pipeline_mode), repetition],
		"target": target.duplicate(true),
		"host_fingerprint": host_fingerprint,
		"measurement_method_revision": Contract.REVISION,
		"workload": workload,
		"workload_hash": Contract.workload_hash(workload),
		"passed": true,
		"canonical_result": {
			"final_workbench_hash": String(snapshot.get("workbench_hash", "")),
			"final_ecology_state_hash": String(snapshot.get("ecology_state_hash", "")),
			"final_population_hash": String(snapshot.get("population_hash", "")),
			"final_classification_hash": String(snapshot.get("classification_hash", "")),
		},
		"metrics": {
			"timings_ms": timings,
			"counts": {
				"generation": int(snapshot.get("generation", -1)),
				"population": int(ecology_snapshot.get("record_count", -1)),
				"parent_count": int(final_ls33.get("parent_count", 0)),
				"candidate_count": int(final_ls33.get("candidate_count", 0)),
				"chunk_count": int(final_ls33.get("stream_chunk_count", 0)),
				"max_parent_chunk": max_parent_chunk,
				"max_candidate_chunk": max_candidate_chunk,
			},
			"memory_bytes": {
				"engine_static_bytes": int(memory.get("engine_static_bytes", 0)),
				"engine_static_peak_bytes": int(memory.get("engine_static_peak_bytes", 0)),
				"process_rss_bytes": memory.get("process_rss_bytes"),
				"process_peak_rss_bytes": memory.get("process_peak_rss_bytes"),
			},
			"stream": {
				"stream_calls": int(operation_delta["stream_calls"]),
				"chunks_processed": int(operation_delta["chunks_processed"]),
				"serial_audit_calls": int(operation_delta["serial_audit_calls"]),
				"oracle_elided_generations": int(operation_delta["oracle_elided_generations"]),
			},
			"window": {
				"measured_generations": MEASURED_GENERATIONS,
				"total_wall_ms": float(observed.get("wall_ms", -1.0)),
			},
		},
		"flags": {
			"canonical": false,
			"side_channel_only": true,
			"measurement_only": true,
			"configuration_id": "STREAM1_CHUNK_%d" % chunk_size,
			"stream_chunk_size": chunk_size,
			"scale_id": scale_id,
			"precondition_generations": precondition_generations,
			"pipeline_mode": pipeline_mode,
			"campaign_context_hash": context_hash,
			"timing_aggregation": "MEAN_PER_MEASURED_GENERATION",
			"optimization_operations": operation_delta,
		},
	}
	if not bool(Contract.validate_sample(sample).get("success", false)):
		return {}
	if not _operation_contract_valid(sample):
		return {}
	return sample


func _telemetry_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var keys := [
		"stream_calls", "chunks_processed", "serial_audit_calls",
		"oracle_elided_generations", "legacy_generation_calls",
		"optimized_generation_calls", "chunk_local_parent_sorts",
		"chunk_local_candidate_sorts", "chunk_local_route_sorts",
		"chunk_local_recruitment_sorts", "recruitment_context_builds",
		"generation_boundary_sorts",
	]
	var delta := {}
	for key in keys:
		if not _is_integral_number(before.get(key, 0)) or not _is_integral_number(after.get(key, 0)):
			return {}
		var value := int(after.get(key, 0)) - int(before.get(key, 0))
		if value < 0:
			return {}
		delta[key] = value
	return delta


func _operation_contract_valid(sample: Dictionary) -> bool:
	var flags: Dictionary = Dictionary(sample.get("flags", {}))
	var operations: Dictionary = Dictionary(flags.get("optimization_operations", {}))
	var pipeline_mode := String(flags.get("pipeline_mode", ""))
	var stream: Dictionary = Dictionary(Dictionary(sample.get("metrics", {})).get("stream", {}))
	if int(stream.get("stream_calls", -1)) != MEASURED_GENERATIONS:
		return false
	if int(stream.get("serial_audit_calls", -1)) != 1:
		return false
	if int(stream.get("oracle_elided_generations", -1)) != MEASURED_GENERATIONS - 1:
		return false
	var chunks := int(stream.get("chunks_processed", 0))
	if chunks <= 0:
		return false
	if int(operations.get("generation_boundary_sorts", -1)) != MEASURED_GENERATIONS * 3:
		return false

	if pipeline_mode == StreamExecutor.PIPELINE_LEGACY:
		if int(operations.get("legacy_generation_calls", -1)) != MEASURED_GENERATIONS:
			return false
		if int(operations.get("optimized_generation_calls", -1)) != 0:
			return false
		for key in [
			"chunk_local_parent_sorts", "chunk_local_candidate_sorts",
			"chunk_local_route_sorts", "chunk_local_recruitment_sorts",
			"recruitment_context_builds",
		]:
			if int(operations.get(key, -1)) != chunks:
				return false
		return true

	if pipeline_mode == StreamExecutor.PIPELINE_OPTIMIZED:
		if int(operations.get("legacy_generation_calls", -1)) != 0:
			return false
		if int(operations.get("optimized_generation_calls", -1)) != MEASURED_GENERATIONS:
			return false
		for key in [
			"chunk_local_parent_sorts", "chunk_local_candidate_sorts",
			"chunk_local_route_sorts", "chunk_local_recruitment_sorts",
		]:
			if int(operations.get(key, -1)) != 0:
				return false
		if int(operations.get("recruitment_context_builds", -1)) != MEASURED_GENERATIONS:
			return false
		return true
	return false


func _build_comparisons(samples: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for scale_id in SCALE_IDS:
		for chunk_size in STREAM_CHUNK_SIZES:
			var legacy: Array[Dictionary] = _group(samples, scale_id, chunk_size, StreamExecutor.PIPELINE_LEGACY)
			var optimized: Array[Dictionary] = _group(samples, scale_id, chunk_size, StreamExecutor.PIPELINE_OPTIMIZED)
			if legacy.size() != REPETITIONS or optimized.size() != REPETITIONS:
				return []

			var exact_pairs := 0
			for repetition in range(REPETITIONS):
				var baseline: Dictionary = _find_sample(legacy, repetition)
				var candidate: Dictionary = _find_sample(optimized, repetition)
				if baseline.is_empty() or candidate.is_empty():
					return []
				if bool(Contract.can_compare(baseline, candidate).get("success", false)):
					exact_pairs += 1
			if exact_pairs != REPETITIONS:
				return []

			var legacy_wall: Dictionary = Contract.summarize(legacy, "timings_ms.wall_ms")
			var optimized_wall: Dictionary = Contract.summarize(optimized, "timings_ms.wall_ms")
			var legacy_stream: Dictionary = Contract.summarize(legacy, "timings_ms.stream_total_ms")
			var optimized_stream: Dictionary = Contract.summarize(optimized, "timings_ms.stream_total_ms")
			var legacy_recruitment: Dictionary = Contract.summarize(legacy, "timings_ms.recruitment_eval_ms")
			var optimized_recruitment: Dictionary = Contract.summarize(optimized, "timings_ms.recruitment_eval_ms")
			if legacy_wall.is_empty() or optimized_wall.is_empty() or legacy_stream.is_empty() or optimized_stream.is_empty():
				return []

			var legacy_wall_p50 := float(legacy_wall.get("p50", 0.0))
			var optimized_wall_p50 := float(optimized_wall.get("p50", 0.0))
			var legacy_stream_p50 := float(legacy_stream.get("p50", 0.0))
			var optimized_stream_p50 := float(optimized_stream.get("p50", 0.0))
			if optimized_wall_p50 <= 0.0 or optimized_stream_p50 <= 0.0:
				return []

			var legacy_proxy := _record_proxy_p50(legacy)
			var optimized_proxy := _record_proxy_p50(optimized)
			if legacy_proxy <= 0.0 or optimized_proxy <= 0.0 or not is_equal_approx(legacy_proxy, optimized_proxy):
				return []

			var legacy_chunks := _operation_p50(legacy, "chunks_processed")
			var legacy_contexts := _operation_p50(legacy, "recruitment_context_builds")
			var optimized_contexts := _operation_p50(optimized, "recruitment_context_builds")
			if legacy_chunks <= 0.0 or optimized_contexts <= 0.0:
				return []

			result.append({
				"scale_id": scale_id,
				"precondition_generations": PRECONDITION_GENERATIONS[SCALE_IDS.find(scale_id)],
				"stream_chunk_size": chunk_size,
				"exact_pairs": exact_pairs,
				"legacy_wall_p50_ms": legacy_wall_p50,
				"optimized_wall_p50_ms": optimized_wall_p50,
				"wall_speedup_legacy_over_optimized": legacy_wall_p50 / optimized_wall_p50,
				"legacy_stream_p50_ms": legacy_stream_p50,
				"optimized_stream_p50_ms": optimized_stream_p50,
				"stream_speedup_legacy_over_optimized": legacy_stream_p50 / optimized_stream_p50,
				"legacy_recruitment_p50_ms": float(legacy_recruitment.get("p50", 0.0)),
				"optimized_recruitment_p50_ms": float(optimized_recruitment.get("p50", 0.0)),
				"record_proxy_p50": legacy_proxy,
				"bounded_working_set_preserved": true,
				"legacy_chunks_processed_p50": legacy_chunks,
				"legacy_recruitment_context_builds_p50": legacy_contexts,
				"optimized_recruitment_context_builds_p50": optimized_contexts,
				"context_build_reduction_factor": legacy_contexts / optimized_contexts,
				"legacy_chunk_local_sorts_p50": _chunk_sort_p50(legacy),
				"optimized_chunk_local_sorts_p50": _chunk_sort_p50(optimized),
				"operation_reduction_proven": _group_operation_reduction_proven(legacy, optimized),
				"wall_point_nonregressed": legacy_wall_p50 / optimized_wall_p50 >= MIN_POINT_WALL_RATIO,
				"wall_point_improved": legacy_wall_p50 > optimized_wall_p50,
			})
	return result


func _build_optimization_summary(comparisons: Array[Dictionary]) -> Dictionary:
	if comparisons.size() != 9:
		return {}
	var wall_ratios: Array[float] = []
	var stream_ratios: Array[float] = []
	var exact_pairs := 0
	var improved_points := 0
	var nonregressed_points := 0
	var operation_reduction_proven := true
	var bounded_working_set_preserved := true
	for comparison in comparisons:
		var wall_ratio := float(comparison.get("wall_speedup_legacy_over_optimized", 0.0))
		var stream_ratio := float(comparison.get("stream_speedup_legacy_over_optimized", 0.0))
		if not _finite_positive(wall_ratio) or not _finite_positive(stream_ratio):
			return {}
		wall_ratios.append(wall_ratio)
		stream_ratios.append(stream_ratio)
		exact_pairs += int(comparison.get("exact_pairs", 0))
		if bool(comparison.get("wall_point_improved", false)):
			improved_points += 1
		if bool(comparison.get("wall_point_nonregressed", false)):
			nonregressed_points += 1
		operation_reduction_proven = operation_reduction_proven and bool(comparison.get("operation_reduction_proven", false))
		bounded_working_set_preserved = bounded_working_set_preserved and bool(comparison.get("bounded_working_set_preserved", false))

	var wall_geomean := _geometric_mean(wall_ratios)
	var stream_geomean := _geometric_mean(stream_ratios)
	var claim := (
		exact_pairs == TOTAL_AB_PAIRS
		and operation_reduction_proven
		and bounded_working_set_preserved
		and improved_points >= MIN_IMPROVED_WALL_POINTS
		and nonregressed_points == comparisons.size()
		and wall_geomean >= MIN_WALL_GEOMEAN_SPEEDUP
		and stream_geomean >= MIN_STREAM_GEOMEAN_SPEEDUP
	)
	return {
		"exact_pairs": exact_pairs,
		"comparison_points": comparisons.size(),
		"wall_geomean_speedup": wall_geomean,
		"stream_geomean_speedup": stream_geomean,
		"improved_wall_points": improved_points,
		"nonregressed_wall_points": nonregressed_points,
		"operation_reduction_proven": operation_reduction_proven,
		"bounded_working_set_preserved": bounded_working_set_preserved,
		"optimization_claim": claim,
		"serial_crossover_required": false,
	}


func _validate_optimization_policy(policy: Dictionary) -> bool:
	return (
		String(policy.get("baseline_pipeline", "")) == StreamExecutor.PIPELINE_LEGACY
		and String(policy.get("candidate_pipeline", "")) == StreamExecutor.PIPELINE_OPTIMIZED
		and _integer_array_equals(Array(policy.get("scale_points", [])), PRECONDITION_GENERATIONS)
		and _integer_array_equals(Array(policy.get("stream_chunk_sizes", [])), STREAM_CHUNK_SIZES)
		and _integer_value_equals(policy.get("measured_generations"), MEASURED_GENERATIONS)
		and _integer_value_equals(policy.get("repetitions"), REPETITIONS)
		and _integer_value_equals(policy.get("total_samples"), TOTAL_SAMPLES)
		and _integer_value_equals(policy.get("exact_ab_pairs_required"), TOTAL_AB_PAIRS)
		and String(policy.get("balanced_order", "")) == "R0_LEGACY_FIRST__R1_OPTIMIZED_FIRST__R2_LEGACY_FIRST"
		and is_equal_approx(float(policy.get("min_wall_geomean_speedup", 0.0)), MIN_WALL_GEOMEAN_SPEEDUP)
		and is_equal_approx(float(policy.get("min_stream_geomean_speedup", 0.0)), MIN_STREAM_GEOMEAN_SPEEDUP)
		and is_equal_approx(float(policy.get("min_point_wall_ratio", 0.0)), MIN_POINT_WALL_RATIO)
		and _integer_value_equals(policy.get("min_improved_wall_points"), MIN_IMPROVED_WALL_POINTS)
		and typeof(policy.get("serial_crossover_required")) == TYPE_BOOL
		and not bool(policy.get("serial_crossover_required"))
		and bool(policy.get("canonical_parity_required", false))
		and not bool(policy.get("bounded_working_set_regression_allowed", true))
	)


func _validate_sample_flags(flags: Dictionary) -> bool:
	var scale_id := String(flags.get("scale_id", ""))
	if scale_id not in SCALE_IDS:
		return false
	var index := SCALE_IDS.find(scale_id)
	if not _integer_value_equals(flags.get("precondition_generations"), PRECONDITION_GENERATIONS[index]):
		return false
	if String(flags.get("pipeline_mode", "")) not in PIPELINE_MODES:
		return false
	if not _is_integral_number(flags.get("stream_chunk_size")):
		return false
	var chunk_size := int(flags.get("stream_chunk_size"))
	if chunk_size not in STREAM_CHUNK_SIZES:
		return false
	if String(flags.get("configuration_id", "")) != "STREAM1_CHUNK_%d" % chunk_size:
		return false
	var operations: Dictionary = Dictionary(flags.get("optimization_operations", {}))
	if operations.size() != 12:
		return false
	for value in operations.values():
		if not _is_integral_number(value) or int(value) < 0:
			return false
	return true


func _validate_exact_ab_pairs(samples: Array[Dictionary]) -> bool:
	var exact := 0
	for scale_id in SCALE_IDS:
		for chunk_size in STREAM_CHUNK_SIZES:
			var legacy: Array[Dictionary] = _group(samples, scale_id, chunk_size, StreamExecutor.PIPELINE_LEGACY)
			var optimized: Array[Dictionary] = _group(samples, scale_id, chunk_size, StreamExecutor.PIPELINE_OPTIMIZED)
			if legacy.size() != REPETITIONS or optimized.size() != REPETITIONS:
				return false
			for repetition in range(REPETITIONS):
				var a: Dictionary = _find_sample(legacy, repetition)
				var b: Dictionary = _find_sample(optimized, repetition)
				if a.is_empty() or b.is_empty():
					return false
				if not bool(Contract.can_compare(a, b).get("success", false)):
					return false
				if not _operation_contract_valid(a) or not _operation_contract_valid(b):
					return false
				exact += 1
	return exact == TOTAL_AB_PAIRS


func _validate_comparison(comparison: Dictionary) -> bool:
	var required := [
		"scale_id", "precondition_generations", "stream_chunk_size", "exact_pairs",
		"legacy_wall_p50_ms", "optimized_wall_p50_ms", "wall_speedup_legacy_over_optimized",
		"legacy_stream_p50_ms", "optimized_stream_p50_ms", "stream_speedup_legacy_over_optimized",
		"legacy_recruitment_p50_ms", "optimized_recruitment_p50_ms",
		"record_proxy_p50", "bounded_working_set_preserved",
		"legacy_chunks_processed_p50", "legacy_recruitment_context_builds_p50",
		"optimized_recruitment_context_builds_p50", "context_build_reduction_factor",
		"legacy_chunk_local_sorts_p50", "optimized_chunk_local_sorts_p50",
		"operation_reduction_proven", "wall_point_nonregressed", "wall_point_improved",
	]
	if comparison.size() != required.size():
		return false
	for key in required:
		if not comparison.has(key):
			return false
	var scale_id := String(comparison["scale_id"])
	if scale_id not in SCALE_IDS:
		return false
	if not _integer_value_equals(comparison["precondition_generations"], PRECONDITION_GENERATIONS[SCALE_IDS.find(scale_id)]):
		return false
	if not _is_integral_number(comparison["stream_chunk_size"]):
		return false
	if int(comparison["stream_chunk_size"]) not in STREAM_CHUNK_SIZES:
		return false
	if not _integer_value_equals(comparison["exact_pairs"], REPETITIONS):
		return false
	for key in [
		"legacy_wall_p50_ms", "optimized_wall_p50_ms", "wall_speedup_legacy_over_optimized",
		"legacy_stream_p50_ms", "optimized_stream_p50_ms", "stream_speedup_legacy_over_optimized",
		"record_proxy_p50", "legacy_chunks_processed_p50",
		"legacy_recruitment_context_builds_p50", "optimized_recruitment_context_builds_p50",
		"context_build_reduction_factor",
	]:
		if not _finite_positive(comparison[key]):
			return false
	for key in ["legacy_recruitment_p50_ms", "optimized_recruitment_p50_ms", "legacy_chunk_local_sorts_p50", "optimized_chunk_local_sorts_p50"]:
		if not _finite_nonnegative(comparison[key]):
			return false
	if not bool(comparison["bounded_working_set_preserved"]):
		return false
	if not bool(comparison["operation_reduction_proven"]):
		return false
	if float(comparison["optimized_chunk_local_sorts_p50"]) != 0.0:
		return false
	if float(comparison["context_build_reduction_factor"]) < 1.0:
		return false
	return true


func _validate_optimization_summary(summary: Dictionary, comparisons: Array) -> bool:
	var expected: Dictionary = _build_optimization_summary(_typed_comparisons(comparisons))
	if expected.is_empty() or summary.size() != expected.size():
		return false
	for key in expected.keys():
		if not summary.has(key):
			return false
		if typeof(expected[key]) in [TYPE_FLOAT, TYPE_INT]:
			if not is_equal_approx(float(summary[key]), float(expected[key])):
				return false
		elif summary[key] != expected[key]:
			return false
	return true


func _typed_comparisons(source: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value in source:
		if not value is Dictionary:
			return []
		out.append(Dictionary(value))
	return out


func _group(samples: Array[Dictionary], scale_id: String, chunk_size: int, pipeline_mode: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sample in samples:
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		if (
			String(flags.get("scale_id", "")) == scale_id
			and int(flags.get("stream_chunk_size", 0)) == chunk_size
			and String(flags.get("pipeline_mode", "")) == pipeline_mode
		):
			out.append(sample)
	return out


func _find_sample(group: Array[Dictionary], repetition: int) -> Dictionary:
	var suffix := "-r%d" % repetition
	for sample in group:
		if String(sample.get("run_id", "")).ends_with(suffix):
			return sample
	return {}


func _record_proxy_p50(group: Array[Dictionary]) -> float:
	var values: Array[float] = []
	for sample in group:
		var counts: Dictionary = Dictionary(Dictionary(sample.get("metrics", {})).get("counts", {}))
		values.append(float(int(counts.get("max_parent_chunk", 0)) + int(counts.get("max_candidate_chunk", 0))))
	return _p50(values)


func _operation_p50(group: Array[Dictionary], key: String) -> float:
	var values: Array[float] = []
	for sample in group:
		var operations: Dictionary = Dictionary(Dictionary(sample.get("flags", {})).get("optimization_operations", {}))
		values.append(float(operations.get(key, 0)))
	return _p50(values)


func _chunk_sort_p50(group: Array[Dictionary]) -> float:
	var values: Array[float] = []
	for sample in group:
		var operations: Dictionary = Dictionary(Dictionary(sample.get("flags", {})).get("optimization_operations", {}))
		var total := (
			int(operations.get("chunk_local_parent_sorts", 0))
			+ int(operations.get("chunk_local_candidate_sorts", 0))
			+ int(operations.get("chunk_local_route_sorts", 0))
			+ int(operations.get("chunk_local_recruitment_sorts", 0))
		)
		values.append(float(total))
	return _p50(values)


func _group_operation_reduction_proven(legacy: Array[Dictionary], optimized: Array[Dictionary]) -> bool:
	for sample in legacy:
		if not _operation_contract_valid(sample):
			return false
	for sample in optimized:
		if not _operation_contract_valid(sample):
			return false
	return (
		_chunk_sort_p50(legacy) > 0.0
		and _chunk_sort_p50(optimized) == 0.0
		and _operation_p50(legacy, "recruitment_context_builds") >= _operation_p50(optimized, "recruitment_context_builds")
	)


func _normalize_sample_for_contract(sample: Dictionary) -> Dictionary:
	var normalized: Dictionary = sample.duplicate(true)
	if not normalized.has("workload") or not normalized["workload"] is Dictionary:
		return {}
	var workload: Dictionary = Dictionary(normalized["workload"])
	for key in [
		"warmup_generations", "measured_generations", "repetitions", "initial_records",
		"parents_per_chunk", "audit_interval_generations", "founder_seed",
		"placement_seed", "evolution_seed", "environment_seed",
	]:
		if not workload.has(key) or not _is_integral_number(workload[key]):
			return {}
		workload[key] = int(workload[key])
	normalized["workload"] = workload

	var metrics: Dictionary = Dictionary(normalized.get("metrics", {}))
	var counts: Dictionary = Dictionary(metrics.get("counts", {}))
	for key in [
		"generation", "population", "parent_count", "candidate_count",
		"chunk_count", "max_parent_chunk", "max_candidate_chunk",
	]:
		if not counts.has(key) or not _is_integral_number(counts[key]):
			return {}
		counts[key] = int(counts[key])
	metrics["counts"] = counts

	var memory: Dictionary = Dictionary(metrics.get("memory_bytes", {}))
	for key in ["engine_static_bytes", "engine_static_peak_bytes"]:
		if not memory.has(key) or not _is_integral_number(memory[key]):
			return {}
		memory[key] = int(memory[key])
	for key in ["process_rss_bytes", "process_peak_rss_bytes"]:
		if memory.has(key) and memory[key] != null:
			if not _is_integral_number(memory[key]):
				return {}
			memory[key] = int(memory[key])
	metrics["memory_bytes"] = memory

	var stream: Dictionary = Dictionary(metrics.get("stream", {}))
	for key in ["stream_calls", "chunks_processed", "serial_audit_calls", "oracle_elided_generations"]:
		if not stream.has(key) or not _is_integral_number(stream[key]):
			return {}
		stream[key] = int(stream[key])
	metrics["stream"] = stream

	var window: Dictionary = Dictionary(metrics.get("window", {}))
	if not _is_integral_number(window.get("measured_generations")):
		return {}
	window["measured_generations"] = int(window["measured_generations"])
	metrics["window"] = window
	normalized["metrics"] = metrics

	var flags: Dictionary = Dictionary(normalized.get("flags", {}))
	for key in ["stream_chunk_size", "precondition_generations"]:
		if not flags.has(key) or not _is_integral_number(flags[key]):
			return {}
		flags[key] = int(flags[key])
	var operations: Dictionary = Dictionary(flags.get("optimization_operations", {}))
	for key in operations.keys():
		if not _is_integral_number(operations[key]):
			return {}
		operations[key] = int(operations[key])
	flags["optimization_operations"] = operations
	normalized["flags"] = flags
	return normalized


func _sample_hash(sample: Dictionary) -> String:
	var normalized: Dictionary = _normalize_sample_for_contract(sample)
	if normalized.is_empty():
		return ""
	var metrics: Dictionary = Dictionary(normalized.get("metrics", {}))
	var timings: Dictionary = Dictionary(metrics.get("timings_ms", {}))
	var counts: Dictionary = Dictionary(metrics.get("counts", {}))
	var flags: Dictionary = Dictionary(normalized.get("flags", {}))
	var operations: Dictionary = Dictionary(flags.get("optimization_operations", {}))
	var parts := PackedStringArray([
		"PERF2_4_SAMPLE_R1",
		String(normalized.get("run_id", "")),
		Contract.workload_hash(Dictionary(normalized.get("workload", {}))),
		Contract.canonical_result_fingerprint(normalized),
		String(flags.get("scale_id", "")),
		str(int(flags.get("stream_chunk_size", 0))),
		String(flags.get("pipeline_mode", "")),
	])
	for key in [
		"wall_ms", "generation_total_ms", "ls33_total_ms", "stream_total_ms",
		"candidate_build_ms", "route_build_ms", "recruitment_eval_ms", "audit_ms",
	]:
		parts.append("%s=%s" % [key, _stable_float_token(timings.get(key, 0.0))])
	for key in [
		"population", "parent_count", "candidate_count", "max_parent_chunk", "max_candidate_chunk",
	]:
		parts.append("%s=%d" % [key, int(counts.get(key, 0))])
	var operation_keys: Array = operations.keys()
	operation_keys.sort()
	for key in operation_keys:
		parts.append("%s=%d" % [String(key), int(operations[key])])
	return "|".join(parts).sha256_text()


func _comparison_hash(comparison: Dictionary) -> String:
	var numeric_keys := [
		"legacy_wall_p50_ms", "optimized_wall_p50_ms",
		"wall_speedup_legacy_over_optimized",
		"legacy_stream_p50_ms", "optimized_stream_p50_ms",
		"stream_speedup_legacy_over_optimized",
		"legacy_recruitment_p50_ms", "optimized_recruitment_p50_ms",
		"record_proxy_p50", "legacy_chunks_processed_p50",
		"legacy_recruitment_context_builds_p50",
		"optimized_recruitment_context_builds_p50",
		"context_build_reduction_factor",
		"legacy_chunk_local_sorts_p50", "optimized_chunk_local_sorts_p50",
	]
	var parts := PackedStringArray([
		String(comparison.get("scale_id", "")),
		str(int(comparison.get("precondition_generations", 0))),
		str(int(comparison.get("stream_chunk_size", 0))),
		str(int(comparison.get("exact_pairs", 0))),
	])
	for key in numeric_keys:
		parts.append("%s=%s" % [key, _stable_float_token(comparison.get(key, 0.0))])
	parts.append("bound=%d" % (1 if bool(comparison.get("bounded_working_set_preserved", false)) else 0))
	parts.append("ops=%d" % (1 if bool(comparison.get("operation_reduction_proven", false)) else 0))
	parts.append("nonregressed=%d" % (1 if bool(comparison.get("wall_point_nonregressed", false)) else 0))
	parts.append("improved=%d" % (1 if bool(comparison.get("wall_point_improved", false)) else 0))
	return "|".join(parts).sha256_text()


func _summary_hash(summary: Dictionary) -> String:
	return "|".join(PackedStringArray([
		str(int(summary.get("exact_pairs", 0))),
		str(int(summary.get("comparison_points", 0))),
		_stable_float_token(summary.get("wall_geomean_speedup", 0.0)),
		_stable_float_token(summary.get("stream_geomean_speedup", 0.0)),
		str(int(summary.get("improved_wall_points", 0))),
		str(int(summary.get("nonregressed_wall_points", 0))),
		"1" if bool(summary.get("operation_reduction_proven", false)) else "0",
		"1" if bool(summary.get("bounded_working_set_preserved", false)) else "0",
		"1" if bool(summary.get("optimization_claim", false)) else "0",
	])).sha256_text()


func _p50(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return ordered[int(ordered.size() / 2)]


func _geometric_mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var log_sum := 0.0
	for value in values:
		if not _finite_positive(value):
			return 0.0
		log_sum += log(value)
	return exp(log_sum / float(values.size()))


func _pipeline_short(pipeline_mode: String) -> String:
	return "legacy" if pipeline_mode == StreamExecutor.PIPELINE_LEGACY else "optimized"


func _integer_array_equals(actual: Array, expected: Array[int]) -> bool:
	if actual.size() != expected.size():
		return false
	for index in range(expected.size()):
		if not _integer_value_equals(actual[index], expected[index]):
			return false
	return true


func _integer_value_equals(value, expected: int) -> bool:
	return _is_integral_number(value) and int(value) == expected


func _is_integral_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)


func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


func _finite_positive(value) -> bool:
	return _finite_nonnegative(value) and float(value) > 0.0


func _stable_float_token(value) -> String:
	if not _finite_nonnegative(value):
		return "INVALID"
	## PERF2 timing sources ultimately originate from microsecond-resolution clocks.
	## Six decimal places in milliseconds are already three orders of magnitude
	## finer than source resolution and remain stable across Godot JSON float
	## stringify/parse round-trips.
	return "%.6f" % float(value)


func _valid_target(target: Dictionary) -> bool:
	return (
		_is_git_sha(String(target.get("head", "")))
		and _is_git_sha(String(target.get("tree", "")))
		and String(target.get("godot_version", "")) == Contract.EXPECTED_GODOT
	)


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


func _failure(code: String, detail) -> Dictionary:
	return {
		"success": false,
		"failure_code": code,
		"detail": detail,
	}
