extends RefCounted

## ECO.EVO7 PERF2.1 R2 — STREAM1 generation profiling campaign.
##
## Measurement-only orchestration over the accepted public Workbench facade.
## It consumes the frozen PERF2.0 measurement contract unchanged and never
## reaches into ecology private state. Reports are machine-local side-channel
## artifacts and are not canonical world/ecology truth.

const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Probe = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const StreamExecutor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_perf2.measurement_report.v1"
const PROFILE_SCHEMA := "distributed_world_simulator.ecology.evo7_perf2_1.generation_profile.v2"
const VERSION := "1.1.0"
const REVISION := "ECO.EVO7-PERF2.1-R2"
const MODE := "RESEARCH_SHADOW_PERFORMANCE_ONLY"
const FROZEN_PERF2_CONTRACT_REVISION := "ECO.EVO7-PERF2.0-R1"
const FROZEN_PERF2_CONTRACT_BLOB_SHA := "b076784f6b4016a0191e937c4e6ada1fe90c783b"

const DEFAULT_RECIPE := "MIXED_PHYSICAL_HETEROGENEITY"
const STREAM_CHUNK_SIZES: Array[int] = [1, 7, 64]
const EXECUTION_CONFIG_IDS: Array[String] = [
	"SERIAL_REFERENCE",
	"STREAM1_CHUNK_1",
	"STREAM1_CHUNK_7",
	"STREAM1_CHUNK_64",
]
const REQUIRED_METRICS: Array[String] = [
	"timings_ms.wall_ms",
	"timings_ms.generation_total_ms",
	"timings_ms.ls33_total_ms",
	"timings_ms.stream_total_ms",
	"timings_ms.candidate_build_ms",
	"timings_ms.route_build_ms",
	"timings_ms.recruitment_eval_ms",
	"timings_ms.audit_ms",
]
const CONFIG_FIELDS: Array[String] = [
	"recipes",
	"warmup_generations",
	"measured_generations",
	"repetitions",
	"initial_records",
	"stream_chunk_sizes",
	"audit_interval_generations",
	"audit_generation_1",
	"founder_seed",
	"placement_seed",
	"evolution_seed",
	"environment_seed",
	"world_seed",
	"competition_enabled",
	"grid_size",
	"cell_size_m",
	"planet_source_kind",
]
const CONTEXT_FIELDS: Array[String] = [
	"planet_source_kind",
	"world_seed",
	"competition_enabled",
	"grid_size",
	"cell_size_m",
]

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


func default_campaign_config() -> Dictionary:
	var contract := Contract.load_contract()
	var defaults: Dictionary = Dictionary(Dictionary(contract.get("workload_contract", {})).get("default_stream1", {}))
	return {
		"recipes": [DEFAULT_RECIPE],
		"warmup_generations": int(defaults.get("warmup_generations", 2)),
		"measured_generations": int(defaults.get("measured_generations", 12)),
		"repetitions": int(defaults.get("repetitions", 3)),
		"initial_records": Workbench.INITIAL_RECORDS,
		"stream_chunk_sizes": STREAM_CHUNK_SIZES.duplicate(),
		"audit_interval_generations": int(defaults.get("audit_interval_generations", 10)),
		"audit_generation_1": bool(defaults.get("audit_generation_1", true)),
		"founder_seed": Workbench.FOUNDER_SEED,
		"placement_seed": Workbench.PLACEMENT_SEED,
		"evolution_seed": Workbench.EVOLUTION_SEED,
		"environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
		"world_seed": Workbench.DEFAULT_WORLD_SEED,
		"competition_enabled": true,
		"grid_size": Workbench.GRID_SIZE,
		"cell_size_m": Workbench.CELL_SIZE_M,
		"planet_source_kind": "PROCEDURAL_EARTH_WORLD",
	}


func validate_campaign_config(config: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var contract := Contract.load_contract()
	if not bool(Contract.validate_contract(contract).get("success", false)):
		errors.append("PERF2_CONTRACT_INVALID")
	if Contract.REVISION != FROZEN_PERF2_CONTRACT_REVISION:
		errors.append("PERF2_CONTRACT_REVISION_DRIFT")
	if config.size() != CONFIG_FIELDS.size():
		errors.append("CONFIG_EXACT_FIELD_COUNT")
	for key in CONFIG_FIELDS:
		if not config.has(key):
			errors.append("CONFIG_MISSING_%s" % key.to_upper())
	if not errors.is_empty():
		return {"success": false, "errors": errors}

	var allowed: Array = Array(Dictionary(contract.get("workload_contract", {})).get("allowed_environment_recipes", []))
	if Array(config["recipes"]) != [DEFAULT_RECIPE]:
		errors.append("R2_RECIPE_SET_DRIFT")
	for value in Array(config["recipes"]):
		if String(value) not in allowed:
			errors.append("RECIPE_%s" % String(value))

	var workload_policy: Dictionary = Dictionary(contract.get("workload_contract", {}))
	for key in [
		"warmup_generations", "measured_generations", "repetitions", "initial_records",
		"audit_interval_generations", "founder_seed", "placement_seed",
		"evolution_seed", "environment_seed", "world_seed", "grid_size",
	]:
		if not _is_integral_number(config[key]):
			errors.append("CONFIG_%s_NOT_INTEGER" % key.to_upper())
	for value in Array(config["stream_chunk_sizes"]):
		if not _is_integral_number(value):
			errors.append("CONFIG_STREAM_CHUNK_SIZE_NOT_INTEGER")
	if typeof(config["cell_size_m"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(config["cell_size_m"])):
		errors.append("CONFIG_CELL_SIZE_NOT_NUMERIC")

	if int(config["warmup_generations"]) != int(Dictionary(workload_policy.get("default_stream1", {})).get("warmup_generations", 2)):
		errors.append("R2_WARMUP_DRIFT")
	if int(config["measured_generations"]) != int(Dictionary(workload_policy.get("default_stream1", {})).get("measured_generations", 12)):
		errors.append("R2_MEASURED_DRIFT")
	if int(config["repetitions"]) != int(Dictionary(workload_policy.get("default_stream1", {})).get("repetitions", 3)):
		errors.append("R2_REPETITIONS_DRIFT")
	if not _integer_value_equals(config["initial_records"], Workbench.INITIAL_RECORDS):
		errors.append("R2_INITIAL_RECORDS_DRIFT")
	if not _integer_array_equals(Array(config["stream_chunk_sizes"]), STREAM_CHUNK_SIZES):
		errors.append("R2_CHUNK_SWEEP_DRIFT")
	if int(config["audit_interval_generations"]) != int(Dictionary(workload_policy.get("default_stream1", {})).get("audit_interval_generations", 10)):
		errors.append("R2_AUDIT_INTERVAL_DRIFT")
	if bool(config["audit_generation_1"]) != bool(Dictionary(workload_policy.get("default_stream1", {})).get("audit_generation_1", true)):
		errors.append("R2_AUDIT_GENERATION_1_DRIFT")

	if not _integer_value_equals(config["founder_seed"], Workbench.FOUNDER_SEED):
		errors.append("R2_FOUNDER_SEED_DRIFT")
	if not _integer_value_equals(config["placement_seed"], Workbench.PLACEMENT_SEED):
		errors.append("R2_PLACEMENT_SEED_DRIFT")
	if not _integer_value_equals(config["evolution_seed"], Workbench.EVOLUTION_SEED):
		errors.append("R2_EVOLUTION_SEED_DRIFT")
	if not _integer_value_equals(config["environment_seed"], Workbench.DEFAULT_ENVIRONMENT_SEED):
		errors.append("R2_ENVIRONMENT_SEED_DRIFT")
	if not _integer_value_equals(config["world_seed"], Workbench.DEFAULT_WORLD_SEED):
		errors.append("R2_WORLD_SEED_DRIFT")
	if typeof(config["competition_enabled"]) != TYPE_BOOL or not bool(config["competition_enabled"]):
		errors.append("R2_COMPETITION_MODE_DRIFT")
	if not _integer_value_equals(config["grid_size"], Workbench.GRID_SIZE):
		errors.append("R2_GRID_SIZE_DRIFT")
	if not is_equal_approx(float(config["cell_size_m"]), Workbench.CELL_SIZE_M):
		errors.append("R2_CELL_SIZE_DRIFT")
	if String(config["planet_source_kind"]) != "PROCEDURAL_EARTH_WORLD":
		errors.append("R2_PLANET_SOURCE_DRIFT")

	return {"success": errors.is_empty(), "errors": errors}


func campaign_context(config: Dictionary) -> Dictionary:
	if not bool(validate_campaign_config(config).get("success", false)):
		return {}
	return {
		"planet_source_kind": String(config["planet_source_kind"]),
		"world_seed": int(config["world_seed"]),
		"competition_enabled": bool(config["competition_enabled"]),
		"grid_size": int(config["grid_size"]),
		"cell_size_m": float(config["cell_size_m"]),
	}


func campaign_context_hash(context: Dictionary) -> String:
	if context.size() != CONTEXT_FIELDS.size():
		return ""
	for key in CONTEXT_FIELDS:
		if not context.has(key):
			return ""
	if typeof(context["planet_source_kind"]) != TYPE_STRING:
		return ""
	if not _is_integral_number(context["world_seed"]):
		return ""
	if typeof(context["competition_enabled"]) != TYPE_BOOL:
		return ""
	if not _is_integral_number(context["grid_size"]):
		return ""
	if typeof(context["cell_size_m"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(context["cell_size_m"])):
		return ""
	return "|".join(PackedStringArray([
		"PERF2_1_CAMPAIGN_CONTEXT_V1",
		String(context["planet_source_kind"]),
		str(int(context["world_seed"])),
		"true" if bool(context["competition_enabled"]) else "false",
		str(int(context["grid_size"])),
		"%.9f" % float(context["cell_size_m"]),
	])).sha256_text()


func run_campaign(planet_source, config: Dictionary, target: Dictionary, host_fingerprint: String) -> Dictionary:
	var validation := validate_campaign_config(config)
	if not bool(validation.get("success", false)):
		return _failure("CONFIG_INVALID", validation.get("errors", []))
	if planet_source == null:
		return _failure("PLANET_SOURCE", [])
	if not _valid_target(target):
		return _failure("TARGET_INVALID", [])
	if host_fingerprint.strip_edges().is_empty():
		return _failure("HOST_FINGERPRINT", [])

	var context := campaign_context(config)
	var context_hash := campaign_context_hash(context)
	if context.is_empty() or not _is_hash(context_hash):
		return _failure("CAMPAIGN_CONTEXT_INVALID", [])

	var samples: Array[Dictionary] = []
	for recipe_value in Array(config["recipes"]):
		var recipe := String(recipe_value)
		for repetition in range(int(config["repetitions"])):
			var serial := _run_repetition(
				planet_source, config, target, host_fingerprint,
				context_hash, recipe, "SERIAL_REFERENCE", 0, repetition)
			if serial.is_empty():
				return _failure("SERIAL_REPETITION_FAILED", [recipe, repetition])
			samples.append(serial)
			for chunk_value in Array(config["stream_chunk_sizes"]):
				var chunk_size := int(chunk_value)
				var streamed := _run_repetition(
					planet_source, config, target, host_fingerprint,
					context_hash, recipe, "STREAM1", chunk_size, repetition)
				if streamed.is_empty():
					return _failure("STREAM1_REPETITION_FAILED", [recipe, chunk_size, repetition])
				var parity := Contract.can_compare_execution_modes(serial, streamed)
				if not bool(parity.get("success", false)):
					return _failure("CROSS_MODE_PARITY_FAILED", [chunk_size, parity.get("errors", [])])
				if String(Dictionary(serial["flags"]).get("campaign_context_hash", "")) != String(Dictionary(streamed["flags"]).get("campaign_context_hash", "")):
					return _failure("CAMPAIGN_CONTEXT_PARITY_FAILED", [chunk_size])
				samples.append(streamed)

	var summaries := _build_summaries(samples, config)
	if summaries.is_empty():
		return _failure("SUMMARY_BUILD_FAILED", [])
	var comparisons := _build_comparisons(samples, summaries, config)
	if comparisons.size() != STREAM_CHUNK_SIZES.size():
		return _failure("COMPARISON_BUILD_FAILED", [])

	var report := {
		"schema": SCHEMA,
		"profile_schema": PROFILE_SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"accepted_measurement_contract_revision": Contract.REVISION,
		"accepted_measurement_contract_blob_sha": FROZEN_PERF2_CONTRACT_BLOB_SHA,
		"target": target.duplicate(true),
		"host_fingerprint": host_fingerprint,
		"config": config.duplicate(true),
		"campaign_context": context.duplicate(true),
		"campaign_context_hash": context_hash,
		"samples": samples.duplicate(true),
		"summaries": summaries.duplicate(true),
		"comparisons": comparisons.duplicate(true),
		"authorities": AUTHORITIES.duplicate(true),
	}
	report["report_hash"] = report_hash(report)
	if not validate_report(report):
		return _failure("REPORT_VALIDATION_FAILED", [])
	return report


func validate_report(report: Dictionary) -> bool:
	var required := [
		"schema", "profile_schema", "version", "revision", "mode",
		"accepted_measurement_contract_revision", "accepted_measurement_contract_blob_sha",
		"target", "host_fingerprint", "config",
		"campaign_context", "campaign_context_hash",
		"samples", "summaries", "comparisons", "authorities", "report_hash",
	]
	if report.size() != required.size():
		return false
	for key in required:
		if not report.has(key):
			return false
	if String(report["schema"]) != Contract.REPORT_SCHEMA:
		return false
	if String(report["profile_schema"]) != PROFILE_SCHEMA:
		return false
	if String(report["version"]) != VERSION or String(report["revision"]) != REVISION or String(report["mode"]) != MODE:
		return false
	if String(report["accepted_measurement_contract_revision"]) != Contract.REVISION:
		return false
	if String(report["accepted_measurement_contract_blob_sha"]) != FROZEN_PERF2_CONTRACT_BLOB_SHA:
		return false
	if not _valid_target(Dictionary(report["target"])):
		return false
	if String(report["host_fingerprint"]).strip_edges().is_empty():
		return false
	var config: Dictionary = Dictionary(report["config"])
	if not bool(validate_campaign_config(config).get("success", false)):
		return false
	var context: Dictionary = Dictionary(report["campaign_context"])
	var expected_context := campaign_context(config)
	var context_hash := campaign_context_hash(context)
	if context_hash.is_empty() or context_hash != campaign_context_hash(expected_context):
		return false
	if String(report["campaign_context_hash"]) != context_hash:
		return false
	if Dictionary(report["authorities"]) != AUTHORITIES:
		return false

	var samples_value = report["samples"]
	if not samples_value is Array:
		return false
	var samples: Array = samples_value
	var expected_samples := int(config["repetitions"]) * (1 + STREAM_CHUNK_SIZES.size()) * Array(config["recipes"]).size()
	if samples.size() != expected_samples:
		return false
	var normalized_samples: Array[Dictionary] = []
	for value in samples:
		if not value is Dictionary:
			return false
		var sample: Dictionary = value
		var normalized_sample := _normalize_sample_for_contract(sample)
		if normalized_sample.is_empty():
			return false
		if not bool(Contract.validate_sample(normalized_sample).get("success", false)) or not bool(normalized_sample.get("passed", false)):
			return false
		if String(Dictionary(normalized_sample["flags"]).get("campaign_context_hash", "")) != String(report["campaign_context_hash"]):
			return false
		normalized_samples.append(normalized_sample)

	for repetition in range(int(config["repetitions"])):
		var serial := _find_sample(normalized_samples, DEFAULT_RECIPE, "SERIAL_REFERENCE", 0, repetition)
		if serial.is_empty():
			return false
		for chunk_size in STREAM_CHUNK_SIZES:
			var streamed := _find_sample(normalized_samples, DEFAULT_RECIPE, "STREAM1", chunk_size, repetition)
			if streamed.is_empty():
				return false
			if not bool(Contract.can_compare_execution_modes(serial, streamed).get("success", false)):
				return false

	var summaries_value = report["summaries"]
	if not summaries_value is Array or Array(summaries_value).size() != EXECUTION_CONFIG_IDS.size() * REQUIRED_METRICS.size():
		return false
	for value in Array(summaries_value):
		if not value is Dictionary:
			return false
		var summary: Dictionary = value
		if int(summary.get("count", 0)) != int(config["repetitions"]):
			return false
		for key in ["p50", "p95", "mean", "min", "max"]:
			if not _finite_nonnegative(summary.get(key)):
				return false

	var comparisons_value = report["comparisons"]
	if not comparisons_value is Array or Array(comparisons_value).size() != STREAM_CHUNK_SIZES.size():
		return false
	for value in Array(comparisons_value):
		if not value is Dictionary:
			return false
		var comparison: Dictionary = value
		if int(comparison.get("exact_pairs", 0)) != int(config["repetitions"]):
			return false
		if not _finite_nonnegative(comparison.get("observed_wall_ratio_serial_over_stream")):
			return false
		if not _finite_nonnegative(comparison.get("observed_generation_ratio_serial_over_stream")):
			return false
		if bool(comparison.get("optimization_claim", true)):
			return false

	return String(report["report_hash"]) == report_hash(report)


func write_report(report: Dictionary, path: String) -> bool:
	if not validate_report(report) or path.strip_edges().is_empty():
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


func report_hash(report: Dictionary) -> String:
	var target: Dictionary = Dictionary(report.get("target", {}))
	var sample_hashes := PackedStringArray()
	for value in Array(report.get("samples", [])):
		sample_hashes.append(_sample_evidence_hash(Dictionary(value)))
	var summary_hashes := PackedStringArray()
	for value in Array(report.get("summaries", [])):
		summary_hashes.append(_summary_evidence_hash(Dictionary(value)))
	var comparison_hashes := PackedStringArray()
	for value in Array(report.get("comparisons", [])):
		comparison_hashes.append(_comparison_evidence_hash(Dictionary(value)))
	return "|".join(PackedStringArray([
		"PERF2_1_REPORT_R2",
		String(target.get("head", "")),
		String(target.get("tree", "")),
		String(target.get("godot_version", "")),
		String(report.get("host_fingerprint", "")),
		Contract.REVISION,
		FROZEN_PERF2_CONTRACT_BLOB_SHA,
		REVISION,
		String(report.get("campaign_context_hash", "")),
		_config_hash(Dictionary(report.get("config", {}))),
		";".join(sample_hashes),
		";".join(summary_hashes),
		";".join(comparison_hashes),
	])).sha256_text()


func _run_repetition(
	planet_source,
	config: Dictionary,
	target: Dictionary,
	host_fingerprint: String,
	context_hash: String,
	recipe: String,
	execution_mode: String,
	chunk_size: int,
	repetition: int
) -> Dictionary:
	var workload := _workload(config, recipe, execution_mode, chunk_size)
	if not bool(Contract.validate_workload(workload).get("success", false)):
		return {}

	var wb = Workbench.new()
	var requested_spec := Workbench.default_spec()
	requested_spec["world_seed"] = int(config["world_seed"])
	requested_spec["environment_seed"] = int(config["environment_seed"])
	requested_spec["environment_recipe"] = recipe
	requested_spec["competition_enabled"] = bool(config["competition_enabled"])
	if not wb.setup(planet_source, requested_spec):
		return {}

	var executor = null
	if execution_mode == "STREAM1":
		executor = StreamExecutor.new()
		if not executor.setup({
			"parents_per_chunk": chunk_size,
			"audit_interval": int(config["audit_interval_generations"]),
			"audit_generation_1": bool(config["audit_generation_1"]),
		}):
			return {}
		if not wb.set_generation_stream_executor(executor):
			return {}

	for _warmup in range(int(config["warmup_generations"])):
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
	for _measured in range(int(config["measured_generations"])):
		if wb.advance_generations(1).is_empty():
			return {}
		var profile: Dictionary = wb.get_last_generation_profile()
		var ecology: Dictionary = Dictionary(profile.get("ecology", {}))
		var ls33: Dictionary = Dictionary(ecology.get("ls33", {}))
		if profile.is_empty() or ls33.is_empty():
			return {}
		timing_sums["generation_total_ms"] += float(profile.get("total_ms", -1.0))
		timing_sums["ls33_total_ms"] += float(ecology.get("ls33_total_ms", -1.0))
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
	var measured_count := float(int(config["measured_generations"]))
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

	var memory: Dictionary = Dictionary(observed.get("memory_bytes", {}))
	var configuration_id := _configuration_id(execution_mode, chunk_size)
	var sample := {
		"schema": Contract.SAMPLE_SCHEMA,
		"version": Contract.VERSION,
		"revision": Contract.REVISION,
		"run_id": "perf2-1-r2-%s-%s-r%d" % [recipe.to_lower(), configuration_id.to_lower(), repetition],
		"target": target.duplicate(true),
		"host_fingerprint": host_fingerprint,
		"measurement_method_revision": Contract.REVISION,
		"workload": workload.duplicate(true),
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
				"measured_generations": int(config["measured_generations"]),
				"total_wall_ms": float(observed.get("wall_ms", -1.0)),
			},
		},
		"flags": {
			"canonical": false,
			"side_channel_only": true,
			"measurement_only": true,
			"configuration_id": configuration_id,
			"stream_chunk_size": chunk_size if execution_mode == "STREAM1" else 0,
			"campaign_context_hash": context_hash,
			"timing_aggregation": "MEAN_PER_MEASURED_GENERATION",
		},
	}
	if not bool(Contract.validate_sample(sample).get("success", false)):
		return {}
	return sample


func _workload(config: Dictionary, recipe: String, execution_mode: String, chunk_size: int) -> Dictionary:
	return {
		"workload_id": "PERF2_1_WORKBENCH_STANDARD_R2",
		"execution_mode": execution_mode,
		"environment_recipe": recipe,
		"warmup_generations": int(config["warmup_generations"]),
		"measured_generations": int(config["measured_generations"]),
		"repetitions": int(config["repetitions"]),
		"initial_records": int(config["initial_records"]),
		"parents_per_chunk": chunk_size if execution_mode == "STREAM1" else int(config["initial_records"]),
		"audit_interval_generations": int(config["audit_interval_generations"]),
		"audit_generation_1": bool(config["audit_generation_1"]) if execution_mode == "STREAM1" else false,
		"founder_seed": int(config["founder_seed"]),
		"placement_seed": int(config["placement_seed"]),
		"evolution_seed": int(config["evolution_seed"]),
		"environment_seed": int(config["environment_seed"]),
	}


func _build_summaries(samples: Array[Dictionary], config: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for configuration_id in EXECUTION_CONFIG_IDS:
		var group: Array[Dictionary] = []
		for sample in samples:
			if String(Dictionary(sample.get("flags", {})).get("configuration_id", "")) == configuration_id:
				group.append(sample)
		if group.size() != int(config["repetitions"]) or not Contract.minimum_repetitions_satisfied(group):
			return []
		for metric_path in REQUIRED_METRICS:
			var summary := Contract.summarize(group, metric_path)
			if summary.is_empty():
				return []
			summary["configuration_id"] = configuration_id
			summary["execution_mode"] = String(Dictionary(group[0]["workload"]).get("execution_mode", ""))
			summary["stream_chunk_size"] = int(Dictionary(group[0]["flags"]).get("stream_chunk_size", 0))
			summary["environment_recipe"] = DEFAULT_RECIPE
			summary["simulation_workload_hash"] = Contract.simulation_workload_hash(Dictionary(group[0]["workload"]))
			result.append(summary)
	return result


func _build_comparisons(samples: Array[Dictionary], summaries: Array[Dictionary], config: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var serial_wall := _find_summary(summaries, "SERIAL_REFERENCE", "timings_ms.wall_ms")
	var serial_generation := _find_summary(summaries, "SERIAL_REFERENCE", "timings_ms.generation_total_ms")
	if serial_wall.is_empty() or serial_generation.is_empty():
		return []
	for chunk_size in STREAM_CHUNK_SIZES:
		var configuration_id := "STREAM1_CHUNK_%d" % chunk_size
		var stream_wall := _find_summary(summaries, configuration_id, "timings_ms.wall_ms")
		var stream_generation := _find_summary(summaries, configuration_id, "timings_ms.generation_total_ms")
		if stream_wall.is_empty() or stream_generation.is_empty():
			return []
		var exact_pairs := 0
		for repetition in range(int(config["repetitions"])):
			var serial := _find_sample(samples, DEFAULT_RECIPE, "SERIAL_REFERENCE", 0, repetition)
			var streamed := _find_sample(samples, DEFAULT_RECIPE, "STREAM1", chunk_size, repetition)
			if serial.is_empty() or streamed.is_empty():
				return []
			if bool(Contract.can_compare_execution_modes(serial, streamed).get("success", false)):
				exact_pairs += 1
		if exact_pairs != int(config["repetitions"]):
			return []
		var stream_wall_p50 := float(stream_wall["p50"])
		var stream_generation_p50 := float(stream_generation["p50"])
		result.append({
			"configuration_id": configuration_id,
			"stream_chunk_size": chunk_size,
			"exact_pairs": exact_pairs,
			"serial_wall_p50_ms": float(serial_wall["p50"]),
			"stream_wall_p50_ms": stream_wall_p50,
			"observed_wall_ratio_serial_over_stream": float(serial_wall["p50"]) / stream_wall_p50 if stream_wall_p50 > 0.0 else 0.0,
			"serial_generation_p50_ms": float(serial_generation["p50"]),
			"stream_generation_p50_ms": stream_generation_p50,
			"observed_generation_ratio_serial_over_stream": float(serial_generation["p50"]) / stream_generation_p50 if stream_generation_p50 > 0.0 else 0.0,
			"optimization_claim": false,
			"note": "Observed execution ratio only; PERF2.1 does not accept an optimization.",
		})
	return result


func _find_sample(samples: Array, recipe: String, execution_mode: String, chunk_size: int, repetition: int) -> Dictionary:
	var suffix := "-r%d" % repetition
	for value in samples:
		if not value is Dictionary:
			continue
		var sample: Dictionary = value
		var workload: Dictionary = Dictionary(sample.get("workload", {}))
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		if String(workload.get("environment_recipe", "")) != recipe:
			continue
		if String(workload.get("execution_mode", "")) != execution_mode:
			continue
		if execution_mode == "STREAM1" and int(flags.get("stream_chunk_size", -1)) != chunk_size:
			continue
		if String(sample.get("run_id", "")).ends_with(suffix):
			return sample
	return {}


func _find_summary(summaries: Array[Dictionary], configuration_id: String, metric_path: String) -> Dictionary:
	for summary in summaries:
		if String(summary.get("configuration_id", "")) == configuration_id and String(summary.get("metric_path", "")) == metric_path:
			return summary
	return {}


func _configuration_id(execution_mode: String, chunk_size: int) -> String:
	if execution_mode == "SERIAL_REFERENCE":
		return "SERIAL_REFERENCE"
	return "STREAM1_CHUNK_%d" % chunk_size


func _sample_evidence_hash(sample: Dictionary) -> String:
	var normalized := _normalize_sample_for_contract(sample)
	if normalized.is_empty():
		return ""
	var metrics: Dictionary = Dictionary(normalized.get("metrics", {}))
	var timings: Dictionary = Dictionary(metrics.get("timings_ms", {}))
	var counts: Dictionary = Dictionary(metrics.get("counts", {}))
	var memory: Dictionary = Dictionary(metrics.get("memory_bytes", {}))
	var stream: Dictionary = Dictionary(metrics.get("stream", {}))
	var window: Dictionary = Dictionary(metrics.get("window", {}))
	var flags: Dictionary = Dictionary(normalized.get("flags", {}))
	var parts := PackedStringArray([
		"PERF2_1_SAMPLE_EVIDENCE_R2",
		String(normalized.get("run_id", "")),
		String(normalized.get("workload_hash", "")),
		Contract.simulation_workload_hash(Dictionary(normalized.get("workload", {}))),
		Contract.canonical_result_fingerprint(normalized),
		Contract.comparison_key(normalized),
		Contract.execution_comparison_key(normalized),
		String(flags.get("configuration_id", "")),
		String(flags.get("campaign_context_hash", "")),
		str(int(flags.get("stream_chunk_size", 0))),
		String(flags.get("timing_aggregation", "")),
		str(int(window.get("measured_generations", 0))),
		"%.12f" % float(window.get("total_wall_ms", -1.0)),
	])
	for key in [
		"wall_ms", "generation_total_ms", "ls33_total_ms", "stream_total_ms",
		"candidate_build_ms", "route_build_ms", "recruitment_eval_ms", "audit_ms",
	]:
		parts.append("%s=%.12f" % [key, float(timings.get(key, -1.0))])
	for key in [
		"generation", "population", "parent_count", "candidate_count",
		"chunk_count", "max_parent_chunk", "max_candidate_chunk",
	]:
		parts.append("%s=%d" % [key, int(counts.get(key, -1))])
	for key in ["engine_static_bytes", "engine_static_peak_bytes"]:
		parts.append("%s=%d" % [key, int(memory.get(key, -1))])
	for key in ["process_rss_bytes", "process_peak_rss_bytes"]:
		parts.append("%s=%s" % [key, _nullable_int_string(memory.get(key))])
	for key in ["stream_calls", "chunks_processed", "serial_audit_calls", "oracle_elided_generations"]:
		parts.append("%s=%d" % [key, int(stream.get(key, -1))])
	return "|".join(parts).sha256_text()


func _summary_evidence_hash(summary: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(summary.get("configuration_id", "")),
		String(summary.get("metric_path", "")),
		str(int(summary.get("count", 0))),
		"%.12f" % float(summary.get("p50", 0.0)),
		"%.12f" % float(summary.get("p95", 0.0)),
		"%.12f" % float(summary.get("mean", 0.0)),
		"%.12f" % float(summary.get("min", 0.0)),
		"%.12f" % float(summary.get("max", 0.0)),
		String(summary.get("simulation_workload_hash", "")),
	])).sha256_text()


func _comparison_evidence_hash(comparison: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(comparison.get("configuration_id", "")),
		str(int(comparison.get("stream_chunk_size", 0))),
		str(int(comparison.get("exact_pairs", 0))),
		"%.12f" % float(comparison.get("serial_wall_p50_ms", 0.0)),
		"%.12f" % float(comparison.get("stream_wall_p50_ms", 0.0)),
		"%.12f" % float(comparison.get("observed_wall_ratio_serial_over_stream", 0.0)),
		"%.12f" % float(comparison.get("serial_generation_p50_ms", 0.0)),
		"%.12f" % float(comparison.get("stream_generation_p50_ms", 0.0)),
		"%.12f" % float(comparison.get("observed_generation_ratio_serial_over_stream", 0.0)),
		"0" if not bool(comparison.get("optimization_claim", true)) else "1",
	])).sha256_text()


func _config_hash(config: Dictionary) -> String:
	var recipe_parts := PackedStringArray()
	for value in Array(config.get("recipes", [])):
		recipe_parts.append(String(value))
	var chunk_parts := PackedStringArray()
	for value in Array(config.get("stream_chunk_sizes", [])):
		chunk_parts.append(str(int(value)))
	return "|".join(PackedStringArray([
		"PERF2_1_CONFIG_R2",
		",".join(recipe_parts),
		str(int(config.get("warmup_generations", -1))),
		str(int(config.get("measured_generations", -1))),
		str(int(config.get("repetitions", -1))),
		str(int(config.get("initial_records", -1))),
		",".join(chunk_parts),
		str(int(config.get("audit_interval_generations", -1))),
		"true" if bool(config.get("audit_generation_1", false)) else "false",
		str(int(config.get("founder_seed", 0))),
		str(int(config.get("placement_seed", 0))),
		str(int(config.get("evolution_seed", 0))),
		str(int(config.get("environment_seed", 0))),
		str(int(config.get("world_seed", 0))),
		"true" if bool(config.get("competition_enabled", false)) else "false",
		str(int(config.get("grid_size", 0))),
		"%.9f" % float(config.get("cell_size_m", 0.0)),
		String(config.get("planet_source_kind", "")),
	])).sha256_text()


func _normalize_sample_for_contract(sample: Dictionary) -> Dictionary:
	var normalized: Dictionary = sample.duplicate(true)
	if not normalized.has("workload") or not normalized["workload"] is Dictionary:
		return {}
	var workload: Dictionary = Dictionary(normalized["workload"])
	for key in [
		"warmup_generations", "measured_generations", "repetitions",
		"initial_records", "parents_per_chunk", "audit_interval_generations",
		"founder_seed", "placement_seed", "evolution_seed", "environment_seed",
	]:
		if not workload.has(key) or not _is_integral_number(workload[key]):
			return {}
		workload[key] = int(workload[key])
	normalized["workload"] = workload

	if not normalized.has("metrics") or not normalized["metrics"] is Dictionary:
		return {}
	var metrics: Dictionary = Dictionary(normalized["metrics"])
	if not metrics.has("counts") or not metrics["counts"] is Dictionary:
		return {}
	var counts: Dictionary = Dictionary(metrics["counts"])
	for key in [
		"generation", "population", "parent_count", "candidate_count",
		"chunk_count", "max_parent_chunk", "max_candidate_chunk",
	]:
		if not counts.has(key) or not _is_integral_number(counts[key]):
			return {}
		counts[key] = int(counts[key])
	metrics["counts"] = counts

	if not metrics.has("stream") or not metrics["stream"] is Dictionary:
		return {}
	var stream: Dictionary = Dictionary(metrics["stream"])
	for key in ["stream_calls", "chunks_processed", "serial_audit_calls", "oracle_elided_generations"]:
		if not stream.has(key) or not _is_integral_number(stream[key]):
			return {}
		stream[key] = int(stream[key])
	metrics["stream"] = stream

	if not metrics.has("memory_bytes") or not metrics["memory_bytes"] is Dictionary:
		return {}
	var memory: Dictionary = Dictionary(metrics["memory_bytes"])
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

	if metrics.has("window") and metrics["window"] is Dictionary:
		var window: Dictionary = Dictionary(metrics["window"])
		if window.has("measured_generations"):
			if not _is_integral_number(window["measured_generations"]):
				return {}
			window["measured_generations"] = int(window["measured_generations"])
		metrics["window"] = window

	normalized["metrics"] = metrics
	return normalized


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


func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


func _nullable_int_string(value) -> String:
	if value == null:
		return "null"
	return str(int(value))


func _failure(code: String, detail) -> Dictionary:
	return {
		"success": false,
		"failure_code": code,
		"detail": detail,
	}
