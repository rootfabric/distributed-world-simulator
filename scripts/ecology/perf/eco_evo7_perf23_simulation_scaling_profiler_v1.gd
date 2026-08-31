extends RefCounted

## ECO.EVO7 PERF2.3 R1 — Simulation Scaling.
##
## Measurement-only scaling campaign over accepted public Workbench/STREAM1 seams.
## The scaling axis is generation-age preconditioning of the same deterministic
## workload. Precondition windows are spaced by exactly one audit interval so
## every measured 12-generation window contains one interval audit:
##
##   precondition 2  -> measured generations 3..14  -> audit at 10
##   precondition 12 -> measured generations 13..24 -> audit at 20
##   precondition 22 -> measured generations 23..34 -> audit at 30
##
## No ecology/runtime optimization is performed here.

const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Probe = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd")
const StreamExecutor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_perf2_3.simulation_scaling_report.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PERF2.3-R1"
const MODE := "RESEARCH_SHADOW_PERFORMANCE_ONLY"

const FROZEN_PERF2_CONTRACT_REVISION := "ECO.EVO7-PERF2.0-R1"
const FROZEN_PERF2_CONTRACT_BLOB_SHA := "b076784f6b4016a0191e937c4e6ada1fe90c783b"
const ACCEPTED_PERF22_HEAD := "c6bef3d6c20d7b468f88f9aaabade2fe809b63e6"
const ACCEPTED_PERF22_TREE := "57d4807095e1e1096a13b665b1ef1a1a90d5dc98"

const DEFAULT_RECIPE := "MIXED_PHYSICAL_HETEROGENEITY"
const PRECONDITION_GENERATIONS: Array[int] = [2, 12, 22]
const SCALE_IDS: Array[String] = ["AGE_2", "AGE_12", "AGE_22"]
const MEASURED_GENERATIONS := 12
const REPETITIONS := 3
const AUDIT_INTERVAL_GENERATIONS := 10
const AUDIT_GENERATION_1 := true
const STREAM_CHUNK_SIZES: Array[int] = [1, 7, 64]
const EXECUTION_CONFIG_IDS: Array[String] = [
	"SERIAL_REFERENCE",
	"STREAM1_CHUNK_1",
	"STREAM1_CHUNK_7",
	"STREAM1_CHUNK_64",
]
const TOTAL_GENERATION_ADVANCES := 864

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
}

const SCALE_POLICY := {
	"kind": "GENERATION_AGE_PRECONDITION",
	"precondition_generations": [2, 12, 22],
	"measured_generations": 12,
	"repetitions": 3,
	"audit_interval_generations": 10,
	"audit_generation_1": true,
	"stream_chunk_sizes": [1, 7, 64],
	"execution_configurations": 4,
	"total_samples": 36,
	"total_generation_advances": 864,
	"audit_alignment": "ONE_INTERVAL_AUDIT_PER_MEASURED_WINDOW",
	"initial_records": 64,
	"load_axis_claim": "OBSERVED_GENERATION_AGED_POPULATION_NOT_SYNTHETIC_INITIAL_LOAD",
}

const TIMING_METRICS: Array[String] = [
	"wall_ms",
	"generation_total_ms",
	"ls33_total_ms",
	"candidate_build_ms",
	"route_build_ms",
	"recruitment_eval_ms",
]


func run_campaign(planet_source, target: Dictionary, host_fingerprint: String) -> Dictionary:
	if planet_source == null:
		return _failure("PLANET_SOURCE", [])
	if not _valid_target(target):
		return _failure("TARGET", [])
	if not _is_hash(host_fingerprint):
		return _failure("HOST_FINGERPRINT", [])
	if Contract.REVISION != FROZEN_PERF2_CONTRACT_REVISION:
		return _failure("PERF2_REVISION_DRIFT", [])

	var context := _campaign_context()
	var context_hash := campaign_context_hash(context)
	if context.is_empty() or not _is_hash(context_hash):
		return _failure("CAMPAIGN_CONTEXT", [])

	var samples: Array[Dictionary] = []
	for scale_index in range(PRECONDITION_GENERATIONS.size()):
		var scale_id := SCALE_IDS[scale_index]
		var precondition := PRECONDITION_GENERATIONS[scale_index]
		for repetition in range(REPETITIONS):
			var serial := _run_repetition(
				planet_source, target, host_fingerprint, context_hash,
				scale_id, precondition, "SERIAL_REFERENCE", 0, repetition)
			if serial.is_empty():
				return _failure("SERIAL_REPETITION", [scale_id, repetition])
			samples.append(serial)

			for chunk_size in STREAM_CHUNK_SIZES:
				var streamed := _run_repetition(
					planet_source, target, host_fingerprint, context_hash,
					scale_id, precondition, "STREAM1", chunk_size, repetition)
				if streamed.is_empty():
					return _failure("STREAM_REPETITION", [scale_id, chunk_size, repetition])
				samples.append(streamed)

	if samples.size() != 36:
		return _failure("SAMPLE_COUNT", [samples.size()])

	var points := _build_points(samples)
	if points.size() != 12:
		return _failure("POINT_COUNT", [points.size()])

	var comparisons := _build_comparisons(samples, points)
	if comparisons.size() != 9:
		return _failure("COMPARISON_COUNT", [comparisons.size()])

	var trends := _build_trends(points)
	if trends.size() != 4:
		return _failure("TREND_COUNT", [trends.size()])

	var crossovers := _build_crossovers(comparisons)
	if crossovers.size() != 3:
		return _failure("CROSSOVER_COUNT", [crossovers.size()])

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"target": target.duplicate(true),
		"host_fingerprint": host_fingerprint,
		"accepted_predecessor": {
			"perf2_2_head": ACCEPTED_PERF22_HEAD,
			"perf2_2_tree": ACCEPTED_PERF22_TREE,
			"perf2_contract_revision": FROZEN_PERF2_CONTRACT_REVISION,
			"perf2_contract_blob_sha": FROZEN_PERF2_CONTRACT_BLOB_SHA,
		},
		"campaign_context": context,
		"campaign_context_hash": context_hash,
		"scale_policy": SCALE_POLICY.duplicate(true),
		"samples": samples,
		"scaling_points": points,
		"comparisons": comparisons,
		"trends": trends,
		"crossovers": crossovers,
		"authorities": AUTHORITIES.duplicate(true),
		"claims": {
			"simulation_scaling_observation": true,
			"crossover_observation": "HOST_LOCAL_DIAGNOSTIC_ONLY",
			"memory_reduction_claim": false,
			"optimization_claim": false,
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
		"scale_policy", "samples", "scaling_points", "comparisons", "trends",
		"crossovers", "authorities", "claims", "report_hash",
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
	if String(predecessor.get("perf2_2_head", "")) != ACCEPTED_PERF22_HEAD:
		return false
	if String(predecessor.get("perf2_2_tree", "")) != ACCEPTED_PERF22_TREE:
		return false
	if String(predecessor.get("perf2_contract_revision", "")) != FROZEN_PERF2_CONTRACT_REVISION:
		return false
	if String(predecessor.get("perf2_contract_blob_sha", "")) != FROZEN_PERF2_CONTRACT_BLOB_SHA:
		return false

	var context: Dictionary = Dictionary(report["campaign_context"])
	var context_hash := campaign_context_hash(context)
	if not _is_hash(context_hash) or String(report["campaign_context_hash"]) != context_hash:
		return false
	if not _validate_scale_policy(Dictionary(report["scale_policy"])):
		return false
	if Dictionary(report["authorities"]) != AUTHORITIES:
		return false

	var claims: Dictionary = Dictionary(report["claims"])
	if claims.size() != 4:
		return false
	if not bool(claims.get("simulation_scaling_observation", false)):
		return false
	if String(claims.get("crossover_observation", "")) != "HOST_LOCAL_DIAGNOSTIC_ONLY":
		return false
	if bool(claims.get("memory_reduction_claim", true)) or bool(claims.get("optimization_claim", true)):
		return false

	var samples: Array = Array(report["samples"])
	if samples.size() != 36:
		return false
	var normalized_samples: Array[Dictionary] = []
	for value in samples:
		if not value is Dictionary:
			return false
		var normalized := _normalize_sample_for_contract(Dictionary(value))
		if normalized.is_empty():
			return false
		if not bool(Contract.validate_sample(normalized).get("success", false)):
			return false
		if not bool(normalized.get("passed", false)):
			return false
		var flags: Dictionary = Dictionary(normalized.get("flags", {}))
		if String(flags.get("campaign_context_hash", "")) != context_hash:
			return false
		if not _validate_sample_scale_flags(flags):
			return false
		normalized_samples.append(normalized)

	if not _validate_exact_parity(normalized_samples):
		return false

	var points: Array = Array(report["scaling_points"])
	if points.size() != 12:
		return false
	var point_keys := {}
	for value in points:
		if not value is Dictionary:
			return false
		var point: Dictionary = value
		if not _validate_point(point):
			return false
		var key := "%s|%s" % [String(point["scale_id"]), String(point["configuration_id"])]
		if point_keys.has(key):
			return false
		point_keys[key] = true
	if point_keys.size() != 12:
		return false

	var comparisons: Array = Array(report["comparisons"])
	if comparisons.size() != 9:
		return false
	var comparison_keys := {}
	for value in comparisons:
		if not value is Dictionary:
			return false
		var comparison: Dictionary = value
		if not _validate_comparison(comparison):
			return false
		var key := "%s|%d" % [String(comparison["scale_id"]), int(comparison["stream_chunk_size"])]
		if comparison_keys.has(key):
			return false
		comparison_keys[key] = true
	if comparison_keys.size() != 9:
		return false

	var trends: Array = Array(report["trends"])
	if trends.size() != 4:
		return false
	var trend_configs := {}
	for value in trends:
		if not value is Dictionary:
			return false
		var trend: Dictionary = value
		if not _validate_trend(trend):
			return false
		var configuration_id := String(trend["configuration_id"])
		if trend_configs.has(configuration_id):
			return false
		trend_configs[configuration_id] = true
	if trend_configs.size() != 4:
		return false

	var crossovers: Array = Array(report["crossovers"])
	if crossovers.size() != 3:
		return false
	var crossover_chunks := {}
	for value in crossovers:
		if not value is Dictionary:
			return false
		var crossover: Dictionary = value
		if not _validate_crossover(crossover):
			return false
		var chunk_size := int(crossover["stream_chunk_size"])
		if crossover_chunks.has(chunk_size):
			return false
		crossover_chunks[chunk_size] = true
	for chunk_size in STREAM_CHUNK_SIZES:
		if not crossover_chunks.has(chunk_size):
			return false

	return String(report["report_hash"]) == report_hash(report)


func write_report(report: Dictionary, path: String) -> bool:
	if path.strip_edges().is_empty() or not validate_report(report):
		return false
	var parent := path.get_base_dir()
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
	if typeof(context["planet_source_kind"]) != TYPE_STRING:
		return ""
	if not _is_integral_number(context["world_seed"]) or not _is_integral_number(context["environment_seed"]):
		return ""
	if typeof(context["environment_recipe"]) != TYPE_STRING:
		return ""
	if typeof(context["competition_enabled"]) != TYPE_BOOL:
		return ""
	if not _is_integral_number(context["grid_size"]):
		return ""
	if typeof(context["cell_size_m"]) not in [TYPE_INT, TYPE_FLOAT]:
		return ""
	var cell_size := float(context["cell_size_m"])
	if not is_finite(cell_size) or cell_size <= 0.0:
		return ""
	return "|".join(PackedStringArray([
		"PERF2_3_CONTEXT_R1",
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
	var point_hashes := PackedStringArray()
	for value in Array(report.get("scaling_points", [])):
		point_hashes.append(_point_hash(Dictionary(value)))
	var comparison_hashes := PackedStringArray()
	for value in Array(report.get("comparisons", [])):
		comparison_hashes.append(_comparison_hash(Dictionary(value)))
	var trend_hashes := PackedStringArray()
	for value in Array(report.get("trends", [])):
		trend_hashes.append(_trend_hash(Dictionary(value)))
	var crossover_hashes := PackedStringArray()
	for value in Array(report.get("crossovers", [])):
		crossover_hashes.append(_crossover_hash(Dictionary(value)))
	var target: Dictionary = Dictionary(report.get("target", {}))
	return "|".join(PackedStringArray([
		"PERF2_3_REPORT_R1",
		String(target.get("head", "")),
		String(target.get("tree", "")),
		String(target.get("godot_version", "")),
		String(report.get("host_fingerprint", "")),
		String(report.get("campaign_context_hash", "")),
		FROZEN_PERF2_CONTRACT_REVISION,
		FROZEN_PERF2_CONTRACT_BLOB_SHA,
		ACCEPTED_PERF22_HEAD,
		REVISION,
		";".join(sample_hashes),
		";".join(point_hashes),
		";".join(comparison_hashes),
		";".join(trend_hashes),
		";".join(crossover_hashes),
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


func _run_repetition(
	planet_source,
	target: Dictionary,
	host_fingerprint: String,
	context_hash: String,
	scale_id: String,
	precondition_generations: int,
	execution_mode: String,
	chunk_size: int,
	repetition: int
) -> Dictionary:
	var workload := _workload(precondition_generations, execution_mode, chunk_size)
	if not bool(Contract.validate_workload(workload).get("success", false)):
		return {}

	var wb = Workbench.new()
	var requested_spec := Workbench.default_spec()
	requested_spec["world_seed"] = Workbench.DEFAULT_WORLD_SEED
	requested_spec["environment_seed"] = Workbench.DEFAULT_ENVIRONMENT_SEED
	requested_spec["environment_recipe"] = DEFAULT_RECIPE
	requested_spec["competition_enabled"] = true
	if not wb.setup(planet_source, requested_spec):
		return {}

	var executor = null
	if execution_mode == "STREAM1":
		executor = StreamExecutor.new()
		if not executor.setup({
			"parents_per_chunk": chunk_size,
			"audit_interval": AUDIT_INTERVAL_GENERATIONS,
			"audit_generation_1": AUDIT_GENERATION_1,
		}):
			return {}
		if not wb.set_generation_stream_executor(executor):
			return {}

	for _warmup in range(precondition_generations):
		if wb.advance_generations(1).is_empty():
			return {}

	var telemetry_before := {
		"stream_calls": 0,
		"chunks_processed": 0,
		"serial_audit_calls": 0,
		"oracle_elided_generations": 0,
	}
	if execution_mode == "STREAM1":
		var raw_before: Dictionary = executor.get_telemetry()
		for key in telemetry_before.keys():
			telemetry_before[key] = int(raw_before.get(key, 0))

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
	var measured_max_parent_chunk := 0
	var measured_max_candidate_chunk := 0
	for _measured in range(MEASURED_GENERATIONS):
		if wb.advance_generations(1).is_empty():
			return {}
		var profile: Dictionary = wb.get_last_generation_profile()
		var ecology_profile: Dictionary = Dictionary(profile.get("ecology", {}))
		var ls33: Dictionary = Dictionary(ecology_profile.get("ls33", {}))
		if profile.is_empty() or ls33.is_empty():
			return {}
		timing_sums["generation_total_ms"] += float(profile.get("total_ms", -1.0))
		timing_sums["ls33_total_ms"] += float(ecology_profile.get("ls33_total_ms", -1.0))
		timing_sums["candidate_build_ms"] += float(ls33.get("candidate_build_ms", -1.0))
		timing_sums["route_build_ms"] += float(ls33.get("route_build_ms", -1.0))
		timing_sums["recruitment_eval_ms"] += float(ls33.get("recruitment_eval_ms", -1.0))
		if execution_mode == "STREAM1":
			var stream_timings: Dictionary = Dictionary(ls33.get("timings_ms", {}))
			timing_sums["stream_total_ms"] += float(stream_timings.get("total_ms", -1.0))
			timing_sums["audit_ms"] += float(stream_timings.get("audit_ms", -1.0))
			measured_max_parent_chunk = maxi(measured_max_parent_chunk, int(ls33.get("stream_max_parent_chunk", 0)))
			measured_max_candidate_chunk = maxi(measured_max_candidate_chunk, int(ls33.get("stream_max_candidate_chunk", 0)))
		else:
			measured_max_parent_chunk = maxi(measured_max_parent_chunk, int(ls33.get("parent_count", 0)))
			measured_max_candidate_chunk = maxi(measured_max_candidate_chunk, int(ls33.get("candidate_count", 0)))
		final_ls33 = ls33.duplicate(true)

	var observed: Dictionary = probe.finish()
	if not bool(observed.get("success", false)):
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

	var telemetry := {
		"stream_calls": 0,
		"chunks_processed": 0,
		"serial_audit_calls": 0,
		"oracle_elided_generations": 0,
	}
	var chunk_count := 1
	if execution_mode == "STREAM1":
		var raw_telemetry: Dictionary = executor.get_telemetry()
		for key in telemetry.keys():
			telemetry[key] = int(raw_telemetry.get(key, 0)) - int(telemetry_before.get(key, 0))
			if int(telemetry[key]) < 0:
				return {}
		chunk_count = int(final_ls33.get("stream_chunk_count", 0))
		if int(telemetry["stream_calls"]) != MEASURED_GENERATIONS:
			return {}
		if int(telemetry["serial_audit_calls"]) != 1:
			return {}
		if int(telemetry["oracle_elided_generations"]) != MEASURED_GENERATIONS - 1:
			return {}

	var memory: Dictionary = Dictionary(observed.get("memory_bytes", {}))
	var configuration_id := _configuration_id(execution_mode, chunk_size)
	var sample := {
		"schema": Contract.SAMPLE_SCHEMA,
		"version": Contract.VERSION,
		"revision": Contract.REVISION,
		"run_id": "perf2-3-r1-%s-%s-r%d" % [scale_id.to_lower(), configuration_id.to_lower(), repetition],
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
				"chunk_count": chunk_count,
				"max_parent_chunk": measured_max_parent_chunk,
				"max_candidate_chunk": measured_max_candidate_chunk,
			},
			"memory_bytes": {
				"engine_static_bytes": int(memory.get("engine_static_bytes", 0)),
				"engine_static_peak_bytes": int(memory.get("engine_static_peak_bytes", 0)),
				"process_rss_bytes": memory.get("process_rss_bytes"),
				"process_peak_rss_bytes": memory.get("process_peak_rss_bytes"),
			},
			"stream": telemetry,
			"window": {
				"measured_generations": MEASURED_GENERATIONS,
				"total_wall_ms": float(observed.get("wall_ms", -1.0)),
			},
		},
		"flags": {
			"canonical": false,
			"side_channel_only": true,
			"measurement_only": true,
			"configuration_id": configuration_id,
			"stream_chunk_size": chunk_size if execution_mode == "STREAM1" else 0,
			"scale_id": scale_id,
			"precondition_generations": precondition_generations,
			"measurement_start_generation": precondition_generations + 1,
			"measurement_end_generation": precondition_generations + MEASURED_GENERATIONS,
			"expected_interval_audit_generation": _expected_audit_generation(precondition_generations),
			"campaign_context_hash": context_hash,
			"timing_aggregation": "MEAN_PER_MEASURED_GENERATION",
		},
	}
	if not bool(Contract.validate_sample(sample).get("success", false)):
		return {}
	return sample


func _workload(precondition_generations: int, execution_mode: String, chunk_size: int) -> Dictionary:
	return {
		"workload_id": "PERF2_3_GENERATION_AGE_SCALING_R1",
		"execution_mode": execution_mode,
		"environment_recipe": DEFAULT_RECIPE,
		"warmup_generations": precondition_generations,
		"measured_generations": MEASURED_GENERATIONS,
		"repetitions": REPETITIONS,
		"initial_records": Workbench.INITIAL_RECORDS,
		"parents_per_chunk": chunk_size if execution_mode == "STREAM1" else Workbench.INITIAL_RECORDS,
		"audit_interval_generations": AUDIT_INTERVAL_GENERATIONS,
		"audit_generation_1": AUDIT_GENERATION_1 if execution_mode == "STREAM1" else false,
		"founder_seed": Workbench.FOUNDER_SEED,
		"placement_seed": Workbench.PLACEMENT_SEED,
		"evolution_seed": Workbench.EVOLUTION_SEED,
		"environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
	}


func _build_points(samples: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for scale_index in range(SCALE_IDS.size()):
		var scale_id := SCALE_IDS[scale_index]
		var precondition := PRECONDITION_GENERATIONS[scale_index]
		for configuration_id in EXECUTION_CONFIG_IDS:
			var group := _group(samples, scale_id, configuration_id)
			if group.size() != REPETITIONS:
				return []
			var point := _point_from_group(scale_id, precondition, configuration_id, group)
			if point.is_empty():
				return []
			result.append(point)
	return result


func _point_from_group(
	scale_id: String,
	precondition_generations: int,
	configuration_id: String,
	group: Array[Dictionary]
) -> Dictionary:
	var wall := Contract.summarize(group, "timings_ms.wall_ms")
	var generation := Contract.summarize(group, "timings_ms.generation_total_ms")
	var population := Contract.summarize(group, "counts.population")
	var parents := Contract.summarize(group, "counts.parent_count")
	var candidates := Contract.summarize(group, "counts.candidate_count")
	var static_end := Contract.summarize(group, "memory_bytes.engine_static_bytes")
	if wall.is_empty() or generation.is_empty() or population.is_empty() or parents.is_empty() or candidates.is_empty() or static_end.is_empty():
		return {}

	var proxy_values: Array[float] = []
	var structural_bound_proven := true
	var execution_mode := String(Dictionary(group[0]["workload"]).get("execution_mode", ""))
	var chunk_size := int(Dictionary(group[0]["flags"]).get("stream_chunk_size", 0))
	for sample in group:
		var counts: Dictionary = Dictionary(Dictionary(sample.get("metrics", {})).get("counts", {}))
		var parent_chunk := int(counts.get("max_parent_chunk", 0))
		var candidate_chunk := int(counts.get("max_candidate_chunk", 0))
		if parent_chunk <= 0 or candidate_chunk <= 0:
			return {}
		proxy_values.append(float(parent_chunk + candidate_chunk))
		if execution_mode == "SERIAL_REFERENCE":
			if parent_chunk < int(counts.get("parent_count", 0)) or candidate_chunk < int(counts.get("candidate_count", 0)):
				structural_bound_proven = false
		else:
			if parent_chunk > chunk_size or candidate_chunk > chunk_size * 2:
				structural_bound_proven = false
	if not structural_bound_proven:
		return {}

	return {
		"scale_id": scale_id,
		"precondition_generations": precondition_generations,
		"measurement_start_generation": precondition_generations + 1,
		"measurement_end_generation": precondition_generations + MEASURED_GENERATIONS,
		"expected_interval_audit_generation": _expected_audit_generation(precondition_generations),
		"configuration_id": configuration_id,
		"execution_mode": execution_mode,
		"stream_chunk_size": chunk_size,
		"repetitions": REPETITIONS,
		"wall_ms": _compact_summary(wall),
		"generation_total_ms": _compact_summary(generation),
		"final_population": _compact_summary(population),
		"final_parent_count": _compact_summary(parents),
		"final_candidate_count": _compact_summary(candidates),
		"record_proxy_upper_bound": _summary_values(proxy_values),
		"engine_static_end_bytes": _compact_summary(static_end),
		"structural_bound_proven": true,
		"allocator_memory_claim": "DIAGNOSTIC_ONLY",
	}


func _build_comparisons(samples: Array[Dictionary], points: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for scale_id in SCALE_IDS:
		var serial_point := _find_point(points, scale_id, "SERIAL_REFERENCE")
		if serial_point.is_empty():
			return []
		for chunk_size in STREAM_CHUNK_SIZES:
			var configuration_id := "STREAM1_CHUNK_%d" % chunk_size
			var stream_point := _find_point(points, scale_id, configuration_id)
			if stream_point.is_empty():
				return []
			var exact_pairs := 0
			for repetition in range(REPETITIONS):
				var serial := _find_sample(samples, scale_id, "SERIAL_REFERENCE", 0, repetition)
				var streamed := _find_sample(samples, scale_id, "STREAM1", chunk_size, repetition)
				if serial.is_empty() or streamed.is_empty():
					return []
				if bool(Contract.can_compare_execution_modes(serial, streamed).get("success", false)):
					exact_pairs += 1
			if exact_pairs != REPETITIONS:
				return []

			var serial_wall := float(Dictionary(serial_point["wall_ms"]).get("p50", 0.0))
			var stream_wall := float(Dictionary(stream_point["wall_ms"]).get("p50", 0.0))
			var serial_generation := float(Dictionary(serial_point["generation_total_ms"]).get("p50", 0.0))
			var stream_generation := float(Dictionary(stream_point["generation_total_ms"]).get("p50", 0.0))
			var serial_proxy := float(Dictionary(serial_point["record_proxy_upper_bound"]).get("p50", 0.0))
			var stream_proxy := float(Dictionary(stream_point["record_proxy_upper_bound"]).get("p50", 0.0))
			var serial_parents := float(Dictionary(serial_point["final_parent_count"]).get("p50", 0.0))
			var stream_parents := float(Dictionary(stream_point["final_parent_count"]).get("p50", 0.0))
			var serial_candidates := float(Dictionary(serial_point["final_candidate_count"]).get("p50", 0.0))
			var stream_candidates := float(Dictionary(stream_point["final_candidate_count"]).get("p50", 0.0))
			if minf(stream_wall, stream_generation, stream_proxy, stream_parents, stream_candidates) <= 0.0:
				return {}
			var wall_ratio := serial_wall / stream_wall
			var generation_ratio := serial_generation / stream_generation
			result.append({
				"scale_id": scale_id,
				"precondition_generations": int(serial_point["precondition_generations"]),
				"stream_chunk_size": chunk_size,
				"configuration_id": configuration_id,
				"exact_pairs": exact_pairs,
				"serial_wall_p50_ms": serial_wall,
				"stream_wall_p50_ms": stream_wall,
				"observed_wall_ratio_serial_over_stream": wall_ratio,
				"serial_generation_p50_ms": serial_generation,
				"stream_generation_p50_ms": stream_generation,
				"observed_generation_ratio_serial_over_stream": generation_ratio,
				"serial_parent_p50": serial_parents,
				"stream_parent_p50": stream_parents,
				"serial_candidate_p50": serial_candidates,
				"stream_candidate_p50": stream_candidates,
				"serial_record_proxy_p50": serial_proxy,
				"stream_record_proxy_p50": stream_proxy,
				"record_proxy_reduction_factor_serial_over_stream": serial_proxy / stream_proxy,
				"observed_faster_side": _faster_side(wall_ratio),
				"near_parity_band_5pct": wall_ratio >= 0.95 and wall_ratio <= 1.05,
				"crossover_claim": false,
				"optimization_claim": false,
			})
	return result


func _build_trends(points: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for configuration_id in EXECUTION_CONFIG_IDS:
		var low := _find_point(points, SCALE_IDS[0], configuration_id)
		var high := _find_point(points, SCALE_IDS[-1], configuration_id)
		if low.is_empty() or high.is_empty():
			return []
		var low_wall := float(Dictionary(low["wall_ms"]).get("p50", 0.0))
		var high_wall := float(Dictionary(high["wall_ms"]).get("p50", 0.0))
		var low_generation := float(Dictionary(low["generation_total_ms"]).get("p50", 0.0))
		var high_generation := float(Dictionary(high["generation_total_ms"]).get("p50", 0.0))
		var low_population := float(Dictionary(low["final_population"]).get("p50", 0.0))
		var high_population := float(Dictionary(high["final_population"]).get("p50", 0.0))
		var low_proxy := float(Dictionary(low["record_proxy_upper_bound"]).get("p50", 0.0))
		var high_proxy := float(Dictionary(high["record_proxy_upper_bound"]).get("p50", 0.0))
		if minf(low_wall, low_generation, low_population, low_proxy) <= 0.0:
			return []
		result.append({
			"configuration_id": configuration_id,
			"low_scale_id": SCALE_IDS[0],
			"high_scale_id": SCALE_IDS[-1],
			"low_precondition_generations": PRECONDITION_GENERATIONS[0],
			"high_precondition_generations": PRECONDITION_GENERATIONS[-1],
			"low_population_p50": low_population,
			"high_population_p50": high_population,
			"population_growth_factor": high_population / low_population,
			"wall_growth_factor": high_wall / low_wall,
			"generation_time_growth_factor": high_generation / low_generation,
			"record_proxy_growth_factor": high_proxy / low_proxy,
			"scaling_observation": "HOST_LOCAL_DIAGNOSTIC",
			"optimization_claim": false,
		})
	return result


func _build_crossovers(comparisons: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chunk_size in STREAM_CHUNK_SIZES:
		var ratios: Array[float] = []
		var faster_sides: Array[String] = []
		var transition := ""
		var previous_side := ""
		for scale_id in SCALE_IDS:
			var comparison := _find_comparison(comparisons, scale_id, chunk_size)
			if comparison.is_empty():
				return []
			var ratio := float(comparison.get("observed_wall_ratio_serial_over_stream", 0.0))
			if not _finite_positive(ratio):
				return []
			var side := _faster_side(ratio)
			ratios.append(ratio)
			faster_sides.append(side)
			if not previous_side.is_empty() and side != previous_side and transition.is_empty():
				transition = "%s_TO_%s" % [SCALE_IDS[ratios.size() - 2], scale_id]
			previous_side = side
		result.append({
			"stream_chunk_size": chunk_size,
			"scale_ids": SCALE_IDS.duplicate(),
			"wall_ratios_serial_over_stream": ratios,
			"observed_faster_sides": faster_sides,
			"crossover_observed": not transition.is_empty(),
			"first_observed_transition": transition,
			"classification": "HOST_LOCAL_DIAGNOSTIC_ONLY",
			"optimization_claim": false,
		})
	return result


func _validate_scale_policy(policy: Dictionary) -> bool:
	var required := [
		"kind", "precondition_generations", "measured_generations", "repetitions",
		"audit_interval_generations", "audit_generation_1", "stream_chunk_sizes",
		"execution_configurations", "total_samples", "total_generation_advances",
		"audit_alignment", "initial_records", "load_axis_claim",
	]
	if policy.size() != required.size():
		return false
	for key in required:
		if not policy.has(key):
			return false
	if String(policy["kind"]) != "GENERATION_AGE_PRECONDITION":
		return false
	if not _integer_array_equals(Array(policy["precondition_generations"]), PRECONDITION_GENERATIONS):
		return false
	if not _integer_value_equals(policy["measured_generations"], MEASURED_GENERATIONS):
		return false
	if not _integer_value_equals(policy["repetitions"], REPETITIONS):
		return false
	if not _integer_value_equals(policy["audit_interval_generations"], AUDIT_INTERVAL_GENERATIONS):
		return false
	if typeof(policy["audit_generation_1"]) != TYPE_BOOL or not bool(policy["audit_generation_1"]):
		return false
	if not _integer_array_equals(Array(policy["stream_chunk_sizes"]), STREAM_CHUNK_SIZES):
		return false
	if not _integer_value_equals(policy["execution_configurations"], 4):
		return false
	if not _integer_value_equals(policy["total_samples"], 36):
		return false
	if not _integer_value_equals(policy["total_generation_advances"], TOTAL_GENERATION_ADVANCES):
		return false
	if String(policy["audit_alignment"]) != "ONE_INTERVAL_AUDIT_PER_MEASURED_WINDOW":
		return false
	if not _integer_value_equals(policy["initial_records"], Workbench.INITIAL_RECORDS):
		return false
	if String(policy["load_axis_claim"]) != "OBSERVED_GENERATION_AGED_POPULATION_NOT_SYNTHETIC_INITIAL_LOAD":
		return false
	return true


func _validate_sample_scale_flags(flags: Dictionary) -> bool:
	var scale_id := String(flags.get("scale_id", ""))
	if scale_id not in SCALE_IDS:
		return false
	var index := SCALE_IDS.find(scale_id)
	if index < 0:
		return false
	var precondition := PRECONDITION_GENERATIONS[index]
	if not _integer_value_equals(flags.get("precondition_generations"), precondition):
		return false
	if not _integer_value_equals(flags.get("measurement_start_generation"), precondition + 1):
		return false
	if not _integer_value_equals(flags.get("measurement_end_generation"), precondition + MEASURED_GENERATIONS):
		return false
	if not _integer_value_equals(flags.get("expected_interval_audit_generation"), _expected_audit_generation(precondition)):
		return false
	if String(flags.get("configuration_id", "")) not in EXECUTION_CONFIG_IDS:
		return false
	if String(flags.get("timing_aggregation", "")) != "MEAN_PER_MEASURED_GENERATION":
		return false
	return true


func _validate_exact_parity(samples: Array[Dictionary]) -> bool:
	var exact_pairs := 0
	for scale_id in SCALE_IDS:
		for repetition in range(REPETITIONS):
			var serial := _find_sample(samples, scale_id, "SERIAL_REFERENCE", 0, repetition)
			if serial.is_empty():
				return false
			for chunk_size in STREAM_CHUNK_SIZES:
				var streamed := _find_sample(samples, scale_id, "STREAM1", chunk_size, repetition)
				if streamed.is_empty():
					return false
				if not bool(Contract.can_compare_execution_modes(serial, streamed).get("success", false)):
					return false
				exact_pairs += 1
	return exact_pairs == 27


func _validate_point(point: Dictionary) -> bool:
	var required := [
		"scale_id", "precondition_generations", "measurement_start_generation",
		"measurement_end_generation", "expected_interval_audit_generation",
		"configuration_id", "execution_mode", "stream_chunk_size", "repetitions",
		"wall_ms", "generation_total_ms", "final_population", "final_parent_count",
		"final_candidate_count", "record_proxy_upper_bound", "engine_static_end_bytes",
		"structural_bound_proven", "allocator_memory_claim",
	]
	if point.size() != required.size():
		return false
	for key in required:
		if not point.has(key):
			return false
	var scale_id := String(point["scale_id"])
	if scale_id not in SCALE_IDS:
		return false
	var scale_index := SCALE_IDS.find(scale_id)
	var precondition := PRECONDITION_GENERATIONS[scale_index]
	if not _integer_value_equals(point["precondition_generations"], precondition):
		return false
	if not _integer_value_equals(point["measurement_start_generation"], precondition + 1):
		return false
	if not _integer_value_equals(point["measurement_end_generation"], precondition + MEASURED_GENERATIONS):
		return false
	if not _integer_value_equals(point["expected_interval_audit_generation"], _expected_audit_generation(precondition)):
		return false
	var configuration_id := String(point["configuration_id"])
	if configuration_id not in EXECUTION_CONFIG_IDS:
		return false
	if not _integer_value_equals(point["repetitions"], REPETITIONS):
		return false
	if not bool(point["structural_bound_proven"]):
		return false
	if String(point["allocator_memory_claim"]) != "DIAGNOSTIC_ONLY":
		return false
	for key in [
		"wall_ms", "generation_total_ms", "final_population", "final_parent_count",
		"final_candidate_count", "record_proxy_upper_bound", "engine_static_end_bytes",
	]:
		if not _validate_summary(Dictionary(point[key]), REPETITIONS):
			return false
	var execution_mode := String(point["execution_mode"])
	if configuration_id == "SERIAL_REFERENCE":
		if execution_mode != "SERIAL_REFERENCE":
			return false
		if not _integer_value_equals(point["stream_chunk_size"], 0):
			return false
	else:
		if execution_mode != "STREAM1":
			return false
		if not _is_integral_number(point["stream_chunk_size"]):
			return false
		var chunk_size := int(point["stream_chunk_size"])
		if configuration_id != "STREAM1_CHUNK_%d" % chunk_size or chunk_size not in STREAM_CHUNK_SIZES:
			return false
		if float(Dictionary(point["record_proxy_upper_bound"]).get("max", 0.0)) > float(chunk_size * 3):
			return false
	return true


func _validate_comparison(comparison: Dictionary) -> bool:
	var required := [
		"scale_id", "precondition_generations", "stream_chunk_size", "configuration_id",
		"exact_pairs", "serial_wall_p50_ms", "stream_wall_p50_ms",
		"observed_wall_ratio_serial_over_stream", "serial_generation_p50_ms",
		"stream_generation_p50_ms", "observed_generation_ratio_serial_over_stream",
		"serial_parent_p50", "stream_parent_p50", "serial_candidate_p50",
		"stream_candidate_p50", "serial_record_proxy_p50", "stream_record_proxy_p50",
		"record_proxy_reduction_factor_serial_over_stream", "observed_faster_side",
		"near_parity_band_5pct", "crossover_claim", "optimization_claim",
	]
	if comparison.size() != required.size():
		return false
	for key in required:
		if not comparison.has(key):
			return false
	var scale_id := String(comparison["scale_id"])
	if scale_id not in SCALE_IDS:
		return false
	var scale_index := SCALE_IDS.find(scale_id)
	if not _integer_value_equals(comparison["precondition_generations"], PRECONDITION_GENERATIONS[scale_index]):
		return false
	if not _is_integral_number(comparison["stream_chunk_size"]):
		return false
	var chunk_size := int(comparison["stream_chunk_size"])
	if chunk_size not in STREAM_CHUNK_SIZES:
		return false
	if String(comparison["configuration_id"]) != "STREAM1_CHUNK_%d" % chunk_size:
		return false
	if not _integer_value_equals(comparison["exact_pairs"], REPETITIONS):
		return false
	for key in [
		"serial_wall_p50_ms", "stream_wall_p50_ms", "observed_wall_ratio_serial_over_stream",
		"serial_generation_p50_ms", "stream_generation_p50_ms",
		"observed_generation_ratio_serial_over_stream", "serial_parent_p50",
		"stream_parent_p50", "serial_candidate_p50", "stream_candidate_p50",
		"serial_record_proxy_p50", "stream_record_proxy_p50",
		"record_proxy_reduction_factor_serial_over_stream",
	]:
		if not _finite_positive(comparison[key]):
			return false
	if not is_equal_approx(float(comparison["serial_parent_p50"]), float(comparison["stream_parent_p50"])):
		return false
	if not is_equal_approx(float(comparison["serial_candidate_p50"]), float(comparison["stream_candidate_p50"])):
		return false
	if float(comparison["record_proxy_reduction_factor_serial_over_stream"]) < 1.0:
		return false
	if String(comparison["observed_faster_side"]) != _faster_side(float(comparison["observed_wall_ratio_serial_over_stream"])):
		return false
	if typeof(comparison["near_parity_band_5pct"]) != TYPE_BOOL:
		return false
	if bool(comparison["crossover_claim"]) or bool(comparison["optimization_claim"]):
		return false
	return true


func _validate_trend(trend: Dictionary) -> bool:
	var required := [
		"configuration_id", "low_scale_id", "high_scale_id",
		"low_precondition_generations", "high_precondition_generations",
		"low_population_p50", "high_population_p50", "population_growth_factor",
		"wall_growth_factor", "generation_time_growth_factor",
		"record_proxy_growth_factor", "scaling_observation", "optimization_claim",
	]
	if trend.size() != required.size():
		return false
	for key in required:
		if not trend.has(key):
			return false
	if String(trend["configuration_id"]) not in EXECUTION_CONFIG_IDS:
		return false
	if String(trend["low_scale_id"]) != SCALE_IDS[0] or String(trend["high_scale_id"]) != SCALE_IDS[-1]:
		return false
	if not _integer_value_equals(trend["low_precondition_generations"], PRECONDITION_GENERATIONS[0]):
		return false
	if not _integer_value_equals(trend["high_precondition_generations"], PRECONDITION_GENERATIONS[-1]):
		return false
	for key in [
		"low_population_p50", "high_population_p50", "population_growth_factor",
		"wall_growth_factor", "generation_time_growth_factor", "record_proxy_growth_factor",
	]:
		if not _finite_positive(trend[key]):
			return false
	if String(trend["scaling_observation"]) != "HOST_LOCAL_DIAGNOSTIC":
		return false
	if bool(trend["optimization_claim"]):
		return false
	return true


func _validate_crossover(crossover: Dictionary) -> bool:
	var required := [
		"stream_chunk_size", "scale_ids", "wall_ratios_serial_over_stream",
		"observed_faster_sides", "crossover_observed", "first_observed_transition",
		"classification", "optimization_claim",
	]
	if crossover.size() != required.size():
		return false
	for key in required:
		if not crossover.has(key):
			return false
	if not _is_integral_number(crossover["stream_chunk_size"]):
		return false
	if int(crossover["stream_chunk_size"]) not in STREAM_CHUNK_SIZES:
		return false
	if Array(crossover["scale_ids"]).map(func(v): return String(v)) != SCALE_IDS:
		return false
	var ratios: Array = Array(crossover["wall_ratios_serial_over_stream"])
	var sides: Array = Array(crossover["observed_faster_sides"])
	if ratios.size() != SCALE_IDS.size() or sides.size() != SCALE_IDS.size():
		return false
	for index in range(ratios.size()):
		if not _finite_positive(ratios[index]):
			return false
		if String(sides[index]) != _faster_side(float(ratios[index])):
			return false
	var transition := _first_transition(sides)
	if bool(crossover["crossover_observed"]) != not transition.is_empty():
		return false
	if String(crossover["first_observed_transition"]) != transition:
		return false
	if String(crossover["classification"]) != "HOST_LOCAL_DIAGNOSTIC_ONLY":
		return false
	if bool(crossover["optimization_claim"]):
		return false
	return true


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

	if not normalized.has("metrics") or not normalized["metrics"] is Dictionary:
		return {}
	var metrics: Dictionary = Dictionary(normalized["metrics"])
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

	if metrics.has("window") and metrics["window"] is Dictionary:
		var window: Dictionary = Dictionary(metrics["window"])
		if not _is_integral_number(window.get("measured_generations")):
			return {}
		window["measured_generations"] = int(window["measured_generations"])
		metrics["window"] = window
	normalized["metrics"] = metrics

	var flags: Dictionary = Dictionary(normalized.get("flags", {}))
	for key in [
		"stream_chunk_size", "precondition_generations", "measurement_start_generation",
		"measurement_end_generation", "expected_interval_audit_generation",
	]:
		if not flags.has(key) or not _is_integral_number(flags[key]):
			return {}
		flags[key] = int(flags[key])
	normalized["flags"] = flags
	return normalized


func _group(samples: Array[Dictionary], scale_id: String, configuration_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for sample in samples:
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		if String(flags.get("scale_id", "")) == scale_id and String(flags.get("configuration_id", "")) == configuration_id:
			result.append(sample)
	return result


func _find_sample(samples: Array, scale_id: String, execution_mode: String, chunk_size: int, repetition: int) -> Dictionary:
	var suffix := "-r%d" % repetition
	for value in samples:
		if not value is Dictionary:
			continue
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


func _find_point(points: Array[Dictionary], scale_id: String, configuration_id: String) -> Dictionary:
	for point in points:
		if String(point.get("scale_id", "")) == scale_id and String(point.get("configuration_id", "")) == configuration_id:
			return point
	return {}


func _find_comparison(comparisons: Array[Dictionary], scale_id: String, chunk_size: int) -> Dictionary:
	for comparison in comparisons:
		if String(comparison.get("scale_id", "")) == scale_id and int(comparison.get("stream_chunk_size", 0)) == chunk_size:
			return comparison
	return {}


func _compact_summary(summary: Dictionary) -> Dictionary:
	return {
		"count": int(summary.get("count", 0)),
		"p50": float(summary.get("p50", 0.0)),
		"p95": float(summary.get("p95", 0.0)),
		"mean": float(summary.get("mean", 0.0)),
		"min": float(summary.get("min", 0.0)),
		"max": float(summary.get("max", 0.0)),
	}


func _summary_values(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var sum := 0.0
	for value in sorted_values:
		sum += value
	return {
		"count": sorted_values.size(),
		"p50": _percentile(sorted_values, 0.50),
		"p95": _percentile(sorted_values, 0.95),
		"mean": sum / float(sorted_values.size()),
		"min": sorted_values[0],
		"max": sorted_values[-1],
	}


func _validate_summary(summary: Dictionary, expected_count: int) -> bool:
	var required := ["count", "p50", "p95", "mean", "min", "max"]
	if summary.size() != required.size():
		return false
	for key in required:
		if not summary.has(key):
			return false
	if not _integer_value_equals(summary["count"], expected_count):
		return false
	for key in ["p50", "p95", "mean", "min", "max"]:
		if not _finite_nonnegative(summary[key]):
			return false
	return (
		float(summary["min"]) <= float(summary["p50"])
		and float(summary["p50"]) <= float(summary["p95"])
		and float(summary["p95"]) <= float(summary["max"]) + 1e-9
	)


func _sample_hash(sample: Dictionary) -> String:
	var normalized := _normalize_sample_for_contract(sample)
	if normalized.is_empty():
		return ""
	var workload: Dictionary = Dictionary(normalized.get("workload", {}))
	var metrics: Dictionary = Dictionary(normalized.get("metrics", {}))
	var timings: Dictionary = Dictionary(metrics.get("timings_ms", {}))
	var counts: Dictionary = Dictionary(metrics.get("counts", {}))
	var memory: Dictionary = Dictionary(metrics.get("memory_bytes", {}))
	var stream: Dictionary = Dictionary(metrics.get("stream", {}))
	var window: Dictionary = Dictionary(metrics.get("window", {}))
	var flags: Dictionary = Dictionary(normalized.get("flags", {}))
	var parts := PackedStringArray([
		"PERF2_3_SAMPLE_R1",
		String(normalized.get("run_id", "")),
		Contract.workload_hash(workload),
		Contract.simulation_workload_hash(workload),
		Contract.canonical_result_fingerprint(normalized),
		String(flags.get("scale_id", "")),
		String(flags.get("configuration_id", "")),
		str(int(flags.get("stream_chunk_size", 0))),
		str(int(flags.get("precondition_generations", 0))),
		_stable_float_token(window.get("total_wall_ms", 0.0)),
	])
	for key in [
		"wall_ms", "generation_total_ms", "ls33_total_ms", "stream_total_ms",
		"candidate_build_ms", "route_build_ms", "recruitment_eval_ms", "audit_ms",
	]:
		parts.append("%s=%s" % [key, _stable_float_token(timings.get(key, 0.0))])
	for key in [
		"generation", "population", "parent_count", "candidate_count",
		"chunk_count", "max_parent_chunk", "max_candidate_chunk",
	]:
		parts.append("%s=%d" % [key, int(counts.get(key, 0))])
	for key in ["engine_static_bytes", "engine_static_peak_bytes"]:
		parts.append("%s=%d" % [key, int(memory.get(key, 0))])
	for key in ["stream_calls", "chunks_processed", "serial_audit_calls", "oracle_elided_generations"]:
		parts.append("%s=%d" % [key, int(stream.get(key, 0))])
	return "|".join(parts).sha256_text()


func _point_hash(point: Dictionary) -> String:
	var parts := PackedStringArray([
		String(point.get("scale_id", "")),
		str(int(point.get("precondition_generations", 0))),
		String(point.get("configuration_id", "")),
		String(point.get("execution_mode", "")),
		str(int(point.get("stream_chunk_size", 0))),
	])
	for key in [
		"wall_ms", "generation_total_ms", "final_population", "final_parent_count",
		"final_candidate_count", "record_proxy_upper_bound", "engine_static_end_bytes",
	]:
		parts.append(_summary_hash(Dictionary(point.get(key, {}))))
	return "|".join(parts).sha256_text()


func _comparison_hash(comparison: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(comparison.get("scale_id", "")),
		str(int(comparison.get("precondition_generations", 0))),
		str(int(comparison.get("stream_chunk_size", 0))),
		str(int(comparison.get("exact_pairs", 0))),
		_stable_float_token(comparison.get("observed_wall_ratio_serial_over_stream", 0.0)),
		_stable_float_token(comparison.get("observed_generation_ratio_serial_over_stream", 0.0)),
		_stable_float_token(comparison.get("serial_parent_p50", 0.0)),
		_stable_float_token(comparison.get("serial_candidate_p50", 0.0)),
		_stable_float_token(comparison.get("record_proxy_reduction_factor_serial_over_stream", 0.0)),
		String(comparison.get("observed_faster_side", "")),
		"1" if bool(comparison.get("near_parity_band_5pct", false)) else "0",
	])).sha256_text()


func _trend_hash(trend: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(trend.get("configuration_id", "")),
		_stable_float_token(trend.get("population_growth_factor", 0.0)),
		_stable_float_token(trend.get("wall_growth_factor", 0.0)),
		_stable_float_token(trend.get("generation_time_growth_factor", 0.0)),
		_stable_float_token(trend.get("record_proxy_growth_factor", 0.0)),
	])).sha256_text()


func _crossover_hash(crossover: Dictionary) -> String:
	var ratios := PackedStringArray()
	for value in Array(crossover.get("wall_ratios_serial_over_stream", [])):
		ratios.append(_stable_float_token(value))
	var sides := PackedStringArray()
	for value in Array(crossover.get("observed_faster_sides", [])):
		sides.append(String(value))
	return "|".join(PackedStringArray([
		str(int(crossover.get("stream_chunk_size", 0))),
		",".join(ratios),
		",".join(sides),
		"1" if bool(crossover.get("crossover_observed", false)) else "0",
		String(crossover.get("first_observed_transition", "")),
	])).sha256_text()


func _summary_hash(summary: Dictionary) -> String:
	return "|".join(PackedStringArray([
		str(int(summary.get("count", 0))),
		_stable_float_token(summary.get("p50", 0.0)),
		_stable_float_token(summary.get("p95", 0.0)),
		_stable_float_token(summary.get("mean", 0.0)),
		_stable_float_token(summary.get("min", 0.0)),
		_stable_float_token(summary.get("max", 0.0)),
	])).sha256_text()


func _expected_audit_generation(precondition_generations: int) -> int:
	return int(ceil(float(precondition_generations + 1) / float(AUDIT_INTERVAL_GENERATIONS))) * AUDIT_INTERVAL_GENERATIONS


func _configuration_id(execution_mode: String, chunk_size: int) -> String:
	if execution_mode == "SERIAL_REFERENCE":
		return "SERIAL_REFERENCE"
	return "STREAM1_CHUNK_%d" % chunk_size


func _faster_side(serial_over_stream_ratio: float) -> String:
	if serial_over_stream_ratio > 1.0:
		return "STREAM1"
	if serial_over_stream_ratio < 1.0:
		return "SERIAL_REFERENCE"
	return "EQUAL"


func _first_transition(sides: Array) -> String:
	for index in range(1, sides.size()):
		if String(sides[index]) != String(sides[index - 1]):
			return "%s_TO_%s" % [SCALE_IDS[index - 1], SCALE_IDS[index]]
	return ""


func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	if sorted_values.size() == 1:
		return sorted_values[0]
	var position := clampf(fraction, 0.0, 1.0) * float(sorted_values.size() - 1)
	var low := int(floor(position))
	var high := int(ceil(position))
	if low == high:
		return sorted_values[low]
	return lerpf(sorted_values[low], sorted_values[high], position - float(low))


func _stable_float_token(value) -> String:
	if not _finite_nonnegative(value):
		return "INVALID"
	return "%.6f" % float(value)


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
